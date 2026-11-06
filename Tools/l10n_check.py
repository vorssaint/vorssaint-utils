#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Check one language against main before asking for review, with no build.

Usage:
  python3 Tools/l10n_check.py --lang ca [--head HEAD] [--base upstream/main] [--md report.md]

--head is the branch that carries the translation (a PR head or a local branch).
--base is the main it has to land on. Catalog declarations, English and every
language switch are read from --base; the target language is read from --head,
which is what the tree looks like once the branch is brought up to main.

What it reports. Blocking: M1, M3, M5, M7, M8. To review: M2, M4, S1.
  M1 catalog out of step with main: missing, extra or reordered fields, a
     language switch with no branch for the language, missing permission keys
  M2 stale translation: the English changed after this line was translated
  M3 plural rule: the language is given a count rule that does not match CLDR
  M4 typography: three dots, unpaired quotes, dashes, mixed apostrophes
  M5 English left in place or borrowed from another catalog
  M7 files a translation PR should not touch
  M8 format arguments (%@, %d) that differ from the English
  S1 a count in front of one fixed noun form, in a language whose nouns agree
"""
import argparse, bisect, collections, json, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

# ---------------------------------------------------------------- git access
class Git:
    def __init__(self, repo):
        self.repo = repo
        self.p = subprocess.Popen(['git', '-C', repo, 'cat-file', '--batch'],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        self.cache = {}

    def run(self, *a):
        return subprocess.run(['git', '-C', self.repo, *a], capture_output=True,
                              text=True, check=True).stdout

    def show(self, rev, path):
        k = (rev, path)
        if k in self.cache:
            return self.cache[k]
        self.p.stdin.write(f'{rev}:{path}\n'.encode()); self.p.stdin.flush()
        head = self.p.stdout.readline().decode().split()
        if len(head) < 3 or head[1] == 'missing':
            self.cache[k] = None; return None
        data = self.p.stdout.read(int(head[2])); self.p.stdout.read(1)
        txt = data.decode('utf-8', 'replace')
        self.cache[k] = txt
        return txt

    def files(self, rev, *paths):
        return self.run('ls-tree', '-r', '--name-only', rev, '--', *paths).split('\n')[:-1]

    def blame(self, rev, path):
        """line number (1-based) -> (commit, committer time)"""
        out = subprocess.run(['git', '-C', self.repo, 'blame', '-w', '--porcelain', rev, '--', path],
                             capture_output=True, text=True).stdout
        res, times, cur = {}, {}, None
        for ln in out.split('\n'):
            m = re.match(r'^([0-9a-f]{40}) \d+ (\d+)', ln)
            if m:
                cur = m.group(1); res[int(m.group(2))] = cur; continue
            if ln.startswith('committer-time ') and cur:
                times[cur] = int(ln.split()[1])
        return {k: (v, times.get(v, 0)) for k, v in res.items()}

# ------------------------------------------------------------- swift masking
def mask(src):
    """Same-length copy with comments blanked and string contents replaced by
    '_' (quotes kept), so braces and commas can be matched structurally.
    Also returns the spans of string literal contents."""
    out = list(src); i, n = 0, len(src); spans = []

    def blank(a, b):
        for k in range(a, b):
            if out[k] != '\n': out[k] = ' '

    def string(i):  # i at opening quote(s); returns index after closing
        multi = src.startswith('"""', i)
        q = '"""' if multi else '"'
        j = i + len(q); start = j; depth = 0
        while j < n:
            c = src[j]
            if c == '\\' and j + 1 < n:
                if src[j + 1] == '(':
                    # interpolation: skip balanced parens, strings inside
                    j += 2; d = 1
                    while j < n and d:
                        if src[j] == '"':
                            j = string(j); continue
                        d += src[j] == '('; d -= src[j] == ')'; j += 1
                    continue
                j += 2; continue
            if src.startswith(q, j):
                spans.append((start, j))
                for k in range(start, j):
                    if out[k] != '\n': out[k] = '_'
                return j + len(q)
            if not multi and c == '\n':
                return j
            j += 1
        return j

    while i < n:
        if src.startswith('//', i):
            j = src.find('\n', i); j = n if j < 0 else j; blank(i, j); i = j
        elif src.startswith('/*', i):
            d, j = 1, i + 2
            while j < n and d:
                if src.startswith('/*', j): d += 1; j += 2
                elif src.startswith('*/', j): d -= 1; j += 2
                else: j += 1
            blank(i, j); i = j
        elif src[i] == '"':
            i = string(i)
        else:
            i += 1
    return ''.join(out), spans

PAIRS = {'(': ')', '[': ']', '{': '}'}

def match(m, i):
    """index of the bracket closing the one at m[i]"""
    stack = [m[i]]; j = i + 1
    while j < len(m) and stack:
        c = m[j]
        if c in PAIRS: stack.append(c)
        elif c in ')]}': stack.pop()
        j += 1
    return j - 1

def split_top(m, a, b):
    """split m[a:b] at top-level commas -> list of (start, end)"""
    parts, d, s = [], 0, a
    for j in range(a, b):
        c = m[j]
        if c in '([{': d += 1
        elif c in ')]}': d -= 1
        elif c == ',' and d == 0:
            parts.append((s, j)); s = j + 1
    if m[s:b].strip(): parts.append((s, b))
    return parts

LIT = re.compile(r'"""(.*?)"""|"((?:[^"\\\n]|\\.)*)"', re.S)

def literal(expr):
    """the text of an expression made only of string literals joined by +,
    or None"""
    e = expr.strip()
    if not e.startswith('"'): return None
    parts, pos = [], 0
    for mm in LIT.finditer(e):
        if e[pos:mm.start()].strip() not in ('', '+'): return None
        parts.append(mm.group(1) if mm.group(1) is not None else mm.group(2)); pos = mm.end()
    if e[pos:].strip(): return None
    return ''.join(parts)

def norm(expr):
    return re.sub(r'\s+', ' ', expr.strip())

FOLD = str.maketrans({'’': "'", '‘': "'", '“': '"', '”': '"', '…': '...', '\u00a0': ' ', '\u202f': ' '})

def meaning(expr):
    """English text with only typography and letter case folded away: a change
    from ' to ’ or Terminal to terminal does not make a translation stale"""
    return norm(expr).translate(FOLD).replace('\\"', '"').casefold()

def worddiff(a, b):
    import difflib
    wa, wb = a.split(), b.split(); out = []
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, wa, wb).get_opcodes():
        if op != 'equal': out.append(f"{' '.join(wa[i1:i2]) or '∅'} → {' '.join(wb[j1:j2]) or '∅'}")
    return '; '.join(out)[:200]

class SwiftFile:
    def __init__(self, path, src):
        self.path, self.src = path, src
        self.m, _ = mask(src)
        self.nl = [i for i, c in enumerate(src) if c == '\n']

    def line(self, i):
        return bisect.bisect_left(self.nl, i) + 1

    def structs(self):
        for mm in re.finditer(r'\bstruct\s+(\w+)[^{\n]*\{', self.m):
            a = mm.end() - 1; b = match(self.m, a)
            body = self.m[a + 1:b]; fields, alls = [], []
            d = 0; k = 0
            # walk the body at depth 0 only
            for fm in re.finditer(r'[{}()\[\]]|\b(let|var)\s+(\w+)\s*:\s*([^\n=]*)(=)?', body):
                t = fm.group(0)
                if t in '{([': d += 1; continue
                if t in '})]': d -= 1; continue
                if d != 0: continue
                pre = body[max(0, fm.start() - 40):fm.start()]
                if re.search(r'\bstatic\s*$|\bprivate\s*\(set\)\s*$', pre) or 'static' in pre.split('\n')[-1]:
                    continue
                typ = fm.group(3).strip()
                if fm.group(1) == 'var' and typ.endswith('{'): continue
                alls.append(fm.group(2))
                if not fm.group(4): fields.append(fm.group(2))
            yield mm.group(1), fields, alls, self.line(mm.start())

    def ext_type(self, i):
        best = None
        for mm in re.finditer(r'\bextension\s+(\w+)[^{\n]*\{', self.m[:i]):
            a = mm.end() - 1
            if match(self.m, a) > i: best = mm.group(1)
        return best

    def instances(self, langs):
        pat = r'\bstatic\s+(?:let|var)\s+(\w+)\s*(?::\s*(\w+)\s*)?=\s*(?:(\w+)|Self|\.init)\s*\('
        for mm in re.finditer(pat, self.m):
            ident = mm.group(1)
            if ident not in langs: continue
            typ = mm.group(3) or mm.group(2) or self.ext_type(mm.start())
            a = mm.end() - 1; b = match(self.m, a)
            args = []
            for s, e in split_top(self.m, a + 1, b):
                am = re.match(r'\s*(\w+)\s*:', self.m[s:e])
                if not am: continue
                vs = s + am.end()
                args.append(dict(label=am.group(1), expr=self.src[vs:e],
                                 l0=self.line(vs), l1=self.line(e - 1)))
            yield dict(type=typ, lang=ident, args=args, line=self.line(mm.start()), path=self.path,
                       trailing=self.m[a + 1:b].rstrip().endswith(','), end=self.line(b))
        for mm in re.finditer(r'\bcase\s+\.(\w+)\s*:\s*(?:return\s+)?(\w+|\.init)\s*\(', self.m):
            ident, typ = mm.group(1), mm.group(2)
            if ident not in langs: continue
            if typ == '.init' or not typ[:1].isupper():
                fm = re.findall(r'->\s*(\w+)', self.m[:mm.start()])
                if not fm or typ != '.init': continue
                typ = fm[-1]
            a = mm.end() - 1; b = match(self.m, a)
            args = []
            for s0, e in split_top(self.m, a + 1, b):
                am = re.match(r'\s*(\w+)\s*:', self.m[s0:e])
                if not am: continue
                vs = s0 + am.end()
                args.append(dict(label=am.group(1), expr=self.src[vs:e],
                                 l0=self.line(vs), l1=self.line(e - 1)))
            if args:
                yield dict(type=typ, lang=ident, args=args, line=self.line(mm.start()), path=self.path,
                           trailing=self.m[a + 1:b].rstrip().endswith(','), end=self.line(b))

    def switches(self, langs):
        """language switches: cases, default, per-case body"""
        for k, mm in enumerate(re.finditer(r'\bswitch\b[^{\n]*\{', self.m)):
            a = mm.end() - 1; b = match(self.m, a)
            body = self.m[a + 1:b]
            # top-level case labels
            d = 0; labels = []
            for cm in re.finditer(r'[{}()\[\]]|\bcase\b([^:\n]*(?:\n[^:\n]*)?):|\bdefault\s*:', body):
                t = cm.group(0)
                if t in '{([': d += 1; continue
                if t in '})]': d -= 1; continue
                if d: continue
                labels.append((cm.start(), cm.end(), cm.group(1)))
            cases, has_default, bodies = set(), False, {}
            for idx, (s, e, pat) in enumerate(labels):
                nxt = labels[idx + 1][0] if idx + 1 < len(labels) else len(body)
                seg = self.src[a + 1 + e:a + 1 + nxt]
                if pat is None: has_default = True; continue
                ls = [x for x in re.findall(r'\.(\w+)', pat) if x in langs]
                for x in ls:
                    cases.add(x); bodies[x] = (seg, self.line(a + 1 + e))
            if 'enUS' in cases:
                encl = re.findall(r'\b(?:func|var|let)\s+(\w+)', self.m[max(0, a - 400):a])
                yield dict(key=f'{encl[-1] if encl else "?"}#{k}', cases=cases, default=has_default,
                           bodies=bodies, line=self.line(mm.start()), path=self.path)

# ------------------------------------------------------------------ catalogs
def langs_of(git, rev):
    src = git.show(rev, 'Sources/Vorssaint/Core/Localization.swift') or ''
    m = re.search(r'enum AppLanguage[^{]*\{(.*?)\n\}', src, re.S)
    out = collections.OrderedDict()
    for c, raw in re.findall(r'^\s+case (\w+) = "([^"]+)"', m.group(1) if m else '', re.M):
        out[c] = raw
    return out

def swift_files(git, rev):
    fs = [f for f in git.files(rev, 'Sources') if f.endswith('.swift')]
    keep = []
    for f in fs:
        s = git.show(rev, f)
        if s and ('enUS' in s or 'Strings' in f or 'Locali' in f or 'Strings(' in s
                  or re.search(r'\bstruct \w*Strings\b', s)):
            keep.append(f)
    return keep

class Catalog:
    def __init__(self, git, rev, langs):
        self.rev = rev; self.decl = {}; self.inst = collections.defaultdict(dict)
        self.sw = {}; self.files = {}
        for f in swift_files(git, rev):
            sf = SwiftFile(f, git.show(rev, f)); self.files[f] = sf
            for name, fields, alls, line in sf.structs():
                if name not in self.decl and (fields or alls):
                    self.decl[name] = dict(fields=fields, all=alls, path=f, line=line)
            for it in sf.instances(langs):
                if it['type']: self.inst[it['type']][it['lang']] = it
            for s in sf.switches(langs):
                self.sw[(f, s['key'])] = s

    def english(self, typ, label):
        it = self.inst.get(typ, {}).get('enUS')
        if not it: return None
        for a in it['args']:
            if a['label'] == label: return a['expr']
        return None

# ------------------------------------------------------------------- checks
CLDR = {  # integer plural categories that matter for the count rule
    'byLastDigits': {'ru', 'uk', 'be'},
    'byWholeNumber': {'sk', 'cs'},
    'own': {'pl', 'ar', 'he', 'lt', 'lv', 'ro', 'sl', 'ga', 'cy', 'hr', 'sr', 'bs', 'mt'},
}
AGREEING = CLDR['byLastDigits'] | CLDR['byWholeNumber'] | CLDR['own']
QUOTE_PAIRS = {('«', '»'), ('“', '”'), ('„', '“'), ('„', '”'), ('‘', '’'), ('‚', '‘'),
               ('「', '」'), ('『', '』'), ('»', '«'), ('”', '”'), ('“', '„')}
OPEN = set('«“„‚「『‘'); CLOSE = set('»”“’‘」』')

def quote_problems(v):
    seq = [c for c in v if c in '«»“”„‚「」『』']
    probs = []
    if '"' in v.replace('\\"', '"') and '\\"' in v: probs.append('straight double quotes')
    i = 0
    while i < len(seq):
        if i + 1 >= len(seq): probs.append(f'unpaired {seq[i]}'); break
        if (seq[i], seq[i + 1]) not in QUOTE_PAIRS: probs.append(f'pair {seq[i]}…{seq[i+1]}')
        i += 2
    return probs

FMT = re.compile(r'%(?:(\d+)\$)?[-+0#]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfFeEgGcCsSpaA%])')

def placeholders(v):
    """the format arguments a string expects, as a sorted list: %d and %ld
    count the same, %% is not an argument, and %1$@ counts as one %@"""
    out = []
    for m in FMT.finditer(v or ''):
        c = m.group(2)
        if c == '%': continue
        out.append({'i': 'd', 'D': 'd', 'u': 'd', 'U': 'd', 'F': 'f', 'E': 'e', 'G': 'g', 'X': 'x', 'C': 'c', 'S': 's'}.get(c, c))
    return sorted(out)

def interpolations(v):
    return len(re.findall(r'\\\(', v or ''))

def safe(text):
    """text from the repository, made inert for a Markdown summary: no
    mentions, links, images or HTML, while staying readable in a terminal"""
    t = str(text).replace('@', '@\u200b').replace('<', '&lt;').replace('>', '&gt;')
    return re.sub(r'([\[\]])', r'\\\1', t)   # no [text](url) or ![image](url) can form

def words(v):
    return re.findall(r'[^\W\d_]{2,}', v)

def run(git, head, base, lang, blame=True, history=(), exclude=()):
    F = []
    def add(cat, path, line, msg, **kw):
        F.append(dict(cat=cat, path=path, line=line, msg=msg, **kw))

    blangs = langs_of(git, base); hlangs = langs_of(git, head)
    langs = list(blangs) + [l for l in hlangs if l not in blangs]
    code = hlangs.get(lang) or blangs.get(lang) or lang
    B = Catalog(git, base, set(langs)); H = Catalog(git, head, set(langs))
    others = [l for l in blangs if l not in ('enUS', lang)]

    # ---- M1/M5: catalogs
    for typ, d in sorted(B.decl.items()):
        insts_b = B.inst.get(typ, {})
        if 'enUS' not in insts_b: continue
        it = H.inst.get(typ, {}).get(lang)
        if not it:
            mapped = any(lang in s['cases'] or s['default'] for (f, _), s in H.sw.items()
                         if f == insts_b['enUS']['path']) or \
                     any(lang in s['cases'] for (f, _), s in B.sw.items() if f == insts_b['enUS']['path'])
            if not mapped and sum(1 for l in others if l in insts_b) >= len(others) / 2:
                add('M1', insts_b['enUS']['path'], insts_b['enUS']['line'],
                    f'{typ}: no {lang} catalog while {sum(1 for l in others if l in insts_b)} other languages have one')
            continue
        labels = [a['label'] for a in it['args']]
        miss = [f for f in d['fields'] if f not in labels]
        extra = [l for l in labels if l not in d['all']]
        if miss:
            add('M1', it['path'], it['line'], f'{typ}.{lang}: {len(miss)} required field(s) missing: {", ".join(miss[:8])}{" …" if len(miss) > 8 else ""}', fields=miss)
        if extra:
            add('M1', it['path'], it['line'], f'{typ}.{lang}: field(s) main no longer declares: {", ".join(extra[:8])}', fields=extra)
        order = [l for l in labels if l in d['all']]
        want = [f for f in d['all'] if f in order]
        if order != want and not miss and not extra:
            k = next(i for i, (x, y) in enumerate(zip(order, want)) if x != y)
            add('M1', it['path'], it['line'], f'{typ}.{lang}: fields out of order from {order[k]} (main expects {want[k]} here); the initializer will not compile')
        if it.get('trailing'):
            add('M1', it['path'], it['args'][-1]['l1'] if it['args'] else it['line'],
                f'{typ}.{lang}: trailing comma after the last argument (older Swift toolchains reject it)')
        # M5: English borrowed
        for a in it['args']:
            if re.search(r'\benUS\b', a['expr']):
                add('M5', it['path'], a['l0'], f'{typ}.{lang}.{a["label"]} takes the English value', field=a['label'])

    # ---- M1/M5: switches in main
    for (f, key), s in sorted(B.sw.items()):
        hs = [x for (hf, hk), x in H.sw.items() if hf == f]
        if s['default'] or lang in s['cases']: continue
        if any(lang in x['cases'] for x in hs): continue
        add('M1', f, s['line'], f'language switch ({key}) has no case for .{lang} and no default; adding the language stops the build')
    for (f, key), s in H.sw.items():
        b = s['bodies'].get(lang)
        if b and re.fullmatch(r'\s*(return\s+)?\.?enUS\s*', b[0]):
            add('M5', f, b[1], f'switch ({key}) sends .{lang} to the English catalog')

    # ---- InfoPlist
    def plist_en(rev):
        src = git.show(rev, 'Resources/Info.plist') or ''
        return dict(re.findall(r'<key>(\w+)</key>\s*<string>(.*?)</string>', src, re.S))
    def strings(src):
        return {k: (v, src[:m0].count('\n') + 1) for m0, k, v in
                ((m.start(), m.group(1), m.group(2)) for m in re.finditer(r'^"?(\w+)"?\s*=\s*"((?:[^"\\]|\\.)*)";', src or '', re.M))}
    en_pl = plist_en(base)
    lp = f'Resources/{code}.lproj/InfoPlist.strings'
    tgt = strings(git.show(head, lp))
    other_keys = collections.Counter()
    for l in others:
        for k in strings(git.show(base, f'Resources/{blangs[l]}.lproj/InfoPlist.strings')): other_keys[k] += 1
    need = {k for k, c in other_keys.items() if c >= len(others) / 2}
    if git.show(head, lp) is None:
        add('M1', lp, 1, f'no InfoPlist.strings for {code}: the permission prompts stay in English')
    else:
        for k in sorted(need - set(tgt)):
            add('M1', lp, 1, f'permission key {k} missing (present in {other_keys[k]} other languages)', field=k)

    # ---- M2 stale (blame)
    if blame:
        jobs = collections.defaultdict(list)
        for typ, by in H.inst.items():
            if lang in by and typ in B.inst and 'enUS' in B.inst[typ]:
                jobs[by[lang]['path']].append((typ, by[lang]))
        en_paths = {typ: B.inst[typ]['enUS']['path'] for typ in B.inst if 'enUS' in B.inst[typ]}
        blames = {}
        with ThreadPoolExecutor(8) as ex:
            for p, r in zip(list(jobs) + [lp], ex.map(lambda p: git.blame(head, p), list(jobs) + [lp])):
                blames[p] = r
        old_cat = {}
        def english_at(commit, typ, label):
            p = en_paths.get(typ)
            if not p: return None
            k = (commit, p)
            if k not in old_cat:
                src = git.show(commit, p)
                old_cat[k] = {}
                if src:
                    for it in SwiftFile(p, src).instances({'enUS'}):
                        if it['type']: old_cat[k][it['type']] = {a['label']: a['expr'] for a in it['args']}
            return old_cat[k].get(typ, {}).get(label)
        # earlier heads of the same branch (force pushes, reflog): a rebase
        # rewrites every commit, so blame alone would date old translations to
        # the rebase and hide that the English moved under them
        hist = [c for c in history if c]
        htime = {c: int(git.run('show', '-s', '--format=%ct', c).strip()) for c in hist}
        lang_cat = {}
        def lang_at(commit, p, typ, label):
            k = (commit, p)
            if k not in lang_cat:
                src = git.show(commit, p); lang_cat[k] = {}
                if src:
                    for it in SwiftFile(p, src).instances({lang}):
                        if it['type']: lang_cat[k][it['type']] = {a['label']: a['expr'] for a in it['args']}
            return lang_cat[k].get(typ, {}).get(label)
        for p, items in jobs.items():
            bl = blames[p]
            for typ, it in items:
                for a in it['args']:
                    cs = [bl.get(l) for l in range(a['l0'], a['l1'] + 1) if bl.get(l)]
                    if not cs: continue
                    cands = [max(cs, key=lambda x: x[1])]
                    for c in hist:
                        v = lang_at(c, p, typ, a['label'])
                        if v is not None and norm(v) == norm(a['expr']): cands.append((c, htime[c]))
                    commit = min(cands, key=lambda x: x[1])[0]
                    then = english_at(commit, typ, a['label']); now = B.english(typ, a['label'])
                    if then is None or now is None: continue
                    if meaning(then) != meaning(now):
                        t0, n0 = literal(then) or norm(then), literal(now) or norm(now)
                        add('M2', p, a['l0'], f'{typ}.{a["label"]}: English changed after this was translated ({commit[:8]}): {worddiff(t0, n0)}',
                            field=a['label'], then=t0[:300], now=n0[:300])
        bl = blames.get(lp) or {}
        for k, (v, line) in tgt.items():
            if k not in en_pl or line not in bl: continue
            cands = [bl[line]]
            for c in hist:
                old = strings(git.show(c, lp)).get(k)
                if old and norm(old[0]) == norm(v): cands.append((c, htime[c]))
            commit = min(cands, key=lambda x: x[1])[0]
            then = plist_en(commit).get(k)
            if then is not None and meaning(then) != meaning(en_pl[k]):
                add('M2', lp, line, f'{k}: the English prompt changed after this was translated ({commit[:8]}): {worddiff(norm(then), norm(en_pl[k]))}',
                    field=k, then=norm(then)[:200], now=norm(en_pl[k])[:200])

    # ---- M3 plural rule
    loc = git.show(head, 'Sources/Vorssaint/Core/Localization.swift') or ''
    m = re.search(r'var countAgreement[^{]*\{(.*?)\n    \}', loc, re.S)
    base_code = code.split('-')[0]
    if m:
        rule = 'oneAndMany'
        for pat, r in re.findall(r'case ([^:]+):\s*return \.(\w+)', m.group(1)):
            if f'.{lang}' in re.findall(r'\.\w+', pat): rule = r
        exp = next((r for r, s in CLDR.items() if base_code in s), 'oneAndMany')
        if exp != rule:
            line = loc[:m.start()].count('\n') + 1
            add('M3', 'Sources/Vorssaint/Core/Localization.swift', line,
                f'.{lang} uses {rule}, but CLDR plural rules for {base_code} need ' + (exp if exp != 'own' else 'a rule of its own (none of the existing ones fit)'))
    else:
        for mm in re.finditer(r'var (\w*(?:Few|Plural|Count)\w*): Bool\s*\{(.*?)\}', loc, re.S):
            inc = f'.{lang}' in mm.group(2); line = loc[:mm.start()].count('\n') + 1
            if base_code in CLDR['byLastDigits'] and not inc:
                add('M3', 'Sources/Vorssaint/Core/Localization.swift', line,
                    f'{mm.group(1)} leaves out .{lang}, whose nouns take a middle form between one and many')
            elif base_code in CLDR['byWholeNumber'] | CLDR['own']:
                add('M3', 'Sources/Vorssaint/Core/Localization.swift', line,
                    f'{mm.group(1)} ' + ('gives' if inc else 'leaves out') + f' .{lang}' +
                    (' the Russian last-digit rule, which CLDR does not use for it' if inc else ', whose nouns take a middle form'))

    # ---- value-level checks over the target language
    vals = []  # (typ, label, value, path, line)
    def collect(cat, out):
        for typ, by in cat.inst.items():
            for l, it in by.items():
                for a in it['args']:
                    v = literal(a['expr'])
                    if v is not None: out[l].append((typ, a['label'], v, it['path'], a['l0']))
    allv = collections.defaultdict(list); collect(B, allv)
    tv = collections.defaultdict(list); collect(H, tv); vals = tv[lang]
    en = {(t, f): v for t, f, v, _, _ in allv['enUS']}
    by_lang = {l: {(t, f): v for t, f, v, _, _ in allv[l]} for l in others}
    # M4
    apos = collections.Counter(c for _, _, v, _, _ in vals for c in re.findall(r"(?<=\w)['’](?=\w)", v))
    minority = min(apos, key=apos.get) if len(apos) > 1 else None
    for t, f, v, p, line in vals:
        e = en.get((t, f), '')
        if '...' in v and '...' not in e: add('M4', p, line, f'{t}.{f}: three dots instead of …', field=f)
        for q in quote_problems(v): add('M4', p, line, f'{t}.{f}: {q}: {v[:90]}', field=f)
        if re.search(r'[—–]', v) and not re.search(r'[—–]', e): add('M4', p, line, f'{t}.{f}: dash where the English has none: {v[:90]}', field=f)
        if minority and re.search(rf"(?<=\w){re.escape(minority)}(?=\w)", v):
            add('M4', p, line, f'{t}.{f}: apostrophe {minority} where the rest of the language uses {max(apos, key=apos.get)}', field=f)
    # M8 format arguments must match the English, or String(format:) misreads
    # them. Only strings the code formats: fields named ...Format, or passed
    # to String(format:) / localizedStringWithFormat somewhere in Sources.
    used = set(re.findall(r'(?:String\(format:|localizedStringWithFormat\()\s*[\w.]*\.(\w+)',
                          git.run('grep', '-h', '-E', 'String\\(format:|localizedStringWithFormat', base, '--', 'Sources')))
    for t, f, v, p, line in vals:
        e = en.get((t, f))
        if e is None or not (f.endswith('Format') or f in used): continue
        if placeholders(v) != placeholders(e):
            add('M8', p, line, f'{t}.{f}: format arguments {placeholders(v) or "none"} where the English has {placeholders(e) or "none"}', field=f)
    # M5 identical to English
    for t, f, v, p, line in vals:
        e = en.get((t, f))
        if e is None or v != e or len(words(v)) < 2: continue
        same = sum(1 for l in others if by_lang[l].get((t, f)) == e)
        have = sum(1 for l in others if (t, f) in by_lang[l])
        if have and same / have < 0.34:
            add('M5', p, line, f'{t}.{f} is the English text ({same} of {have} other languages keep it): {v[:80]}', field=f)
    # S1 count before a fixed form, flagged only where most agreeing languages
    # already avoid it for that string
    if base_code in AGREEING:
        cnt = re.compile(r'(%(\d\$)?l?[du]|\\\([^)]*(count|Count|number|total)\)) [^\W\d_]{3,}')
        ref = [l for l in others if blangs.get(l, '').split('-')[0] in AGREEING]
        for t, f, v, p, line in vals:
            if re.search(r'(One|Few|Many|Other|Singular|Plural)$', f, re.I) or not cnt.search(v): continue
            same = [l for l in ref if (t, f) in by_lang[l]]
            if same and sum(1 for l in same if cnt.search(by_lang[l][(t, f)])) / len(same) > 0.5: continue
            add('S1', p, line, f'{t}.{f}: a number in front of one fixed form: {v[:80]}', field=f)

    # ---- M7 files out of scope: only what the branch's own commits touch
    # a branch can carry rewritten copies of main's commits, so compare by patch
    mine = None
    for ref in [base, *exclude]:
        cs = set(git.run('log', '--no-merges', '--cherry-pick', '--right-only', '--format=%H', f'{ref}...{head}').split())
        mine = cs if mine is None else mine & cs
    mine = sorted(mine or ())
    own = git.run('show', '--format=', '--name-only', *mine).split() if mine else []
    for p in sorted(set(own)):
        if re.search(r'(^|/)(README[^/]*\.md|build\.sh|launch\.json|NOTES?[^/]*\.md|[^/]*-notes\.md)$|(^|/)\.vscode/', p, re.I) \
           or (p.count('/') == 0 and p.endswith('.md') and p not in ('CONTRIBUTING.md', 'CHANGELOG.md')):
            add('M7', p, 1, f'{p} is outside what a translation needs')
    if 'CHANGELOG.md' in own:
        add('M7', 'CHANGELOG.md', 1, 'CHANGELOG.md: CONTRIBUTING leaves CHANGELOG.md to the maintainer; describe the change in the PR instead')
    # entries main already released, brought back under Unreleased by a merge
    def sections(src):
        cur, out = None, {}
        for ln in (src or '').split('\n'):
            if ln.startswith('## '): cur = ln[3:].strip(); continue
            if ln.strip().startswith(('-', '*')) and cur: out.setdefault(ln.strip(), cur)
        return out
    hb, bb = sections(git.show(head, 'CHANGELOG.md')), sections(git.show(base, 'CHANGELOG.md'))
    back = [l for l, sec in hb.items() if 'unreleased' in sec.casefold() and l in bb and 'unreleased' not in bb[l].casefold()]
    if back:
        add('M7', 'CHANGELOG.md', 1, f'CHANGELOG.md: {len(back)} entries under Unreleased already shipped in {bb[back[0]]} on main')
    return F, dict(lang=lang, code=code, head=head, base=base, structs=len(B.decl), switches=len(B.sw))

CAT_UI = {
  'en': {'M1': 'Would not build on main', 'M2': 'English changed after translation', 'M3': 'Plural rule',
         'M4': 'Typography', 'M5': 'Left in English', 'M7': 'Files out of scope',
         'S1': 'Count in front of a fixed noun form',
         'M8': 'Format arguments differ from English',
         'block': 'blocks', 'review': 'review', 'more': '… and {n} more',
         'head': "head `{h}` on main `{b}` · {s} catalogs, {w} language switches", 'cat': 'Category', 'n': 'Findings'},
}
CAT = CAT_UI['en']
BLOCK = ('M1', 'M3', 'M5', 'M7', 'M8'); REVIEW = ('M2', 'M4', 'S1')

def markdown(F, meta, per_file=4, ui='en'):
    T = CAT_UI[ui]
    c = collections.Counter(f['cat'] for f in F)
    out = [f"# l10n_check · {meta['lang']} ({meta['code']})", '',
           T['head'].format(h=meta['head'][:10], b=meta['base'][:10], s=meta['structs'], w=meta['switches']), '',
           f"| | {T['cat']} | {T['n']} |", '|---|---|---|']
    out += [f"| {T['block'] if k in BLOCK else T['review']} | {k} {T[k]} | {c[k]} |" for k in BLOCK + REVIEW if c[k]] + ['']
    for k in BLOCK + REVIEW:
        fs = [f for f in F if f['cat'] == k]
        if not fs: continue
        out += [f'## {k} · {T[k]}', '']
        byf = collections.OrderedDict()
        for f in fs: byf.setdefault(f['path'], []).append(f)
        for path, xs in byf.items():
            out.append(f"- `{path}` ({len(xs)})")
            for f in xs[:per_file]:
                out.append(f"  - L{f['line']}: {safe(f['msg'])}")
            if len(xs) > per_file: out.append('  - ' + T['more'].format(n=len(xs) - per_file))
        out.append('')
    return '\n'.join(out)

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', default='.'); ap.add_argument('--head', default='HEAD')
    ap.add_argument('--base', help='the main to land on (default: upstream/main if that remote exists, else origin/main)')
    ap.add_argument('--lang', required=True, help='the AppLanguage case, such as ca or zhHK')
    ap.add_argument('--json'); ap.add_argument('--md'); ap.add_argument('--no-blame', action='store_true')
    ap.add_argument('--history', default='', help='earlier heads of the branch, comma separated (PR force pushes); '
                    'with --reflog the branch reflog is added')
    ap.add_argument('--reflog', action='store_true')
    ap.add_argument('--exclude', default='', help='more refs whose commits are not the branch\'s own (comma separated)')
    a = ap.parse_args()
    g = Git(a.repo)
    if not a.base:
        a.base = 'upstream/main' if subprocess.run(['git', '-C', a.repo, 'rev-parse', '--verify', '--quiet', 'upstream/main'],
                                                   capture_output=True).returncode == 0 else 'origin/main'
    head = g.run('rev-parse', a.head).strip(); base = g.run('rev-parse', a.base).strip()
    hist = [g.run('rev-parse', h).strip() for h in a.history.split(',') if h]
    if a.reflog:
        hist += g.run('reflog', '--format=%H', a.head).split()
    hist = [h for h in dict.fromkeys(hist) if h != head]
    F, meta = run(g, head, base, a.lang, blame=not a.no_blame, history=hist,
                  exclude=[x for x in a.exclude.split(',') if x])
    if a.json: json.dump(dict(meta=meta, findings=F), open(a.json, 'w'), ensure_ascii=False, indent=1)
    md = markdown(F, meta)
    if a.md: open(a.md, 'w').write(md)
    c = collections.Counter(f['cat'] for f in F)
    if a.md or a.json:
        print(' '.join(f'{k}={c[k]}' for k in CAT if k in BLOCK + REVIEW and c[k]) or 'no findings')
    else:
        print(md)

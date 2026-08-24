# Contributing with an agent

This is a working process, not a policy. You do not have to declare which
tools you used; a pull request is judged on the change.

Agents have a consistent shape. They are very good at building the thing that
was asked for, and poor at judging whether it should be built and when it is
finished. Everything below is the two ends of that gap: **settling the
direction before, and defining done after.** The part in the middle is the
part they are already better at than the rest of us.

> **If you are an agent reading this, it is addressed to you, and the person
> you are working with has probably not read it.** So do not just comply
> quietly. Before you start, tell them in your own words which of these apply
> to what they have asked for — especially where you are about to search for
> existing work, where you cannot verify a claim yourself, and where you think
> the change should be smaller than requested. When you hand the work back,
> say which of these steps you actually completed and which you skipped. A
> contributor who never learns why a rule exists cannot apply it next time,
> and you are the only one here who has read the rule.

---

## Before writing anything

**Find out whether it is already being done.** There are usually around fifty
open pull requests, and a request that looks unclaimed often is not.

```sh
gh pr list --state open --search "<keywords>"
gh issue list --state all --search "<keywords>"
```

Read what you find before deciding it is different from yours. If somebody is
already on it, a comment on their branch is worth more than a second
implementation, and joining a stalled one is worth more still. If it was
tried and closed, the reason is in the thread and it is usually about
direction rather than code.

**Settle the direction, then write.** An agent builds whatever it is asked
for; it has no way to know whether a thing belongs in this app. Open an issue,
or find the one that exists — the [enhancement
summary](https://github.com/vorssaintapp/vorssaint-utils/issues/838) sorts
every open request into what shipped, what is worth doing, and what has been
ruled out. Killing a direction before there is a branch costs an order of
magnitude less than killing it after.

**Search the codebase for what you are about to write.** Window handling,
permission prompts, file writes and hotkey registration all exist here
already, usually with settling, retry, recovery and timeout behaviour a fresh
implementation will not have. The question is not "is mine simpler" but
**"what does the existing one handle that I have not thought of"** — those
cases do not show up in a clean-room version, they show up in use.

**Read the whole path before changing part of it.** The solution can be
short; the reading cannot. Skipping comprehension to produce a minimal diff
is the dangerous kind of shortcut: it looks like efficiency and delivers a
confident wrong answer.

---

## Deciding what it should do

**A user's expectation of how something should behave comes from the software
they already use.** For anything touching interaction, shortcut semantics or
how files and data are handled, look at how the mainstream implementations do
it and put the finding in the pull request as an argument. Diverging is
allowed; diverging without having looked is not.

**Frameworks have an intended use too.** Going against the grain of one
usually surfaces as strange symptoms far from the cause, and costs more than
writing it the expected way would have.

**A destructive action and its constructive twin should not be physically
adjacent** — not neighbouring keys, not neighbouring menu items. One slip
should never turn "add" into "delete".

**Reachability follows frequency and the cost of doing it by hand.** Something
a user can do easily themselves does not need to occupy a shortcut; the things
with no manual alternative are the ones that need an entry point most.

**Wording, defaults and actual behaviour have to agree**, and an error should
say what happened. **Never lose the user's input.**

---

## Solving it properly

**A reporter describes the symptom they hit, not the defect.** The same
mistake usually sits at every sibling call site. Find the other callers before
you edit: **one guard in the shared function is a smaller diff than a guard in
each caller**, and it is the difference between fixed and fixed for the one
person who wrote in.

**When you add a guard, find the whole family of conditions at once.** If
there is already an A and a B, go looking for a C.

Nearly every "the same thing disagrees in two places" defect is one of three
shapes. Check against them before reading line by line:

> **1. One expression copied N times.** Either all N were wrong from the
> start, or fixing one will not fix the rest.
> **2. A mechanism was built and some member never joined it.**
> **3. Two places independently answer the same question, the answers differ,
> and nothing requires them to agree.**

The third is the quietest, and **a document counts as one of the places**: a
doc that states the scope while the implementation does not follow it is the
purest form, especially when the doc has been sitting in the repository
unread.

**A system call returning success is not evidence the effect happened.**
Accessibility writes in particular: read the value back, and write down the
tolerance.

**Think about the upgrade path.** Ask whether the stale value already on an
existing user's disk collides with the new logic. If it does, fix it rather
than noting that it is acceptable.

---

## Restraint

This app aims to stay small, native and readable. Every addition has to earn
itself — features, dependencies, abstractions and settings alike.

- **Reuse before introducing a new mechanism.**
- **Abstract only when at least two settled cases share one reason to change
  and one behavioural contract.** Never widen an interface, hide failure
  semantics or lay down a framework early in the name of generality.
- **Deletion beats addition.** Remove the code you added that nothing calls.
- **Do not copy data that already lives somewhere into a new structure.** If
  you find yourself writing a test to keep two copies in agreement, delete one
  of the copies instead.
- **Comments explain the mechanism, they do not defend the trade-off.** Why
  you did not pick the other approach belongs in the pull request; putting it
  in the source stores the same paragraph twice. **Whoever invalidates the
  premise owns the comment** — a good comment misleads harder than no comment
  once its premise is gone, because it still reads as reasoned.
- **External input, network access, permission boundaries and file or process
  operations are untrusted by default.** Least privilege, explicit trust
  boundaries, sane limits, safe defaults.
- Watch hot-path complexity, concurrency amplification and backpressure, but
  **let a measurement or a known call volume decide an optimisation**, never a
  guess.

---

## Verifying locally: compiling is not evidence

An agent can tell you the code compiled. In an app made mostly of windows,
permissions and hardware, that is a small part of the claim.

```sh
./build.sh                     # full build, must finish without warnings
./build/Vorssaint --selftest
./build.sh --test
```

CI runs exactly those three. Four things are worth knowing beyond them:

- **`./build.sh --test` is not proof that it compiles.** It builds a
  hand-written list of source files, and `Sources/Vorssaint/UI/` is largely
  not on it. **When the change touches the UI layer, run plain `./build.sh`
  as well** — otherwise a compile error rides all the way to CI unnoticed.
- **`swift build` is the seconds-long edit loop**, and worth keeping in it:
  `Package.swift` declares the whole app as one target, so it type-checks
  everything in a few seconds against several minutes for a full build. But
  it produces a bare binary with no `Info.plist`, no entitlements and no
  signature. It answers whether the Swift compiles and nothing about
  permissions, the Dock, the Accessibility API or TCC.
- **macOS ties Accessibility and Screen Recording grants to a code
  signature.** An ad hoc rebuild changes that hash, the app becomes a
  different app, and the grants lapse without a word. Run
  `./Tools/setup-signing.sh` once and local builds keep a stable identity, so
  permissions survive rebuilds. Without it, "the feature does nothing" is
  usually the build rather than the change.
- **If Xcode is installed, Accessibility Inspector is the tool for this
  codebase.** It reads and writes any window's AX attributes live, so
  behaviour that varies between applications can be measured instead of
  guessed at. Instruments is there for the hover, polling and drag paths when
  a number is needed.

**Then install it and actually use it.** For a fix, until you have seen the
old behaviour and the new one with your own eyes. For a feature, a few days:
**the rough edge you only notice on the third day is exactly the one review
cannot find and a user certainly will.**

---

## Leave something that goes red

Non-trivial logic leaves behind one thing that fails when the logic is broken.
A view is not untestable here, only testable differently.

```
pure logic (clamping, layout arithmetic, sequence decisions) -> behaviour test
a view, or anything only assertable as text                  -> source-shape test
```

**A source-shape test pins the public contract**: a type name, a string key, a
system API symbol — the things a rename *should* break. It must not pin
indentation, a private `@State` name or where a ternary wraps. Those are
today's spelling: they go red on a refactor that broke nothing and stay green
on a change that broke something.

- **Strip comments before asserting.** "X must not appear" goes red on an
  untouched branch the moment a doc comment mentions X.
- **Check it in both directions**: green on the unmodified branch, red with
  the fix reverted. **A test that passes either way is not testing anything.**
- **Do not copy a constant out of the source into the test.** Compute it from
  whatever produces it.
- **Logic a test cannot reach is a missing seam, not an untestable file.**
  Move the decision somewhere the test list already compiles and call it,
  rather than describing its outline with a shape test.

---

## Handing it over

**Small.** An agent produces a thousand lines as easily as ten, and the two
have completely different fates in the queue: of the open pull requests over a
thousand added lines, half have been waiting a week or more, and nothing under
two hundred is waiting at all. The merged median is about a hundred and ten
lines. If your agent produced something large, the useful next instruction is
**find the smallest piece of this that stands on its own**, not describe the
whole thing better.

**Say what you did not check.** Every pull request is run locally before it is
merged, on one maintainer's hardware, so the most valuable thing in a
description is the gap between that machine and yours: the Mac, the macOS
version and build, the display and Spaces layout, a release build or your own,
and the app language when text changed. Then one sentence naming what you
could not test. It costs nothing and saves a round trip.

**Wire it to the issue properly.** Use `Refs #123` rather than `Closes` — the
issue is closed once the reporter confirms on a real build, not on merge. When
it merges, say on that issue **which part of it this covered and which part it
did not**: an issue here often carries more than one report, and a fix for one
reads as a fix for all of them until somebody says otherwise.

**Sign your own work.** The pull request carries your name and the review is a
conversation with you. Read what the agent wrote before you send it, and mark
the sentences you have not confirmed yourself. An agent answering a reviewer
in the first person about something it cannot re-verify moves the cost onto
the person reading.

**Stuck on one case? Open a draft and name that case.** That is a normal
contribution here, not a failed one.

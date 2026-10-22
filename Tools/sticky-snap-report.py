#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint
"""Summarise ~/Library/Logs/Vorssaint/sticky-snap.log, one block per drag.

Record first:  defaults write <bundle id> windowStickySnapLog -bool YES
Then restart the app, drag one placed window, and run this script.
Line format: <uptime> <kind> <window> <x> <y> <w> <h> <note>
"""
import collections
import os
import sys

GAP = 0.6  # seconds without any ax/poll line that split two drags
path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/Library/Logs/Vorssaint/sticky-snap.log")


def parse(line):
    parts = line.split()
    if len(parts) < 7:
        return None
    try:
        return dict(t=float(parts[0]), kind=parts[1], win=parts[2], note=" ".join(parts[7:]))
    except ValueError:
        return None


rows = [r for r in map(parse, open(path, errors="replace")) if r]
if not rows:
    sys.exit("no log lines in " + path)

print("registrations:")
for r in rows:
    if r["kind"] in ("observe", "observe-failed", "untrack", "placed", "stop"):
        print(f"  {r['t']:.3f} {r['kind']:<15} win {r['win']} {r['note']}")

moving = [r for r in rows if r["kind"] in ("ax", "poll", "write", "settle", "session", "skip", "reset", "drag-end")]
drags, current = [], []
for r in moving:
    if current and r["t"] - current[-1]["t"] > GAP:
        drags.append(current)
        current = []
    current.append(r)
if current:
    drags.append(current)

def candidates(drag, span):
    """Counters for the five jump candidates of one drag, with a verdict each."""
    wr = [r for r in drag if r["kind"] == "write"]
    # 5: several writes to one follower inside one 60 Hz step (16.7 ms).
    multi = 0
    gaps = []
    per_win = collections.defaultdict(list)
    for r in wr:
        per_win[r["win"]].append(r["t"])
    for times in per_win.values():
        for a, b in zip(times, times[1:]):
            gaps.append(b - a)
            if b - a < 1 / 60:
                multi += 1
    pct = 100 * multi / len(wr) if wr else 0
    print(f"  [5 multi-write] writes: {len(wr)}, within 16.7 ms of the previous: {multi} ({pct:.0f}%), "
          f"shortest gap: {min(gaps) * 1000:.1f} ms" if gaps else f"  [5 multi-write] writes: {len(wr)}")
    print(f"      verdict: {'APPLIES' if multi else 'not seen'}")
    # 2: follower events that looked foreign right after our own write.
    drifts = [r for r in drag if r["kind"] in ("ax", "poll") and r["note"].startswith("follower-drift")]
    missed = [r for r in drifts if "missed-echo" in r["note"]]
    devs = [float(r["note"].split("dev=")[1]) for r in missed if "dev=" in r["note"]]
    share = 100 * len(missed) / len(drifts) if drifts else 0
    print(f"  [2 echo tolerance] follower events read as foreign: {len(drifts)}, of those our own echo: "
          f"{len(missed)} ({share:.0f}%)" + (f", largest offset {max(devs):.1f} pt" if devs else ""))
    print(f"      verdict: {'APPLIES' if missed else 'not seen'}")
    # 3: pauses of the follower while the driver kept moving.
    drives = [r["t"] for r in drag if r["kind"] in ("ax", "poll") and r["note"] == "drive"]
    stalls = []
    for times in per_win.values():
        for a, b in zip(times, times[1:]):
            if b - a > 0.1 and any(a < d < b for d in drives):
                stalls.append(b - a)
    rate = len(drives) / span if span > 0 else 0
    print(f"  [3 polling] driver steps: {len(drives)} ({rate:.0f}/s), follower pauses over 100 ms "
          f"during motion: {len(stalls)}" + (f", longest {max(stalls) * 1000:.0f} ms" if stalls else ""))
    skips_live = [r for r in drag if r["kind"] == "skip" and r["note"] == "not-live"]
    print(f"      not-live skips (follower frozen by the eligibility check): {len(skips_live)}")
    print(f"      verdict: {'APPLIES' if stalls or skips_live else 'not seen'}")
    # 4: the app refused the size and we put it back.
    resets = [r for r in drag if r["kind"] == "reset"]
    print(f"  [4 minimum size] resets after a refused size: {len(resets)}")
    print(f"      verdict: {'APPLIES' if resets else 'not seen'}")
    # 1: settle correction at the end.
    settles = [r for r in drag if r["kind"] == "settle"]
    devs = [float(r["note"].split("deviation=")[1].split()[0]) for r in settles if "deviation=" in r["note"]]
    fired = [r for r in settles if "corrects=True" in r["note"]]
    print(f"  [1 settle] settle steps: {len(settles)}, with correction: {len(fired)}"
          + (f", deviation(s) in pt: {', '.join(f'{d:.1f}' for d in devs)}" if devs else ""))
    print(f"      verdict: {'APPLIES' if fired else 'not seen'} (corrections only above 1 pt)")
    jitter = [r for r in drag if r["kind"] == "skip" and r["note"] == "jitter"]
    paced = [r for r in drag if r["kind"] == "skip" and r["note"].startswith("paced")]
    print(f"  smoothing: jitter skips {len(jitter)}, paced (merged) writes {len(paced)}")
    for r in drag:
        if r["kind"] == "drag-end":
            print(f"  drag-end win {r['win']}: {r['note']}")


for n, drag in enumerate(drags, 1):
    t0, t1 = drag[0]["t"], drag[-1]["t"]
    span = max(t1 - t0, 1e-6)
    print(f"\ndrag {n}: {t1 - t0:.2f} s, from {t0:.3f}")
    by_win = collections.defaultdict(list)
    for r in drag:
        if r["kind"] in ("ax", "poll"):
            by_win[r["win"]].append(r)
    for win, items in by_win.items():
        for source in ("ax", "poll"):
            sel = [r for r in items if r["kind"] == source]
            if not sel:
                continue
            verdicts = collections.Counter(r["note"] for r in sel)
            real = sum(v for k, v in verdicts.items() if k in ("drive", "move"))
            dropped = len(sel) - real
            last = sel[-1]["t"] - t0
            print(f"  win {win} {source:<4}: {len(sel)} lines, {len(sel) / span:.1f}/s, "
                  f"last at +{last:.2f} s, dropped {dropped} ({100 * dropped / len(sel):.0f}%)")
            print("      " + ", ".join(f"{k}={v}" for k, v in sorted(verdicts.items())))
    writes = sum(1 for r in drag if r["kind"] == "write")
    settles = sum(1 for r in drag if r["kind"] == "settle")
    print(f"  follower writes: {writes}, settle corrections: {settles}")
    ax = [r for r in drag if r["kind"] == "ax"]
    poll_changes = [r for r in drag if r["kind"] == "poll" and r["note"] in ("drive", "echo")]
    if not ax and poll_changes:
        print("  READING: no Accessibility events during the drag, only polling saw it.")
    elif ax and poll_changes and poll_changes[-1]["t"] - ax[-1]["t"] > 0.3:
        print(f"  READING: events stopped {poll_changes[-1]['t'] - ax[-1]['t']:.2f} s before the drag ended.")
    elif len(ax) < 4 and span > 0.5:
        print("  READING: very few events for a drag of this length; the source is sparse.")
    candidates(drag, span)


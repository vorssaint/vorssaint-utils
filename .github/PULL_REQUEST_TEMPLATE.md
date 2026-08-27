<!--
Only the issue reference at the bottom is required. A one-line fix needs
nothing else beyond the first section, and the shortest description ever
merged here was five lines.

Size is what decides how long this waits. The median merged pull request is
+110 lines and lands within a day. Nothing under +200 lines is stuck right
now; half of everything over +1000 lines is. Splitting a large change is
worth more than describing it well.
-->

## Summary

What changes, and for a fix, what was wrong.

If this adds or changes a feature, say why it belongs in Vorssaint. Direction
is the most common reason a pull request is turned down here, and it is far
cheaper to settle in an issue before the code exists. Say what the feature is
built on and whether that will still be here, what it drags in at runtime and
who carries that when it breaks, what it exposes the project to, and how much
permanent surface it adds against how many people will ever switch it on.
Intel support, hardcoded integrations with particular third-party apps, a
plugin system and video downloading have all been declined on those grounds;
CONTRIBUTING works them through with the cases.

## Verification

Where you ran it, in as much detail as you have, and **what you could not
test**. The Mac model, the macOS version and build, the display and Spaces
layout, whether it was a release build or one of your own — any of those can
be the whole difference. Every pull request is run locally before it is
merged, on one maintainer's hardware, so the gap between your machine and
that one is the useful part; changes have passed review and then failed on a
different Mac.

```sh
./build.sh                     # must finish without warnings
./build/Vorssaint --selftest
./build.sh --test
```

New user-facing text has to compile in every supported language; a missing
translation is a failed build, not a missing string.

## Anything else

**If an issue exists for this, reference it, written exactly as `Refs #N`.**
Not `Closes`/`Fixes`, which closes the report on merge when the fix has not
reached anyone's Mac yet, and not a bare `#N` or a sentence about it. That
line is what the fix-status bot reads when this merges: it labels the issue,
comments again when a release carries the fix, and closes the issue after two
weeks of silence. A pull request that leaves it out drops the report out of
that track, and nobody notices until the reporter asks months later.

Several issues means several references, each on its own line and each
starting with its own `Refs`. The bot reads the word and the number as a pair,
so `Refs #N, #M` reaches the first number and leaves the second one
sitting there.

If the issue carries more than one report and this covers only one, say which,
here and on the issue when this merges. `Depends on #N` if it has to land
after another branch.

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

## Whether it belongs here

Vorssaint is one menu bar icon doing the job of a dozen paid Mac apps. Doing
their job is not the same as becoming them. The app reaches for what macOS
almost does, or for what one small paid app does, and it does not grow a
subsystem of its own — a network stack, an audio graph with drift
compensation, a plugin host, a client that has to exist on the other end of
the wire. Each of those has been asked for here, and each was turned down for
that reason rather than for lack of interest.

Four questions settle most proposals, and an agent will raise none of them on
its own. They are about what the project is committing to rather than about
how well the code is written: the video downloader that was declined was
carefully built.

**What carries it, and will that still be here?** Touch Bar support was
declined because the hardware is discontinued and the audience only shrinks —
the feature would have been right on the day it merged and dead weight a year
later. Lock screen widgets were declined because macOS has no API for them at
all, so the demand has nothing to attach to. And anything riding a private
enumeration path is rented rather than owned: macOS 27 changed the menu bar
backend, and the call that listed other apps' status item windows stopped
returning them. Ask what the feature stands on, who controls that, and what
the app looks like the day it goes.

**What does it expose the project to?** A signed, notarised, branded
application puts the project's distribution identity behind whatever it does,
in a way a user running the same command line tool themselves does not. Video
downloading was declined on exactly that: the tool chain needs a JavaScript
runtime to solve YouTube's signature challenge, which is the mechanism the
DMCA 1201 notice against youtube-dl was written about, and the feature also
read the browser's login cookies to reach members-only videos. Typing sounds
carry sample licensing. A plugin system loading third-party code carries a GPL
boundary on top of signing, notarisation and crash isolation. When the value
of a feature depends on getting past something, raise that before writing it,
not in the description afterwards.

**What does it drag in?** The app builds with a plain `swiftc` call and no
external dependencies, and a runtime dependency counts the same way. A tool
the user has to install through Homebrew is one. A tool that ships fixes on a
near daily cadence is a maintenance contract. The cost is not the install: it
is that every upstream breakage arrives here as a Vorssaint bug, reported by
somebody with no way to tell whose fault it is, against a release cadence that
cannot track it. A privileged helper, a new signing target, an extension the
user has to switch on by hand in System Settings — those are release process
changes wearing the clothes of a code change, and the issue should say so.

**How many people want it, and how specific is the want?** One vendor's one
mouse button, one chat application's shortcut hardcoded into the media key
path, a network management protocol for a narrow audience: all declined.
Narrow on its own is fine, and the app is full of things only some people ever
switch on. Narrow **and** needing a new subsystem is what fails. The ratio to
weigh is the permanent surface a feature adds — a service, a permission,
settings, strings in every locale — against how many people will ever turn
it on.

The ruled-out section of the enhancement summary linked above is the record of
these four being applied, with the reasoning attached to each. It is worth
reading before proposing anything large: re-proposing something costs as much
as proposing it did, and the answer may already be written there.

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

**A fix that takes something away from everyone to help some of them is a
direction question, not a fix.** A Settings page here overflowed its window in
eight of the thirteen languages, because a segmented control has no compressed
size — it asks for the sum of its segments and pushes whatever contains it.
The fix on offer replaced it with a pop-up menu: one visible choice instead of
four, in all thirteen languages, including the five where nothing was wrong.
Measuring the problem exhaustively does not settle that. The measurement says
how big it is, not what it is worth. Take it to the issue while it is still a
paragraph.

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

**Do not stack your own branches.** Two follow-ups here sat on a branch that
had not merged, all three touching the same file and answering the same
design question. Installing the build once replaced that design with a view
the App Switcher already had, and all three had to be abandoned together.
Depending on somebody else's branch is sometimes unavoidable; depending on
your own means that when the shape changes — and after living with it, the
shape usually does — you lose the stack rather than a branch. If a later
branch would change an earlier one's shape, the earlier one was not ready to
open.

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

**If you close it yourself, leave the findings on the issue.** The measuring
is usually the expensive part and the code the cheap part. That overflowing
Settings page was measured in all thirteen languages against the width the
window guarantees; the branch was withdrawn, the issue is still open, and the
numbers now exist nowhere. A comment costs a minute, and it is the only part
of a withdrawn branch that keeps its value.

**Sign your own work.** The pull request carries your name and the review is a
conversation with you. Read what the agent wrote before you send it, and mark
the sentences you have not confirmed yourself. An agent answering a reviewer
in the first person about something it cannot re-verify moves the cost onto
the person reading.

**Stuck on one case? Open a draft and name that case.** That is a normal
contribution here, not a failed one.

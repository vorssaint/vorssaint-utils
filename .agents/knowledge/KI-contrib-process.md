# KI: Contribution process (agent)

Mandatory reading: `docs/AI-CONTRIBUTIONS.md`, `CONTRIBUTING.md`.

## Before coding

1. `gh pr list --state open --search "<keywords>"`
2. `gh issue list --state all --search "<keywords>"`
3. Check enhancement summary issue #838 for ruled-out directions
4. Search codebase for existing AX / permission / hotkey / file paths

## Fit test (four questions)

1. What carries it — will that still exist?
2. What exposure (signing, legal, GPL boundary)?
3. What does it drag in (deps, helpers, Settings surface)?
4. How many people × how much permanent surface?

## Done definition

```sh
./build.sh
./build/Vorssaint --selftest
./build.sh --test
```

UI changes: full `./build.sh` required (`--test` skips most of `UI/`).

Use installed app with stable signing; compile ≠ evidence for AX/TCC features.

## Open themes (snapshot 2026-09-05)

Hot issues: switcher multi-monitor (#1391), switcher broken (#1388), Super Key hot corners (#1382), Command Bar Wi-Fi main-thread (#1381), snippets inline completion (#1377).

Hot PRs: deep links (#1393 draft), mixer software master (#1387), fan profiles (#1385), snap layouts (#1383), snippet fix (#1378).

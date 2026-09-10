# Fifty-issues campaign

**Rule:** one issue at a time → analyze → TDD → `./build.sh --test` → PR (`Refs #N`) → next.

| # | Issue | PR | Status |
|---|-------|-----|--------|
| 1 | #1551 keyboard debounce 1 ms step | #1559 | shipped |
| 2 | #1463/#1464/#1539/#1555 screenshot preview focus | #1560 | shipped |
| 3 | #1556 Homebrew cask false Trash alert | #1561 | shipped |
| 4 | #1534 AutoQuit kills Phone on Continuity call | #1562 | shipped |
| 5 | #1554 Outlook attachments → shelf | #1563 | shipped |
| 6 | #1424 Finder Space → Get Info on folder | TBD | in progress (agent) |
| — | #1557 allow display sleep | — | skipped (already shipped) |

## Skip
Intel (#1514/#1494), huge editor (#1550), OS crash (#1552), sticky (#1480), done (#1495).

## Discipline
Before every commit: `test "$(git branch --show-current)" = "feat/<slug>"`. Never stage `.agents/` / `.codebase-memory/` / `docs/superpowers/`.

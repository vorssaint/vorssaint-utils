# Agent meter

A personal Developer build of Vorssaint that shows Claude, Codex, and Cursor the way Codenotch does: one ring per account, official plan limits, and a live working, waiting, or finished state. The closed Dynamic Island and an optional edge pin read the same store. Upstream pull requests can be cut from this later. This document is the build spec, not a release note.

## Goal

While a coding assistant is in use, Vorssaint shows how much of its plan is left, when that window resets, and whether the current turn is working, waiting on the person, or finished. Finishing or starting to wait plays a sound once. Crossing 80% or 100% posts one notification. Clicking a ring brings that assistant's app forward.

## Decisions

- Extend Vorssaint's existing agent service. Do not embed Codenotch's source.
- The first assistants on the meter are Claude, Codex, and Cursor. OpenCode and Copilot keep their current AI Agents behavior and do not gain rings in this build.
- An account is one login. `~/.claude` is Claude. A sibling directory named `.claude-<slug>` or `.codex-<slug>` becomes another account only when it already contains that assistant's log folder. Cursor is one account.
- Both surfaces ship. The edge pin is off until AI Agents settings turn it on. The first enabled edge is the top. The chosen edge and the position along it are remembered.
- Sign-in uses each assistant's own login command. Vorssaint then reads the session that command saved. It does not keep a separate browser login.
- Live turns come from local logs. Plan percentages come from the signed-in session. Message text, prompts, and replies are not stored.
- Waiting is amber only for Claude `AskUserQuestion` and Cursor `AskQuestion`. Codex spins while a task is open and does not turn amber.
- The island and the edge pin share one snapshot. Sounds and notifications are decided once, from that snapshot, so the two views cannot double-fire.
- The first snapshot after launch is quiet, even if a turn is already open or a limit is already past 80%.

## Accounts

`AgentAccount` is a provider plus a slug. An empty slug is the default account. The id is the provider name, or `provider:slug` for an extra login. The display name is `Claude`, `Codex`, `Cursor`, or `Claude (slug)` and `Codex (slug)`.

Discovery looks in the home directory:

- Claude default: `~/.claude/projects`
- Claude extra: `~/.claude-<slug>/projects` when that directory exists
- Codex default: `~/.codex/sessions`
- Codex extra: `~/.codex-<slug>/sessions` when that directory exists
- Cursor: `~/.cursor/projects/*/agent-transcripts/`

An extra directory with no log folder does not create an account. OpenCode and Copilot roots stay as they are today and stay keyed by provider.

The store, limits, live turns, and settings toggles for the meter are keyed by account. Two Claude logins cannot overwrite each other's percentage.

## Log reader

Claude, Codex, OpenCode, and Copilot keep their current parsers. The Cursor parser reads `~/.cursor/projects/<project>/agent-transcripts/<session>/<session>.jsonl`.

From each Cursor line it may keep the role, the line type, a tool's name, the time, the project folder name, and the session id. It does not keep `message.content` text or tool input. The project name shown on the island is the transcript's project folder name.

Cursor phases:

- A user line opens a turn. The account is **working**.
- Later assistant lines keep it working.
- The account is **waiting** when the latest tool name is `AskQuestion` and no later assistant line or `turn_ended` has arrived.
- `turn_ended` closes the turn. A `success` status can emit the existing finish event. An `error` status closes the turn without a finish sound.

Claude and Codex phases:

- An open turn with activity inside the current idle window (`NotchAgentSupport.idleTurn`, 10 minutes) is **working**. The ring spins.
- Claude is **waiting** when the latest tool name is `AskUserQuestion` and no later tool result has arrived. Codex logs have no separate approval event, so Codex does not turn amber in this build: it spins from `task_started` until `task_complete`, `turn_aborted`, or the idle window, and it does not play the waiting sound. Ordinary tool calls such as reads, edits, and shell commands stay **working**, then return to idle when the idle window passes.
- A completed turn uses the existing finish event. An aborted or failed end closes the turn without a finish sound.
- A quiet turn still uses `closeIdleTurns` so work can resume. Moving into that internal waiting set does not, by itself, turn the ring amber or play the waiting sound.

A replaced or truncated log closes its old turn without a finish sound and is read again from the start. A line that cannot be parsed is skipped.

## Sign-in

AI Agents settings shows one row per discovered account. Each row has Sign in and Log out.

| Account | Sign in | Log out | Session the poller reads |
|---|---|---|---|
| Claude default | `claude auth login` | `claude auth logout` | Claude Code session for `~/.claude` |
| Claude extra | `CLAUDE_CONFIG_DIR=<dir> claude auth login` | same logout with that directory | Claude Code session for that directory |
| Cursor | `cursor-agent login` | `cursor-agent logout` | the `cursor-agent` session |
| Codex default | `codex login` | `codex logout` | `~/.codex/auth.json` |
| Codex extra | `CODEX_HOME=<dir> codex login` | same logout with that home | `<dir>/auth.json` |

If the executable is missing, the button says that assistant is not installed and does not create a session. Canceling or failing a login leaves an existing session connected. With no session, the account is signed out.

A session that is already present is used without pressing Sign in. `claude auth status` and `cursor-agent status` report Claude and Cursor. Codex is connected when that account's `auth.json` exists. Log out runs the tool's own logout, then drops that account's readings. The tool keeps its own files.

## Quota poller

The poller runs only for a signed-in, enabled account. It runs every 60 seconds while any metered account is working, and every 5 minutes when none are. One check per account is in flight at a time. A response that arrives after logout is discarded.

Each check stores the official used percentage and reset time for every window the account reports, usually the session window and the weekly window. It does not store raw API bodies.

- Claude uses the Claude app's `plan-usage-history.json` when that file matches the signed-in organization. Otherwise it requests usage with the Claude Code session for that config directory.
- Codex uses `rate_limits` already parsed from the session log when that reading is under 5 minutes old. Otherwise it requests usage with the Codex session for that home.
- Cursor requests usage with the `cursor-agent` session.

A failed check, an expired session, or an unreadable response keeps the last good percentage and reset time and marks the reading stale. The open island shows the time of the last good reading. The next success clears the stale mark. An expired session offers Sign in again.

The ring draws the current window with the highest used percentage. The open island lists every window and its reset time.

## Attention

Attention diffs the previous snapshot with the new one.

- A new finish event plays the finish sound once and keeps Vorssaint's existing finish notice.
- A transition into **waiting** plays the waiting sound once.
- Each limit window notifies at 80% and at 100%, once per crossing. The same window can notify again only after its reset time has passed.
- Launch suppression: events already true in the first snapshot do not play or notify.

Finished and waiting have separate sounds, each with a preview in AI Agents settings. If notification permission is denied, the sounds and the rings still work.

Clicking a ring activates the app that owns the session. Cursor activates Cursor when it is running. Claude uses the pid in that account's `sessions/<pid>.json` and activates the terminal that launched it. Codex activates the app for its session pid when one is recorded. If no app is running, the click opens the island on that account.

## Surfaces

The closed island draws one ring per metered account that is signed in or has a live turn, in one row across the wings. A ring spins while its account is working and turns amber while it is waiting. More than six rings show the six accounts closest to a full window; the opened AI Agents page shows the rest.

Opening the island shows, for each metered account, the percentage, every reset time, the stale mark, and the live project name.

The edge pin is a separate panel. It draws the same rings on the selected screen edge. Top and bottom lay them in a row. Left and right stack them. Dragging moves the pin along the selected edge. It has no attention logic of its own.

Switching an assistant off stops its watcher and its poller and drops its readings. Login files on disk stay in place.

## Failure behavior

- Missing CLI: the Sign in button names the missing tool and launches nothing.
- Canceled or failed login: a previous session stays connected. No session means signed out, and the poller does not call the usage endpoint.
- Logout: drop that account's readings only.
- Bad log line: skip it.
- Replaced transcript: close the old turn with no finish sound.
- Empty extra folder: no account and no ring.
- Waiting clears when the turn ends or new work arrives.
- Two polls for one account cannot overlap.
- A usage response after logout is ignored.
- The first snapshot is silent.
- Each finish, each new waiting state, and each 80% or 100% crossing fires once.

## Testing

Automated tests use fixtures and a temporary home directory. They do not log in and they do not read prompt text.

- Discovery: `~/.claude` and `~/.claude-work` become two accounts. An empty `~/.codex-empty` does not. Cursor appears when a transcript directory or a saved `cursor-agent` session is present.
- Cursor fixtures: a user line, later assistant work, an `AskQuestion` tool name with no following line, and `turn_ended` with `success` and `error`. The stored result has no message text. A replaced file closes the old turn without a finish sound.
- Two Claude accounts hold different percentages. Logout drops one account. A usage response after logout is ignored.
- The first snapshot is silent. A finish plays once. A transition into waiting plays once. Each window notifies at 80% and at 100% once, and not again until that window's reset time.
- A failed poll keeps the last percentage and marks it stale.
- The command builder returns the sign-in and logout commands in the table above, including `CLAUDE_CONFIG_DIR` and `CODEX_HOME` only for extra accounts. A missing executable is reported and nothing is launched.
- `AskUserQuestion` with no later tool result enters waiting. `AskQuestion` with no later line enters waiting. `Bash`, `Read`, and `Edit` do not. Codex fixtures for `task_started` and `task_complete` never enter waiting.

`./build.sh --test` runs those suites. `./build.sh --dev` and `./build/VorssaintDeveloper --selftest` cover the build. On a Mac, the manual check is: sign in, see the rings, finish a turn, hear the finish sound once, and click a ring to bring that app forward.

## Out of scope

- Phone pairing, local-model rings, and assistants other than Claude, Codex, and Cursor on the meter.
- A Vorssaint-owned browser login or a copied Codenotch provider module.
- Storing prompts, replies, or tool arguments.
- Publishing this build as an official Vorssaint release. The Developer app keeps its own name, bundle id, and signing identity.

## Later pull requests

This build can be split, in order, into: Cursor live sessions from local transcripts, extra Claude and Codex logins, official usage checks after the tool's own sign-in, the multi-ring island, then the edge pin and attention. Each of those is a separate upstream proposal. The personal Developer build contains all of them.

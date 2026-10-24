# Companion chat

## Quick start

Click the companion in the Dynamic Island (or **Settings → Dynamic Island →
Companion → Ask**). There is nothing to configure: the chat uses the first of
Claude, ChatGPT (Codex) or Cursor installed on this Mac. Switch AI from the
menu in the chat header or pick one in the same settings page.

The first time for each AI, it checks three things and shows one fix if any
fails. After one passes it is remembered, so opening the chat later runs
nothing. The check only runs again if a question later fails, or when you press
**Check now** in Settings or refresh in the chat:

1. the command-line tool is installed;
2. it is signed in;
3. a one-word test question gets an answer.

Your subscription sign-in is used first (Claude subscription, ChatGPT, Cursor
account). Vorssaint hides `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` and
`CURSOR_API_KEY` from that first attempt and only uses a key if the subscription
attempt fails. If Claude refuses a subscription, the fix is
`launchctl setenv ANTHROPIC_API_KEY <key>`, then relaunch Vorssaint.

| Tool | Install | Sign in |
| --- | --- | --- |
| Claude | `curl -fsSL https://claude.ai/install.sh \| bash` | `claude auth login` |
| Codex | `npm install -g @openai/codex` or the ChatGPT app | `codex login` |
| Cursor | `curl https://cursor.com/install -fsS \| bash` | `agent login` |

A failed check shows a **Sign in** or **Install** button that runs the command in
Terminal. Vorssaint notices when it finishes and completes setup by itself.
Settings → Dynamic Island → Companion lists every AI with its status and a
**Check now** button.

## What it runs and what stays on the Mac

- Each question runs the AI's own command-line tool once, read-only: Claude with
  no tools, Cursor in ask mode, Codex in a read-only sandbox. They start in an
  empty folder of their own, not your home folder.
- The question goes to the tool as one argument, never through a shell string.
- Chat text and drafts stay in memory and are cleared when the chat closes.
- The only things saved are which AI you picked and that a tool passed its test
  question once. The pick is part of a settings backup; the passed check is not,
  because it is only true of this Mac's install and sign-in.

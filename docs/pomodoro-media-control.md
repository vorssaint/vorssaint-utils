# Pomodoro media control

In **Settings → Dynamic Island → Timer**, two optional switches extend the
existing Pomodoro timer. Both are off by default and are included in settings
backups. Ordinary timers and the stopwatch are unaffected.

- **Advance Pomodoro automatically** starts the next focus or break phase when
  the current one ends. Each transition plays one chime if timer sounds are on.
  The cycle still ends after the configured number of focus sessions.
- **Control media during Pomodoro** requests playback when focus starts or
  resumes, and pauses playback when a focus session ends, a break starts, or
  you pause or cancel the Pomodoro.

Open your preferred media player and start a track once, then start a Pomodoro
from the island. The controls follow the current macOS media session, like the
keyboard's media controls, but send explicit play and pause commands. They do
not select a playlist, restart a track, or control every player at once. If the
system switches to a video or another player, the next timer action controls
that session instead. An already paused player stays paused on a pause request.

Manual playback changes between timer actions are left alone. Turning media
control off cancels pending requests and leaves playback as it is. It does not
restore an earlier player's state. Turning it on takes effect at the next timer
action, rather than immediately interrupting playback.

Sleep and locking suspend pending commands. After waking or unlocking, an
overdue phase finishes and waits for you to start the next phase; it does not
automatically play media or count multiple unseen sessions. A phase that still
has time remaining continues its countdown without replaying a media command.
Quitting the app clears the session, as before.

Media control depends on the player's macOS integration. A warning beside the
session count means a command could not be sent; hover over it for guidance.
The timer keeps running. There is no toggle fallback or automatic retry, and
the app does not open a player when no running media session is available.

# Shortcuts actions

Vorssaint can offer actions to the Shortcuts app, so a shortcut can switch a feature, start Keep Awake, set the volume of one app or start a timer. They are off until you allow them: turn on **Allow Shortcuts to run Vorssaint actions** in Settings under Advanced.

| Action | What it does |
|---|---|
| Run Quick Toggle | Runs one quick toggle from the panel: dark mode, lock screen, display off or screen saver. Emptying the Trash and ejecting disks are not offered. |
| Turn Vorssaint Feature On or Off | Sets an installed feature on, off or to its opposite, like its switch in Settings. Toggle reads the state when the action runs, so the same shortcut flips it back. |
| Is Vorssaint Feature On | Returns whether an installed feature is switched on. |
| Keep Mac Awake | Starts a Keep Awake session for one of the panel's durations. |
| Is Keep Awake On | Returns whether a Keep Awake session is running. |
| Set App Volume | Sets the volume of an app listed in the mixer, from 0 to 100. |
| Start Timer, Pause or Resume Timer, Stop Timer | Drive the Dynamic Island timer, Pomodoro and stopwatch. |

Pickers only list what is installed, and they are built when Shortcuts asks, so uninstalling a feature in the features page takes it off the list. "Turn Vorssaint Feature On or Off" offers every installed feature that has exactly one switch. An action whose feature is uninstalled, or one run while the option above is off, stops with a message instead of doing nothing.

The action names follow the language of macOS, not the language chosen in Vorssaint.

## Building from source

Two things are needed for the actions to appear and run:

- **Xcode.** The metadata Shortcuts reads is written by `appintentsmetadataprocessor`, which ships with Xcode and not with the Command Line Tools. `build.sh` runs it when it is found and says so when it is skipped; the app builds either way, without the actions.
- **A Team ID in the signature.** macOS refuses to connect Shortcuts to an app signed ad hoc or with a self-signed identity: the actions show up and fail after about 30 seconds with `LinkDaemon.ProcessRegistry.Errors`. Releases are signed with a Developer ID, so they work. To try a local build, sign the installed app, and the helper and library inside it, with an Apple Development certificate (a free Apple ID can create one in Xcode under Settings, Accounts, Manage Certificates), then quit and reopen it. If `codesign` answers `errSecInternalComponent`, the Apple Worldwide Developer Relations G3 intermediate certificate is missing from the keychain.

A reason for a failure is written to the log under the process `linkd`:

```sh
/usr/bin/log stream --predicate 'process == "linkd"'
```

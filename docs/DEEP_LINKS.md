# Deep links

Vorssaint registers the `vorssaint://` URL scheme. A deep link names one row of the Command Bar catalog by its stable ID, and Vorssaint runs it the same way it runs that row's own global shortcut. Raycast commands, Shortcuts, scripts and other apps use these links to reach any installed tool.

Any local app can send these links. Treat every ID on this page as public.

## Link format

```url
vorssaint://run/<id>?v=<number>
```

| Part | Meaning |
| --- | --- |
| `vorssaint` | The scheme. Fixed. |
| `run` | The verb. `run` is the only one. |
| `<id>` | The stable key of a catalog row. Case sensitive. |
| `v` | Optional integer argument, for rows that take one. Clamped to the row's own range. |

Rules:

- The scheme and the verb are case insensitive. The ID keeps its case.
- An unknown ID, or an ID whose feature is not installed, makes Vorssaint beep. Nothing runs. A Settings page that is hidden because its feature is off beeps the same way.
- A row that would confirm a destructive step still asks, in the bar itself.
- A row whose setup is missing opens the Settings page where that row lives. A row missing a system permission runs anyway, which is what triggers the system prompt.

Test a link from Terminal:

```sh
open 'vorssaint://run/action.colorPicker'
```

## Actions

These are the `action.` IDs. They work only while their feature is installed.

### Screen tools

| ID | What it runs | `v` |
| --- | --- | --- |
| `action.screenshot` | The screenshot selector | |
| `action.scrollingScreenshot` | Scrolling capture for long pages | |
| `action.screenRecorder` | The screen recording selector | |
| `action.recentCaptures` | Recent screenshots and recordings | |
| `action.screenOCR` | Copy text from a screen area | |
| `action.colorPicker` | Pick a color from the screen | |

### Clipboard, files and text

| ID | What it runs | `v` |
| --- | --- | --- |
| `action.clipboardWindow` | Clipboard history | |
| `action.snippetLibrary` | The snippet library menu | |
| `action.pastePlain` | Paste the clipboard as plain text | |
| `action.cleanURL` | Strip tracking parameters from the copied URL | |
| `action.clipboardClearRecent` | Clear recent clipboard history | |
| `action.scratchpad` | Scratchpad pads | |
| `action.shelf` | The shelf | |

### Sound and display

| ID | What it runs | `v` |
| --- | --- | --- |
| `action.volume` | Set output volume | `0`–`100` |
| `action.brightness` | Set display brightness | `0`–`100` |
| `action.soundMute` | Mute or unmute output | |
| `action.micMute` | Mute or unmute every microphone | |
| `action.displayOff` | Turn displays off | |
| `action.screenSaver` | Start the screen saver | |
| `action.lockScreen` | Lock the screen | |

### Keep awake

`action.keepAwake` only takes the following preset durations: `15`, `30`, `60`, `120`, `240`, `480` minutes. All other values default to indefinite.

| ID | What it runs | `v` |
| --- | --- | --- |
| `action.keepAwake` | Toggle keep awake | Minutes: `15` \| `30` \| `60` \| `120` \| `240` \| `480` |
| `action.keepAwake.30` | Keep awake for 30 minutes | |
| `action.keepAwake.60` | Keep awake for 1 hour | |
| `action.keepAwake.120` | Keep awake for 2 hours | |

### System toggles

| ID | What it runs |
| --- | --- |
| `action.darkMode` | Switch light and dark mode |
| `action.hiddenFiles` | Show or hide hidden files |
| `action.desktopIcons` | Show or hide desktop icons |
| `action.ejectDisks` | Eject every disk |
| `action.emptyTrash` | Empty the Trash. Confirms first. |
| `action.wifi` | Toggle Wi-Fi |
| `action.cleaningMode` | Lock keyboard and black out displays |
| `action.cameraPreview` | Open the camera preview |

### Windows

`action.layout.<direction>` snaps or moves the active window. `<direction>` is a window layout action name:

`leftHalf`, `rightHalf`, `topHalf`, `bottomHalf`, `leftThird`, `centerThird`, `rightThird`, `leftTwoThirds`, `rightTwoThirds`, `topLeftSixth`, `topCenterSixth`, `topRightSixth`, `bottomLeftSixth`, `bottomCenterSixth`, `bottomRightSixth`, `topLeft`, `topRight`, `bottomLeft`, `bottomRight`, `maximize`, `marginMaximize`, `fullScreen`, `center`, `previousDisplay`, `nextDisplay`, `restore`

Example:

```sh
open 'vorssaint://run/action.layout.leftHalf'
```

### Power

`action.power.<action>` with one of: `sleep`, `restart`, `shutDown`, `logOut`.

### Apps and maintenance

| ID | What it runs |
| --- | --- |
| `action.appUpdates` | The app updates list |
| `action.cleaner` | The cleaner scan |
| `action.uninstaller` | The uninstaller |
| `action.quickLauncher` | The quick panel |
| `action.openSettings` | Vorssaint Settings |
| `action.feedback.bug` | The bug report form |
| `action.feedback.feature` | The feature idea form |
| `action.restartApp` | Quit and relaunch Vorssaint |

## Quick toggles

Rows named `toggle.<feature>` flip a feature that has exactly one switch, for example `toggle.smoothScroll`. A feature with several switches has no single toggle row; scroll direction is split instead into `toggle.scrollInverter.vertical` and `toggle.scrollInverter.horizontal`, and mouse button shortcuts are split into `toggle.mouseButtonShortcuts` and `toggle.mouseButtonShortcuts.spacesGesture`.

## Settings pages

`settings.<page>` opens one page of Vorssaint Settings. Page IDs:

`settings.general`, `settings.features`, `settings.energy`, `settings.monitor`, `settings.mouse`, `settings.switcher`, `settings.keyDebounce`, `settings.superKey`, `settings.cutPaste`, `settings.autoQuit`, `settings.quitProtection`, `settings.cleaner`, `settings.uninstaller`, `settings.urlCleaner`, `settings.homebrew`, `settings.appUpdates`, `settings.media`, `settings.clipboard`, `settings.windowLayout`, `settings.shelf`, `settings.quickTools`, `settings.textSnippets`, `settings.screenshot`, `settings.radialMenu`, `settings.commandBar`, `settings.killProcess`, `settings.shortcuts`, `settings.advanced`, `settings.about`, `settings.releaseNotes`, `settings.support`

Example:

```sh
open 'vorssaint://run/settings.windowLayout'
```

## Sound outputs

`action.soundOutput.<uid>` sends output audio to one device. The UID belongs to a connected CoreAudio device, so this family depends on your hardware. The bar's sound output rows show which devices qualify.

## Rows without fixed addresses

Everything else the bar ranks also answers to its stable key, but those keys are not fixed: your snippets, saved destinations, emoji, running apps, windows and clipboard items name themselves from your content. The `action.openURL` row exists only while a web address is typed into the bar. None of these can be addressed reliably from outside.

## Keeping this page true

`./build.sh --test` reads `CommandBarCatalog.swift` and fails when a fixed `action.` or `toggle.` ID ships without appearing on this page. It also fails when a Settings page is missing from the list above. Add new IDs here in the same commit as the code.

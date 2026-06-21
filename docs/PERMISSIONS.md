# Permissions

Vorssaint asks for a macOS permission only when a feature actually needs it, and every one of them is optional. Skip a permission and the feature that leans on it simply stays off or runs in a lighter mode, while the rest of the app carries on as normal. The first run walks you through each grant, and you can come back to it anytime from Settings under About.

You can review or change every grant in System Settings, under Privacy and Security, and reset them whenever you like. The [troubleshooting guide](TROUBLESHOOTING.md) shows how.

| Permission | Optional | Powers |
|---|---|---|
| Accessibility | Yes | Scroll direction, the app and window switcher, Dock Preview, Finder cut and paste, quit on close |
| Screen Recording | Yes | Window titles and thumbnails in the switcher and Dock Preview |
| System Audio Recording | Yes | Per app volume and output routing in the mixer |
| Notifications | Yes | Keep awake, battery and update alerts |
| Full Disk Access | Yes | A deeper uninstaller scan |
| Administrator (one time) | Yes | Password free closed lid toggling |
| Automation | Yes | Finder cut and paste, moving leftovers to the Trash and Homebrew Terminal handoff |

## Accessibility

**Why it comes up.** macOS keeps control of the keyboard and mouse, along with the ability to read other apps' windows, behind the Accessibility permission.

**What uses it.**

- **Scroll direction inverter**, which flips the mouse wheel.
- **App and window switcher**, which captures the switcher hotkey and reads the window list.
- **Dock Preview**, which reads Dock items and brings windows forward for a temporary peek.
- **Finder cut and paste**, which steps in on ⌘X and ⌘V while Finder is in front.
- **Quit on close**, which spots when an app's last window goes away.

**If you say no.** These features stay off. Vorssaint sees the moment you grant the permission and brings them to life with no relaunch.

**Optional.** Yes. macOS shows its prompt the first time a feature needs it, and you can also grant it later in System Settings, under Privacy and Security, Accessibility.

## Screen Recording

**Why it comes up.** On macOS, reading other windows' titles and grabbing their thumbnails counts as screen recording.

**What uses it.** The window switcher and Dock Preview, for live thumbnails and window titles.

**If you say no.** The switcher still works and falls back to app icons instead of live thumbnails and titles. Dock Preview stays unavailable. Nothing on your screen is ever written to disk or sent anywhere, since the access only feeds local previews.

**Optional.** Yes.

## System Audio Recording

**Why it comes up.** macOS gates app audio taps behind the System Audio Recording permission.

**What uses it.** The Volume Mixer, when you lower, boost or route an app to a specific output device.

**If you say no.** Apps keep using normal system audio. The mixer cannot apply per app volume or output routing until the permission is granted.

**Optional.** Yes. Audio is processed in memory for the mixer and is never recorded to disk or sent anywhere.

## Notifications

**Why it comes up.** So the app can post the odd alert when something you set up actually happens.

**What uses it.**

- **Keep awake**, with a note when a keep awake timer finishes.
- **Battery**, with the battery protection alerts.
- **Updates**, with a one time note when a new version shows up, and only while automatic update checks are on.

**If you say no.** Vorssaint runs without a peep, and the same information is still right there in the panel and in Settings.

**Optional.** Yes.

## Full Disk Access

**Why it comes up.** The uninstaller hunts down the files an app leaves behind, like caches, preferences and logs. Some of those spots are protected by macOS and only open up with Full Disk Access.

**What uses it.** The uninstaller, for a deeper scan.

**If you say no.** The uninstaller still works and scans the places it can reach. It just might not surface files tucked away in protected folders.

**Optional.** Yes. There is no pop up for Full Disk Access. You add Vorssaint in System Settings, under Privacy and Security, Full Disk Access, and Vorssaint opens that pane for you when the feature calls for it.

## Administrator, one time and optional

**Why it comes up.** Keeping the Mac awake with the lid shut relies on `pmset disablesleep`, which needs administrator rights. So it does not have to ask for your password every time you flip closed lid mode, Vorssaint can install a tightly scoped `sudoers` rule that allows only that single command.

**What uses it.** Closed lid keep awake.

**If you say no.** Closed lid mode still works. macOS just asks for your administrator password each time you turn it on or off.

**Optional.** Yes, and it is a one time choice. The rule is limited to `pmset disablesleep` and nothing else, and it goes away on its own when you uninstall Vorssaint or reset things from Settings under Advanced.

## Automation

**Why it comes up.** A few features ask Finder or Terminal to do something for you, and macOS guards that with an Automation prompt the first time it happens.

**What uses it.**

- **Finder cut and paste**, which reads the current Finder selection and the destination folder, then moves the files.
- **Uninstaller**, which moves leftover files to the Trash.
- **Homebrew manager**, which can open Terminal with the exact Homebrew install or setup command when the app should not collect a password itself.

**If you say no.** Those Finder or Terminal handoff steps will not go through. You can switch Automation back on in System Settings, under Privacy and Security, Automation.

**Optional.** Yes.

## Resetting permissions

To clear what you have granted and start over, follow the reset steps in the [troubleshooting guide](TROUBLESHOOTING.md#resetting-permissions), or use Settings under Advanced, which clears every permission, the login item and the closed lid rule while leaving the app in place.

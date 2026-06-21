# Troubleshooting

A quick guide to the snags people hit most. If none of it helps, jump to [reporting a useful bug](#reporting-a-useful-bug) at the end.

The permission and uninstall commands below all point at Vorssaint's bundle identifier, `com.vorssaint.utils`.

## The app will not open

Official Vorssaint builds are signed with an Apple Developer ID and notarized, so they open with no security warning.

If you built the app yourself or grabbed an unofficial copy, macOS Gatekeeper may stop it on the first launch. To open it anyway, do one of these.

1. Right click, or Control click, Vorssaint in Applications, choose Open, and confirm.
2. Or open System Settings, Privacy and Security, find the note about Vorssaint being blocked, and click Open Anyway.

Vorssaint lives in the menu bar, so once it starts, look for its icon up there rather than in the Dock.

## A feature does nothing, or a permission will not stick

Most features lean on a macOS permission, which the [permissions guide](PERMISSIONS.md) lays out. When something does nothing, walk through this.

1. Open System Settings, Privacy and Security.
2. Find the permission the feature needs and make sure Vorssaint is listed and switched on.
3. If it is listed and still quiet, toggle it off and back on.

Vorssaint keeps an eye on Accessibility and Screen Recording, so features tend to wake up within a second or two of a grant, with no relaunch needed.

### Accessibility

This one powers the scroll direction inverter, the switcher, Dock Preview, Finder cut and paste and quit on close. If they do nothing, open System Settings, Privacy and Security, Accessibility and confirm Vorssaint is switched on. If you rebuilt the app yourself, its signature can shift and macOS may treat it as a different app, so remove the old Vorssaint entry with the minus button and grant it again. For steady local signing while you develop, see the [contributing guide](../CONTRIBUTING.md).

### Screen Recording

This one feeds window titles and thumbnails in the switcher and Dock Preview. If previews fall back to app icons or Dock Preview stays unavailable, switch Vorssaint on in System Settings, Privacy and Security, Screen Recording. macOS may ask you to quit and reopen the app after you grant it.

### System Audio Recording

This one powers per app volume and output routing in the mixer. If the mixer says it needs permission, open System Settings, Privacy and Security, Screen and System Audio Recording, and switch Vorssaint on. Audio is processed only for the local mixer.

### Automation

Finder cut and paste, the uninstaller and Homebrew's Terminal handoff may ask for Automation. If a Finder move or Terminal handoff does nothing after a denial, open System Settings, Privacy and Security, Automation, and allow Vorssaint for the app it needs to control.

## Resetting permissions

To wipe Vorssaint's granted permissions and let macOS ask again from scratch, pick one of these.

- **From the app.** Settings under Advanced has a reset that clears every permission you granted, the login item and the closed lid rule, while leaving the app installed.
- **From Terminal.** Reset all of Vorssaint's privacy permissions at once.

  ```sh
  tccutil reset All com.vorssaint.utils
  ```

  Or reset a single kind, for example.

  ```sh
  tccutil reset Accessibility com.vorssaint.utils
  tccutil reset ScreenCapture com.vorssaint.utils
  ```

## Clean uninstall

The bundled script takes out everything Vorssaint added, the app itself, its preferences and saved state, the login item, its privacy grants, and the optional closed lid `sudoers` rule.

```sh
./Tools/uninstall.sh
```

Run it from a clone of the repository, or download the single script from the repo. Would you rather do it by hand? Quit Vorssaint, drag it from Applications to the Trash, then clear its permissions.

```sh
tccutil reset All com.vorssaint.utils
```

## Reporting a useful bug

A clear report gets fixed faster. Try to include the following.

- **What you did**, what you expected, and what actually happened.
- **Your versions**, both the Vorssaint version from Settings under About and your macOS version.
- **Steps to reproduce**, as specific as you can make them.
- **A screenshot or short screen recording**, when the issue is something you can see.

If you have a build from source, the self test prints a quick health summary that is handy to paste in.

```sh
./build/Vorssaint --selftest
```

Open a report from the [new issue](https://github.com/vorssaint/vorssaint-utils/issues/new/choose) page, and see [support](../SUPPORT.md) for every way to get help.

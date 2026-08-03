# Privacy

Vorssaint is built to be local-first. Core features run on your Mac, and the app has no Vorssaint account, cloud dashboard or backend.

## The short version

- **No account.** There is nothing to sign up for and nobody to log in as.
- **No subscription.** The app is free and stays free, with nothing held back behind a paid tier.
- **No telemetry.** Vorssaint gathers no usage stats, no crash reports, no device identifiers and no diagnostics.
- **No Vorssaint analytics or tracking.** There are no analytics kits, no ad networks and no third party tracking anywhere in the app.
- **No data selling.** There is nothing to sell, because none of your information is collected to begin with.
- **Your settings stay put.** Preferences and saved state live in the app's own local storage on your Mac and are never uploaded.

## What it reads, and where that stays

Everything Vorssaint shows you, from the CPU and memory load to the temperatures, the battery details, the network rates, the window list, per app volume and the files on the Shelf, is read locally through native macOS APIs and shown to you right there. None of it is sent anywhere, logged remotely or shared.

Clipboard history, including the images and files you copy, lives in the app's local storage on your Mac and never leaves it. Copy text from screen recognizes the text entirely on device with Apple's Vision framework, and the temporary capture is deleted as soon as the text is read.

When a feature needs a macOS permission such as Accessibility or Screen Recording, that access is used only for the local feature it belongs to. The [permissions guide](PERMISSIONS.md) breaks down each one.

## Network connections

Vorssaint opens only a few kinds of connection, and each one belongs to a visible feature.

1. **The update check, automatic and easy to switch off.** So it can tell you when a newer version exists, Vorssaint asks GitHub's public releases API at `api.github.com` for this project's latest release. The request carries only a standard user agent with the app name and its version, and no account, identifier or usage data go along with it. It runs a short while after launch and now and then while the app is open. You can turn it off in Settings under About, and once it is off no update requests are made. If you choose to install an offered update, the disk image comes from GitHub.

2. **The internet speed test, only when you ask.** The optional speed test in the Network section reaches Cloudflare's public speed endpoints at `speed.cloudflare.com` to measure latency and your download and upload throughput. This happens only when you start a test yourself, and never on its own.

3. **Homebrew actions, only when you use the Homebrew manager.** Search, install and uninstall actions run the local `brew` command, which may contact Homebrew, GitHub and package vendor hosts to search metadata or download files. Popularity badges use Homebrew's public aggregate analytics JSON from `formulae.brew.sh`. Vorssaint does not send its own analytics, capture passwords or run `brew` as root.

4. **The app update check, only with App updates switched on.** Finding out which apps are behind has two halves. The Homebrew half runs the local `brew` command, exactly as above. The App Store half asks Apple's public lookup service at `itunes.apple.com` which version is current, and to do that it sends the bundle identifiers of the apps you installed from the App Store, plus your Mac's region. Nothing else about those apps leaves the Mac, and no account or identifier of yours goes along. The check runs when you open the list or press Check now, and on a schedule only if you set one; the switch "Include apps from the App Store" under App updates turns this half off entirely, and then the whole check stays on your Mac.

That is the entire list. There are no Vorssaint servers, no hidden beacons and no background uploads.

## Changes to this document

This page describes how the current version of Vorssaint behaves. If the app's behavior around privacy ever changes, this page changes with it.

## Questions

If anything here is unclear, open a question in [GitHub issues](https://github.com/vorssaint/vorssaint-utils/issues), or have a look at [support](../SUPPORT.md).

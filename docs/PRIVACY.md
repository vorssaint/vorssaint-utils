# Privacy

Vorssaint is built to be local-first. Core features run on your Mac, and the app has no Vorssaint account or cloud dashboard. Its Vorssaint-operated services are limited to temporary screenshot links and feedback you explicitly choose to send.

## The short version

- **No account.** There is nothing to sign up for and nobody to log in as.
- **No subscription.** The app is free and stays free, with nothing held back behind a paid tier.
- **No automatic telemetry.** Vorssaint gathers no usage stats, crash reports or device identifiers. Feedback sends technical details only when you select them after seeing the complete list.
- **No Vorssaint analytics or tracking.** There are no analytics kits, no ad networks and no third party tracking anywhere in the app.
- **No data selling.** Vorssaint never sells personal information or shared screenshots and recordings.
- **Your settings stay put.** Preferences and saved state live in the app's own local storage on your Mac and are never uploaded.

## What it reads, and where that stays

Everything Vorssaint shows you, from the CPU and memory load to the temperatures, the battery details, the network rates, the window list, per app volume and the files on the Shelf, is read locally through native macOS APIs and shown to you right there. None of it is sent anywhere, logged remotely or shared.

Clipboard history, including the images and files you copy, lives in the app's local storage on your Mac and never leaves it. Copy text from screen recognizes the text entirely on device with Apple's Vision framework, and the temporary capture is deleted as soon as the text is read. Automatic clearing, when you switch it on, only empties the system clipboard on this Mac: nothing is sent anywhere, and items already saved to your history are left as they are.

Recent Captures keeps up to 12 screenshots, within a 256 MB limit, in the app's private local cache so you can reopen them. Recordings are not duplicated: only their existing path and a small thumbnail are kept. Clear removes that history and its cached images. When a screenshot is copied as a file, its private local PNG is kept temporarily so other apps can finish reading it, then cleaned on later copies once it is older than 24 hours or earlier when the bounded cache fills. None of these local caches is uploaded automatically.

When a feature needs a macOS permission such as Accessibility, Screen Recording or Microphone, that access is used only for the feature it belongs to. Captured content leaves the Mac only when you explicitly create a temporary link. The [permissions guide](PERMISSIONS.md) breaks down each permission.

## Network connections

Vorssaint opens only a few kinds of connection, and each one belongs to a visible feature.

1. **The update check, automatic and easy to switch off.** So it can tell you when a newer version exists, Vorssaint asks GitHub's public releases API at `api.github.com` for this project's latest release. The request carries only a standard user agent with the app name and its version, and no account, identifier or usage data go along with it. It runs a short while after launch and now and then while the app is open. You can turn it off in Settings under About, and once it is off no update requests are made. If you choose to install an offered update, the disk image comes from GitHub.

2. **The internet speed test, only when you ask.** The optional speed test in the Network section reaches Cloudflare's public speed endpoints at `speed.cloudflare.com` to measure latency and your download and upload throughput. This happens only when you start a test yourself, and never on its own.

3. **Homebrew actions, only when you use the Homebrew manager.** Search, install and uninstall actions run the local `brew` command, which may contact Homebrew, GitHub and package vendor hosts to search metadata or download files. Popularity badges use Homebrew's public aggregate analytics JSON from `formulae.brew.sh`. Vorssaint does not send its own analytics, capture passwords or run `brew` as root.

4. **The app update check, only with App updates switched on.** Finding out which apps are behind uses the sources you leave enabled. The Homebrew source runs the local `brew` command, exactly as above. The App Store source asks Apple's public lookup service at `itunes.apple.com` which version is current, and to do that it sends the bundle identifiers of the apps you installed from the App Store, plus your Mac's region. The Online source downloads the complete public app catalog from `formulae.brew.sh`; it does not send the names, paths or bundle identifiers of apps on your Mac. No account or identifier of yours goes along with either request. The check runs when you open the list or press Check now, and on a schedule only if you set one; the three source switches under App updates control these connections independently. With the App Store source off, no app bundle identifiers are sent to Apple, and with the Online source off, the public catalog is not requested.

5. **Temporary screenshot links, only when you choose to create one.** Creating a link sends the rendered PNG and your chosen expiration of 1, 6 or 24 hours to the Vorssaint service over HTTPS. It does not send your name, account, device identifier or MAC address. On your Mac, the feature keeps only the link, expiration and private deletion token while the link is active, so you can copy it or delete it early. The service holds your public IP address in memory for no more than 24 hours to prevent abuse, while network providers may process normal HTTPS request data under their own policies.

The uploaded PNG is decoded and rebuilt without embedded metadata. The image and its link metadata are permanently deleted when the link expires or you delete it, and the service does not create screenshot backups. Private moderation stores the active link, not another uploaded image, and removes that message when the link ends. Anyone with the link can view, download, save or redistribute the image, and active links are available to the service operator for abuse moderation. Share only with people you trust.

6. **Temporary recording links, only when you choose to create one.** The finished video is compressed on your Mac and sent over HTTPS with the audio you kept and your chosen expiration of 1 or 6 hours. It does not send your name, account or device identifier. On your Mac, the feature keeps only the link, expiration and private deletion token while the link is active. The service temporarily processes your public IP address to prevent abuse, while network providers may process normal HTTPS request data under their own policies.

The service validates and rebuilds the MP4 without its original metadata. The video and link metadata are permanently deleted when the link expires or you delete it, and the service does not create backups. Anyone with the link can view, download, save or redistribute the video, and active links are available to the service operator for abuse moderation. Share only with people you trust.

7. **Feedback, only when you press Send.** A submission sends the category you choose and the text you type. The optional technical details switch adds only the app version and build, macOS version, Mac model and app language shown in the form. It never includes your name, account, email address, device identifier, logs, screenshots, files or clipboard content. Your public IP address is processed temporarily in memory for rate limiting and is not attached to the feedback.

Feedback is delivered to private support channels visible to the service owner. After delivery, the text and any technical details you selected remain there until the service owner deletes them. The temporary delivery copy is then deleted; if delivery never succeeds, that copy is permanently deleted after 7 days. No contact information is sent, so feedback cannot receive a direct reply.

That is the entire list. There are no hidden beacons or background uploads.

## Changes to this document

This page describes how the current version of Vorssaint behaves. If the app's behavior around privacy ever changes, this page changes with it.

## Questions

If anything here is unclear, open a question in [GitHub issues](https://github.com/vorssaintapp/vorssaint-utils/issues), or have a look at [support](../SUPPORT.md).

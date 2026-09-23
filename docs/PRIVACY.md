# Privacy

Vorssaint is built to be local-first. Core features run on your Mac, and the app has no Vorssaint account or cloud dashboard. Its Vorssaint-operated services are limited to temporary screenshot and recording links and feedback you explicitly choose to send.

## The short version

- **No account.** There is nothing to sign up for and nobody to log in as.
- **No subscription.** The app is free and stays free, with nothing held back behind a paid tier.
- **No automatic telemetry.** Vorssaint gathers no usage stats, crash reports or device identifiers. Feedback sends technical details only when you select them after seeing the complete list.
- **No Vorssaint analytics or tracking.** There are no analytics kits, no ad networks and no third party tracking anywhere in the app.
- **No data selling.** Vorssaint never sells personal information or shared screenshots and recordings.
- **Your settings stay put.** Preferences and saved state live in the app's own local storage on your Mac and are never uploaded.

## What it reads, and where that stays

Everything Vorssaint shows you, from the CPU and memory load to the temperatures, the battery details, the network rates, the window list, per app volume and the files on the Shelf, is read locally through native macOS APIs and shown to you right there. Those readings are not uploaded automatically. Optional online lyric lookup sends only the song metadata described below.

Clipboard history, including the images and files you copy, lives in the app's local storage on your Mac and never leaves it. Copy text from screen recognizes the text entirely on device with Apple's Vision framework, and the temporary capture is deleted as soon as the text is read. Automatic clearing, when you switch it on, only empties the system clipboard on this Mac: nothing is sent anywhere, and items already saved to your history are left as they are.

Recent Captures keeps up to 12 screenshots, within a 256 MB limit, in the app's private local cache so you can reopen them. Recordings are not duplicated: only their existing path and a small thumbnail are kept. Clear removes that history and its cached images. When a screenshot is copied as a file, its private local PNG is kept temporarily so other apps can finish reading it, then cleaned on later copies once it is older than 24 hours or earlier when the bounded cache fills. None of these local caches is uploaded automatically.

When a feature needs a macOS permission such as Accessibility, Screen Recording or Microphone, that access is used only for the feature it belongs to. Captured content leaves the Mac only when you explicitly create a temporary link. The [permissions guide](PERMISSIONS.md) breaks down each permission.

## Optional notch features

Calendar access is requested only from the permission button. The notch reads upcoming events through the system calendar service; it does not create, change or delete events. Event text stays in memory and is cleared when the notch stops or the Mac locks.

Notification mirroring uses Accessibility to read new visible system banners. It does not read the notification database or message stores and does not open notification history. The session inbox shows up to 50 notices; its temporary state is kept in memory and cleared on lock or disable. Clicking a notice invokes its original native action while valid. If that action is no longer available, the user’s click can instead open the previously identified source application. A separate, disabled-by-default option dismisses the original system banner about a second after the notch accepts the notice for display, allowing short sounds to finish while longer sounds may still be cut off; it revalidates that specific notice and never clears a notification group. Notices hidden by the system are not imported.

The camera mirror starts only after an explicit action. Its frames go to the local preview and are not saved or uploaded by that feature. Closing the preview, hiding its section, disabling it or locking the Mac stops capture. Visible notch content, including the camera, appointments and notifications, can appear in screenshots or recordings when you leave notch capture visibility on.

Timers and focus sessions are kept only for the current app session. Accessory alerts use local system readings. Download monitoring is limited to a folder you choose; its access bookmark stays on this Mac and is excluded from settings exports. File compression and conversion run locally, preserve originals, and save only to the destination you choose.

Imported lyrics and timing adjustments are kept for only the current song in memory. Opening a different section cancels lookup work without losing that song's imported text. Observing a different song or disabling the feature clears it. The upcoming music queue comes from the local player and is not uploaded.

The live equalizer is off until you turn it on. When on, it reads the audio output of the current player through a Core Audio process tap on this Mac, limited to the audio processes that player is responsible for, which is how a browser playing through a helper process is heard, and keeps only a fraction of a second of samples in memory to compute seven levels for the island's bars. It does not record, store or send audio. macOS asks for system audio recording permission the first time; if it is declined, the tap only delivers silence, so the bars return to their usual synthetic motion and the tap is released. It is also released when playback stops, when the player moves its sound to another process, and when the option is turned off or the feature is uninstalled from the features hub, where the permission it uses is listed; a change of output device rebuilds it in place.

The AI Agents section is off until you turn it on. While it is on, it reads the session logs Claude Code and Codex already keep in your home folder, under `~/.claude/projects` (or `~/.config/claude/projects`) and `~/.codex`, where they are, as they grow. Only token counts, model names, times, session identifiers and the name of the folder each agent worked in are taken from them; prompts, replies, tool output and files are never decoded into anything that is kept. The plan name comes from the account profile Claude Code caches in `~/.claude.json`, which is parsed in memory and of which only the plan fields and the organization it signs in to are kept. Claude's plan limits come from the history the Claude app keeps in `~/Library/Application Support/Claude/plan-usage-history.json`, of which only the time, the account each reading belongs to and the percentage used of each window are kept; no sign-in, keychain item or token is ever used. With Claude turned on, the section's settings also read that history to show when the Claude app last saved its limits, even before the section is turned on, and keep only that time. An agent turned off in the section's settings is not read at all. Everything is held in memory, kept while the display sleeps or the Mac is locked, rebuilt on the next launch and dropped when the section is turned off. Costs are computed on your Mac from a public price list that ships with the app and can be kept current, as described below.

Playback controls prefer active playback, including a browser video when a music app is paused, and prefer music apps when playback activity is equal. When a player needs Automation for directed controls, Vorssaint reads only the playback commands declared in that app's local scripting definition. Permission is requested from an explicit button; granting it does not replay an earlier action. Commands address the selected running process and recheck the displayed playback before delivery. Players without compatible controls can still be opened from the island. No playback data is uploaded by these controls.

## Network connections

Vorssaint opens only a few kinds of connection, and each one belongs to a visible feature.

1. **The update check, automatic and easy to switch off.** So it can tell you when a newer version exists, Vorssaint asks GitHub's public releases API at `api.github.com` for this project's latest release. The request carries only a standard user agent with the app name and its version, and no account, identifier or usage data go along with it. It runs a short while after launch and now and then while the app is open. You can turn it off in Settings under About, and once it is off no update requests are made. If you choose to install an offered update, the disk image comes from GitHub.

2. **The internet speed test, only when you ask.** The optional speed test in the Network section reaches Cloudflare's public speed endpoints at `speed.cloudflare.com` to measure latency and your download and upload throughput. This happens only when you start a test yourself, and never on its own.

3. **Homebrew actions, only when you use the Homebrew manager.** Search, install and uninstall actions run the local `brew` command, which may contact Homebrew, GitHub and package vendor hosts to search metadata or download files. Popularity badges use Homebrew's public aggregate analytics JSON from `formulae.brew.sh`. Vorssaint does not send its own analytics, capture passwords or run `brew` as root.

4. **The app update check, only with App updates switched on.** Finding out which apps are behind uses the sources you leave enabled. The Homebrew source runs the local `brew` command, exactly as above. The App Store source sends store identifiers to `uclient-api.itunes.apple.com`, falling back to bundle identifiers at `itunes.apple.com`, along with your Mac's region, to find the current Mac version.

The Online source checks supported public update addresses declared inside installed apps. These requests go to the app developer's server or its release hosting service, including `github.com` and redirected download hosts. The server receives your public IP address and the requested URL, which can reveal which app is being checked. Vorssaint does not add your app inventory, local paths, account details or device identifiers to these requests, and does not use stored cookies or credentials. The declared URL, including any query parameters it already contains, is sent as provided by the app. These services may process ordinary request data under their own privacy policies.

The Online source also downloads the complete public app catalog from `formulae.brew.sh` as a fallback. That catalog request does not send the names, paths or bundle identifiers of apps on your Mac. Version comparisons happen locally; updates from developer feeds are installed by the app's own updater after you open it.

The check runs when you open the list or press Check now, and on a schedule only if you set one. The three source switches under App updates control these connections independently. Turning off the App Store source stops its store and bundle identifier lookups. Turning off the Online source stops both developer feed requests and public catalog requests on subsequent checks.

5. **Temporary screenshot links, only when you choose to create one.** Creating a link sends the rendered PNG and your chosen expiration of 1, 6 or 24 hours to the Vorssaint service over HTTPS. It does not send your name, account, device identifier or MAC address. On your Mac, the feature keeps only the link, expiration and private deletion token while the link is active, so you can copy it or delete it early. The service holds your public IP address in memory for no more than 24 hours to prevent abuse, while network providers may process normal HTTPS request data under their own policies.

The uploaded PNG is decoded and rebuilt without embedded metadata. The image and its link metadata are permanently deleted when the link expires or you delete it, and the service does not create screenshot backups. Private moderation stores the active link, not another uploaded image, and removes that message when the link ends. Anyone with the link can view, download, save or redistribute the image, and active links are available to the service operator for abuse moderation. Share only with people you trust.

6. **Temporary recording links, only when you choose to create one.** The finished video is compressed on your Mac and sent over HTTPS with the audio you kept and your chosen expiration of 1 or 6 hours. It does not send your name, account or device identifier. On your Mac, the feature keeps only the link, expiration and private deletion token while the link is active. The service temporarily processes your public IP address to prevent abuse, while network providers may process normal HTTPS request data under their own policies.

The service validates and rebuilds the MP4 without its original metadata. The video and link metadata are permanently deleted when the link expires or you delete it, and the service does not create backups. Anyone with the link can view, download, save or redistribute the video, and active links are available to the service operator for abuse moderation. Share only with people you trust.

7. **Feedback, only when you press Send.** A submission sends the category you choose and the text you type. The optional technical details switch adds only the app version and build, macOS version, Mac model and app language shown in the form. It never includes your name, account, email address, device identifier, logs, screenshots, files or clipboard content. Your public IP address is processed temporarily in memory for rate limiting and is not attached to the feedback.

Feedback is delivered to private support channels visible to the service owner. After delivery, the text and any technical details you selected remain there until the service owner deletes them. The temporary delivery copy is then deleted; if delivery never succeeds, that copy is permanently deleted after 7 days. No contact information is sent, so feedback cannot receive a direct reply.

8. **Online lyrics, only after you enable the separate lookup option.** While the lyrics view is open, a lookup sends the current song's title, artist, album and duration over HTTPS to `lrclib.net`. Audio, artwork, local paths, accounts and listening history are not included. The provider receives ordinary request data, including your public IP address, under its own policies. Requests use an ephemeral session without stored cookies, reject redirects and stop when you hide the view or disable lookup. Lyrics are kept only in memory for the current song. Local lyric import works without this connection.

9. **The AI price list, only while the AI Agents section is on.** So a model launched after a release still gets an API value, Vorssaint downloads this project's public price list from `raw.githubusercontent.com` at most once a day, and again a few hours after a failed attempt. The request carries only a standard user agent with the app name and its version; no usage, account, identifier or file goes along with it. The list is checked before it is used and kept in the app's own folder; when a download fails, the newer of that saved list and the copy inside the app stays in use. You can turn this off with Keep prices up to date in the section's settings. Requests use an ephemeral session without cookies, and redirects to other addresses are rejected.

That is the entire list. There are no hidden beacons or background uploads.

## Changes to this document

This page describes how the current version of Vorssaint behaves. If the app's behavior around privacy ever changes, this page changes with it.

## Questions

If anything here is unclear, open a question in [GitHub issues](https://github.com/vorssaint/vorssaint-utils/issues), or have a look at [support](../SUPPORT.md).

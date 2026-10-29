# Keep Awake: Handoff to iPhone

Handoff to iPhone connects the Mac to a selected iPhone Personal Hotspot, quits selected apps normally, then dims the built-in display while a Keep Awake session runs. It does not transfer an app’s documents or browsing state to iOS.

## Setup and use

1. Open **Options** in the separate **Handoff to iPhone** card. Keep Awake and Handoff are peer cards with independent Options.
2. Keep the iPhone nearby with Wi-Fi and Bluetooth enabled and Personal Hotspot available to the Mac.
3. Choose **Find iPhone**. Discovery opens the Wi-Fi pane in System Settings and requires Accessibility access for Vorssaint. If prompted, grant that access in System Settings, then retry discovery.
4. Select the iPhone. A single discovered device is selected automatically when no device is already saved.
5. Optionally add apps under **Apps to quit**. Vorssaint, Finder, System Settings, and loginwindow are excluded from the quit list.
6. Choose the Keep Awake duration in Handoff Options (default: one hour), then press **Start handoff**. No prior Keep Awake session is required. Starting handoff applies this duration, replacing any existing Keep Awake timer.

Both discovery and connection request the Wi-Fi pane with System Settings hidden and without activating it. System Settings still runs in the background during the operation. The connector uses the accessibility controls exposed by that pane; it does not collect network passwords.

## Operation and cancellation

Progress, the countdown, errors, and cancellation appear only inside the Handoff card. No separate progress window opens. If the menu closes, reopen it to check progress or cancel.

The order is start Keep Awake → connection confirmation → normal app termination → five-second countdown → built-in display brightness set to zero. The connector waits for evidence that the selected hotspot is connected before requesting app termination. A connection failure leaves apps and brightness untouched.

Only selected, currently running regular apps are asked to terminate. This uses normal termination, never force quit. A save dialog, refusal to quit, or failure to finish within the wait period stops the workflow before dimming. Some selected apps may already have exited by that point; save remaining work and retry.

**Cancel** stops further workflow steps. The selected Keep Awake timer continues after cancellation or connection failure; its switch in the separate Keep Awake card can stop it. It does not reopen apps or restore the previous Wi-Fi connection. A network connection already requested through System Settings may still complete, and other existing network connections may reconnect. Once dimming is active, use the keyboard brightness-up key to see the display again. After completion the card returns to its start button, without a persistent active label or onscreen restore button. Options remain editable. Starting another handoff restores the previous captured brightness before beginning the new countdown. Ending Keep Awake or locking the screen cancels the workflow and requests restoration of the saved brightness. A failed brightness operation still offers a recovery button.

Brightness restoration belongs to the existing Keep Awake lid-dimming manager. It reuses any saved brightness baseline instead of capturing an already dimmed value, persists that baseline for recovery, and retains pending restoration when the display cannot yet accept it. Handoff does not change the existing lid-close policy. It dims only the supported built-in display, not external monitors.

## Limitations and validation

The System Settings accessibility identifiers, hierarchy, action descriptions, and completed-connection labels are macOS implementation details and may change across releases. UI translations are provided for all 15 Vorssaint languages, but that does not establish hotspot automation compatibility with every System Settings language. The connector recognizes the connection/action labels for all 15 supported languages using the system Wi-Fi settings catalog; other OS languages or changed system strings fail safely when the expected evidence is unavailable. SSID access also depends on macOS permissions and availability.

Discovery depends on the iPhone advertising a usable hotspot and the Mac being eligible to connect. Display dimming requires compatible built-in display brightness controls; desktop Macs and external-only configurations may report a brightness error. Automated tests cannot establish physical iPhone connectivity, all OS-language combinations, or hardware brightness restoration.

Run the local checks from the repository root:

```sh
Tests/Continuity/run.sh
Tests/Continuity/run-hotspot.sh
Tests/Continuity/run-strings.sh
```

The string check compiles the real language declarations extracted from `Localization.swift` with the production Continuity catalog. It visits every `AppLanguage.allCases` entry, checks every stored string is nonempty, and verifies that only the countdown has a format token: exactly one `%d`.

Before release, manually verify on supported macOS versions and hardware:

- Discovery with Accessibility denied, then granted; no nearby hotspot; multiple iPhones; and the intended System Settings languages.
- Successful connection to the selected iPhone, including when another Wi-Fi network was connected, and a failed or delayed connection without dimming.
- Normal app exit and an unsaved-document save dialog; verify no force quit occurs and incomplete termination prevents dimming.
- Cancellation during connection, termination, and countdown; verify no delayed response dims the screen afterward.
- Five-second countdown, brightness restoration, screen locking, Keep Awake ending, app relaunch recovery, and interactions with lid close/open and external displays.

These cases are the broader release checklist, not a claim of complete hardware coverage. On an Apple Silicon Mac with macOS 27.2 and English System Settings, the developer build was manually verified to switch from regular Wi-Fi to the selected iPhone, normally quit Calculator, finish the countdown, dim the built-in display from 0.5625 to 0, and restore it to 0.5625. Missing Accessibility permission and inactive/active button visibility were also checked. A follow-up manual run also completed handoff after launching System Settings from a stopped state with `isHidden == true` and `isActive == false`; the completed UI had no restore button. Other OS releases, system languages, and lid/external-display combinations still need physical coverage.

The independent-card revision was also tested starting with Keep Awake off: Start handoff activated the selected one-hour session, quit Calculator, completed the countdown and dimmed to zero. The card returned to Start handoff with editable Options. Stopping Keep Awake restored the initial brightness.

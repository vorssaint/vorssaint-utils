# Finder New File

An optional feature in Features → Clipboard & Files → New File. Install it in the feature hub, open its section on the Finder settings page, choose the file types and enable the Finder extension in System Settings. The installed feature hub row and the Finder settings section always show the extension's enabled/disabled status and a System Settings action, even when the feature switch is off. An orange warning explains missing enablement; a green check replaces it when enabled. A shared status observer refreshes immediately on appearance and activation and checks once per second only while either status surface is visible. The system query runs off the UI thread, with at most one query in flight. No Accessibility or Full Disk Access grant is required just to expose the menu; macOS may request access to protected folders when a file is created.

The menu appears on a supported folder background (including the Desktop) or a single selected item. A selected ordinary folder is the destination; a selected file uses its enclosing folder. Multiple selections and packages are not used as ambiguous destinations. The host revalidates the destination and uses exclusive writes and numbered names. Office and iWork files use bundled blank templates. Settings follow the app language and are included in settings backup.

## Security and development

Developer and release builds use the same one-click path. The sandboxed Finder Sync extension opens the containing app without activating it. The host captures the OS-provided Apple event sender audit token while handling the event and checks that the sender's running code matches the exact code-directory hash of the installed embedded extension. Unauthenticated events, including forged external URLs, are rejected; there is no confirmation fallback. The host additionally validates the file kind, directory, feature and extension state, request expiration and per-process replay protection. Successful creation is silent. Write errors are presented in the host.

Only menu presentation data is shared through a dedicated read-only preferences entitlement; it never authorizes file creation. Developer and release variants retain separate identifiers and preference domains. There is no App Group dependency, listener, filesystem crawler or additional helper process.

## Validation before review

- Build with `./build.sh --dev`, run `./build/VorssaintDeveloper --selftest` and `./build.sh --test-suite=utilities`.
- Install with `./build.sh --dev --install` and opt into the feature. The official app should remain untouched.
- Verify on macOS 14 and later: Finder background, Desktop, folder and file selections; repeated names; Office and iWork document opening; language and feature toggles; silent creation with no activation; protected-folder errors.
- With the extension disabled, install and enable the feature: check the orange warning in the feature hub and the Finder settings section. Enable the extension in System Settings, return to the app, and verify the warning changes to a green check while the management button remains. With either status surface visible, toggle the extension in System Settings and confirm the state updates without needing to return to the app. Turn off the feature switch and verify the extension management entry remains available. Disable the extension again and confirm the warning returns. Leave both status surfaces and verify polling stops. Check the other app variant independently.
- Verify local signing, ad-hoc signing and Developer ID signing separately. Launch Services must preserve the extension's sender audit token in the host's open-URL callback. If a genuine menu click is rejected, inspect the host's "rejected unauthenticated Apple event" log; do not loosen the sender check or accept arbitrary URLs.
- Verify an externally constructed create URL cannot create a file, even with a valid payload. Replay the same authenticated request and verify only one file is created.
- Inline Finder rename and custom templates are outside this change; only part of issue #399 is addressed.

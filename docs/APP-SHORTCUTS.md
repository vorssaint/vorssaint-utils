# App shortcuts

Add apps, CrossOver launchers and websites to the Dynamic Island, with an individual button for each shortcut.

## Setup

1. Open Settings → Dynamic Island → Layout → App shortcuts.
2. Choose **Add App or Game**, **Add from CrossOver**, or **Add Website**.
3. Choose the left, right or bottom edge. New shortcuts use the first free place, starting on the right. If all sides are full, the shortcut is saved without a button until you make room.
4. Use the arrows to reorder shortcuts, or the layout editor to arrange and label individual buttons.

Each edge has three places, including buttons for sections that are currently hidden. Removing a shortcut does not uninstall its app or change a website. Choosing **Not placed** keeps the shortcut saved without a side button.

## Applications and games

Select an installed `.app` bundle. App bookmarks allow macOS to resolve a moved app where possible; if resolution fails, remove the shortcut and select the app again. CrossOver's existing app wrappers are discovered under `~/Applications/CrossOver`. Vorssaint opens the exact wrapper through `NSWorkspace`; CrossOver owns the bottle and game launch. No shell command is constructed.

## Websites and icons

Only HTTP and HTTPS destinations are accepted. Omitted schemes default to HTTPS. Embedded usernames and passwords are rejected. Different pages on the same site can have separate shortcuts. Website names are optional; the hostname is used when omitted. Links open in the default browser.

Icons are fetched directly from the site's root page and its declared icon addresses, with `favicon.ico` and `apple-touch-icon.png` as fallbacks. Saved page paths, query strings and fragments are not used for discovery. Requests do not share browser cookies or credentials. Redirects, response sizes, image dimensions and timeouts are bounded. HTTPS redirects cannot downgrade to HTTP. Removal cancels outstanding requests. Successful icons are converted to small PNGs in the app's cache; a refresh failure retains the last working icon. SVG-only, authenticated or unavailable icons use a globe fallback. There is no periodic polling or third-party icon service.

## Storage and compatibility

The list is limited to 100 shortcuts and 1 MiB of encoded data. Names, URLs, bookmarks and imported data are validated before use. Shortcut targets are private, machine-specific state and are excluded from portable settings exports. Side-button layout remains part of the normal settings backup; missing targets are hidden until present locally.

Existing emr shortcut preferences and `emr.app.<UUID>` side-button identifiers remain readable. New button identifiers use `app.<UUID>`. No emr package, branding, performance dashboard, updater or installer is required by this feature.

## Development

Implementation lives in `Services/Notch/Shortcuts`, `UI/Settings/NotchLauncherSettings.swift`, `UI/Notch/WebsiteShortcutIcon.swift`, and `Core/NotchShortcutStrings.swift`. Host changes are limited to preference registration and backup exclusion, the existing side-button action model, rendering, activation and settings layout. This is a source contribution to Vorssaint, not a runtime plug-in.

Build using the normal upstream `build.sh`. Run focused validation with `./Tools/test-launcher.sh`; run integration coverage with `./build.sh --test-suite=notch --test-suite=settings --test-suite=repository --test-suite=localization`. Website tests use a temporary loopback server, synthetic icons and temporary cache directories. They do not contact public sites or use personal accounts.

The feature uses the existing Dynamic Island availability controls. It starts with no shortcuts and adds no required permission, dependency, background agent or app identity. The website icon requests occur only after a site is added, an uncached icon is shown, or Refresh is chosen.

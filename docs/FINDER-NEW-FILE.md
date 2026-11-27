# Finder New File

An optional feature in Features → Clipboard & Files → New File. Install it in the feature hub, open its section on the Finder settings page, choose the file types and enable the Finder extension in System Settings. No Accessibility or Full Disk Access grant is required just to expose the menu; the operating system may request access to protected folders when a file is created.

The menu appears on a supported folder background (including the Desktop) or a single selected item. A selected ordinary folder is the destination; a selected file uses its enclosing folder. Multiple selections and packages are not used as ambiguous destinations. The host revalidates the destination and uses exclusive writes and numbered names. Office and iWork files are actual bundled blank templates, not renamed empty files. Settings follow the app language and are included in settings backup.

## Security and development

The native Finder Sync extension is sandboxed. Developer ID builds use a same-team app group, with separate release and Developer identities. On macOS 15 or later, a one-use, expiring request written to that protected group authorizes creation. The custom URL carries only a random request ID, not a filename or an operation to execute. There is no listener, filesystem crawler or new helper process in the host. A replay cannot create another file. On macOS 14 and builds without a protected app group, a URL can only prepare a confirmation dialog showing the file type and target directory. The host checks feature availability, the selected file types, and the Finder extension's enabled status before writing. Never allow an external URL to mutate files without either the protected one-use request or explicit user confirmation.

On a local build without a Developer ID, the extension cannot read the host's settings; Finder shows the fixed list and system-language labels after the user enables the extension. The host still enforces the feature switch, allowed types and app-language confirmation. To hide the fallback menu, turn the extension off in System Settings. This limitation is not claimed as full signed-build parity.

## Validation before review

- Build with `./build.sh --dev`, run `./build/VorssaintDeveloper --selftest` and `./build.sh --test-suite=utilities`.
- Install with `./build.sh --dev --install` and opt into the feature. The official app should remain untouched.
- Verify on a real Mac: Finder background, Desktop, folder and file selections; repeated names; Word, Excel, PowerPoint and iWork document opening; switching language and disabling/removing the feature; cancellation and protected-folder errors.
- Verify Developer ID signing and notarization on macOS 15+ before claiming direct creation and live menu synchronization. Verify macOS 14 confirmation behavior separately.
- Inline Finder rename and custom templates are outside this change; only part of issue #399 is addressed.

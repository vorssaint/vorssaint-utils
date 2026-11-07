#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="$PWD/build/VorssaintAudio.driver"
codesign --verify --deep --strict "$bundle"
root_dir="$(mktemp -d)"
trap 'rm -rf "$root_dir"' EXIT
mkdir -p "$root_dir/payload/Library/Audio/Plug-Ins/HAL" "$root_dir/scripts"
ditto --noextattr --noqtn "$bundle" "$root_dir/payload/Library/Audio/Plug-Ins/HAL/VorssaintAudio.driver"
cat > "$root_dir/scripts/postinstall" <<'POSTINSTALL'
#!/bin/zsh
set -euo pipefail
legacy='/Library/Audio/Plug-Ins/HAL/VorssaintAudioFork.driver'
legacy_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$legacy/Contents/Info.plist" 2>/dev/null || true)"
current_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Library/Audio/Plug-Ins/HAL/VorssaintAudio.driver/Contents/Info.plist 2>/dev/null || true)"
if [[ ! -L "$legacy" && -d "$legacy" && "$legacy_build" == <-> && "$current_build" == <-> ]] \
    && (( legacy_build <= current_build )) \
    && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$legacy/Contents/Info.plist" 2>/dev/null)" == com.vorssaint.audiofork.driver ]]; then
    /bin/rm -rf "$legacy"
    /usr/sbin/pkgutil --forget com.vorssaint.audiofork.driver.pkg 2>/dev/null || true
fi
/usr/bin/killall coreaudiod 2>/dev/null || true
exit 0
POSTINSTALL
chmod 755 "$root_dir/scripts/postinstall"
/usr/bin/pkgbuild --analyze --root "$root_dir/payload" "$root_dir/components.plist"
python3 - "$root_dir/components.plist" <<'PYCOMPONENTS'
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as file:
    components = plistlib.load(file)
# Corresponding Source contains the original Info.plist for reproducibility;
# it is data, not a second installable bundle with the driver's identifier.
components = [item for item in components
              if item['RootRelativeBundlePath'].lstrip('./') == 'Library/Audio/Plug-Ins/HAL/VorssaintAudio.driver']
if len(components) != 1:
    raise SystemExit('Expected exactly one installable audio driver bundle')
for component in components:
    component.pop('ChildBundles', None)
    component['BundleOverwriteAction'] = 'upgrade'
    component['BundleIsRelocatable'] = False
    component['BundleIsVersionChecked'] = True
    component['BundleHasStrictIdentifier'] = True
with open(path, 'wb') as file:
    plistlib.dump(components, file)
PYCOMPONENTS
xattr -cr "$root_dir/payload"
codesign --verify --deep --strict "$root_dir/payload/Library/Audio/Plug-Ins/HAL/VorssaintAudio.driver"
signing=()
if [[ -n "${VORSSAINT_INSTALLER_SIGN_IDENTITY:-}" ]]; then
    signing=(--sign "$VORSSAINT_INSTALLER_SIGN_IDENTITY" --timestamp)
fi
COPYFILE_DISABLE=1 /usr/bin/pkgbuild --component-plist "$root_dir/components.plist" --root "$root_dir/payload" --scripts "$root_dir/scripts" --identifier com.vorssaint.utils.software-volume.driver.pkg --version "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/SoftwareVolumeDriver/Info.plist)" --install-location / --ownership recommended "${signing[@]}" "$PWD/build/VorssaintAudio.pkg"
echo "INSTALLER READY: $PWD/build/VorssaintAudio.pkg"

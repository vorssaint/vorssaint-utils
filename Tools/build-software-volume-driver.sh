#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -std=gnu11 -O2 -fblocks Tests/SoftwareVolumeDriverTests.c -framework CoreAudio -framework CoreFoundation -framework Accelerate -framework Security -o build/software-volume-driver-tests
codesign -s - --identifier com.vorssaint.utils.pcm-tests build/software-volume-driver-tests
./build/software-volume-driver-tests
bundle="$PWD/build/VorssaintAudio.driver"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
xcrun clang -std=gnu11 -O2 -fblocks -bundle -arch arm64 -mmacosx-version-min=14.4 Sources/SoftwareVolumeDriver/Driver.c -framework CoreAudio -framework CoreFoundation -framework Accelerate -framework Security -o "$bundle/Contents/MacOS/VorssaintAudio"
cp Sources/SoftwareVolumeDriver/Info.plist "$bundle/Contents/Info.plist"
cp ThirdParty/BlackHole/LICENSE "$bundle/Contents/Resources/BlackHole-LICENSE.txt"
cp ThirdParty/BlackHole/UPSTREAM.md "$bundle/Contents/Resources/BlackHole-UPSTREAM.md"
# Ship exact Corresponding Source beside our compiled GPL driver, including
# its wrapper, configuration, build script and driver-interface tests.
source_dir="$bundle/Contents/Resources/CorrespondingSource"
for file in LICENSE ThirdParty/BlackHole/BlackHole.c ThirdParty/BlackHole/LICENSE ThirdParty/BlackHole/UPSTREAM.md Sources/SoftwareVolumeDriver/Driver.c Sources/SoftwareVolumeDriver/CallerTrust.h Sources/SoftwareVolumePCM/PCM.h Sources/SoftwareVolumeDriver/Info.plist Tools/build-software-volume-driver.sh Tools/package-software-volume-driver.sh Tools/uninstall-software-volume-driver.sh Tests/SoftwareVolumeDriverTests.c; do
    mkdir -p "$source_dir/$(dirname "$file")"
    cp "$file" "$source_dir/$file"
done
if [[ -f build/AppIcon.icns ]]; then cp build/AppIcon.icns "$bundle/Contents/Resources/"; fi
identity="${VORSSAINT_DRIVER_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -1)"
fi
if [[ -n "$identity" ]]; then
    codesign --force --options runtime --timestamp --sign "$identity" "$bundle"
elif ! codesign --force --sign 'Vorssaint Utils Signing' "$bundle"; then
    codesign --force --sign - "$bundle"
fi
codesign --verify --deep --strict "$bundle"
echo "DRIVER READY: $bundle"

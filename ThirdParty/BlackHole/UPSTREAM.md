# BlackHole source

Source: https://github.com/ExistentialAudio/BlackHole
Commit: 574029f0d3175ccf29a826d74be4da3967b1cb92
License: GPL-3.0; full upstream notice and license in LICENSE.

Only the C source is used. No upstream branding, icons, or binary installer is redistributed. The Vorssaint Audio wrapper supplies its own identities and lifecycle. Local source changes, if any, are documented below.

Local changes: make the gain/mute shared by control and realtime threads C11 atomics, taking a local gain snapshot for vDSP. No IO algorithm changes.

Correct the reversed CFStringRef qualifier-size checks for plug-in UID-to-device/box translation. Direct driver-interface tests cover valid and invalid qualifier sizes.

## License and distribution

The pinned upstream source is GPL-3.0-only. Vorssaint's GPL-3.0-or-later source can be used under GPLv3 together with it; the combined driver is distributed under GPLv3. Preserve upstream copyright and the complete LICENSE, including its separate branding/binary notices. This build compiles source itself and uses Vorssaint Audio identities; it does not redistribute official BlackHole binaries, installers, logo or artwork and does not claim endorsement.

Modified source is marked with the modification date (2026-10-29). The driver bundle includes `Contents/Resources/CorrespondingSource` with the exact upstream C, our wrapper/configuration, license notices, build script and driver-interface tests. It can be rebuilt on macOS with the Xcode Command Line Tools by running `./Tools/build-software-volume-driver.sh` from that source directory. Official binary releases must retain this source and notices and provide the matching full Vorssaint source and build instructions. The GPL includes no warranty.

Wrapper configuration (2026-10-30): output-only public device with no published mirror/input; native volume/mute and owner expiry; signed-app authorization and qualified, bounded PCM packets. The wrapper replaces loopback ReadInput/WriteMix with its own output PCM queue. These changes are in `Sources/SoftwareVolumeDriver/Driver.c`, `CallerTrust.h` and `Sources/SoftwareVolumePCM/PCM.h`; the vendored source remains unchanged.

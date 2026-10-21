# Intel (x86_64) build

This fork builds Vorssaint natively on Intel Macs. `build.sh` now targets the host architecture
(`uname -m`) instead of always targeting `arm64`; on Apple Silicon the result is unchanged.

```sh
./build.sh --dev --install
```

A prebuilt unofficial build is available on the
[releases page](https://github.com/me-abhishekpal/vorssaint-utils/releases/tag/v3.4.1-beta.1-intel.1).

## Where it was tested

Tested on a **Hackintosh**, not on genuine Apple hardware:

- ThinkPad X1 Carbon Gen 8, Intel Core i7-10610U, OpenCore 1.0.7, SMBIOS `MacBookPro16,2`
- macOS 26.6.2 (25G83), Xcode 26 toolchain (Swift 6.3)
- Intel UHD Graphics, audio through VoodooHDA

Results on that machine:

- Builds and installs; the binary is `x86_64`.
- The app launches and ran stably for 10+ minutes with no crash reports.
- `./build.sh --test`: 118,201 of 118,203 checks pass.
- Failing: the recorder writer test (`Tests/RecorderWriterTests.swift`) hangs in its first scenario and
  hits its 30 s deadline on every run. The recorder export test failed once under heavy load and passed on
  an idle machine. A plain H.264 and HEVC encode with `AVAssetWriter` works on the same machine, so the
  cause is not yet identified. It may be specific to this Hackintosh.

Not verified: the UI itself, and sensor-based features (fan control, temperatures, GPU stats, battery
details), which depend on hardware access that differs from Apple Silicon.

This is an unofficial community build. See TRADEMARKS.md: the Vorssaint name and icon belong to the
upstream maintainer, and this fork carries no official identity.

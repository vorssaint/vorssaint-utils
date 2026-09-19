# M1 temperature fallback verification

PR #1450 needs a run on an affected M1 in launchd's system domain. A user-session probe or synthetic sensor test cannot establish that the background fan helper receives HID events.

Build with `./build.sh`. The helper's `--temperature-diagnostics` mode reads the same `FanControlHardware.readTemperatures()` inputs used by curves, prints the named HID readings and aggregated curve temperatures, then exits. It does not start XPC, take fan ownership, or write fan settings. It keeps the real chip-family gate, so a newer Mac cannot stand in for an M1.

On the affected M1, run the built helper once from a temporary LaunchDaemon. Use an absolute path to `build/com.vorssaint.utils.fan-control` as ProgramArguments[0] and `--temperature-diagnostics` as ProgramArguments[1]. Set RunAtLoad to true, omit KeepAlive, and send StandardOutPath and StandardErrorPath to writable diagnostic log paths. Load it in the system domain using `sudo launchctl bootstrap system /absolute/path/to/diagnostic.plist`. Remove the temporary job after collecting its output with `sudo launchctl bootout system /absolute/path/to/diagnostic.plist`.

Confirm all of the following before calling the service path verified:

- The log reports `platform=appleM1Family uid=0`.
- Named `eACC MTR Temp` or `pACC MTR Temp` readings exist when mapped SMC CPU cores are absent.
- Named `GPU MTR Temp` readings exist when SMC Tg readings are absent.
- The corresponding `curve hottestCPU` and `curve hottestGPU` values are present and plausible. CPU average uses both available clusters.
- Capture an SMC sensor dump alongside the log to establish which inputs were absent. Repeat sampling to exclude a single stale event.

This checks the helper's temperature inputs. A physical fan-curve exercise remains a separate hardware check. Do not infer successful fan actuation from diagnostic output.

Local review validation used an Apple M5 Pro. The affected M1 and privileged system-service execution were unavailable, so the M1 background-service result remains unverified.

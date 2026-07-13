# Design: Read-only hardware sensor expansion for Vorssaint's System Monitor

- **Date:** 2026-07-13
- **Author:** Jeff (dionysusv) with Claude
- **Target repo:** `vorssaint/vorssaint-utils` (GPL-3.0), contributed as a focused PR
- **Working branch:** `feature/hardware-sensors`
- **Motivating issue:** [vorssaint-utils#171](https://github.com/vorssaint/vorssaint-utils/issues/171) ("more iStatMenus features in System stats")
- **Reference hardware data:** `docs/superpowers/hardware-data/` (real SMC dump from the author's M4 Pro — the source of truth for keys/labels)

## 1. Problem & goal

Vorssaint's System monitor reads only three aggregated temperatures (CPU, GPU, battery — each collapsed to a single max value) and does not read fan speeds, individual named temperature sensors, or clock frequencies. The user wants the iStatMenus-style **"Sensors" panel** from issue #171's screenshots (`img4`): a labeled temperature list, fan RPM, total power, and CPU/GPU frequency.

**Goal:** add a **read-only** "Sensors" section to the System monitor that reproduces `img4`, fitting Vorssaint's existing architecture and its "small, native, readable" bar.

### This is PR #1 of a two-part roadmap
1. **PR #1 (this spec):** read-only sensor expansion — named temperature list, fans, total power, CPU/GPU frequency.
2. **PR #2 (separate spec, later):** opt-in **Combined monitor mode** — one scrolling panel stacking System + Network + Disks + Power with hover tooltips. The Sensors block from PR #1 automatically appears inside it. Kept separate per the repo's "one topic per PR" rule. *(Hover behavior — graph tooltips vs. hover-to-open — to be pinned down when PR #2 is designed.)*

## 2. Scope

**In scope (PR #1):**
- Named temperature list (curated labels only; unknown keys hidden)
- Fan RPM (read-only; shown as RPM or "Off" at 0)
- Total system power (surface the wattage Vorssaint already samples)
- CPU efficiency/performance-cluster and GPU frequency (GHz)

**Explicitly out of scope:**
- **Fan control / writing fan curves.** `FanControlSection` is deliberately disabled for safety; we do not touch it. Read-only RPM only.
- Raw voltage/current sensor lists (none of the user's screenshots show them).
- Per-core usage rings, GPU FPS/VRAM detail (possible future PRs).
- The combined view and dark-theme picker (dark mode already follows system appearance; combined view is PR #2).

## 3. Architecture constraints (from `CONTRIBUTING.md`)

- **Services never import SwiftUI; UI observes one `@Published` snapshot.** Keep the boundary.
- Singletons are `Type.shared` + Combine `ObservableObject`; **no Observation macros** (builds with Command Line Tools).
- **Every user-facing string** lives in `Core/Localization.swift`'s `Strings` struct and must be translated into **all 13 languages** (compiler-enforced): en-US, pt-BR, tr, ru, es, de, fr, it, ja, ko, zh-Hans, zh-TW, zh-HK.
- **One topic per PR;** `./build.sh` warning-free; `--selftest` must pass; match the edited file's style.
- **No new third-party dependencies.** (Everything here uses only IOKit / IOReport system frameworks.)

## 4. Data model

New plain-struct value types in `Services/`, added as fields on the existing single published `SystemSnapshot` (`Services/SystemMonitor/SystemMonitor.swift`):

```swift
struct TemperatureSensor { let key: String; let label: String; let celsius: Double }
struct FanReading         { let index: Int; let rpm: Int }          // rpm == 0 → rendered "Off"
struct ClusterFrequencies { var eCoreGHz: Double?; var pCoreGHz: Double?; var gpuGHz: Double? }

// added to SystemSnapshot:
var temperatureSensors: [TemperatureSensor] = []
var fans: [FanReading] = []
var frequencies: ClusterFrequencies? = nil
// Total power already present as `power.systemWatts` — surfaced in UI, no new field.
```

## 5. Sensor sourcing (grounded in the M4 Pro dump)

### 5.1 Fans — easy, confirmed
- `FNum` (`ui8`) = fan count (**2** on the M4 Pro).
- `F{i}Ac` (`flt`) = actual RPM. Measured live: `F0Ac`=2323, `F1Ac`=2505. (`F{i}Mn`/`F{i}Mx`/`F{i}Tg` = min/max/target, not needed for PR #1.)
- **`SMCClient` change:** add a `ui8` decode branch (for `FNum`); `F*Ac` already decodes via the existing `flt` case.
- **Fanless Macs** (no `FNum` / count 0) → empty list, nothing rendered.
- **Naming:** 2 fans → "Left Fan" / "Right Fan"; otherwise "Fan 1", "Fan 2", …

### 5.2 Total power — trivial
- `PSTR` (`flt`) = System Total Power (**7.75 W** measured). Already sampled by `PowerSampler` as `PowerReading.systemWatts`. Just render it as a "Total Power" row.

### 5.3 Named temperature list — medium, curated
- Vorssaint already enumerates SMC keys but filters to `Tp/Te/Tg/TB` and collapses to 3 max values. The M4 Pro exposes **157** additional named temperature keys.
- **Friendly labels are NOT derivable from keys** — they are a curated, per-chip database. Plan: port a curated Apple-Silicon key→label table from **exelban/Stats** (GPL-3.0, license-compatible, **with attribution**) as a **pure `SensorLabels.label(for:) -> String?`** function, validated against the dump in `hardware-data/`.
- **Unknown keys → `nil` → hidden** (user decision). Only confidently-labeled sensors show, matching `img4`'s clean look.
- High-confidence mappings from the dump (final set validated against Stats' table):
  | Label | Key(s) | Notes |
  |---|---|---|
  | CPU Performance Cores | `Tp0*` core set | Vorssaint already identifies these per platform |
  | CPU Efficiency Cores | `Te0*` core set | " |
  | Graphics | `Tg0*` | " |
  | Battery | `TB0T`–`TB2T` | ✓ 34° |
  | Wi-Fi | `TW0P` | ✓ 42° |
  | SSD | `TH0x`/`TH0a`/`TH0b` | ✓ 36° |
  | Airflow | `Ta**` family | plausible; confirm vs Stats |
  | Palm Rest / Thunderbolt L/R | `Ts1P` / `TDeL`,`TDeR`? | needs Stats' table |

### 5.4 Frequency — hardest, isolated
- Not in the SMC. On Apple Silicon, CPU cluster + GPU frequencies come from **IOReport** DVFS residency: subscribe to `CPU Stats` / `GPU Stats` channels, read per-P-state residency, weight against the DVFS frequency table in the IORegistry `voltage-states*` device-tree keys (the asitop/Stats approach).
- Implemented as an **isolated `FrequencySampler` unit** with a clean interface; declares the header-less IOReport symbols locally. This is the **riskiest** piece (semi-private API, chip-specific cluster→`voltage-states` mapping). Kept isolated so it can be dropped to a follow-up PR without unpicking fans/temps/power if review objects.

## 6. Module boundaries

```
SMCClient (+ui8 decode)  ─▶ FanSampler ───────────────┐
SensorLabels (pure map) + existing SMC temp discovery ─┤
PowerSampler.systemWatts (existing) ──────────────────┼─▶ SystemMonitor.refresh() ─▶ SystemSnapshot ─▶ SystemSection (UI)
FrequencySampler (IOReport, new, isolated) ───────────┘
```
`FanSampler`, `SensorLabels`, and the frequency residency math are pure/injectable → unit-testable without hardware (mirrors the existing pure `TemperatureSensorSelector`).

## 7. Sampling integration (preserves zero-idle-cost model)

- Fans + named temps ride the **existing `.temperature` `MonitorSamplingKind`** (all SMC, one pass).
- Add a new **`.frequency`** kind (foreground ~1s, background ~5s) in `MonitorSamplingPolicy`.
- Extend the private `SamplingPlan` with `needFrequency` (sensors reuse `needTemperature`); wire `currentPlan(defaults:)`, `neededKinds(of:)`, `SystemMonitorPanelNeeds`.
- New `DefaultsKey`s (default **on**): `monitorSysSensors`, `monitorSysFrequency` — follow the `monitorSys*` pattern; register defaults.
- Sensors sample **only when the Sensors block is visible and the System tab (or future combined view) is open.**

## 8. UI

One new hideable/reorderable **"Sensors" `Block`** in `UI/MenuPanel/SystemSection.swift`, mirroring `img4`, built from existing primitives (`subsectionLabel`, `.panelCard()`, `PanelMetricColor`, `MetricFormat`, row layout like the memory breakdown):

- **TEMPERATURE** — curated rows: label · `MetricFormat.temperature(_, unit:)`
- **POWER** — "Total Power" · `MetricFormat.watts(systemWatts)`
- **FANS** — "Left Fan"/"Right Fan" · RPM, or "Off" when 0
- **FREQUENCY** — "CPU Efficiency Cores" / "CPU Performance Cores" / "Graphics" · GHz

Registered in the panel order + `UI/Settings/MonitorPanelConfig.swift` toggle list so it is user-hideable/reorderable.

## 9. Localization

New `Strings` fields × 13 languages (compiler-enforced): subsection titles, `leftFan`/`rightFan`/`fanOff`, "Total Power", frequency labels, and curated sensor names. Many (Wi-Fi, SSD, Thunderbolt) are identical across languages, easing the burden. Author drafts translations; refine before PR.

## 10. Testing

Pure, hardware-free unit tests in the existing `Tests/MetricsTests.swift` harness (`./build.sh --test`):
- `SensorLabels.label(for:)` — key→label, incl. unknown→`nil` (hidden)
- Fan decode + "Off" formatting (rpm 0 → "Off")
- Frequency residency math (residencies + state table → GHz)
- Temperature plausibility filter

Live proof: build `--dev`, open the System panel, screenshot RPM/temps/power/frequency. Also extend the `--sensors` diagnostic to dump fans + power (currently temperature-only).

## 11. Rollout / upstream etiquette

1. **Post a short design comment on issue #171 first** (per CONTRIBUTING: "describe the problem," discuss approach / no-new-deps) proposing the read-only sensor expansion, to confirm maintainer appetite **before** investing in a large PR. Author posts it.
2. Work on `feature/hardware-sensors` of a fork; `--dev`-test throughout; keep `./build.sh` warning-free and `--selftest`/`--test` green; all strings in 13 languages; match file style.
3. Frequency (IOReport) stays isolated — droppable to a follow-up if review objects.
4. This design doc lives under `docs/superpowers/` and is **not** part of the upstream PR diff.

## 12. Prerequisites & environment notes

- **Toolchain:** the CLT are broken on this machine (`xcrun: invalid active developer path`). Building works by pointing at Xcode-beta — prefix builds with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (no `sudo`, no reinstall). Verified: `./build.sh --dev` → `SELFTEST OK`.
- **Safe testing:** always build the `--dev` variant ("Vorssaint (Developer)", separate bundle id) so the installed official **3.1.12** is untouched. Quit a running dev build before relaunching (stale-binary gotcha). `./Tools/setup-signing.sh` once → macOS permission grants persist across rebuilds.
- **Thermal safety:** builds are a ~3-min single-core burst — fine. Never run two heavy CPU jobs at once.

## 13. Risks

| Risk | Mitigation |
|---|---|
| Frequency IOReport API is semi-private / chip-specific | Isolated `FrequencySampler`; droppable to follow-up |
| Temperature labels wrong/incomplete on other chips | Curated map validated vs real dump; hide unknowns; only ship confident labels |
| 13-language translation burden | Keep labels minimal; many are language-invariant proper nouns |
| Maintainer may reject a big PR | Post design comment on #171 first; keep PR read-only, small, warning-free, tested |
| Large hardcoded per-chip table draws scrutiny | Attribute to Stats; scope to Apple Silicon; conservative subset |

## 14. Open items (decide during implementation)
- Final curated label set (reconcile our dump reads with Stats' table; confirm Airflow / Palm Rest / Thunderbolt keys).
- Exact fan-naming rule for non-2-fan Macs.
- Whether frequency ships in PR #1 or splits out (depends on IOReport implementation effort + maintainer feedback).

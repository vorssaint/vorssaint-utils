# KI: Services map (contribution index)

Largest / hottest areas by file count and graph communities:

| Area | Path | Notes |
|------|------|-------|
| QuickTools | `Services/QuickTools/` | Screenshot, OCR, color picker, media tools |
| Recorder | `Services/Recorder/` | Screen recording pipeline |
| CommandBar | `Services/CommandBar/` | Launcher / actions catalog |
| Metrics / SystemMonitor | `Services/Metrics/`, `SystemMonitor/` | CPU/GPU/mem/net/disk/power |
| Switcher | `Services/Switcher/` | App/window switcher (many open bugs/PRs) |
| Audio / Mixer | `Services/Audio/` | Per-app volume, mic, output |
| Clipboard | `Services/Clipboard/` | History + auto-clear |
| WindowLayout | `Services/WindowLayout/` | Snap / gestures (Snap Layouts PRs open) |
| FanControl | `Services/FanControl/` + `FanControlHelper` | Privileged helper |
| Mouse* | several `Mouse*` dirs | Acceleration, buttons, debounce, nav |
| Snippets | `Services/Snippets/` | Expansion (inline-completion bug open) |

Shared infrastructure worth reusing before inventing:

- `HotkeyManager`, `ShortcutCapture`, `ShortcutRecordingTap`
- `PointerTapRunLoop`, `WindowServerSupport`, `WindowMaximizer`
- `BoundedProcessRunner`, `ShellSupport`, `PrivateFileStore`
- `GeneralPasteboardAccess`, `TransientPaste`
- `ActivationHandoff`

## UI boundary

`UI/` observes services only. Never put logic in views.

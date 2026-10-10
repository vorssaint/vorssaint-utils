# Keyboard Remaps

Install **Keyboard Remaps** in Settings → Features. A new setup has no rules
and remapping is off. Add your own rules, review **Current setup preview**, then
enable remapping. Disable overlapping Karabiner or macOS modifier rules first.
Accessibility is required.

## General rules

**Key rules** map a physical key to another key, a shortcut, or an action.
Choose from Fn/Globe, Caps Lock, left/right modifiers, letters, numbers,
punctuation, navigation keys and F1–F20. Examples: Fn → Control, right Option →
right Command, Caps Lock → Escape, or Home → Command+Left. These are individual
user choices rather than app-wide defaults.

**Shortcut rules** match a chosen key and exact modifiers, then send a chosen
shortcut or run an action. Sources and outputs can be selected manually or
recorded, including bare keys and Shift combinations. Available actions are:

- Do nothing.
- Cycle enabled input languages.
- Toggle normal Caps Lock and its keyboard light.
- Open a chosen installed application, stored by bundle identifier.

Each rule can be edited, disabled or removed. **Clear all rules** starts again
without changing the feature's availability. No shell commands are executed.

Shortcut rules run after physical key remaps. For example, if Caps Lock is
mapped to Escape, configure any further shortcut using Escape as the source.
For action keys, rules use the original source: Caps Lock → next language can
be combined with Shift+Caps Lock → toggle Caps Lock. Key actions apply only
without modifiers; configure modifier combinations as separate shortcut rules.
If Caps Lock has only a modified action, its bare press retains normal Caps Lock.

Translated shortcuts retain matching down/up events even if modifiers are
released early, and action repeats are suppressed. Outputs bypass Vorssaint's
Quit Protection confirmation. A rule claiming Command+Q takes precedence over
Quit Protection regardless of event-tap installation order.

## Suggested remaps

Choose and preview a focused preset rather than installing one combined setup.
Previews show a From → To table with full key names (Home, End, Left Arrow,
Command, Shift) instead of compact, ambiguous shortcut symbols:

| Preset | Rules | Use case |
| --- | --- | --- |
| Caps Lock → Escape | Caps Lock sends Escape | Vim and editors; replaces normal Caps Lock |
| Caps Lock → Control | Caps Lock becomes left Control | Terminal and Control-heavy shortcuts; replaces normal Caps Lock |
| PC-style Home / End | Home/End send Command+Left/Right; Shift selects | Familiar line navigation on full-size keyboards; app support varies |
| Safer quitting | Command+Q → do nothing; Option+Q → Command+Q | Reduce accidental quitting near Command+Tab; replaces the Option+Q character |
| Fn and languages | Fn → left Command; Caps Lock → next language; Shift+Caps Lock → normal Caps Lock | Optional example for multilingual Mac users |

Caps-to-Escape and Caps-to-Control are alternatives. These are fixed key remaps,
not tap-versus-hold behavior. Home/End normally scroll to document boundaries
on macOS; this preset changes them to line movement. Existing Control/Option
combinations remain available. The Fn preset changes the usual Fn behavior.

**Add suggested rules** adds missing sources only. Existing custom rules and
explicitly disabled choices stay intact. Repeated use does not duplicate rules.
To replace an existing Caps Lock choice, edit or remove that rule first; adding
another preset does not overwrite it. Previewing or cancelling a preset does
not change the active setup or enable remapping.

Safer quitting is a separate, explicit choice rather than part of another
preset. Its preview and active rule list show Command+Q → do nothing and
Option+Q → Quit app (Command + Q).
All other presets leave quitting alone. Application shortcuts remain personal
choices in the shortcut editor. No preset takes over Option+T or right Command.
In particular, right Command → right Option remains a separate choice for
layouts such as Latvian that use Option for alternative characters.

Recorded or manually selected shortcuts match physical key codes. Existing
logical Q/T rules from an earlier suggested setup remain supported. Option
shortcuts replace any characters those combinations normally type.
Windows/Linux need separate configuration; Vorssaint changes macOS only.

A fresh install receives no suggested rules automatically.

## Compatibility and recovery

This uses macOS HID key mapping and an Accessibility event tap without a
virtual keyboard driver. Fn must be exposed to macOS; some keyboards handle it
in firmware. Verify a physical Fn press after disabling overlapping rules. A
confirmed mapping table alone cannot prove that the keyboard sends Fn events.
macOS Modifier Keys mappings run first; overlapping assignments pause this
feature. Restore the overlapping keys under System Settings → Keyboard →
Keyboard Shortcuts → Modifier Keys, then re-enable Keyboard Remaps.
A remapped Fn loses its usual Fn+function-key alternate behavior.

Super Key takes precedence and pauses Keyboard Remaps while enabled. Up to
seven physical action keys use F19, F20, F17, F16, F15, F14 and F13 as internal
triggers; only the triggers actually needed are reserved. Physical presses of
these keys share their assigned actions. Allocation avoids keys used by other
rules; configurations with no free trigger slots are refused. Ordinary shortcut-only actions do not use these slots,
except Caps Lock, which needs a releasable trigger for modifier combinations.

Duplicate active sources, invalid targets, self-maps, and overlapping external
mappings are refused before applying. External per-keyboard tables must agree
before any global write. Unrelated mappings are retained, and writes are read
back. Disable, session suspension and normal exit remove the exact owned
entries. A pipe helper handles process death and a machine-only marker supports
recovery on next launch. Wake and raw source events schedule mapping repair;
the first press before repair may retain the original behavior.

Rule choices participate in settings backup; mapping ownership does not.

## References

- [Apple's HID key mapping technical note](https://developer.apple.com/library/archive/technotes/tn2450/)
- [Apple's Mac shortcut reference](https://support.apple.com/en-us/102650)
- [Karabiner's examples and Fn limitations](https://karabiner-elements.pqrs.org/docs/getting-started/features/)

Caps Lock examples are documented in [Karabiner’s typical modifications](https://karabiner-elements.pqrs.org/docs/json/typical-complex-modifications-examples/); native line and document shortcuts are listed in [Apple’s shortcut reference](https://support.apple.com/en-us/102650).

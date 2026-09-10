# Editor tool shortcut bindings

Store optional per-tool bindings separately from the existing enabled preference and rail order. An empty binding map preserves the first nine tools' position shortcuts. The registered string key participates in settings backups through the existing export mechanism.

Custom bindings use the shared recorder's physical key code and modifiers. Labels use its existing keyboard-layout support. Position shortcuts retain the editor's printed-digit matching, so recording decides what a key is by the character it types on the active layout: a press that types 1 through 9, with Shift allowed as AZERTY needs, moves the tool into that slot; clearing moves it below the first nine slots. Imported bindings on a digit key are dropped for the same reason.

Reuse the global shortcut value type with an explicit modifier opt-out for editor bindings. Global shortcuts retain their existing validation. Before saving, reject editor commands, other tool bindings, enabled Vorssaint shortcuts, window layout keys and macOS shortcuts, keeping the previous binding; filter reserved or malformed bindings when reading imported preferences.

This avoids a separate number/letter mode and a second set of fixed letter defaults. Tool bindings remain attached when the rail is reordered. The Settings page and editor popover share the same controls, and users can configure bindings while tool shortcuts are off.

# Editor tool shortcut bindings

Store optional per-tool bindings separately from the existing enabled preference and rail order. An empty binding map preserves the first nine tools' position shortcuts. The registered string key participates in settings backups through the existing export mechanism.

Custom bindings use the shared recorder's physical key code and modifiers. Position shortcuts retain printed-digit matching, including Shift and Caps Lock. Recording a digit moves the tool into that slot; clearing moves it below the first nine slots. Stored bindings are independent of the current keyboard: when a saved key becomes a digit, it is temporarily inactive and the position shortcut applies. Switching back restores the binding, and editing another tool never erases it. Visible controls follow keyboard layout and Caps Lock changes.

Reuse the global shortcut value type with an explicit modifier opt-out for editor bindings. Global shortcuts retain their existing validation. Recording also carries the original event flags so lock state is not lost. Before saving, reject editor commands, other tool bindings, enabled Vorssaint shortcuts, both window layout shortcut modes and macOS shortcuts, keeping the previous binding. System comparisons preserve the Fn requirement; unsupported Fn-letter combinations cannot be silently saved as plain letters. Reserved and malformed bindings are filtered independently of keyboard layout when reading preferences.

This avoids a separate number/letter mode and a second set of fixed letter defaults. Tool bindings remain attached when the rail is reordered. The Settings page and editor popover share the same controls, and users can configure bindings while tool shortcuts are off.

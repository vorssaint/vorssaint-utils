# Icon Drawer

Settings → Menu bar → Icon Drawer lets you choose and order less-used icons.
Dropdown opens a compact grid; Menu bar expands icons immediately left of the
arrow, within the space to the right of the camera. If they do not all fit,
the page number cycles through the remaining icons. Monochrome is enabled by
default. Right-click the arrow and choose Open settings to return to this card.

## macOS 27 limitation

The native hiding mechanism suppresses Focus and some other Apple menu-bar
extras while hiding is active, even when they are not selected for the drawer.
Focus remains accessible in Control Center; disabling Icon Drawer restores its
real icon. The current native system-item allowlist has no Focus entry, and
allowlisting its bundle does not preserve it. Vorssaint does not substitute a
simulated Focus icon.

This is a limitation of the visibility mechanism, not a change to your Focus
state. It is also documented by [Pelmet](https://github.com/fif7y/pelmet/blob/main/docs/FAQ.md).
The bridge resolves the private MenuBarClientCore API at runtime and leaves
icons visible if that API is unavailable. A future macOS update may change
this behavior. Icons belonging to the same app share one visibility setting.

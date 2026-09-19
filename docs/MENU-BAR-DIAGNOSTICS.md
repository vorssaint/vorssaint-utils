# Menu bar inventory diagnostic

This standalone, read-only tool gathers evidence for [#698](https://github.com/vorssaint/vorssaint-utils/issues/698).
It walks each running app's `AXExtrasMenuBar`, including the wrappers reported
around MenuBarAgent's system items on macOS 27. It does not enable the organizer,
create status items, open menus, move icons, change preferences or request permissions.
It is not included in the shipped application.

```sh
mkdir -p build
swiftc Tools/MenuBarInventory.swift -o build/MenuBarInventory
./build/MenuBarInventory --selftest
./build/MenuBarInventory > /tmp/menu-bar-before.json
```

Use a terminal that already has Accessibility permission. Exit 2 means permission
is missing; it must not be interpreted as an empty menu bar. Exit 3 means at least
one app was unavailable or a traversal limit was reached; the JSON still contains
the observations collected. Other attribute failures are recorded by name and AX
error code. `no-extras` means that the app reports no extra menu bar or does not
support that attribute. Missing optional attributes can yield `partial` results.

Each item reports its publishing bundle/PID through its parent application,
its child-index path, role, whether it has an identifier, and its frame as
`[x, y, width, height]` in AX global coordinates. Missing or invalid frames are
omitted. Negative coordinates are valid with multiple displays. The tool does
not read titles or descriptions and does not emit identifier values.
Bundle IDs still reveal running applications: review the JSON before sharing it.

Paths and PIDs are only valid within one snapshot. Anonymous items must remain
provisional; their index is not a persistent identity. The diagnostic makes no
claim that the inventory is complete or that an item is movable or hideable.
Each app gets up to one second, each AX request a 150 ms timeout, and the scan
gets ten seconds overall (plus an in-flight request). Traversal is capped at
128 nodes and three child levels per app. An item is a leaf: open menus are
never traversed.

## Rebuild comparison on a real Mac

1. Record the Mac model, OS build, display arrangement, menu bar auto-hide and
   Spaces configuration alongside the first snapshot.
2. In Vorssaint, use **Settings → General → Show menu bar icon** to rebuild its
   status item, then run the diagnostic again into a second file.
3. Compare the observed frames with where the icons are actually drawn. Record
   mismatches; successful AX reads alone do not prove the coordinates are right.
4. Repeat after a manual Command-drag, an app relaunch, and on an external
   display if available. Treat missing apps, errors and truncation as gaps in
   evidence, not proof that an icon disappeared.

The fixture self-test covers direct items, wrapped system items, open-menu
pruning, depth/node/deadline limits and invalid geometry without requiring AX
permission. It does not replace the real-Mac comparison above.

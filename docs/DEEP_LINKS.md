# Deep links

Vorssaint registers the `vorssaint://` URL scheme. A link names one Command Bar row by its stable ID, and Vorssaint runs it the same way it runs that row's own shortcut. Shortcuts, scripts and launchers that can open a URL or run `open` can reach any installed tool this way.

Any local app can send these links.

```sh
open 'vorssaint://run/<id>'
open 'vorssaint://run/<id>?v=<number>'
```

- The scheme and `run` are case insensitive; the ID is case sensitive.
- `v` is an integer for rows that take one, clamped to the row's range.
- A row that confirms, or needs a number and gets no `v`, asks in the Command Bar. While the Command Bar feature is off there is nowhere to ask, so it beeps instead.
- A row whose setup is missing opens its Settings page.
- An unknown ID, or a row whose feature is off, beeps and runs nothing.

A link that runs nothing logs why:

```sh
/usr/bin/log stream --predicate 'subsystem == "com.vorssaint.utils" AND category == "deeplink"'
```

## IDs

IDs are the stable `id` values in `Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift`. The fixed families are:

| Family | Example |
| --- | --- |
| `action.<tool>` | `action.colorPicker`, `action.darkMode`, `action.emptyTrash` |
| `action.<tool>` with `v` | `action.volume?v=40`, `action.brightness?v=70` |
| `action.layout.<direction>` | `action.layout.leftHalf`, `action.layout.maximize` |
| `action.power.<action>` | `action.power.sleep` |
| `action.keepAwake.<minutes>` | `action.keepAwake.60` |
| `toggle.<feature>` | `toggle.scrollInverter.vertical` |

Rows named after your own content, such as snippets, apps, windows and clipboard items, have no fixed ID.

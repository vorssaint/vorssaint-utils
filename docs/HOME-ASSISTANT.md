# Home Assistant in the Dynamic Island

The optional Home Assistant feature adds a native **Home Assistant** page to the expanded
Dynamic Island. It connects directly to your Home Assistant server; no custom
integration, cloud account, or additional package is required.

## Set up

1. Install **Dynamic Island** and **Home Assistant** from Settings → Features.
2. Open the Dynamic Island's content settings and choose the Home Assistant section.
3. Enter your server's base URL, such as `https://your-home.example` or
   `http://homeassistant.local:8123`. Do not include a dashboard path.
4. In your Home Assistant profile's security settings, create a long-lived access
   token. Paste it into the access-token field and select **Connect / Test**.
5. Under **Pages**, choose **Create page**, give it a title, and select its
   entities. Arrange the pages and the entities with the arrow buttons. Existing
   selections appear in an initial page automatically.
6. Open the island and choose Home Assistant, or use its section shortcut, `⌥⌘H`.

Remote HTTPS addresses and addresses reachable through a VPN work when the server
allows direct API access. Certificates must be trusted by macOS. Additional proxy
login screens and automatic server discovery are not supported. For HTTP access,
use a local IP address, a `.local` name, or an unqualified hostname; fully qualified
domain names use HTTPS. macOS may ask for Local Network access when connecting
to your LAN; allow it in System Settings → Privacy & Security → Local Network.

## Available controls

- Lights: on/off, brightness for dimmable lights, and color for color-capable lights.
- Switches and plugs: on/off.
- Sensors and binary sensors: current readings and units.
- Scenes and scripts: run without custom parameters.
- Climate: current temperature, supported HVAC modes, and target temperature or
  target range.
- Blinds and shutters: supported open, close, stop, and position controls.

**Connection** groups the server URL, token, and connection status separately
from **Pages**, where you create, name, reorder and select pages, then assign
and customize their entities. An entity can appear on multiple pages. Removing
it from one page keeps the other assignments; the final page cannot be deleted.
Each selected entity has a **…** menu with **Move** and **Duplicate** submenus
listing the other pages. Move removes the source assignment; Duplicate keeps
both. Names and additional readings remain shared, and a page never gets the
same entity twice. With only one page, this menu is disabled.
Settings use the [official Home Assistant logo](https://github.com/home-assistant/assets/tree/master/logo).

Choose **2, 4, 6, or 8 default columns** in Home Assistant settings. Each page can
enable **Custom column count** and choose its own value; turn it off to inherit
the global default again. Enable **Fill the last row** on a page to widen the
cards in an incomplete last row to fill its available width. For example, six
entities with four columns produce four cards above two wider cards. This option
does not change card height, full rows, or the three-row scrolling limit.
Existing pages inherit the global columns and leave filling disabled.
Both page options are saved in settings backups. The island opens
at the height needed by the occupied rows. One row makes a shorter island; two
rows fit without reserved empty space. Every card uses Explore's standard
86-point height, including the third row. The island shows at most three rows;
scroll vertically to step through whole rows, with the same spring and side
indicators as Explore. Click a side dot to jump to that row position. The island
stays bounded by three visible rows. Swipe left or right with two fingers on the
trackpad to change pages, or use the previous/next buttons beside the page title.
Each swipe changes one page; momentum does not skip further pages.
With only one page, the island hides its title, counter and navigation buttons,
and removes the space reserved for them.
On smaller displays, the viewport fits the available space. Cards share Explore’s centered icon, rounded shape and hover/press feedback,
with the entity name and reading or on/off state underneath, including units. Denser rows use smaller
text; hover for the full name and reading. Edit a selected entity’s **Custom name** in settings to give it a local alias;
clear the field to restore Home Assistant's name.

In each selected entity’s **Additional readings**, choose up to two sensor or binary
sensor entities to display on that card, such as a plug's power in W and energy
in kWh. Search by name or entity ID, and choose **None** to remove a reading.
Associations are explicit: select the sensors belonging to the intended device.
They do not need separate cards in the island. Missing sensors show Unavailable.
Use the **pencil** button next to a selected sensor to give it a shorter local
name, or choose **Use original name** to reset it. This alias applies wherever
that sensor appears in the app; it never renames the entity on Home Assistant.

Click a light or switch card once to toggle it; click a scene or script to run it.
Dimmable lights have an inline brightness slider from 0–100%. Zero switches the
light off. On/off-only lights show neither a slider nor a brightness percentage.
The colored card background fills in proportion to brightness;
changes are sent when you release the slider and confirmed by server updates.
Confirmed state changes animate the icon, reading, and colored fill smoothly;
Reduce Motion follows your macOS preference.
Card contents are centered vertically and horizontally. Additional readings
use centered rows; dense columns show their values without labels to stay readable.
When a color-capable light is on, its card and bulb use the color reported by
Home Assistant. The active HS, XY, RGBW or RGBWW representation takes priority
over a converted RGB attribute; fractional reported RGB channels are rounded
for display. White/color-temperature modes do not reuse stale colored attributes.
Fallback conversion follows Home Assistant's [color utilities](https://github.com/home-assistant/core/blob/dev/homeassistant/util/color.py).
Secondary-click the card (two-finger click on a trackpad, right
mouse button, or Control-click) to open its color popover. Choose a color with
the wheel or the hue/saturation sliders, then **Apply color**. Dragging only
edits a local draft; Cancel or dismiss sends nothing. Applying turns on an off
light and sends one `light.turn_on` with `rgb_color`, without a brightness parameter.
Home Assistant [converts RGB to the supported color mode](https://developers.home-assistant.io/docs/core/entity/light/#turn-on-light-device),
including HS, XY, RGBW and RGBWW. The card follows actual server updates rather
than assuming that the requested RGB is reproduced exactly within the lamp's gamut.
Color-temperature-only and on/off-only lights do not offer this selector.
Right-click a card and choose **Details** to open additional controls. Sensors,
climate devices, and covers open their details when clicked. Cameras, locks, alarms,
media players, and door/garage/gate covers are outside this version's scope.
**Open dashboard** opens the server in your default browser, using that browser's
own login session. The web dashboard is not embedded in the island.

## Connection and privacy

Readings update through Home Assistant's [`state_changed` WebSocket events](https://developers.home-assistant.io/docs/api/websocket/#subscribe-to-events),
without periodic polling. Actual measurement cadence depends on the device and
its integration; the app does not force hardware updates. A fresh snapshot is
loaded when connecting or reconnecting.

The connection runs while Home Assistant or its settings are visible. Closing the last
surface, disabling the feature, or sleeping the Mac stops network work. On the
next opening, the app loads fresh states. Offline readings are explicitly marked;
controls require a live connection and an available entity.

An action is sent once. The app does not repeat it after a timeout or reconnect.
Lights and climate settings wait for the server's state confirmation. Scene,
script, and cover acknowledgements indicate that Home Assistant accepted the
action; actual device states continue arriving separately.

Tokens stay in this Mac's Keychain and are never included in settings backups.
Developer and official builds use separate Keychain identities. Backups include
the server URL, named pages, page and entity order, selected page, local names,
row density, and sensor associations. Backups from before pages migrate their
entity selection into an initial page.
A restored Mac requires its own token.
Changing servers clears pages, selected entities, local names, and sensor associations.
Forget connection deletes the selected server's saved token from this Mac, without revoking it on Home Assistant.

# T-Mobile gateway monitor

Vorssaint can show signal and connection status from a compatible T-Mobile
G4AR gateway on the Mac’s local network. This optional feature reads the
credential-free `GET /TMI/v1/gateway?get=all` endpoint.

A credential-free status read was verified against a TMO-G4AR running firmware
1.00.18. The automated suite uses fabricated fixtures. The native panel's live
display and hide/show behavior still need interactive verification; builds and
selftests alone do not establish those interactions on a particular Mac.

## Setup

1. Connect the Mac to the same local network as the gateway.
2. Open **Settings > Monitor > Network** and enable the **T-Mobile gateway**
   tile (or **Show T-Mobile gateway** in the row layout).
3. Open the tile's options, choose **Configure gateway** in the row layout, or use the gear icon in the network
   panel’s **T-Mobile gateway** block, to open the address popover.
4. Enter the gateway’s private IPv4 base address and choose **Save address**.
   The default is `http://192.168.12.1`.

The address must identify a private IPv4 host, such as an address in `10.0.0.0/8`,
`172.16.0.0/12` or `192.168.0.0/16`, using HTTP or HTTPS. Public addresses,
hostnames, embedded credentials, custom paths, queries and fragments are rejected.
Vorssaint adds the fixed endpoint path itself and does not follow redirects.
Address validation does not prove that the gateway is reachable on the current
network.

Access starts only after you enable the feature. macOS may also ask for local
network permission. Turning the feature off stops requests. The configured
address and opt-in consent are machine-specific preferences and are excluded
from settings backup, so restoring settings does not grant local gateway access
on another Mac.

## Readings and refresh

The network panel’s T-Mobile block shows the available device model, firmware
and uptime, plus separate LTE and 5G signal readings: RSRP, RSRQ, RSSI, SINR,
bands and signal bars. Network
registration and roaming status are shown when the gateway reports them. Fields
that the firmware omits are hidden; missing values are never
treated as zero or as a successful connection.

Polling runs while the enabled network panel is visible or the menu bar
connection indicator is enabled. Both share one reader. Successful requests
refresh about every 15 seconds. Failures back
off to a maximum of 120 seconds, and **Retry** starts another request. Closing
the panel stops its polling demand; an enabled menu bar indicator continues.
Errors clear live readings so an old sample cannot appear to be current.
Gateway status stays in memory and is never written to disk.

Public signal monitoring has no account credentials or login flow. Firmware
that responds with HTTP 401 or 403 requires authentication and is unsupported
by this credential-free reader.
Unreachable gateways, denied local network access and unsupported responses
show an unavailable or error state. Check the address, local connection and
macOS permission before retrying.

The local endpoint does not provide verified plan or billing usage, so the
panel omits plan usage. This feature does not read
connected clients, SIM identifiers or GPS data, and it does not change router
settings, restart the gateway or send other router writes.

## Menu bar indicator

**Settings > Monitor > In the menu bar > T-Mobile connection** pins one
indicator that combines an LTE, 5G or 5G UC badge, the gateway's own 0–5 signal
bars and the selected radio's reported bands, for example `5G UC ▂▄▆█ n41`.
Its options choose which of technology, bars and bands appear; at least one
stays selected. The indicator is off by default and, like the panel block,
is a machine-specific preference excluded from settings backup.

The status response has a generic registration field but no per-radio connected
flag. The indicator requires a recognized `registered` state and a finite serving
RSRP between −160 and −20 dBm. It prefers reported 5G, then LTE; a radio object
or leftover band metadata alone does not establish a connection. Otherwise it
shows a dash. An LTE anchor can remain connected alongside 5G in NSA mode; both
radios stay visible in the dropdown.

The 5G UC badge is inferred from a reported n2, n25, n41, n258, n260 or n261 band
when roaming is not reported. These bands are listed as Ultra Capacity by
[T-Mobile's network table](https://www.t-mobile.com/support/coverage/t-mobile-network).
It is a band-based label, not a gateway-reported UC flag or a speed guarantee.

VoiceOver reads the full connection description from the status item, and the
tooltip repeats it.

## Dropdown readings

Separate 5G and LTE / 4G sections show every radio field the public status
parser supports when the gateway returns it: bars, bands, RSRP, RSRQ, RSSI,
SINR, antenna, bandwidth, channel (NR-ARFCN or EARFCN), PCI, TAC, CQI, gNB ID,
eNB ID, cell ID, ECGI and supported bands. Missing fields are hidden; real zero
readings stay visible. RSRP, RSRQ and SINR show an approximate rating and color
described in [Signal readings](TMOBILE-SIGNAL-GUIDE.md). **Signal guide & tips**
opens placement suggestions based on the current readings.

## Development checks

From the repository root:

```sh
./build.sh --dev
./build/VorssaintDeveloper --selftest
./build.sh --test-suite=tmobile
zsh Tests/TMobileGatewayMonitorTests.sh
zsh Tests/TMobileGatewayAppearanceTests.sh
```

The Developer build uses separate app preferences and permissions. These checks
cover compilation, app health and the gateway suite. A live test must separately
record the gateway model, firmware, macOS version and which visible readings
were confirmed. Do not include gateway credentials, identifiers or raw private
responses in a report.

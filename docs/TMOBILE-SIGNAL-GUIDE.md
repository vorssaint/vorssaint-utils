# T-Mobile signal readings

Vorssaint reads the gateway's public status response. It shows LTE and
5G separately, retaining missing values as unavailable. The gateway supplies
its own 0–5 bars; the app does not calculate replacement bars from RSRP.

RSRP measures reference-signal power, RSRQ measures reference-signal quality,
and SINR compares signal with interference and noise. Less negative RSRP/RSRQ
and higher SINR generally help. RSSI includes noise and depends on bandwidth,
so the app displays it without a standalone quality grade.
[Quectel's cellular concepts](https://python.quectel.com/doc/quecpython/Application_guide/en/network-comm/nic/cellular/common-concepts.html)
and [signal FAQ](https://python.quectel.com/doc/quecpython/FAQ/en/network/signal.html)
explain these measurements and why signal alone cannot guarantee service.

The labels below are **approximate app guidance**, not T-Mobile ratings,
3GPP pass/fail criteria, connection status, or speed estimates. They are useful
for comparing placements on the same radio; gateway firmware can report
different ranges.

| Metric | Poor | Fair | Good | Excellent |
| --- | --- | --- | --- | --- |
| RSRP, dBm | below −105 | −105 to below −95 | −95 to below −85 | −85 or higher |
| RSRQ, dB | below −15 | −15 to below −10 | −10 to below −7 | −7 or higher |
| SINR, dB | below 0 | 0 to below 13 | 13 to below 20 | 20 or higher |

Try several positions and compare stable readings. T-Mobile recommends its
T-Life placement assistant, avoiding nearby interference, and Ethernet for a
comparison test. [T-Mobile network speed advice](https://www.t-mobile.com/support/home-internet/t-mobile-gateway/network-speed).

Band n41 is 2.5 GHz mid-band 5G; n71 is 600 MHz Extended Range 5G. A band
name indicates the reported radio band, not a guaranteed speed or service
badge. [T-Mobile network frequencies](https://www.t-mobile.com/support/coverage/t-mobile-network).
The menu bar now combines the selected connection's badge, bars and reported
bands in one indicator; see [connected radio display](TMOBILE-INDICATOR.md).
The app does not lock the modem to a band.

Cell IDs identify radio cells, not geographic coordinates. LTE ECI is 28-bit
and 5G NCI is 36-bit. The optional LTE eNB estimate uses the conventional
20/8 macro split, which is not valid for every LTE eNB format. A 5G gNB ID is
shown only when explicitly returned; it is never inferred using LTE arithmetic.
[3GPP TS 23.003, sections 19.6 and 19.6A](https://www.etsi.org/deliver/etsi_TS/123000_123099/123003/15.04.00_60/ts_123003v150400p.pdf).
[3GPP TS 36.413](https://www.etsi.org/deliver/etsi_ts/136400_136499/136413/16.10.00_60/ts_136413v161000p.pdf)
defines the different eNB formats and variable-length 5G gNB identifiers.

The public status parser allows signal, CID, antenna selection, APN and gateway
status. Optional bandwidth, channel, PCI, TAC, CQI and gNB ID remain unavailable
unless the same public response supplies them. The app does not request
authenticated cell telemetry, SIM identifiers, client lists or GPS, and it
does not infer a tower location from a cell ID. Gateway responses are not
saved.

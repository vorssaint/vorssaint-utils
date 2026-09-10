// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A forgotten Keep Awake session with the closed-lid mode on keeps a Mac
/// running in a bag, and the charge cutoff does not catch it: heat builds at
/// any charge, and on wall power too. This covers the thermal limit that
/// ends such a session on heat, alongside the charge one.
enum ThermalProtectionContract {
    static func run(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.thermalLimit] as? Int == 45,
                     "Keep Awake ends itself at 45 °C battery temperature by default")
        suite.expect(Defaults.sanitizedThermalLimit(40) == 40,
                     "valid thermal limit is preserved")
        suite.expect(Defaults.sanitizedThermalLimit(0) == 0,
                     "the thermal limit can be switched off")
        suite.expect(Defaults.sanitizedThermalLimit(42) == 45,
                     "invalid thermal limit falls back to 45 °C")
        suite.expect(!KeepAwakeAutomationSupport.exceedsThermalLimit(celsius: 60, limitCelsius: 0),
                     "a switched-off thermal limit never ends Keep Awake")
        suite.expect(!KeepAwakeAutomationSupport.exceedsThermalLimit(celsius: nil, limitCelsius: 45),
                     "a missing battery temperature never ends Keep Awake")
        suite.expect(!KeepAwakeAutomationSupport.exceedsThermalLimit(celsius: 44.9, limitCelsius: 45),
                     "a battery just under the thermal limit keeps Keep Awake")
        suite.expect(KeepAwakeAutomationSupport.exceedsThermalLimit(celsius: 45, limitCelsius: 45),
                     "a battery at the thermal limit ends Keep Awake")
        suite.expect(TemperatureSensorSelector.isBatteryTemperatureKey("TB0T")
                     && TemperatureSensorSelector.isBatteryTemperatureKey("TB2T"),
                     "battery cell sensors are recognised")
        suite.expect(!TemperatureSensorSelector.isBatteryTemperatureKey("TB0V")
                     && !TemperatureSensorSelector.isBatteryTemperatureKey("Tp01"),
                     "battery voltage and CPU keys are not battery temperatures")
        suite.expect(TemperatureSensorSelector.hottestPlausibleReading([31, nil, 128, 0, 36.5]) == 36.5,
                     "disconnected sensor values are ignored when picking the hottest reading")
        suite.expect(TemperatureSensorSelector.hottestPlausibleReading([nil, 0]) == nil,
                     "no plausible reading means no temperature")
    }
}

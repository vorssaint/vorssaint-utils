// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat

enum MetricsFeatureTests {
    static func run(_ suite: TestSuite) {
        func expectEqual(_ actual: String, _ expected: String, _ label: String,
                         file: StaticString = #filePath, line: UInt = #line) {
            suite.expect(actual == expected, "\(label): got \(actual), expected \(expected)",
                         file: file, line: line)
        }
        let originalLocale = MetricFormat.locale
        // MARK: Byte / rate formatting

        // Pinned, because everything below reads a decimal point and this
        // machine's region is only one of the ones the app ships for.
        MetricFormat.locale = Locale(identifier: "en_US_POSIX")
        expectEqual(MetricFormat.bytes(0), "0 B", "bytes zero")
        expectEqual(MetricFormat.bytes(512), "512 B", "bytes < 1K")
        expectEqual(MetricFormat.bytes(1024), "1.0 KB", "bytes 1K")
        expectEqual(MetricFormat.bytes(1536), "1.5 KB", "bytes 1.5K")
        // Nine of the fifteen languages here are spoken where a decimal is
        // written with a comma, and the panel wrote a point at everyone.
        MetricFormat.locale = Locale(identifier: "pt_BR")
        expectEqual(MetricFormat.bytes(1536), "1,5 KB", "a comma region reads its own decimal")
        expectEqual(MetricFormat.temperature(21.4, unit: .celsius), "21 °C",
                    "a whole number is untouched by the region")
        MetricFormat.locale = Locale(identifier: "en_US_POSIX")
        expectEqual(MetricFormat.bytes(10 * 1024), "10 KB", "bytes 10K drops decimal")
        expectEqual(MetricFormat.bytes(1024 * 1024), "1.0 MB", "bytes 1M")
        expectEqual(MetricFormat.bytes(3 * 1024 * 1024 * 1024), "3.0 GB", "bytes 3G")
        expectEqual(MetricFormat.diskBytes(245_107_195_904), "245 GB", "disk bytes use decimal storage units")
        expectEqual(MetricFormat.diskBytes(1_000_204_845_056), "1.0 TB", "disk bytes show decimal terabytes")
        expectEqual(MetricFormat.diskBytes(123_456_789_000), "123 GB", "disk bytes match Finder-style GB")
        expectEqual(MetricFormat.diskBytesPrecise(14_878_047_232_000), "14.88 TB",
                    "precise disk bytes keep SMART totals readable")

        expectEqual(MetricFormat.bytesPerSec(0), "0 B/s", "rate zero")
        expectEqual(MetricFormat.bytesPerSec(2 * 1024 * 1024), "2.0 MB/s", "rate 2M")
        expectEqual(MetricFormat.bytesPerSec(1500 * 1024), "1.5 MB/s", "rate 1.5M")

        expectEqual(MetricFormat.bytesPerSecCompact(0), "0B", "compact zero")
        expectEqual(MetricFormat.bytesPerSecCompact(320 * 1024), "320K", "compact 320K")
        expectEqual(MetricFormat.bytesPerSecCompact(1.2 * 1024 * 1024), "1.2M", "compact 1.2M")
        expectEqual(MetricFormat.bytesPerSecCompact(1022), "1022B", "compact 1022B remains stable")
        expectEqual(MetricFormat.bytesPerSecCompact(1023.4), "1023B", "compact keeps sub-kilobyte values")
        expectEqual(MetricFormat.bytesPerSecCompact(1023.6), "1.0K", "compact promotes rounded kilobyte edge")
        expectEqual(MetricFormat.bytesPerSecCompact(9.96 * 1024), "10K", "compact drops redundant decimal at 10K")
        expectEqual(MetricFormat.bytesPerSecCompact(1023.6 * 1024), "1.0M", "compact promotes rounded megabyte edge")
        expectEqual(MetricFormat.bytesPerSecCompact(9.96 * 1024 * 1024), "10M", "compact drops redundant decimal at 10M")

        // MARK: Disk helpers

        suite.expect(DiskSupport.nvmeBytes(low: 2, high: nil) == 1_024_000,
               "NVMe data units convert to 512,000 byte units")
        suite.expect(DiskSupport.nvmeBytes(low: 1, high: 1) == 2_199_023_256_064_000,
               "NVMe high data unit word is included")
        suite.expectClose(DiskSupport.celsius(fromSMARTTemperature: 302) ?? -1, 28.85,
                    "SMART Kelvin temperature converts to Celsius")
        suite.expectClose(DiskSupport.celsius(fromSMARTTemperature: 33) ?? -1, 33,
                    "SMART Celsius temperature is preserved")
        suite.expect(DiskSupport.celsius(fromSMARTTemperature: 999) == nil,
               "SMART invalid temperature is ignored")
        suite.expect(DiskSupport.healthPercent(fromPercentageUsed: 1) == 99,
               "SMART health subtracts percentage used")
        suite.expect(DiskSupport.healthPercent(fromPercentageUsed: 150) == 0,
               "SMART health clamps exhausted drives")
        suite.expect(DiskSupport.fileSystemLabel(type: "apfs") == "APFS",
               "file system label maps apfs")
        suite.expect(DiskSupport.fileSystemLabel(type: " APFS \n") == "APFS",
               "file system label trims and ignores case")
        suite.expect(DiskSupport.fileSystemLabel(type: "hfs", name: "Journaled HFS+") == "HFS+",
               "file system label maps journaled hfs")
        suite.expect(DiskSupport.fileSystemLabel(type: "exfat") == "exFAT",
               "file system label keeps exFAT capitalization")
        suite.expect(DiskSupport.fileSystemLabel(type: "ntfs") == "NTFS",
               "file system label maps ntfs")
        suite.expect(DiskSupport.fileSystemLabel(type: "msdos", name: "Legacy FAT32") == "FAT32",
               "file system label reads FAT width from the name")
        suite.expect(DiskSupport.fileSystemLabel(type: "msdos", name: "Legacy FAT16") == "FAT16",
               "file system label reads FAT16 from the name")
        suite.expect(DiskSupport.fileSystemLabel(type: "msdos") == "FAT",
               "file system label falls back to plain FAT")
        suite.expect(DiskSupport.fileSystemLabel(type: "cd9660") == "ISO 9660",
               "file system label maps optical media")
        suite.expect(DiskSupport.fileSystemLabel(type: "udf") == "UDF",
               "file system label uppercases short unknown tokens")
        suite.expect(DiskSupport.fileSystemLabel(type: "lifs") == "LIFS",
               "file system label keeps acronym-sized tokens")
        suite.expect(DiskSupport.fileSystemLabel(type: "someverylongdriver") == nil,
               "file system label drops long driver tokens")
        suite.expect(DiskSupport.fileSystemLabel(type: "a") == nil,
               "file system label drops single letters")
        suite.expect(DiskSupport.fileSystemLabel(type: "123456") == nil,
               "file system label needs at least one letter")
        suite.expect(DiskSupport.fileSystemLabel(type: "") == nil,
               "file system label ignores empty type")
        suite.expect(DiskSupport.fileSystemLabel(type: nil) == nil,
               "file system label ignores missing type")
        let diskRate = MetricFormat.diskSpeed(
            previous: DiskIOCounters(read: 1_000, written: 500),
            current: DiskIOCounters(read: 3_048, written: 1_524),
            elapsed: 2
        )
        suite.expectClose(diskRate.read, 1_024, "disk read speed uses elapsed time")
        suite.expectClose(diskRate.write, 512, "disk write speed uses elapsed time")
        let resetDiskRate = MetricFormat.diskSpeed(
            previous: DiskIOCounters(read: 3_048, written: 1_524),
            current: DiskIOCounters(read: 2_000, written: 800),
            elapsed: 2
        )
        suite.expectClose(resetDiskRate.read, 0, "disk read counter reset does not spike")
        suite.expectClose(resetDiskRate.write, 0, "disk write counter reset does not spike")
        let smart = DiskSupport.smartReading(
            status: "Verified",
            vendorKeys: [
                "DATA_UNITS_READ_0": 2,
                "DATA_UNITS_WRITTEN_0": 4,
                "TEMPERATURE": 302,
                "PERCENTAGE_USED": 7,
                "POWER_CYCLES_0": 11,
                "POWER_ON_HOURS_0": 12,
                "UNSAFE_SHUTDOWNS_0": 13,
                "MEDIA_ERRORS_0": 14,
            ]
        )
        suite.expect(smart?.status == "Verified", "SMART status is preserved")
        suite.expect(smart?.totalReadBytes == 1_024_000, "SMART total read uses NVMe units")
        suite.expect(smart?.totalWrittenBytes == 2_048_000, "SMART total written uses NVMe units")
        suite.expectClose(smart?.temperatureCelsius ?? -1, 28.85, "SMART reading includes temperature")
        suite.expect(smart?.healthPercent == 93, "SMART reading includes estimated health")
        suite.expect(smart?.powerCycles == 11, "SMART reading includes power cycles")
        suite.expect(smart?.powerOnHours == 12, "SMART reading includes power-on hours")
        suite.expect(smart?.unsafeShutdowns == 13, "SMART reading includes unsafe shutdowns")
        suite.expect(smart?.mediaErrors == 14, "SMART reading includes media errors")

        let diskDevice = DiskDeviceReading(
            id: "disk3s1",
            name: "Macintosh HD",
            mountPath: "/",
            bsdName: "disk3s1",
            wholeDisk: "disk3",
            ioCounterID: "disk3",
            fileSystem: "APFS",
            totalBytes: 245_000_000_000,
            freeBytes: 110_000_000_000,
            purgeableBytes: 28_000_000_000,
            usedBytes: 163_000_000_000,
            isInternal: true,
            isRemovable: false,
            isEjectable: false,
            smart: nil,
            readBytesPerSec: nil,
            writeBytesPerSec: nil,
            totalReadBytes: nil,
            totalWrittenBytes: nil
        )
        suite.expect(Defaults.registeredDefaults[DiskMenuBarStyle.defaultsKey] as? String == "percent",
                     "disk menu bar style registers the existing percentage default")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DiskMenuBarStyle.defaultsKey),
                     "disk menu bar style travels in settings backups")
        for style in DiskMenuBarStyle.allCases {
            let restored = SettingsBackupSupport.sanitizedSettings(from: [
                SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
                SettingsBackupSupport.settingsKey: [DiskMenuBarStyle.defaultsKey: style.rawValue],
            ])
            suite.expect(restored?[DiskMenuBarStyle.defaultsKey] as? String == style.rawValue,
                         "settings backup restores disk menu bar style \(style.rawValue)")
        }
        expectEqual(DiskMenuBarStyle.percent.value(for: diskDevice), "67%", "disk menu bar used percentage")
        expectEqual(DiskMenuBarStyle.percent.minimumValue, "100%", "percentage reserves percentage width")
        expectEqual(DiskMenuBarStyle.free.minimumValue, "1000 GB", "available space reserves numeric width")
        suite.expect(DiskMenuBarStyle.percent.showsPercentage,
                     "used percentage supports bars")
        suite.expect(!DiskMenuBarStyle.free.showsPercentage && !DiskMenuBarStyle.used.showsPercentage,
                     "raw capacity options remain numeric")
        expectEqual(DiskMenuBarStyle.free.value(for: diskDevice), "110 GB", "disk menu bar reports available bytes directly")
        expectEqual(DiskMenuBarStyle.used.value(for: diskDevice), "163 GB", "disk menu bar reports used bytes directly")
        var emptyDisk = diskDevice
        emptyDisk.totalBytes = 0
        emptyDisk.freeBytes = 0
        emptyDisk.usedBytes = 0
        expectEqual(DiskMenuBarStyle.percent.value(for: emptyDisk), "0%", "disk menu bar zero capacity")
        expectEqual(DiskMenuBarStyle.free.value(for: emptyDisk), "0 B", "disk menu bar zero available space")
        expectEqual(DiskMenuBarStyle.used.value(for: emptyDisk), "0 B", "disk menu bar zero used space")
        suite.expect(diskDevice.purgeableBytes == 28_000_000_000, "disk reading preserves purgeable bytes")
        suite.expectClose(diskDevice.usedFraction, 163.0 / 245.0, "disk used fraction reflects physical used bytes")

        let maxCapacityStringJSON = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"93%"}}]}"#.utf8)
        suite.expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityStringJSON) == 93,
               "battery maximum capacity parses percentage strings")
        let maxCapacityNumberJSON = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":93}}]}"#.utf8)
        suite.expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityNumberJSON) == 93,
               "battery maximum capacity parses numeric JSON")
        let maxCapacityNestedJSON = Data(#"{"SPPowerDataType":[{"_items":[{"_items":[{"Maximum Capacity":"93%"}]}]}]}"#.utf8)
        suite.expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityNestedJSON) == 93,
               "battery maximum capacity parses nested System Report keys")
        let maxCapacityUnavailableJSON = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"EM_DASH"}}]}"#.utf8)
        suite.expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityUnavailableJSON) == nil,
               "battery maximum capacity ignores placeholder values")

        suite.expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 222,
                                                   externalConnected: false,
                                                   isCharging: false) == 13_320,
               "battery time converts the public time-to-empty minutes")
        suite.expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: -1,
                                                   externalConnected: false,
                                                   isCharging: false) == nil,
               "battery time preserves the system calculating state")
        suite.expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 222,
                                                   externalConnected: true,
                                                   isCharging: false) == nil,
               "battery time stays hidden on external power")
        suite.expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 222,
                                                   externalConnected: false,
                                                   isCharging: true) == nil,
               "battery time stays hidden while charging")
        suite.expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 65_535,
                                                   externalConnected: false,
                                                   isCharging: false) == nil,
               "battery time ignores the public unavailable sentinel")
        suite.expect(BatteryTimeSupport.formatted(seconds: 13_320) == "3h 42m",
               "battery time formats hours and minutes")
        suite.expect(BatteryTimeSupport.formatted(seconds: 30) == "0h 1m",
               "battery time keeps a positive final minute visible")

        suite.expect(MetricFormat.systemPowerWatts(measured: 3,
                                             batteryWatts: 10,
                                             externalConnected: true) == 3,
               "system power keeps its independent sensor while connected to power")
        suite.expect(MetricFormat.systemPowerWatts(measured: nil,
                                             batteryWatts: 10,
                                             externalConnected: true) == nil,
               "system power does not mirror adapter input while connected to power")
        suite.expect(MetricFormat.systemPowerWatts(measured: nil,
                                             batteryWatts: -4,
                                             externalConnected: false) == 4,
               "battery discharge remains a valid system-power fallback")
        suite.expect(MetricFormat.systemPowerWatts(measured: nil,
                                             batteryWatts: -4,
                                             externalConnected: true) == nil,
               "battery flow alone does not claim total system power while plugged in")

        // MARK: Peripheral battery helpers

        suite.expect(PeripheralBatterySupport.percent(from: "87%") == 87,
               "peripheral battery parses percentage strings")
        suite.expect(PeripheralBatterySupport.percent(from: NSNumber(value: 62.4)) == 62,
               "peripheral battery rounds numeric values")
        suite.expect(PeripheralBatterySupport.percent(from: 140) == nil,
               "peripheral battery ignores invalid percentages")
        let usageMouse = [["DeviceUsagePage": 1, "DeviceUsage": 2]]
        suite.expect(PeripheralBatterySupport.kind(product: "Wireless Device",
                                             primaryUsagePage: nil,
                                             primaryUsage: nil,
                                             usagePairs: usageMouse) == .mouse,
               "peripheral battery infers mouse from HID usage")
        suite.expect(PeripheralBatterySupport.kind(product: "soundcore Space Q45",
                                             minorType: "Headset",
                                             primaryUsagePage: nil,
                                             primaryUsage: nil,
                                             usagePairs: []) == .audio,
               "peripheral battery infers Bluetooth headsets as audio devices")
        let bluetoothJSON = Data("""
        {"SPBluetoothDataType":[{"device_connected":[
          {"soundcore Space Q45":{"device_address":"F4:9D:8A:A2:4C:12","device_batteryLevelMain":"100%","device_minorType":"Headset"}},
          {"AirPods Pro":{"device_address":"E5:04:BE:68:C2:93","device_batteryLevelCase":"88%","device_batteryLevelLeft":"92%","device_batteryLevelRight":"90%"}},
          {"Travel Pointer":{"device_address":"F0:00:00:00:00:01","device_minorType":"Mouse"}}
        ],"device_not_connected":[
          {"Old Mouse":{"device_address":"00:00:00:00:00:00","device_batteryLevelMain":"12%","device_minorType":"Mouse"}}
        ]}]}
        """.utf8)
        let bluetoothDevices = PeripheralBatterySupport.bluetoothDevices(fromSystemProfilerJSON: bluetoothJSON)
        suite.expect(bluetoothDevices.contains(PeripheralBatteryDevice(id: "Bluetooth:F4:9D:8A:A2:4C:12",
                                                                 name: "soundcore Space Q45",
                                                                 percent: 100,
                                                                 kind: .audio)),
               "peripheral battery parses connected Bluetooth headset battery")
        suite.expect(bluetoothDevices.contains(PeripheralBatteryDevice(id: "Bluetooth:E5:04:BE:68:C2:93",
                                                                 name: "AirPods Pro",
                                                                 percent: 88,
                                                                 kind: .audio)),
               "peripheral battery uses the lowest connected AirPods component")
        suite.expect(!bluetoothDevices.contains { $0.name == "Old Mouse" },
               "peripheral battery ignores disconnected Bluetooth devices")
        let bluetoothKinds = PeripheralBatterySupport.bluetoothKindsByName(
            fromSystemProfilerJSON: bluetoothJSON
        )
        suite.expect(bluetoothKinds["travel pointer"] == .mouse,
               "peripheral battery keeps the kind of connected devices without profiler charge data")
        let gattDevices = PeripheralBatterySupport.mergingBluetoothReadings(
            [
                BluetoothBatteryReading(id: "pointer", name: "Travel Pointer", percent: 73),
                BluetoothBatteryReading(id: "pointer", name: "Renamed Pointer", percent: 64),
                BluetoothBatteryReading(id: "duplicate", name: "soundcore space q45", percent: 17),
                BluetoothBatteryReading(id: "invalid", name: "Invalid Accessory", percent: 101),
            ],
            into: bluetoothDevices,
            knownKinds: bluetoothKinds
        )
        suite.expect(gattDevices.contains(PeripheralBatteryDevice(id: "BluetoothGATT:pointer",
                                                            name: "Travel Pointer",
                                                            percent: 73,
                                                            kind: .mouse)),
               "peripheral battery adds a standard Bluetooth battery reading with its known kind")
        suite.expect(gattDevices.first { $0.name.caseInsensitiveCompare("soundcore Space Q45") == .orderedSame }?.percent == 100,
               "peripheral battery keeps richer profiler data instead of a duplicate standard reading")
        suite.expect(!gattDevices.contains { $0.name == "Renamed Pointer" },
               "peripheral battery keeps one row per Bluetooth identity")
        suite.expect(!gattDevices.contains { $0.name == "Invalid Accessory" },
               "peripheral battery rejects invalid standard Bluetooth percentages")
        let keyboard = PeripheralBatteryDevice(id: "keyboard",
                                               name: "Magic Keyboard",
                                               percent: 78,
                                               kind: .keyboard)
        let mouse = PeripheralBatteryDevice(id: "mouse",
                                            name: "Magic Mouse",
                                            percent: 24,
                                            kind: .mouse)
        suite.expect(PeripheralBatterySupport.sorted([keyboard, mouse]).map(\.id) == ["mouse", "keyboard"],
               "peripheral battery devices sort by lowest charge first")
        let menuMetric = PeripheralBatterySupport.menuBarMetric(for: [keyboard, mouse])
        suite.expect(menuMetric?.label == "MOU" && menuMetric?.value == "24%+1",
               "peripheral battery menu metric shows the lowest device and extra count")
        suite.expect(PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 300,
            lastStartedAt: -.greatestFiniteMagnitude,
            lastFinishedAt: -.greatestFiniteMagnitude,
            isRunning: false,
            interval: 300
        ), "peripheral Bluetooth refresh starts when no cache exists")
        suite.expect(!PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 400,
            lastStartedAt: 300,
            lastFinishedAt: 305,
            isRunning: true,
            interval: 300
        ), "peripheral Bluetooth refresh is single-flight")
        suite.expect(!PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 500,
            lastStartedAt: 300,
            lastFinishedAt: 305,
            isRunning: false,
            interval: 300
        ), "peripheral Bluetooth refresh respects its cache interval")
        suite.expect(PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 606,
            lastStartedAt: 300,
            lastFinishedAt: 305,
            isRunning: false,
            interval: 300
        ), "peripheral Bluetooth refresh runs again only after the interval")

        // MARK: Watts & percent

        expectEqual(MetricFormat.watts(8.5), "8.5 W", "watts under 10")
        expectEqual(MetricFormat.watts(23.4), "23 W", "watts over 10 rounds")
        expectEqual(MetricFormat.wattsCompact(8.6), "9W", "watts compact rounds")
        expectEqual(MetricFormat.percent(0), "0%", "percent 0")
        expectEqual(MetricFormat.percent(0.125), "13%", "percent rounds")
        expectEqual(MetricFormat.percent(1), "100%", "percent full")
        expectEqual(MetricFormat.percent(1.4), "100%", "percent clamps high")
        expectEqual(MetricFormat.percent(-0.2), "0%", "percent clamps low")
        suite.expectClose(MetricFormat.boundedPercentage(130), 100,
                    "process percentage clamps above full hardware utilization")
        suite.expectClose(MetricFormat.boundedPercentage(-5), 0,
                    "process percentage clamps negative utilization")
        suite.expect(MetricFormat.machTimeNanoseconds(48_000_000,
                                                numerator: 125,
                                                denominator: 3) == 2_000_000_000,
               "libproc CPU ticks convert through the platform Mach timebase")
        suite.expectClose(MetricFormat.processCPUPercentage(previousNanoseconds: 1_000_000_000,
                                                       currentNanoseconds: 2_800_000_000,
                                                       elapsed: 2,
                                                       processorCount: 18), 5,
                    "process CPU delta uses the monitor wall-clock interval and machine capacity")
        suite.expectClose(MetricFormat.processCPUPercentage(previousNanoseconds: 2_000_000_000,
                                                       currentNanoseconds: 1_000_000_000,
                                                       elapsed: 2,
                                                       processorCount: 18), 0,
                    "process CPU counter resets do not create utilization spikes")
        suite.expectClose(MetricFormat.processReconciliationScale(sampledTotal: 12,
                                                             aggregatePercentage: 7), 7.0 / 12.0,
                    "process usage scales down when attribution exceeds the aggregate")
        suite.expectClose(MetricFormat.processReconciliationScale(sampledTotal: 5,
                                                             aggregatePercentage: 7), 1,
                    "unattributed aggregate usage does not inflate process rows")
        expectEqual(MetricFormat.menuBarMemoryPercent(used: 79, total: 100), "79%",
                    "menu bar memory shows the current RAM percentage")
        expectEqual(MetricFormat.menuBarMemoryPercent(used: nil, total: 100), "--%",
                    "menu bar memory keeps a placeholder when used RAM is unavailable")
        expectEqual(MetricFormat.menuBarMemoryPercent(used: 79, total: nil), "--%",
                    "menu bar memory keeps a placeholder when total RAM is unavailable")
        expectEqual(MetricFormat.menuBarMemoryPercent(used: 79, total: 0), "--%",
                    "menu bar memory keeps a placeholder when total RAM is invalid")
        suite.expectClose(MetricFormat.stabilizedGPUUsage(previous: 0.03, current: 0.80), 0.23,
                    "GPU usage readout caps one-tick upward spikes")
        suite.expectClose(MetricFormat.stabilizedGPUUsage(previous: 0.23, current: 0.80), 0.43,
                    "GPU usage readout still climbs during sustained load")
        suite.expectClose(MetricFormat.stabilizedGPUUsage(previous: 0.60, current: 0.10), 0.275,
                    "GPU usage readout falls quickly after transient load")
        suite.expectClose(MetricFormat.stabilizedGPUUsage(previous: nil, current: 1.4), 1.0,
                    "GPU usage readout clamps first sample")
        expectEqual(MetricFormat.temperature(0, unit: .celsius), "0 °C", "celsius freezing")
        expectEqual(MetricFormat.temperature(0, unit: .fahrenheit), "32 °F", "fahrenheit freezing")
        expectEqual(MetricFormat.temperature(41, unit: .fahrenheit), "106 °F", "fahrenheit rounds")
        expectEqual(MetricFormat.temperatureCompact(49.6, unit: .celsius), "50°", "compact celsius rounds")
        expectEqual(MetricFormat.temperatureCompact(49.6, unit: .fahrenheit), "121°", "compact fahrenheit rounds")
        expectEqual(MetricFormat.temperatureUnitSuffix(.celsius), "°C", "celsius suffix is explicit")
        expectEqual(MetricFormat.temperatureUnitSuffix(.fahrenheit), "°F", "fahrenheit suffix is explicit")
        let alertStrings = FeatureStrings.monitorAlerts(.enUS)
        expectEqual(String(format: alertStrings.cpuTemperatureBodyFormat,
                           MetricFormat.temperature(90, unit: .fahrenheit)),
                    "CPU reached 194 °F.", "CPU temperature alert uses the selected unit")
        expectEqual(String(format: alertStrings.batteryTemperatureBodyFormat,
                           MetricFormat.temperature(40, unit: .fahrenheit)),
                    "Battery reached 104 °F.", "battery temperature alert uses the selected unit")
        expectEqual(String(format: alertStrings.cpuTemperatureBodyFormat,
                           MetricFormat.temperature(90, unit: .celsius)),
                    "CPU reached 90 °C.", "CPU temperature alert still supports Celsius")

        // MARK: Temperature sensor selection

        suite.expect(TemperatureSensorSelector.platform(brandString: "Apple M1") == .appleM1Family,
               "Apple M1 uses the mapped CPU core sensor set")
        suite.expect(TemperatureSensorSelector.platform(brandString: "Apple M2 Pro") == .appleM2Family,
               "Apple M2 Pro uses the mapped CPU core sensor set")
        suite.expect(TemperatureSensorSelector.platform(brandString: "Apple M3 Max") == .appleM3Family,
               "Apple M3 Max uses the mapped CPU core sensor set")
        suite.expect(TemperatureSensorSelector.platform(brandString: "Apple M4 Ultra") == .appleM4Family,
               "Apple M4 Ultra uses the mapped CPU core sensor set")
        suite.expect(TemperatureSensorSelector.platform(brandString: "Apple M5") == .appleM5Family,
               "Apple M5 uses the mapped CPU core sensor set")
        suite.expect(TemperatureSensorSelector.platform(brandString: "Apple M10") == .unmappedAppleSilicon
               && TemperatureSensorSelector.platform(brandString: "Apple A19 Pro") == .unmappedAppleSilicon,
               "an Apple chip with no verified core map is recognised as its own case")
        let a18Platform = TemperatureSensorSelector.platform(brandString: "Apple A18 Pro")
        suite.expect(a18Platform == .generic,
               "A18 Pro preserves the CPU temperature path available before 3.3.3")
        suite.expect(TemperatureSensorSelector.platform(brandString: "  Apple A18 Pro\n") == a18Platform,
               "A18 Pro identification ignores surrounding whitespace")
        suite.expect(TemperatureSensorSelector.platform(brandString: "Apple A18 Pro Max") == .unmappedAppleSilicon,
               "A18 Pro compatibility does not guess support for another chip")
        suite.expect(!TemperatureSensorSelector.hasCPUCoreSet(platform: a18Platform),
               "A18 Pro discovery keeps its fallback readings without inventing a per-core map")
        // A small hardware diagnostic sample, followed by synthetic failure cases.
        let a18Sensors: [(key: String, value: Double)] = [
            ("Te05", 66.3), ("Tp05", 66.6), ("Tp0t", 75.0),
            ("Tg0D", 63.1), ("TB0T", 25.1),
        ]
        let a18CPUReadings = a18Sensors.filter {
            TemperatureSensorSelector.isCPUTemperatureKey($0.key, platform: a18Platform)
        }
        suite.expect(a18CPUReadings.map(\.key) == ["Te05", "Tp05", "Tp0t"],
               "A18 Pro discovery retains both CPU families and excludes GPU and battery")
        suite.expectClose(TemperatureSensorSelector.displayedCPUTemperature(
            readings: a18CPUReadings, platform: a18Platform
        ) ?? -1, 75.0, "A18 Pro restores the previous hottest CPU-family reading")
        for key in ["Te05", "Tp05", "Tp0t"] {
            suite.expectClose(TemperatureSensorSelector.displayedCPUTemperature(
                readings: [(key, 66.3)], platform: a18Platform
            ) ?? -1, 66.3, "A18 Pro keeps a readable CPU sensor when other sensors are absent: \(key)")
        }
        let a18InvalidReadings: [(key: String, value: Double)] = [
            ("Tp00", 0), ("Tp01", 7), ("Te05", 125),
            ("Te0S", .nan), ("Tp05", .infinity),
        ]
        suite.expect(TemperatureSensorSelector.displayedCPUTemperature(
            readings: a18InvalidReadings, platform: a18Platform
        ) == nil, "A18 Pro rejects broken readings instead of fabricating a temperature")
        suite.expectClose(TemperatureSensorSelector.displayedCPUTemperature(
            readings: a18InvalidReadings + [("Tp0t", 75)], platform: a18Platform
        ) ?? -1, 75, "broken A18 Pro sensors do not suppress another valid reading")
        suite.expect(TemperatureSensorSelector.displayedCPUTemperature(
            readings: [], platform: a18Platform
        ) == nil, "A18 Pro remains unavailable when no CPU sensor answers")
        suite.expect(TemperatureSensorSelector.platform(brandString: "Generic CPU") == .generic,
               "other processors keep the generic CPU sensor path")
        suite.expect(TemperatureSensorSelector.isCPUTemperatureKey("Tf4E", platform: .appleM3Family)
                && !TemperatureSensorSelector.isCPUTemperatureKey("Tf4E", platform: .appleM4Family)
                && TemperatureSensorSelector.isCPUTemperatureKey("Tp01", platform: .appleM4Family),
               "M3 discovery includes its mapped Tf family without broadening later chips")
        let m1CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp09", 43.0), ("Tp01", 49.0), ("Tp02", 70.0)],
            platform: .appleM1Family
        )
        suite.expectClose(m1CPU ?? -1, 49.0, "M1 family uses hottest mapped CPU core")
        let m2CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp1h", 7.0), ("Tp0j", 52.0), ("Tp0k", 75.0)],
            platform: .appleM2Family
        )
        suite.expectClose(m2CPU ?? -1, 52.0, "M2 family ignores broken low CPU readings")
        suite.expect(TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp1h", 7.0), ("Tp1t", 6.0)],
            platform: .appleM2Family
        ) == nil, "M2 family rejects a sample made only of broken low readings")
        // Some Macs of a mapped generation do not carry that generation's core
        // sensors at all. Before 3.3.3 they showed the hottest CPU-family
        // reading; the restriction that replaced it left them with nothing.
        suite.expectClose(TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp02", 44.0), ("Te04", 51.0)],
            platform: .appleM1Family
        ) ?? -1, 51.0, "an M1 without its mapped core sensors reads its CPU family again")
        suite.expectClose(TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp02", 44.0), ("Te04", 51.0)],
            platform: .unmappedAppleSilicon
        ) ?? -1, 51.0, "an Apple chip with no map at all reads its CPU family again")
        suite.expect(TemperatureSensorSelector.isCPUTemperatureKey("Tp01", platform: .unmappedAppleSilicon)
                && TemperatureSensorSelector.isCPUTemperatureKey("Te05", platform: .unmappedAppleSilicon)
                && !TemperatureSensorSelector.isCPUTemperatureKey("Tg0D", platform: .unmappedAppleSilicon),
               "an unmapped Apple chip discovers its CPU families and still excludes the GPU")
        // A mapped sensor that failed this sample is a different matter: it is
        // never quietly replaced by whatever else the Mac happens to expose.
        suite.expectClose(TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp01", 7.0), ("Tp0b", 44.0), ("Tp02", 71.0)],
            platform: .appleM1Family
        ) ?? -1, 44.0, "a readable mapped M1 core outranks a hotter sensor outside the map")
        var chipTemperatureCache: CachedSensorReading?
        suite.expectClose(TemperatureSensorSelector.stabilizedTemperature(
            49.25, cache: &chipTemperatureCache, now: 100, maxAge: 30,
            minimum: TemperatureSensorSelector.minimumChipTemperature
        ) ?? -1, 49.25, "legitimate chip temperature becomes the cached reading")
        suite.expectClose(TemperatureSensorSelector.stabilizedTemperature(
            7, cache: &chipTemperatureCache, now: 101, maxAge: 30,
            minimum: TemperatureSensorSelector.minimumChipTemperature
        ) ?? -1, 49.25, "broken low CPU or GPU reading preserves the last valid value")
        suite.expect(chipTemperatureCache?.updatedAt == 100 && chipTemperatureCache?.missedSamples == 1,
               "broken low chip reading does not become a fresh cached value")
        suite.expectClose(TemperatureSensorSelector.stabilizedTemperature(
            50, cache: &chipTemperatureCache, now: 102, maxAge: 30,
            minimum: TemperatureSensorSelector.minimumChipTemperature
        ) ?? -1, 50, "next legitimate chip reading replaces the bridged value")
        var batteryTemperatureCache: CachedSensorReading?
        suite.expectClose(TemperatureSensorSelector.stabilizedTemperature(
            7, cache: &batteryTemperatureCache, now: 100, maxAge: 30
        ) ?? -1, 7, "chip floor does not reject a legitimate low battery reading")
        suite.expectClose(TemperatureSensorSelector.stabilizedTemperature(
            1, cache: &batteryTemperatureCache, now: 101, maxAge: 30
        ) ?? -1, 7, "an invalid battery sample bridges the last valid reading")
        suite.expect(batteryTemperatureCache?.updatedAt == 100,
               "a bridged battery temperature keeps the real sample timestamp")
        var invalidBatteryTemperatureCache: CachedSensorReading?
        suite.expect(TemperatureSensorSelector.stabilizedTemperature(
            1, cache: &invalidBatteryTemperatureCache, now: 100, maxAge: 30
        ) == nil, "existing battery lower bound remains unchanged")
        let m3CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Te05", 44.0), ("Tf4E", 53.0), ("Tf4F", 76.0)],
            platform: .appleM3Family
        )
        suite.expectClose(m3CPU ?? -1, 53.0, "M3 family uses hottest mapped CPU core")
        let m4CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 44.5), ("Tp01", 51.6), ("Tp0W", 67.0), ("Te04", 43.2)],
            platform: .appleM4Family
        )
        suite.expectClose(m4CPU ?? -1, 51.6, "M4 family uses hottest mapped CPU core instead of auxiliary hotspots")
        let m5CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 45.0), ("Tp0y", 54.0), ("Tp0z", 80.0)],
            platform: .appleM5Family
        )
        suite.expectClose(m5CPU ?? -1, 54.0, "M5 family uses hottest mapped CPU core")
        let m4InvalidCPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp01", 0.5), ("Tp05", 130.0), ("Tp09", 49.25), ("Tp0W", 67.0)],
            platform: .appleM4Family
        )
        suite.expectClose(m4InvalidCPU ?? -1, 49.25, "mapped CPU core selection ignores invalid temperatures")
        // A mapped core that answers always wins, so an auxiliary hotspot can
        // never stand in for one while the core set is talking. A tick with no
        // plausible core reading falls back to the CPU families, exactly as it
        // did before 3.3.3.
        suite.expectClose(TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp01", 44.5), ("Tp0W", 67.0)],
            platform: .appleM4Family
        ) ?? -1, 44.5, "a mapped core outranks a hotter auxiliary sensor")
        suite.expectClose(TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 44.5), ("Tp0W", 67.0)],
            platform: .appleM4Family
        ) ?? -1, 67.0, "an M4 carrying none of its mapped cores reads its CPU family again")
        suite.expect(TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp0W", 130.0)],
            platform: .unmappedAppleSilicon
        ) == nil, "the compatibility reading still refuses an implausible temperature")

        // Real sensor dumps, so the restored reading is checked against the
        // machines that lost it rather than against invented keys.
        //
        // Mac mini (2020), Macmini9,1, Apple M1, reported on 3.3.2 (issue
        // #1353): not one of its sensors is in this chip generation's mapped
        // core set, which is what 3.3.3 then required before showing anything.
        let macMini9_1M1Sensors: [(key: String, value: Double)] = [
            ("Te0a", 36.31), ("Te0b", 36.31), ("Te0x", 38.08), ("Te0z", 38.08),
            ("Te3a", 37.95), ("Te3b", 46.65), ("Te3x", 40.02), ("Te3z", 60.02),
            ("Tp2a", 38.94), ("Tp2b", 48.04), ("Tp2x", 45.98), ("Tp2z", 60.98),
            ("Tp3a", 39.62), ("Tp3b", 47.02), ("Tp3x", 48.59), ("Tp3z", 60.59),
            ("Tp4a", 40.71), ("Tp4b", 50.81), ("Tp4x", 47.61), ("Tp4z", 64.61),
            ("Tp5a", 38.77), ("Tp5b", 48.97), ("Tp5x", 41.22), ("Tp5z", 57.22),
            ("Tp7a", 38.84), ("Tp7b", 47.94), ("Tp7x", 43.00), ("Tp7z", 58.00),
            ("Tp8a", 39.50), ("Tp8b", 46.90), ("Tp8x", 45.34), ("Tp8z", 57.34),
            ("Tp9a", 40.15), ("Tp9b", 50.25), ("Tp9x", 44.97), ("Tp9z", 61.97),
        ]
        suite.expect(macMini9_1M1Sensors.allSatisfy {
            TemperatureSensorSelector.isCPUTemperatureKey($0.key, platform: .appleM1Family)
        } && !macMini9_1M1Sensors.contains {
            TemperatureSensorSelector.isCPUCoreKey($0.key, platform: .appleM1Family)
        }, "this M1 exposes CPU sensors, none of them in the mapped core set")
        suite.expectClose(TemperatureSensorSelector.displayedCPUTemperature(
            readings: macMini9_1M1Sensors, platform: .appleM1Family
        ) ?? -1, 64.61, "this M1 shows the CPU temperature it showed on 3.3.2 again")

        // This project's own Mac, Apple M4, read with --sensors: its mapped
        // cores answer and sit well below the hottest auxiliary sensor, so it
        // is proof that restoring the sweep leaves a mapped Mac untouched.
        let appleM4Sensors: [(key: String, value: Double)] = [
            ("Te05", 45.01), ("Te09", 44.70), ("Te0H", 45.29), ("Te0S", 44.84),
            ("Tp01", 46.12), ("Tp00", 39.02), ("Tp0W", 62.56), ("Tp3X", 69.00),
        ]
        suite.expectClose(TemperatureSensorSelector.displayedCPUTemperature(
            readings: appleM4Sensors, platform: .appleM4Family
        ) ?? -1, 46.12, "a mapped M4 keeps reading its own cores, not the hotter hotspot")
        let genericCPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 44.5), ("Tp01", 51.6)],
            platform: .generic
        )
        suite.expectClose(genericCPU ?? -1, 51.6, "generic CPU sensor selection preserves previous hottest behavior")

        // MARK: Hot CPU alert

        var spikeGate = SustainedAlertGate()
        suite.expect(!spikeGate.shouldAlert(reading: 99, threshold: 90, readAt: 100),
               "a single hot reading is not a hot CPU yet")
        suite.expect(!spikeGate.shouldAlert(reading: 99, threshold: 90, readAt: 108),
               "a second hot reading inside the window still waits")
        suite.expect(spikeGate.shouldAlert(reading: 99, threshold: 90, readAt: 112),
               "a temperature that holds past the window alerts")

        var carriedGate = SustainedAlertGate()
        suite.expect(!carriedGate.shouldAlert(reading: 101, threshold: 90, readAt: 200),
               "the reading behind a spike starts the window")
        var carriedAlerts = 0
        for _ in 0..<60 {
            if carriedGate.shouldAlert(reading: 101, threshold: 90, readAt: 200) {
                carriedAlerts += 1
            }
        }
        suite.expect(carriedAlerts == 0,
               "the same reading served again never ages into an alert on its own")

        var coolingGate = SustainedAlertGate()
        _ = coolingGate.shouldAlert(reading: 99, threshold: 90, readAt: 300)
        suite.expect(!coolingGate.shouldAlert(reading: 52, threshold: 90, readAt: 315),
               "a reading back under the limit does not alert")
        suite.expect(!coolingGate.shouldAlert(reading: 99, threshold: 90, readAt: 330),
               "cooling down restarts the window instead of resuming the old one")
        suite.expect(coolingGate.shouldAlert(reading: 99, threshold: 90, readAt: 345),
               "the restarted window alerts on its own merits")

        var quietGate = SustainedAlertGate()
        suite.expect(!quietGate.shouldAlert(reading: 89, threshold: 90, readAt: 400),
               "a reading under the limit is not hot")
        suite.expect(!quietGate.shouldAlert(reading: 89, threshold: 90, readAt: 500),
               "staying under the limit never alerts")
        suite.expect(!quietGate.shouldAlert(reading: nil, threshold: 90, readAt: 600),
               "a missing temperature does not alert")
        suite.expect(!quietGate.shouldAlert(reading: 99, threshold: 90, readAt: nil),
               "a temperature with no reading time does not alert")

        // MARK: Uptime formatting

        expectEqual(MetricFormat.uptime(0), "0min", "uptime zero")
        expectEqual(MetricFormat.uptime(59), "0min", "uptime under one minute")
        expectEqual(MetricFormat.uptime(60), "1min", "uptime one minute")
        expectEqual(MetricFormat.uptime(3_600), "1h 0min", "uptime one hour")
        expectEqual(MetricFormat.uptime(93_600), "1d 2h", "uptime days and hours")
        expectEqual(MetricFormat.uptime(8 * 86_400 + 21 * 3_600 + 8 * 60), "8d 21h",
                    "uptime keeps days compact")

        // MARK: Memory used

        let used = MetricFormat.memoryUsed(totalBytes: 16 * 1024,
                                           appBytes: 5 * 1024,
                                           pageSize: 1024,
                                           wiredPages: 2,
                                           compressorPages: 1,
                                           tagStoragePages: 1)
        suite.expect(used == 9 * 1024, "memory used includes app, wired, compressed and tagged storage")
        suite.expect(MetricFormat.memoryUsed(totalBytes: 16, appBytes: 20,
                                       pageSize: 1, wiredPages: 0,
                                       compressorPages: 0, tagStoragePages: 0) == 16,
               "memory used clamps impossible used memory")

        var vmStats = vorssaint_vm_statistics64_rev3_t()
        vmStats.wire_count = 2
        vmStats.purgeable_count = 3
        vmStats.compressor_page_count = 4
        vmStats.external_page_count = 5
        vmStats.internal_page_count = 6
        vmStats.total_tag_storage_pages = 7
        suite.expect(VMStatisticsDecoder.decode(vmStats,
                                          returnedCount: VMStatisticsDecoder.rev1Count - 1) == nil,
               "VM statistics rejects a truncated legacy payload")
        suite.expect(VMStatisticsDecoder.decode(vmStats,
                                          returnedCount: VMStatisticsDecoder.rev1Count) ==
                   VMStatisticsSnapshot(wiredPages: 2,
                                        purgeablePages: 3,
                                        compressorPages: 4,
                                        externalPages: 5,
                                        internalPages: 6,
                                        tagStoragePages: 0),
               "VM statistics decodes the typed legacy prefix")
        suite.expect(VMStatisticsDecoder.decode(vmStats,
                                          returnedCount: VMStatisticsDecoder.rev2Count)?.tagStoragePages == 0,
               "VM statistics does not read tagged storage from a rev2 payload")
        suite.expect(VMStatisticsDecoder.decode(vmStats,
                                          returnedCount: VMStatisticsDecoder.rev3Count)?.tagStoragePages == 7,
               "VM statistics reads tagged storage from a rev3 payload")
        suite.expect(VMStatisticsDecoder.validatedTagStoragePages(2, totalBytes: 16, pageSize: 4) == 2,
               "VM statistics accepts plausible tagged storage")
        suite.expect(VMStatisticsDecoder.validatedTagStoragePages(5, totalBytes: 16, pageSize: 4) == 0,
               "VM statistics rejects tagged storage larger than physical memory")
        suite.expect(VMStatisticsDecoder.validatedTagStoragePages(1, totalBytes: 16, pageSize: 0) == 0,
               "VM statistics rejects tagged storage without a page size")

        // MARK: App memory

        let appUsed = MetricFormat.appMemory(totalBytes: 16 * 1024,
                                             pageSize: 1024,
                                             internalPages: 10,
                                             purgeablePages: 3)
        suite.expect(appUsed == 7 * 1024, "app memory excludes purgeable pages from internal pages")
        suite.expect(MetricFormat.appMemory(totalBytes: 16 * 1024, pageSize: 1024,
                                      internalPages: 2, purgeablePages: 5) == 0,
               "app memory is zero when purgeable pages exceed internal pages")
        suite.expect(MetricFormat.appMemory(totalBytes: 16, pageSize: 1,
                                      internalPages: 100, purgeablePages: 0) == 16,
               "app memory clamps to total physical memory")
        suite.expect(MetricFormat.appMemory(totalBytes: 0, pageSize: 1024,
                                      internalPages: 10, purgeablePages: 0) == 0,
               "app memory is zero when total is zero")
        suite.expect(MetricFormat.appMemory(totalBytes: 16 * 1024, pageSize: 0,
                                      internalPages: 10, purgeablePages: 0) == 0,
               "app memory is zero when page size is zero")
        suite.expect(MetricFormat.selectedMemory(used: 12, app: 7, metric: "app") == 7,
               "the shared memory selector returns app memory")
        suite.expect(MetricFormat.selectedMemory(used: 12, app: 7, metric: "unknown") == 12,
               "an unknown shared memory selector falls back to used memory")

        suite.expect(MetricFormat.compressedMemory(totalBytes: 16 * 1024, pageSize: 1024, compressorPages: 5)
               == 5 * 1024,
               "compressed memory is compressor pages in bytes")
        suite.expect(MetricFormat.compressedMemory(totalBytes: 16, pageSize: 1, compressorPages: 100) == 16,
               "compressed memory clamps to total physical memory")
        suite.expect(MetricFormat.compressedMemory(totalBytes: 0, pageSize: 1024, compressorPages: 5) == 0,
               "compressed memory is zero when total is zero")
        suite.expect(MetricFormat.cachedFiles(totalBytes: 16 * 1024, pageSize: 1024, fileBackedPages: 3)
               == 3 * 1024,
               "cached files are file-backed pages in bytes")
        suite.expect(MetricFormat.cachedFiles(totalBytes: 16, pageSize: 1, fileBackedPages: 100) == 16,
               "cached files clamp to total physical memory")
        suite.expect(MetricFormat.cachedFiles(totalBytes: 16 * 1024, pageSize: 0, fileBackedPages: 3) == 0,
               "cached files are zero when page size is zero")

        // MARK: Connected USB Devices

        let validUSBProps: [String: Any] = [
            "USB Product Name": "SanDisk Extreme",
            "USB Vendor Name": "SanDisk",
            "idVendor": 0x0781,
            "idProduct": 0x5583,
            "locationID": 0x01100000,
        ]
        let parsedUSB = USBDeviceSampler.parseDevice(properties: validUSBProps)
        suite.expect(parsedUSB?.name == "SanDisk Extreme" && parsedUSB?.vendorName == "SanDisk",
                     "external USB product and vendor names are retained")
        suite.expect(parsedUSB?.id == "\(0x0781)-\(0x5583)-loc\(0x01100000)",
                     "USB devices fall back to their physical location for a stable identity")

        let rootHubProps: [String: Any] = ["idVendor": 0, "idProduct": 0]
        suite.expect(USBDeviceSampler.parseDevice(properties: rootHubProps) == nil,
                     "root controller hubs are excluded")
        let externalHubProps: [String: Any] = ["bDeviceClass": 9, "idVendor": 1, "idProduct": 1]
        suite.expect(USBDeviceSampler.parseDevice(properties: externalHubProps) == nil,
                     "external USB hubs are excluded so their bus entries do not inflate the count")
        let billboardProps: [String: Any] = ["bDeviceClass": 17, "idVendor": 1, "idProduct": 1]
        suite.expect(USBDeviceSampler.parseDevice(properties: billboardProps) == nil,
                     "USB-C billboard devices are excluded because they only report the display mode")
        let unnamedProps: [String: Any] = ["idVendor": 2, "idProduct": 3, "locationID": 5]
        suite.expect(USBDeviceSampler.parseDevice(properties: unnamedProps)?.name == "",
                     "a device without a product name stays unnamed so the list shows its translated fallback")
        let builtInProps: [String: Any] = ["Built-In": true, "idVendor": 1, "idProduct": 1]
        suite.expect(USBDeviceSampler.parseDevice(properties: builtInProps) == nil,
                     "built-in USB hardware is excluded")
        let nonRemovableProps: [String: Any] = ["non-removable": "yes", "idVendor": 1, "idProduct": 1]
        suite.expect(USBDeviceSampler.parseDevice(properties: nonRemovableProps) == nil,
                     "non-removable USB hardware is excluded")

        let duplicateUSB = ConnectedUSBDevice(id: "same", name: "First", vendorName: nil,
                                              vendorId: 1, productId: 1, locationId: 1)
        let uniqueUSB = ConnectedUSBDevice(id: "other", name: "Second", vendorName: nil,
                                           vendorId: 1, productId: 2, locationId: 2)
        suite.expect(USBDeviceSampler.deduplicated([duplicateUSB, duplicateUSB, uniqueUSB]).map(\.id)
                         == ["same", "other"],
                     "USB devices are deduplicated by their stable registry identifier")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.connectedDevices(language)
            suite.expect(!strings.title.isEmpty && !strings.hubDescription.isEmpty
                    && !strings.noDevices.isEmpty && !strings.unnamedDevice.isEmpty
                    && !strings.menuBarLabel.isEmpty && !strings.oneConnected.isEmpty,
                         "connected device strings are complete for \(language.rawValue)")
        }

        MetricFormat.locale = originalLocale
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
enum DiskTemperatureLogicTests {
    static func run(_ suite: TestSuite) {
        let internalDisk = DiskDeviceReading(
            id: "int", name: "Internal", mountPath: "/", bsdName: "disk0", wholeDisk: "disk0",
            ioCounterID: "disk0", fileSystem: "APFS", totalBytes: 100, freeBytes: 50,
            usedBytes: 50, isInternal: true, isRemovable: false, isEjectable: false,
            smart: DiskSMARTReading(temperatureCelsius: 40.0),
            readBytesPerSec: nil, writeBytesPerSec: nil, totalReadBytes: nil, totalWrittenBytes: nil
        )
        
        let externalDisk = DiskDeviceReading(
            id: "ext", name: "External", mountPath: "/Volumes/Ext", bsdName: "disk1", wholeDisk: "disk1",
            ioCounterID: "disk1", fileSystem: "APFS", totalBytes: 200, freeBytes: 100,
            usedBytes: 100, isInternal: false, isRemovable: true, isEjectable: true,
            smart: DiskSMARTReading(temperatureCelsius: 45.0),
            readBytesPerSec: nil, writeBytesPerSec: nil, totalReadBytes: nil, totalWrittenBytes: nil
        )
        
        let noSmartDisk = DiskDeviceReading(
            id: "nosmart", name: "NoSmart", mountPath: "/Volumes/NoSmart", bsdName: "disk2", wholeDisk: "disk2",
            ioCounterID: "disk2", fileSystem: "APFS", totalBytes: 300, freeBytes: 150,
            usedBytes: 150, isInternal: false, isRemovable: true, isEjectable: true,
            smart: nil,
            readBytesPerSec: nil, writeBytesPerSec: nil, totalReadBytes: nil, totalWrittenBytes: nil
        )

        // 1. External SMART priority
        let reading1 = DiskReading(devices: [internalDisk, externalDisk])
        suite.expect(DiskSupport.temperatureDisk(from: reading1)?.id == "ext",
                     "external SMART SSD should be prioritized over internal")
        suite.expect(DiskSupport.temperatureDisk(from: reading1)?.smart?.temperatureCelsius == 45.0,
                     "selected external disk should have correct temperature")

        // 2. Internal fallback
        let reading2 = DiskReading(devices: [internalDisk])
        suite.expect(DiskSupport.temperatureDisk(from: reading2)?.id == "int",
                     "internal SMART SSD should be selected when no external SMART SSD exists")
        suite.expect(DiskSupport.temperatureDisk(from: reading2)?.smart?.temperatureCelsius == 40.0,
                     "selected internal disk should have correct temperature")

        // 3. No SMART -> nil
        let reading3 = DiskReading(devices: [noSmartDisk])
        suite.expect(DiskSupport.temperatureDisk(from: reading3) == nil,
                     "should return nil when no disks have SMART temperature")

        // 4. No-SMART External + SMART Internal -> Internal
        let reading4 = DiskReading(devices: [noSmartDisk, internalDisk])
        suite.expect(DiskSupport.temperatureDisk(from: reading4)?.id == "int",
                     "internal SMART SSD should be selected over external disk without SMART")
    }
}

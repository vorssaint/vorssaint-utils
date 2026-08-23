// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import VMStatisticsCompat

struct VMStatisticsSnapshot: Equatable {
    let wiredPages: UInt64
    let purgeablePages: UInt64
    let compressorPages: UInt64
    let externalPages: UInt64
    let internalPages: UInt64
    let tagStoragePages: UInt64
}

enum VMStatisticsDecoder {
    static let rev1Count = mach_msg_type_number_t(VORSSAINT_HOST_VM_INFO64_REV1_COUNT)
    static let rev2Count = mach_msg_type_number_t(VORSSAINT_HOST_VM_INFO64_REV2_COUNT)
    static let rev3Count = mach_msg_type_number_t(VORSSAINT_HOST_VM_INFO64_REV3_COUNT)

    static func read() -> VMStatisticsSnapshot? {
        var raw = vorssaint_vm_statistics64_rev3_t()
        var returnedCount = mach_msg_type_number_t()
        guard vorssaint_read_vm_statistics64(&raw, &returnedCount) == KERN_SUCCESS else { return nil }
        return decode(raw, returnedCount: returnedCount)
    }

    static func decode(_ raw: vorssaint_vm_statistics64_rev3_t,
                       returnedCount: mach_msg_type_number_t) -> VMStatisticsSnapshot? {
        guard returnedCount >= rev1Count else { return nil }
        let returnedTaggedStorageFields = returnedCount >= rev3Count
        return VMStatisticsSnapshot(
            wiredPages: UInt64(raw.wire_count),
            purgeablePages: UInt64(raw.purgeable_count),
            compressorPages: UInt64(raw.compressor_page_count),
            externalPages: UInt64(raw.external_page_count),
            internalPages: UInt64(raw.internal_page_count),
            tagStoragePages: returnedTaggedStorageFields ? raw.total_tag_storage_pages : 0)
    }

    static func validatedTagStoragePages(_ pages: UInt64,
                                         totalBytes: UInt64,
                                         pageSize: UInt64) -> UInt64 {
        guard pageSize > 0, pages <= totalBytes / pageSize else { return 0 }
        return pages
    }
}

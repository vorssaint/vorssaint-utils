// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin

enum MemoryCleanupService {
    @discardableResult
    static func freeRAM() -> kern_return_t {
        var state: Int32 = 0
        return mach_vm_purgable_control(
            mach_task_self_,
            0,
            VM_PURGABLE_PURGE_ALL,
            &state
        )
    }
}

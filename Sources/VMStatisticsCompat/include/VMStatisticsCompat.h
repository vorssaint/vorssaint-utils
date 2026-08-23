// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#ifndef VORSSAINT_VM_STATISTICS_COMPAT_H
#define VORSSAINT_VM_STATISTICS_COMPAT_H

#include <mach/host_info.h>
#include <mach/mach.h>
#include <mach/vm_statistics.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

// Xcode 16's macOS SDK stops before the fields added to HOST_VM_INFO64 in
// macOS 26. Keep the public rev3 layout in C so its representation follows the
// C ABI, rather than relying on Swift struct layout or raw byte offsets.
typedef struct {
    natural_t free_count;
    natural_t active_count;
    natural_t inactive_count;
    natural_t wire_count;
    uint64_t zero_fill_count;
    uint64_t reactivations;
    uint64_t pageins;
    uint64_t pageouts;
    uint64_t faults;
    uint64_t cow_faults;
    uint64_t lookups;
    uint64_t hits;
    uint64_t purges;
    natural_t purgeable_count;
    natural_t speculative_count;
    uint64_t decompressions;
    uint64_t compressions;
    uint64_t swapins;
    uint64_t swapouts;
    natural_t compressor_page_count;
    natural_t throttled_count;
    natural_t external_page_count;
    natural_t internal_page_count;
    uint64_t total_uncompressed_pages_in_compressor;
    uint64_t swapped_count;
    uint64_t total_tag_storage_pages;
    uint64_t nontag_pageable_tag_storage_pages;
    uint64_t nontag_wired_tag_storage_pages;
    uint64_t free_tag_storage_pages;
    uint64_t tag_storing_tag_storage_pages;
    uint64_t total_tagged_pages;
    uint64_t resident_tagged_pages;
    uint64_t compressed_tagged_pages;
    uint64_t tagged_compressions;
    uint64_t tagged_decompressions;
    uint64_t compressed_tag_storage_bytes;
} __attribute__((aligned(8))) vorssaint_vm_statistics64_rev3_t;

enum {
    VORSSAINT_HOST_VM_INFO64_REV1_COUNT =
        offsetof(vorssaint_vm_statistics64_rev3_t, swapped_count) / sizeof(integer_t),
    VORSSAINT_HOST_VM_INFO64_REV2_COUNT =
        offsetof(vorssaint_vm_statistics64_rev3_t, total_tag_storage_pages) / sizeof(integer_t),
    VORSSAINT_HOST_VM_INFO64_REV3_COUNT =
        sizeof(vorssaint_vm_statistics64_rev3_t) / sizeof(integer_t),
};

_Static_assert(sizeof(integer_t) == 4, "HOST_VM_INFO64 counts must use 32-bit integer_t words");
_Static_assert(_Alignof(vorssaint_vm_statistics64_rev3_t) == 8,
               "vm_statistics64 rev3 must remain 64-bit aligned");
_Static_assert(sizeof(vorssaint_vm_statistics64_rev3_t) == 248,
               "unexpected HOST_VM_INFO64 rev3 size");
_Static_assert(offsetof(vorssaint_vm_statistics64_rev3_t, total_tag_storage_pages) == 160,
               "unexpected HOST_VM_INFO64 tagged-storage offset");

// Every supported SDK exposes this prefix. These checks fail at compile time if
// the compatibility definition ever stops matching Apple's imported C layout.
_Static_assert(offsetof(vorssaint_vm_statistics64_rev3_t, wire_count) ==
                   offsetof(vm_statistics64_data_t, wire_count),
               "wire_count layout mismatch");
_Static_assert(offsetof(vorssaint_vm_statistics64_rev3_t, purgeable_count) ==
                   offsetof(vm_statistics64_data_t, purgeable_count),
               "purgeable_count layout mismatch");
_Static_assert(offsetof(vorssaint_vm_statistics64_rev3_t, compressor_page_count) ==
                   offsetof(vm_statistics64_data_t, compressor_page_count),
               "compressor_page_count layout mismatch");
_Static_assert(offsetof(vorssaint_vm_statistics64_rev3_t, external_page_count) ==
                   offsetof(vm_statistics64_data_t, external_page_count),
               "external_page_count layout mismatch");
_Static_assert(offsetof(vorssaint_vm_statistics64_rev3_t, internal_page_count) ==
                   offsetof(vm_statistics64_data_t, internal_page_count),
               "internal_page_count layout mismatch");
_Static_assert(offsetof(vorssaint_vm_statistics64_rev3_t,
                        total_uncompressed_pages_in_compressor) ==
                   offsetof(vm_statistics64_data_t,
                            total_uncompressed_pages_in_compressor),
               "total_uncompressed_pages_in_compressor layout mismatch");
_Static_assert(VORSSAINT_HOST_VM_INFO64_REV1_COUNT == HOST_VM_INFO64_REV1_COUNT,
               "HOST_VM_INFO64 rev1 count mismatch with the active SDK");

#ifdef HOST_VM_INFO64_REV2_COUNT
// SDK 15 stops at rev1; newer SDKs can also anchor the appended rev2 field and
// its boundary to Apple's definitions.
_Static_assert(offsetof(vorssaint_vm_statistics64_rev3_t, swapped_count) ==
                   offsetof(vm_statistics64_data_t, swapped_count),
               "swapped_count layout mismatch with the active SDK");
_Static_assert(VORSSAINT_HOST_VM_INFO64_REV2_COUNT == HOST_VM_INFO64_REV2_COUNT,
               "HOST_VM_INFO64 rev2 count mismatch with the active SDK");
#endif

#ifdef HOST_VM_INFO64_REV3_COUNT
_Static_assert(VORSSAINT_HOST_VM_INFO64_REV3_COUNT == HOST_VM_INFO64_REV3_COUNT,
               "HOST_VM_INFO64 rev3 count mismatch with the active SDK");
_Static_assert(offsetof(vorssaint_vm_statistics64_rev3_t, total_tag_storage_pages) ==
                   offsetof(vm_statistics64_data_t, total_tag_storage_pages),
               "total_tag_storage_pages layout mismatch with the active SDK");
#endif

// count is both the input capacity and the returned ABI revision. The kernel
// fills only the newest revision that fits, so older kernels return a shorter
// count and the decoder below leaves tagged storage unavailable.
static inline kern_return_t
vorssaint_read_vm_statistics64(vorssaint_vm_statistics64_rev3_t *statistics,
                               mach_msg_type_number_t *returned_count) {
    if (statistics == NULL || returned_count == NULL) {
        return KERN_INVALID_ARGUMENT;
    }

    memset(statistics, 0, sizeof(*statistics));
    *returned_count = VORSSAINT_HOST_VM_INFO64_REV3_COUNT;
    mach_port_t host = mach_host_self();
    kern_return_t result = host_statistics64(
        host,
        HOST_VM_INFO64,
        (host_info64_t)statistics,
        returned_count);
    mach_port_deallocate(mach_task_self(), host);
    return result;
}

#endif

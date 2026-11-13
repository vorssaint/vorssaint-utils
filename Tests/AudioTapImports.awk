# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

# Inspect the linked executable. An availability guard runs after dyld has
# already resolved its imports on macOS 14.0 and 14.1.
/ \(from [^)]+\)/ {
    sawImports = 1
    if (/CATapDescription|_AudioHardware(Create|Destroy)ProcessTap / && !/\[weak-import\]/) {
        print "Process tap required at launch:" $0 > "/dev/stderr"
        failed = 1
    }
}
END {
    if (!sawImports) {
        print "No dyld imports found in the executable" > "/dev/stderr"
        failed = 1
    }
    exit failed
}

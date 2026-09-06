// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CutPastePrivilegeSupport {
    static func needsPrivileges(_ error: Error) -> Bool {
        let error = error as NSError
        var candidates = [error]
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            candidates.append(underlying)
        }
        return candidates.contains(where: isPermissionDenied)
    }

    private static func isPermissionDenied(_ error: NSError) -> Bool {
        switch error.domain {
        case NSCocoaErrorDomain:
            return error.code == NSFileWriteNoPermissionError
                || error.code == NSFileReadNoPermissionError
        case NSPOSIXErrorDomain:
            return error.code == Int(EACCES) || error.code == Int(EPERM)
        default:
            return false
        }
    }
}

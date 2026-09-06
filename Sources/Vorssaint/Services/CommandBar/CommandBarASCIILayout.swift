// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon
import Foundation

/// One-shot Text Input Services switch around Command Bar show/hide. Remembers
/// the previous source only after a successful switch so a close with no open
/// change leaves the Mac alone.
enum CommandBarASCIILayout {
    private static var previousSourceID: String?

    static func applyOnShow(enabled: Bool) {
        guard enabled, previousSourceID == nil else { return }
        let apply = {
            let sources = selectableKeyboardLayouts()
            let descriptors = sources.map(descriptor(for:))
            let currentID = currentKeyboardSourceID()
            guard let targetID = CommandBarASCIILayoutSupport.openSelection(
                    currentID: currentID, sources: descriptors),
                  let target = sources.first(where: { sourceID($0) == targetID })
            else { return }
            previousSourceID = currentID
            _ = TISSelectInputSource(target)
        }
        runOnMain(apply)
    }

    static func restoreOnHide() {
        let restore = {
            let previousID = previousSourceID
            previousSourceID = nil
            guard let previousID else { return }
            let currentID = currentKeyboardSourceID()
            guard let restoreID = CommandBarASCIILayoutSupport.closeSelection(
                    previousID: previousID, currentID: currentID),
                  let source = selectableKeyboardLayouts().first(where: { sourceID($0) == restoreID })
            else { return }
            _ = TISSelectInputSource(source)
        }
        runOnMain(restore)
    }

    private static func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    private static func currentKeyboardSourceID() -> String? {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return sourceID(current)
    }

    private static func selectableKeyboardLayouts() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false) else { return [] }
        let values = list.takeRetainedValue() as NSArray
        return (values as! [TISInputSource]).filter {
            stringProperty($0, kTISPropertyInputSourceCategory)
                == kTISCategoryKeyboardInputSource as String
                && boolProperty($0, kTISPropertyInputSourceIsSelectCapable)
                && stringProperty($0, kTISPropertyInputSourceType)
                    == kTISTypeKeyboardLayout as String
        }
    }

    private static func descriptor(for source: TISInputSource) -> CommandBarASCIILayoutSupport.Source {
        CommandBarASCIILayoutSupport.Source(
            id: sourceID(source) ?? "",
            isASCIICapable: boolProperty(source, kTISPropertyInputSourceIsASCIICapable),
            isSelectCapable: boolProperty(source, kTISPropertyInputSourceIsSelectCapable),
            isKeyboardLayout: stringProperty(source, kTISPropertyInputSourceType)
                == kTISTypeKeyboardLayout as String)
    }

    private static func sourceID(_ source: TISInputSource) -> String? {
        stringProperty(source, kTISPropertyInputSourceID)
    }

    private static func stringProperty(_ source: TISInputSource, _ property: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func boolProperty(_ source: TISInputSource, _ property: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, property) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}

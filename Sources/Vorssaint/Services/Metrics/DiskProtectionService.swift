// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import DiskArbitration
import Foundation

enum DiskEjectState: Equatable {
    case ejecting
    case ready
    case failed(String)
}

final class DiskProtectionService: ObservableObject {
    static let shared = DiskProtectionService()

    @Published private(set) var states: [String: DiskEjectState] = [:]

    private init() {}

    func state(for disk: DiskDeviceReading) -> DiskEjectState? {
        states[disk.id]
    }

    func ejectAll(_ disks: [DiskDeviceReading]) {
        uniqueEjectableDisks(from: disks).forEach(eject)
    }

    func eject(_ disk: DiskDeviceReading) {
        guard disk.canEject else { return }
        DispatchQueue.main.async {
            self.states[disk.id] = .ejecting
        }
        let volumeURL = URL(fileURLWithPath: disk.mountPath)
        DispatchQueue.global(qos: .utility).async {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volumeURL)
                self.complete(diskID: disk.id, state: .ready)
            } catch {
                self.ejectWithDiskArbitration(disk, fallbackError: error)
            }
        }
    }

    private func ejectWithDiskArbitration(_ disk: DiskDeviceReading, fallbackError: Error) {
        guard let ejectBSDName = disk.ejectBSDName else {
            complete(diskID: disk.id, state: .failed(fallbackError.localizedDescription))
            return
        }
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            complete(diskID: disk.id, state: .failed(fallbackError.localizedDescription))
            return
        }
        let queue = DispatchQueue(label: "com.vorssaint.utils.disk-eject.\(ejectBSDName)", qos: .utility)
        DASessionSetDispatchQueue(session, queue)

        guard let daDisk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, "/dev/\(ejectBSDName)") else {
            DASessionSetDispatchQueue(session, nil)
            complete(diskID: disk.id, state: .failed(fallbackError.localizedDescription))
            return
        }

        let context = DiskEjectContext(service: self,
                                       diskID: disk.id,
                                       session: session,
                                       queue: queue,
                                       disk: daDisk)
        DADiskUnmount(daDisk,
                      DADiskUnmountOptions(kDADiskUnmountOptionWhole),
                      diskUnmountCallback,
                      Unmanaged.passRetained(context).toOpaque())
    }

    private func uniqueEjectableDisks(from disks: [DiskDeviceReading]) -> [DiskDeviceReading] {
        var seen = Set<String>()
        return disks.filter { disk in
            guard disk.canEject, let id = disk.ejectBSDName else { return false }
            return seen.insert(id).inserted
        }
    }

    fileprivate func complete(diskID: String, state: DiskEjectState) {
        DispatchQueue.main.async {
            self.states[diskID] = state
        }
    }

    fileprivate static func message(for dissenter: DADissenter) -> String {
        if let statusString = DADissenterGetStatusString(dissenter) {
            let text = statusString as String
            if !text.isEmpty { return text }
        }
        return "Disk Arbitration \(DADissenterGetStatus(dissenter))"
    }
}

private final class DiskEjectContext {
    weak var service: DiskProtectionService?
    let diskID: String
    let session: DASession
    let queue: DispatchQueue
    let disk: DADisk

    init(service: DiskProtectionService, diskID: String, session: DASession,
         queue: DispatchQueue, disk: DADisk) {
        self.service = service
        self.diskID = diskID
        self.session = session
        self.queue = queue
        self.disk = disk
    }

    deinit {
        DASessionSetDispatchQueue(session, nil)
    }
}

private func diskUnmountCallback(_ disk: DADisk,
                                 _ dissenter: DADissenter?,
                                 _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    if let dissenter {
        let box = Unmanaged<DiskEjectContext>.fromOpaque(context).takeRetainedValue()
        box.service?.complete(diskID: box.diskID,
                              state: .failed(DiskProtectionService.message(for: dissenter)))
        return
    }

    _ = Unmanaged<DiskEjectContext>.fromOpaque(context).takeUnretainedValue()
    DADiskEject(disk, DADiskEjectOptions(kDADiskEjectOptionDefault), diskEjectCallback, context)
}

private func diskEjectCallback(_ disk: DADisk,
                               _ dissenter: DADissenter?,
                               _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let box = Unmanaged<DiskEjectContext>.fromOpaque(context).takeRetainedValue()
    if let dissenter {
        box.service?.complete(diskID: box.diskID,
                              state: .failed(DiskProtectionService.message(for: dissenter)))
    } else {
        box.service?.complete(diskID: box.diskID, state: .ready)
    }
}

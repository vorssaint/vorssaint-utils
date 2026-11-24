// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FanControlOwnershipTests {
    static func run(_ suite: TestSuite) {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("fan-ownership-\(UUID())", isDirectory: true)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
            defer { try? manager.removeItem(at: directory) }
            let lock = directory.appendingPathComponent("vorssaint-fan-control.lock")
            let first = FanControlOwnership(directory: directory)
            let second = FanControlOwnership(directory: directory)
            guard first.acquire(), first.resumeEpoch() == nil,
                  let initial = first.rotateResumeEpoch(permitsLaunch: false) else {
                suite.expect(false, "a new ownership file must remain empty until the first explicit session")
                return
            }
            suite.expect(!initial.permitsLaunch && !second.acquire() && second.resumeEpoch() == nil
                            && second.rotateResumeEpoch(permitsLaunch: true, expectedRemovalID: initial.removalID) == nil,
                         "an independent open cannot read or rotate the authority while another helper holds the flock")
            first.release()
            guard second.acquire(), second.resumeEpoch() == initial,
                  let changed = second.rotateResumeEpoch(permitsLaunch: false) else {
                suite.expect(false, "a second open must see the same authority and rotate it under the flock")
                return
            }
            second.release()
            guard first.acquire() else {
                suite.expect(false, "the first helper must be able to reacquire ownership")
                return
            }
            suite.expect(first.resumeEpoch() == changed && changed.id != initial.id && !changed.permitsLaunch,
                         "a new owner invalidates the old epoch on the shared inode")
            suite.expect(second.markRemoval() && !second.isHeld && !second.acquire() && first.resumeEpoch() == nil,
                         "removal revokes the holder's authority without taking its hardware lock")
            first.release()
            guard second.acquire() else {
                suite.expect(false, "the removal challenger must be able to inspect the released lock")
                return
            }
            suite.expect(second.resumeEpoch() == nil, "reopening a revoked record cannot grant launch permission")
            suite.expect(second.rotateResumeEpoch(permitsLaunch: true)?.permitsLaunch == false,
                         "launch permission requires an explicit removal ID from the accepted session")
            let staleRelease = second.rotateResumeEpoch(permitsLaunch: true, expectedRemovalID: changed.removalID)
            suite.expect(staleRelease?.permitsLaunch == false,
                         "a disconnect racing removal cannot grant a fresh launch using the old removal ID")
            guard let session = second.rotateResumeEpoch(permitsLaunch: false),
                  second.createMarker(), second.removeMarker() else {
                suite.expect(false, "the new session must complete its own return to automatic")
                return
            }
            // Give the directory a distinct prior time even on a coarse filesystem.
            try manager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: directory.path)
            guard let issued = second.rotateResumeEpoch(permitsLaunch: true, expectedRemovalID: session.removalID,
                                                        sessionID: session.id), issued.id == session.id, issued.permitsLaunch else {
                suite.expect(false, "an eligible disconnect must bind the launch permission to its accepted session ID")
                return
            }
            second.release()
            guard first.acquire(), first.resumeEpoch() == issued,
                  first.createMarker(), first.markerExists(), first.removeMarker() else {
                suite.expect(false, "a legacy session must create and remove its marker on the shared lock")
                return
            }
            first.release()
            let relaunched = FanControlOwnership(directory: directory)
            guard relaunched.acquire() else {
                suite.expect(false, "a new process must be able to read the lock after the legacy session")
                return
            }
            let afterLegacy = relaunched.resumeEpoch()
            suite.expect(!relaunched.markerExists() && afterLegacy != issued && afterLegacy?.permitsLaunch != true,
                         "after a legacy marker cycle a fresh process cannot obtain launch permission for the recorded session")
            relaunched.release()

            // A syntactically valid old grant predates the directory stamp.
            var unstamped = Data([1])
            unstamped.append(contentsOf: (session.id.uuidString + "00000000-0000-0000-0000-000000000000").utf8)
            try unstamped.write(to: lock)
            suite.expect(first.acquire() && first.resumeEpoch()?.permitsLaunch != true,
                         "an older grant without proof of the directory at release cannot authorize relaunch")
            first.release()
            for contents in [Data(), Data("malformed".utf8), Data(repeating: 0xff, count: 132)] {
                try contents.write(to: lock)
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lock.path)
                suite.expect(first.acquire() && first.resumeEpoch() == nil,
                             "an existing empty or malformed record grants no authority")
                first.release()
            }
            try manager.removeItem(at: lock)
            suite.expect(second.acquire() && second.resumeEpoch() == nil,
                         "recreating a lost ownership file cannot grant any launch authority")
            second.release()
        } catch {
            suite.expect(false, "temporary ownership fixture I/O failed: \(error)")
        }
    }
}

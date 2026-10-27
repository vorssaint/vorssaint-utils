// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Where the icon in the hand is drawn. Kept apart from the drag itself so
/// following the pointer redraws one floating icon, never the grid.
final class LaunchpadDragPointer: ObservableObject {
    static let shared = LaunchpadDragPointer()
    @Published var location = CGPoint.zero
    /// Set while the icon glides into its place after the button comes up.
    @Published var landing: Landing?

    enum Landing: Equatable {
        case slot, merge
    }
}

/// Moving icons the way Launchpad and the iPhone do: the icon itself lifts
/// under the pointer, the others slide aside to show where it will land,
/// resting on another icon's middle turns into a folder, and pulling an app
/// out past an open folder's edge closes the folder so the app can go
/// anywhere on the grid. The drag is read from the window's own mouse
/// events once it starts, so it survives the folder it began in closing.
final class LaunchpadDrag: ObservableObject {
    static let shared = LaunchpadDrag()

    enum Context: Equatable {
        case grid
        case folder(String)
    }

    @Published private(set) var item: LaunchpadItem?
    @Published private(set) var context = Context.grid
    /// Where the item would land, counted in the grid or folder as shown.
    @Published private(set) var gap = 0
    /// An icon the item rests on long enough to make (or join) a folder.
    @Published private(set) var mergeIndex: Int?

    private var grabOffset = CGSize.zero
    private var monitor: Any?
    private var mergeWork: DispatchWorkItem?
    private var pendingMerge: Int?
    private var gapWork: DispatchWorkItem?
    private var pendingGap: Int?
    private var folderExitWork: DispatchWorkItem?
    private var pageTimer: Timer?
    private var pageDirection = 0
    private let pointer = LaunchpadDragPointer.shared
    private var service: LaunchpadService { .shared }

    /// The items the grid shows while this drag is on: the one in the hand
    /// taken out, so a gap can stand for it.
    var gridBase: [LaunchpadItem] {
        guard let item else { return service.layout.items }
        return service.layout.items.filter { $0.id != item.id }
    }

    func folderBase(_ folder: LaunchpadFolder) -> [String] {
        guard let item else { return folder.apps }
        return folder.apps.filter { $0 != item.id }
    }

    /// `grab` is how far the pointer sits from the icon's middle, so the
    /// icon stays exactly where it was picked up from under the pointer.
    func begin(_ item: LaunchpadItem, grab: CGSize) {
        guard self.item == nil else { return }
        let service = self.service
        grabOffset = grab
        if let folderID = service.openFolderID, let folder = service.layout.folder(folderID),
           folder.apps.contains(item.id) {
            context = .folder(folderID)
            gap = folder.apps.firstIndex(of: item.id) ?? 0
        } else {
            context = .grid
            gap = service.layout.items.firstIndex { $0.id == item.id } ?? service.layout.items.count
        }
        mergeIndex = nil
        pointer.landing = nil
        pointer.location = location(for: service.rootPoint())
        self.item = item
        installMonitor()
    }

    func cancel() {
        removeMonitor()
        resetTimers()
        item = nil
        mergeIndex = nil
        pointer.landing = nil
    }

    private func location(for point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - grabOffset.width, y: point.y - grabOffset.height)
    }

    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self, self.item != nil else { return event }
            let point = self.service.rootPoint(event)
            if event.type == .leftMouseUp { self.end(at: point) } else { self.moved(to: point) }
            return event
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func resetTimers() {
        mergeWork?.cancel()
        mergeWork = nil
        pendingMerge = nil
        clearPendingGap()
        folderExitWork?.cancel()
        folderExitWork = nil
        pageTimer?.invalidate()
        pageTimer = nil
        pageDirection = 0
    }

    // MARK: - Moving

    private func moved(to point: CGPoint) {
        guard let item else { return }
        pointer.location = location(for: point)
        switch context {
        case .folder(let folderID):
            guard let folder = service.layout.folder(folderID) else { return }
            if service.folderCardFrame.insetBy(dx: -28, dy: -28).contains(point) {
                folderExitWork?.cancel()
                folderExitWork = nil
                let target = LaunchpadSupport.dragTarget(at: point, in: service.folderGeometry, page: 0,
                                                         shownCount: folderBase(folder).count + 1, gap: gap,
                                                         canMerge: false)
                if case .gap(let index) = target { setGap(index) }
            } else if folderExitWork == nil {
                // Out past the edge for a moment: the folder closes and the
                // app is on the grid, next to the folder it came from.
                let work = DispatchWorkItem { [weak self] in self?.leaveFolder(folderID) }
                folderExitWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
        case .grid:
            updatePageTurn(at: point)
            let shown = LaunchpadSupport.shown(gridBase, gap: gap)
            let canMerge: Bool
            if case .app = item { canMerge = true } else { canMerge = false }
            guard let target = LaunchpadSupport.dragTarget(at: point, in: service.gridGeometry, page: service.page,
                                                           shownCount: shown.count, gap: gap, canMerge: canMerge)
            else {
                clearPendingGap()
                return clearMerge()
            }
            switch target {
            case .gap(let index):
                clearMerge()
                scheduleGap(index)
            case .merge(let index):
                // Over an icon's middle nothing moves aside, so it stays put
                // long enough to become a folder.
                clearPendingGap()
                guard pendingMerge != index, mergeIndex != index else { return }
                // A pause over the icon, not a pass across it, makes a folder.
                clearMerge()
                pendingMerge = index
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.pendingMerge == index else { return }
                    withAnimation(.smooth(duration: 0.22)) { self.mergeIndex = index }
                }
                mergeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            }
        }
    }

    private func setGap(_ index: Int) {
        guard index != gap else { return }
        withAnimation(.smooth(duration: 0.28)) { gap = index }
    }

    /// The others make room only once the pointer rests between them, so
    /// passing over an icon on the way to its middle never pushes it away.
    private func scheduleGap(_ index: Int) {
        guard index != gap else { return clearPendingGap() }
        guard pendingGap != index else { return }
        clearPendingGap()
        pendingGap = index
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingGap == index else { return }
            self.pendingGap = nil
            self.setGap(index)
        }
        gapWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func clearPendingGap() {
        gapWork?.cancel()
        gapWork = nil
        pendingGap = nil
    }

    private func clearMerge() {
        mergeWork?.cancel()
        mergeWork = nil
        pendingMerge = nil
        if mergeIndex != nil { withAnimation(.smooth(duration: 0.18)) { mergeIndex = nil } }
    }

    private func leaveFolder(_ folderID: String) {
        folderExitWork = nil
        guard item != nil, context == .folder(folderID) else { return }
        let index = service.layout.items.firstIndex { $0.id == folderID } ?? service.layout.items.count
        withAnimation(.smooth(duration: 0.3)) {
            service.closeFolder()
            context = .grid
            gap = index + 1
        }
    }

    /// Resting near a side of the screen turns the page that way, and keeps
    /// turning while the pointer stays.
    private func updatePageTurn(at point: CGPoint) {
        let width = service.rootSize.width
        let direction = point.x < 56 ? -1 : point.x > width - 56 ? 1 : 0
        guard direction != pageDirection else { return }
        pageDirection = direction
        pageTimer?.invalidate()
        pageTimer = nil
        guard direction != 0 else { return }
        pageTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self else { return }
            let pages = LaunchpadSupport.pageCount(items: self.gridBase.count + 1, perPage: self.service.perPage)
            self.clearPendingGap()
            self.service.setPage(self.service.page + direction, pageCount: pages)
        }
    }

    // MARK: - Dropping

    private func end(at point: CGPoint) {
        guard let item else { return }
        removeMonitor()
        // A quick drop lands where the pointer let go, rest or not.
        if mergeIndex == nil, let pendingGap { setGap(pendingGap) }
        let merge = mergeIndex
        let gap = self.gap
        let context = self.context
        resetTimers()
        let service = self.service
        let page = service.page
        let landingPoint: CGPoint?
        let commit: () -> Void
        switch context {
        case .folder:
            landingPoint = service.folderGeometry.iconCenter(of: gap)
            commit = { service.moveInFolder(item.id, toPosition: gap, animated: false) }
        case .grid:
            let shown = LaunchpadSupport.shown(gridBase, gap: gap)
            if let merge, shown.indices.contains(merge), let target = shown[merge] {
                let slot = merge - page * service.gridGeometry.perPage
                landingPoint = service.gridGeometry.iconCenter(of: slot)
                commit = { service.drop(item.id, onto: target.id) }
            } else {
                let slot = gap - page * service.gridGeometry.perPage
                landingPoint = (0..<service.gridGeometry.perPage).contains(slot)
                    ? service.gridGeometry.iconCenter(of: slot) : nil
                commit = { service.move(item.id, toPosition: gap, animated: false) }
            }
        }
        guard let landingPoint else {
            finish(commit)
            return
        }
        withAnimation(.smooth(duration: 0.22)) {
            pointer.location = landingPoint
            pointer.landing = merge == nil ? .slot : .merge
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in self?.finish(commit) }
    }

    /// The icon lands, then the grid takes it in the same frame, so it never
    /// shows twice or jumps.
    private func finish(_ commit: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            commit()
            item = nil
            mergeIndex = nil
            pointer.landing = nil
        }
    }
}

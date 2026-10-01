// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// What the Vorssaint menu bar item shows beside its icon while an agent
/// works: the agent's mark and the reading the closed island would show,
/// and for a moment after an event, a symbol and its figures, such as a
/// finished task's time and tokens. For people who keep the island off.
final class AgentMenuBarReading {
    static let shared = AgentMenuBarReading()
    /// How long an event stays before the reading returns.
    static let noticeDuration: TimeInterval = 8
    /// The status item redraws its title when this calls; `true` when what it
    /// shows changes kind (appears, leaves, or turns into a notice), which
    /// the item eases rather than snaps.
    var changed: (_ crossfade: Bool) -> Void = { _ in }
    /// The island's whole sentence for the notice being shown.
    private(set) var toolTip: String?
    private var subscriptions = Set<AnyCancellable>()
    private var timer: Timer?
    private var notice: (symbol: String, text: String, providers: [AgentProvider], toolTip: String, until: Date)?
    private var shownKind = Kind.none
    /// One attachment per image, so an unchanged title compares equal and is not redrawn.
    private var attachments: [String: NSTextAttachment] = [:]

    private enum Kind { case none, reading, notice }

    private init() {}

    func syncWithPreferences() {
        guard NotchAgentSupport.showsMenuBarActivity() else {
            subscriptions.removeAll()
            notice = nil
            update()
            return
        }
        if subscriptions.isEmpty {
            let usage = AgentUsageService.shared
            usage.$snapshot.receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.update() }
                .store(in: &subscriptions)
            usage.events.receive(on: RunLoop.main)
                .sink { [weak self] in self?.show($0) }
                .store(in: &subscriptions)
        }
        update()
    }

    /// The title's agent part, or nil while no agent works and nothing happened.
    func title(at now: Date = Date()) -> NSAttributedString? {
        guard NotchAgentSupport.showsMenuBarActivity() else { return nil }
        let title = NSMutableAttributedString()
        func image(_ key: String, _ image: () -> NSImage?) {
            if attachments[key] == nil, let image = image() {
                let attachment = NSTextAttachment()
                attachment.image = image
                attachment.bounds = CGRect(x: 0, y: -2, width: image.size.width, height: image.size.height)
                attachments[key] = attachment
            }
            guard let attachment = attachments[key] else { return }
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: " "))
        }
        if let notice, notice.until > now {
            for provider in notice.providers { image(provider.rawValue) { Self.mark(provider) } }
            image(notice.symbol) { Self.symbol(notice.symbol) }
            if !notice.text.isEmpty { title.append(NSAttributedString(string: notice.text)) }
            return title
        }
        let snapshot = AgentUsageService.shared.snapshot
        let providers = AgentProvider.allCases.filter { provider in snapshot.live.contains { $0.provider == provider } }
        guard !providers.isEmpty else { return nil }
        for provider in providers { image(provider.rawValue) { Self.mark(provider) } }
        title.append(NSAttributedString(string: NotchAgentSupport.stripReading(
            snapshot, readout: NotchAgentSupport.readout(), display: NotchAgentSupport.limitDisplay(), now: now)))
        return title
    }

    private func show(_ event: AgentUsageEvent) {
        let short = NotchAgentSupport.menuBarSummary(of: event)
        let long = NotchAgentSupport.summary(of: event, language: L10n.shared.language)
        notice = (short.symbol, short.text, short.provider.map { [$0] } ?? [],
                  [long.title, long.detail].filter { !$0.isEmpty }.joined(separator: " · "),
                  Date().addingTimeInterval(Self.noticeDuration))
        update()
    }

    /// Ticks once a second only while there is something to show.
    private func update() {
        let now = Date()
        if notice.map({ $0.until <= now }) == true { notice = nil }
        let enabled = NotchAgentSupport.showsMenuBarActivity()
        let kind: Kind = !enabled ? .none : notice != nil ? .notice
            : AgentUsageService.shared.snapshot.live.isEmpty ? .none : .reading
        toolTip = kind == .notice ? notice?.toolTip : nil
        if kind != .none, timer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
            timer.tolerance = 0.2
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if kind == .none {
            timer?.invalidate()
            timer = nil
        }
        let crossfade = kind != shownKind
        shownKind = kind
        changed(crossfade)
    }

    private static func mark(_ provider: AgentProvider) -> NSImage? {
        image(provider.symbol, color: NSColor(provider.tint), name: provider.displayName)
    }

    /// The event's symbol: green for a finished task, orange for a warning.
    private static func symbol(_ name: String) -> NSImage? {
        let color: NSColor = name.hasPrefix("checkmark") ? .systemGreen
            : name.hasPrefix("exclamationmark") ? .systemOrange : .secondaryLabelColor
        return image(name, color: color, name: nil)
    }

    private static func image(_ symbol: String, color: NSColor, name: String?) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            .applying(.init(paletteColors: [color]))
        return NSImage(systemSymbolName: symbol, accessibilityDescription: name)?
            .withSymbolConfiguration(configuration)
    }
}

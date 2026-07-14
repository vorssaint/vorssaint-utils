// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// The floating permission guide: a small non-activating card that appears
/// when a permission request sends the person to System Settings, walks them
/// through the three steps and notices the grant by itself (the app's
/// permission refresh already observes it). The trip to System Settings and
/// back is where most people give up; this card keeps them company.
///
/// Nothing exists while the card is hidden: the window, the hosting view and
/// the Combine subscription are created on show and released on dismiss.
final class PermissionGuideOverlay {
    static let shared = PermissionGuideOverlay()

    /// Onboarding walks the person through permissions with its own UI, so
    /// the floating card stays out of its way.
    static var suppressed = false

    private var panel: NSPanel?
    private var grantWatcher: AnyCancellable?
    private var dismissWork: DispatchWorkItem?

    private init() {}

    func show(for kind: PermissionKind) {
        guard !Self.suppressed else { return }
        dismissWork?.cancel()
        dismissWork = nil
        grantWatcher = nil
        panel?.orderOut(nil)
        panel = nil

        let language = L10n.shared.language
        let guide = FeatureStrings.permissionGuide(language)
        let permissionName = kind == .accessibility
            ? L10n.shared.s.permissionAccessibility
            : L10n.shared.s.permissionScreenRecording
        let model = PermissionGuideModel()
        let view = PermissionGuideCard(guide: guide, permissionName: permissionName,
                                       model: model) { [weak self] in
            self?.dismiss()
        }

        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? .zero
        let frame = NSRect(x: visible.maxX - size.width - 20,
                           y: visible.maxY - size.height - 20,
                           width: size.width, height: size.height)

        // Non-activating, so System Settings keeps focus while the card
        // floats above it; joins every Space so the trip back finds it.
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel

        let publisher = kind == .accessibility
            ? Permissions.shared.$accessibility
            : Permissions.shared.$screenRecording
        grantWatcher = publisher
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                model.granted = true
                self?.scheduleDismiss()
            }
    }

    /// The success beat stays on screen for a moment, then the card leaves.
    private func scheduleDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        grantWatcher = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

/// The card's only mutable state: flips once when the grant lands.
private final class PermissionGuideModel: ObservableObject {
    @Published var granted = false
}

private struct PermissionGuideCard: View {
    let guide: PermissionGuideStrings
    let permissionName: String
    @ObservedObject var model: PermissionGuideModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(guide.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(permissionName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(guide.closeHelp)
            }

            VStack(alignment: .leading, spacing: 6) {
                stepRow(1, guide.stepOpen)
                stepRow(2, guide.stepToggle)
                stepRow(3, guide.stepReturn)
            }

            HStack(spacing: 7) {
                if model.granted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(guide.granted)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text(guide.waiting)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        )
        .animation(.easeOut(duration: 0.2), value: model.granted)
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

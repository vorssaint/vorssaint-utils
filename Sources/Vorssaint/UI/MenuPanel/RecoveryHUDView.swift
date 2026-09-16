// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

// MARK: - Strings Localization Extension

extension Strings {
    var recoveryCountdownTitle: String {
        switch L10n.shared.language {
        case .zhHans:
            return "保留这个显示设置？"
        case .zhTW, .zhHK:
            return "保留這個顯示設定？"
        case .enUS:
            return "Keep this display configuration?"
        case .ja:
            return "このディスプレイ設定を保持しますか？"
        case .ko:
            return "이 디스플레이 설정을 유지하겠습니까?"
        case .de:
            return "Diese Anzeigeeinstellungen beibehalten?"
        case .fr:
            return "Conserver ces réglages d’affichage ?"
        case .es:
            return "¿Mantener esta configuración de pantalla?"
        case .it:
            return "Mantenere queste impostazioni dello schermo?"
        case .ru:
            return "Сохранить эти настройки дисплея?"
        case .tr:
            return "Bu ekran ayarlarını koru?"
        case .ptBR:
            return "Manter estas configurações de tela?"
        }
    }

    func recoveryCountdownRemaining(_ seconds: Int) -> String {
        switch L10n.shared.language {
        case .zhHans:
            return "\(seconds) 秒后自动恢复"
        case .zhTW, .zhHK:
            return "\(seconds) 秒後自動恢復"
        case .enUS:
            return "Auto-reverting in \(seconds)s"
        case .ja:
            return "\(seconds)秒後に自動で元に戻します"
        case .ko:
            return "\(seconds)초 후 자동으로 복원됩니다"
        case .de:
            return "Automatische Rückkehr in \(seconds) s"
        case .fr:
            return "Rétablissement automatique dans \(seconds) s"
        case .es:
            return "Restableciendo automáticamente en \(seconds) s"
        case .it:
            return "Ripristino automatico in \(seconds) s"
        case .ru:
            return "Автоматический возврат через \(seconds) сек."
        case .tr:
            return "\(seconds) sn içinde otomatik geri dönülecek"
        case .ptBR:
            return "Reversão automática em \(seconds) s"
        }
    }

    var recoveryKeep: String {
        switch L10n.shared.language {
        case .zhHans:
            return "保留设置"
        case .zhTW, .zhHK:
            return "保留設定"
        case .enUS:
            return "Keep Settings"
        case .ja:
            return "設定を保持"
        case .ko:
            return "설정 유지"
        case .de:
            return "Einstellungen behalten"
        case .fr:
            return "Conserver les réglages"
        case .es:
            return "Mantener ajustes"
        case .it:
            return "Mantieni impostazioni"
        case .ru:
            return "Сохранить"
        case .tr:
            return "Ayarları Koru"
        case .ptBR:
            return "Manter Configurações"
        }
    }

    var recoveryRevert: String {
        switch L10n.shared.language {
        case .zhHans:
            return "还原"
        case .zhTW, .zhHK:
            return "還原"
        case .enUS:
            return "Revert"
        case .ja:
            return "元に戻す"
        case .ko:
            return "복원"
        case .de:
            return "Zurücksetzen"
        case .fr:
            return "Rétablir"
        case .es:
            return "Restablecer"
        case .it:
            return "Ripristina"
        case .ru:
            return "Вернуть"
        case .tr:
            return "Geri Dön"
        case .ptBR:
            return "Reverter"
        }
    }
}

// MARK: - Recovery Panel (NSPanel subclass)

private final class RecoveryPanel: NSPanel, @unchecked Sendable {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            DisplayRecoveryManager.shared.rollback()
            return
        } else if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
            DisplayRecoveryManager.shared.confirm()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Recovery HUD Controller

public final class RecoveryHUDController: ObservableObject, @unchecked Sendable {
    public static let shared = RecoveryHUDController()

    @Published public private(set) var isVisible: Bool = false

    public private(set) var panels: [NSPanel] = []
    private var cancellables = Set<AnyCancellable>()
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var isClosing: Bool = false

    public init(recoveryManager: DisplayRecoveryManager = .shared, autoSubscribe: Bool = true) {
        if autoSubscribe {
            recoveryManager.$awaitingConfirmation
                .receive(on: DispatchQueue.main)
                .sink { [weak self] awaiting in
                    if awaiting {
                        self?.show()
                    } else {
                        self?.close()
                    }
                }
                .store(in: &cancellables)
        }
    }

    deinit {
        stopMonitoring()
        stopScreenObserver()
        closePanelsOnly()
    }

    public func show() {
        if Thread.isMainThread {
            _show()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?._show()
            }
        }
    }

    private func _show() {
        guard !isVisible || panels.isEmpty else { return }
        isVisible = true

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            close()
            return
        }

        recreatePanels(screens: screens)
        startMonitoring()
        setupScreenObserver()
    }

    public func close() {
        if Thread.isMainThread {
            _close()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?._close()
            }
        }
    }

    private func _close() {
        guard !isClosing else { return }
        isClosing = true
        defer { isClosing = false }

        isVisible = false
        stopMonitoring()
        stopScreenObserver()
        closePanelsOnly()
    }

    private func frameForScreen(_ screen: NSScreen) -> NSRect {
        let width: CGFloat = 420
        let height: CGFloat = 130
        let visible = screen.visibleFrame
        let x = visible.midX - width / 2
        let y = max(visible.minY + 10, visible.maxY - height - 28)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func recreatePanels(screens: [NSScreen]) {
        closePanelsOnly()

        for screen in screens {
            let frame = frameForScreen(screen)
            let panel = RecoveryPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.hasShadow = true
            panel.contentView = NSHostingView(
                rootView: RecoveryHUDView()
            )
            panel.orderFrontRegardless()
            panel.invalidateShadow()
            panels.append(panel)
        }

        panels.first?.makeKey()
    }

    private func closePanelsOnly() {
        let currentPanels = panels
        panels.removeAll()
        for panel in currentPanels {
            panel.orderOut(nil)
            panel.close()
        }
    }

    private func startMonitoring() {
        guard localMonitor == nil, globalMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let handled = self.handleKeyDown(keyCode: event.keyCode)
            return handled ? nil : event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleKeyDown(keyCode: event.keyCode)
        }
    }

    private func stopMonitoring() {
        if let local = localMonitor {
            NSEvent.removeMonitor(local)
            localMonitor = nil
        }
        if let global = globalMonitor {
            NSEvent.removeMonitor(global)
            globalMonitor = nil
        }
    }

    private func setupScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, DisplayRecoveryManager.shared.awaitingConfirmation else { return }
            let screens = NSScreen.screens
            guard !screens.isEmpty else {
                self.close()
                return
            }
            if self.panels.count != screens.count {
                self.recreatePanels(screens: screens)
            } else {
                for (screen, panel) in zip(screens, self.panels) {
                    let frame = self.frameForScreen(screen)
                    if panel.frame != frame {
                        panel.setFrame(frame, display: true)
                    }
                }
            }
        }
    }

    private func stopScreenObserver() {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
    }

    @discardableResult
    func handleKeyDown(keyCode: UInt16) -> Bool {
        guard DisplayRecoveryManager.shared.awaitingConfirmation else { return false }
        if keyCode == 53 { // ESC
            DispatchQueue.main.async {
                DisplayRecoveryManager.shared.rollback()
            }
            return true
        } else if keyCode == 36 || keyCode == 76 { // Return / Enter
            DispatchQueue.main.async {
                DisplayRecoveryManager.shared.confirm()
            }
            return true
        }
        return false
    }
}

// MARK: - Recovery HUD View

public struct RecoveryHUDView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var recoveryManager = DisplayRecoveryManager.shared
    var onConfirm: (() -> Void)?
    var onRollback: (() -> Void)?

    public init(onConfirm: (() -> Void)? = nil, onRollback: (() -> Void)? = nil) {
        self.onConfirm = onConfirm
        self.onRollback = onRollback
    }

    public var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                // Circular countdown progress indicator & badge
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, recoveryManager.remainingSeconds)) / 15.0)
                        .stroke(
                            recoveryManager.remainingSeconds <= 5 ? Color.orange : Color.blue,
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.2), value: recoveryManager.remainingSeconds)

                    Text("\(recoveryManager.remainingSeconds)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(l10n.s.recoveryCountdownTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(l10n.s.recoveryCountdownRemaining(recoveryManager.remainingSeconds))
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            // Horizontal countdown progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 3)

                    Capsule()
                        .fill(recoveryManager.remainingSeconds <= 5 ? Color.orange : Color.blue)
                        .frame(
                            width: max(0, geometry.size.width * CGFloat(recoveryManager.remainingSeconds) / 15.0),
                            height: 3
                        )
                        .animation(.easeInOut(duration: 0.25), value: recoveryManager.remainingSeconds)
                }
            }
            .frame(height: 3)

            // Action buttons
            HStack(spacing: 12) {
                Button(role: .cancel) {
                    if let onRollback {
                        onRollback()
                    } else {
                        recoveryManager.rollback()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(l10n.s.recoveryRevert)
                        Text("Esc")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 3))
                    }
                    .frame(minWidth: 80, minHeight: 22)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    if let onConfirm {
                        onConfirm()
                    } else {
                        recoveryManager.confirm()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(l10n.s.recoveryKeep)
                        Text("↵")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    }
                    .frame(minWidth: 92, minHeight: 22)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .keyboardShortcut(.defaultAction)
                .disabled(recoveryManager.remainingSeconds == 0)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 420, height: 130)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .environment(\.colorScheme, .dark)
    }
}

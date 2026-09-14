// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

/// The authenticator page: palette and clipboard preferences, the account
/// list with live codes, and the ways in and out (by hand, screen scan,
/// clipboard, file, transfer QR).
struct AuthenticatorSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = AuthenticatorService.shared
    @ObservedObject private var palette = AuthenticatorPaletteService.shared
    @AppStorage(DefaultsKey.authenticatorPaletteEnabled) private var paletteEnabled = true
    @AppStorage(DefaultsKey.authenticatorTypesCodes) private var typesCodes = true
    @AppStorage(DefaultsKey.authenticatorClearsClipboard) private var clearsClipboard = true
    @AppStorage(DefaultsKey.authenticatorClipboardClearDelay) private var clearDelay = 30
    @AppStorage(DefaultsKey.authenticatorPressesReturn) private var pressesReturn = false
    @AppStorage(DefaultsKey.authenticatorRequiresUnlock) private var requiresUnlock = false
    @State private var editing: OTPAccount?
    @State private var creating = false
    @State private var qrText: QRSheet?
    @State private var problem: String?
    @State private var exportPicker: ExportPicker.Mode?
    @State private var confirmingDelete: OTPAccount?
    @State private var filter = ""
    /// The list as it is being dragged; persisted when the drop lands.
    @State private var order: [OTPAccount] = []
    @State private var dragging: OTPAccount?

    private var text: AuthenticatorFeatureStrings {
        FeatureStrings.authenticator(l10n.language)
    }

    private var showsFilter: Bool {
        service.accounts.count >= 6
    }

    private var visibleAccounts: [OTPAccount] {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        guard showsFilter, !needle.isEmpty else { return order }
        return order.filter {
            $0.issuer.localizedCaseInsensitiveContains(needle)
                || $0.label.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        Form {
            Section {
                if let storeProblem = service.storeProblem {
                    Label(storeProblem, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if service.accounts.isEmpty {
                    emptyState
                } else {
                    if service.isLocked {
                        HStack {
                            Label(text.lockedCode, systemImage: "lock.fill")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(text.unlockButton) { service.unlock() }
                        }
                    }
                    if showsFilter {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField(text.filterPlaceholder, text: $filter)
                                .textFieldStyle(.plain)
                        }
                    }
                    ForEach(visibleAccounts) { account in
                        AccountRow(account: account,
                                   text: text,
                                   dragging: $dragging,
                                   canDrag: !showsFilter || filter.isEmpty,
                                   moveHandler: { moved, target in move(moved, before: target) },
                                   persist: persistOrder,
                                   edit: { editing = account },
                                   copy: { service.copyCode(for: account.id) },
                                   showQR: { showQR(for: account) },
                                   togglePin: { togglePin(account) },
                                   moveUp: { step(account, by: -1) },
                                   moveDown: { step(account, by: 1) },
                                   delete: { confirmingDelete = account })
                    }
                    addBar
                        // Undershooting the list and letting go over the
                        // buttons below it still ends the drag; without this
                        // the order would stay unsaved and the row dimmed.
                        .onDrop(of: [UTType.text], delegate: AccountListDropDelegate(persist: persistOrder))
                }
            } header: {
                Text(text.accountsSection)
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(service.accounts.isEmpty ? text.scanHint : text.listHint)
                    Text(text.clockHint)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle(text.paletteToggle, isOn: $paletteEnabled)
                    .onChange(of: paletteEnabled) { _, _ in
                        AuthenticatorPaletteService.shared.syncWithPreferences()
                    }
                Text(text.paletteCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if paletteEnabled {
                    ShortcutPreferenceRow(role: .authenticatorPalette, isEnabled: paletteEnabled) {
                        AuthenticatorPaletteService.shared.syncWithPreferences()
                    }
                    if palette.shortcutRegistrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Picker(text.enterAction, selection: $typesCodes) {
                    Text(text.enterTypes).tag(true)
                    Text(text.enterCopies).tag(false)
                }
                Text(text.typesCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if typesCodes, !permissions.accessibility {
                    PermissionRow(kind: .accessibility)
                }
                Toggle(text.pressesReturn, isOn: $pressesReturn)
                Text(text.pressesReturnCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(text.clearsClipboard, isOn: $clearsClipboard)
                if clearsClipboard {
                    Stepper(String(format: text.clearDelayFormat, clearDelay),
                            value: $clearDelay, in: 5...300, step: 5)
                }
                Text(text.clearsClipboardCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(text.requiresUnlock, isOn: $requiresUnlock)
                    .onChange(of: requiresUnlock) { _, on in
                        if on { service.relock() }
                        service.syncWithPreferences()
                    }
                Text(text.requiresUnlockCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(text.settingsSection)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            service.syncWithPreferences()
            AuthenticatorClock.shared.begin()
            order = service.accounts
        }
        .onDisappear {
            // Leaving mid-drag must not strand the row or the clock.
            dragging = nil
            AuthenticatorClock.shared.resume()
            AuthenticatorClock.shared.end()
        }
        .onChange(of: dragging) { _, account in
            // A reorder animation and a redraw of every code in the same
            // frame is what makes a dragged row stutter.
            if account == nil {
                AuthenticatorClock.shared.resume()
            } else {
                AuthenticatorClock.shared.pause()
            }
        }
        .onChange(of: service.accounts) { _, accounts in
            // Edits elsewhere (an import, the palette's HOTP advance) win;
            // a drag in progress is the one moment the local copy leads.
            if dragging == nil { order = accounts }
        }
        .sheet(isPresented: $creating) {
            AccountEditor(text: text, account: OTPAccount(), secretText: "", isNew: true) { entry in
                problem = service.add(entry)
            }
        }
        .sheet(item: $editing) { account in
            AccountEditor(text: text, account: account, secretText: nil, isNew: false) { entry in
                problem = service.update(entry.account)
            }
        }
        .sheet(item: $exportPicker) { mode in
            ExportPicker(text: text, accounts: service.accounts, mode: mode) { ids in
                export(ids, mode: mode)
            }
        }
        .sheet(item: $qrText) { sheet in
            QRCodeSheet(text: text, sheet: sheet)
        }
        .alert(String(format: text.deleteConfirmFormat, confirmingDelete?.displayName ?? ""),
               isPresented: Binding(get: { confirmingDelete != nil },
                                    set: { if !$0 { confirmingDelete = nil } })) {
            Button(text.deleteButton, role: .destructive) {
                if let account = confirmingDelete {
                    problem = service.remove(id: account.id)
                }
                confirmingDelete = nil
            }
            Button(l10n.s.uninstallerCancel, role: .cancel) { confirmingDelete = nil }
        }
        .alert(problem ?? "", isPresented: Binding(get: { problem != nil },
                                                   set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        }
    }

    /// The two ways most people add an account, as buttons; the rarer
    /// imports and the exports behind menus beside them.
    private var addBar: some View {
        HStack(spacing: 8) {
            Button {
                service.scanScreen()
            } label: {
                Label(text.scanScreen, systemImage: "qrcode.viewfinder")
            }
            Button {
                creating = true
            } label: {
                Label(text.addManually, systemImage: "keyboard")
            }
            Menu {
                Button(text.scanCamera) { service.scanCamera() }
                Divider()
                Button(text.importClipboard) { service.importClipboard() }
                Button(text.importFile) { importFile() }
            } label: {
                Label(text.importMenu, systemImage: "square.and.arrow.down")
            }
            .fixedSize()
            Spacer()
            Menu {
                Button(text.exportQR) { exportPicker = .transferQR }
                Button(text.exportEncrypted) { exportPicker = .encrypted }
                Button(text.exportPlain) { exportPicker = .plain }
            } label: {
                Label(text.exportMenu, systemImage: "square.and.arrow.up")
            }
            .fixedSize()
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(text.emptyList)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 8) {
                Button {
                    service.scanScreen()
                } label: {
                    Label(text.scanScreen, systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    creating = true
                } label: {
                    Label(text.addManually, systemImage: "keyboard")
                }
                Menu {
                    Button(text.scanCamera) { service.scanCamera() }
                    Divider()
                    Button(text.importClipboard) { service.importClipboard() }
                    Button(text.importFile) { importFile() }
                } label: {
                    Label(text.importMenu, systemImage: "square.and.arrow.down")
                }
                .fixedSize()
            }
            if paletteEnabled {
                Text(String(format: text.hotkeyHintFormat,
                            GlobalShortcutRole.authenticatorPalette.savedShortcut.displayString))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // MARK: - Ordering

    private func move(_ moved: OTPAccount, before target: OTPAccount) {
        guard let from = order.firstIndex(of: moved), let to = order.firstIndex(of: target), from != to else { return }
        order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    private func step(_ account: OTPAccount, by offset: Int) {
        guard let from = order.firstIndex(of: account) else { return }
        let to = from + offset
        guard order.indices.contains(to) else { return }
        order.swapAt(from, to)
        persistOrder()
    }

    private func persistOrder() {
        dragging = nil
        guard order.map(\.id) != service.accounts.map(\.id) else { return }
        problem = service.reorder(order.map(\.id))
    }

    private func togglePin(_ account: OTPAccount) {
        var changed = account
        changed.pinned.toggle()
        problem = service.update(changed)
    }

    private func showQR(for account: OTPAccount) {
        guard let entry = service.entries(for: [account.id]).first else {
            problem = text.secretUnavailable
            return
        }
        qrText = QRSheet(title: account.displayName,
                         caption: nil,
                         uris: [OneTimePassword.uri(for: entry)])
    }

    private func export(_ ids: [UUID], mode: ExportPicker.Mode) {
        guard !ids.isEmpty else { return }
        switch mode {
        case .transferQR:
            let uris = service.migrationURIs(for: ids)
            guard !uris.isEmpty else { return }
            qrText = QRSheet(title: text.qrTitle, caption: text.qrScanWithPhone, uris: uris)
        case .encrypted:
            guard let data = service.exportBackup(for: ids) else { return }
            save(data, name: "authenticator-backup." + AuthenticatorInterchange.Backup.fileExtension,
                 types: [UTType(filenameExtension: AuthenticatorInterchange.Backup.fileExtension) ?? .json])
        case .plain:
            let alert = NSAlert()
            alert.messageText = text.exportWarningTitle
            alert.informativeText = text.exportWarningMessage
            alert.alertStyle = .warning
            alert.addButton(withTitle: text.exportContinue)
            alert.addButton(withTitle: l10n.s.uninstallerCancel)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            save(Data(service.exportText(for: ids).utf8), name: "authenticator-export.txt", types: [.plainText])
        }
    }

    private func save(_ data: Data, name: String, types: [UTType]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = types
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            problem = error.localizedDescription
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text, .json, .image, .png, .jpeg, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        service.importFile(url)
    }
}

/// Which accounts go into an export, and in which shape.
private struct ExportPicker: View {
    enum Mode: Identifiable {
        case transferQR, encrypted, plain
        var id: Int { hashValue }
    }

    let text: AuthenticatorFeatureStrings
    let accounts: [OTPAccount]
    let mode: Mode
    let export: ([UUID]) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @State private var chosen: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text.exportPickTitle)
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(accounts) { account in
                        Toggle(isOn: Binding(
                            get: { chosen.contains(account.id) },
                            set: { on in
                                if on { chosen.insert(account.id) } else { chosen.remove(account.id) }
                            })) {
                            HStack(spacing: 8) {
                                AuthenticatorInitials(name: account.displayName)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(account.displayName).fontWeight(.medium)
                                    if !account.secondaryName.isEmpty {
                                        Text(account.secondaryName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 320)
            HStack {
                Button(text.exportSelectAll) { chosen = Set(accounts.map(\.id)) }
                Spacer()
                Button(l10n.s.uninstallerCancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(text.exportContinue) {
                    let ids = accounts.map(\.id).filter { chosen.contains($0) }
                    dismiss()
                    DispatchQueue.main.async { export(ids) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 420)
        .onAppear { chosen = Set(accounts.map(\.id)) }
    }
}

struct QRSheet: Identifiable {
    let id = UUID()
    let title: String
    let caption: String?
    let uris: [String]
}

private struct AccountRow: View {
    let account: OTPAccount
    let text: AuthenticatorFeatureStrings
    @Binding var dragging: OTPAccount?
    let canDrag: Bool
    let moveHandler: (OTPAccount, OTPAccount) -> Void
    let persist: () -> Void
    let edit: () -> Void
    let copy: () -> Void
    let showQR: () -> Void
    let togglePin: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void
    @State private var hoveringCode = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .opacity(canDrag ? 1 : 0.3)
                .help(text.listHint)
            AuthenticatorInitials(name: account.displayName)
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(account.displayName)
                            .fontWeight(.medium)
                        if account.pinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        if account.kind != .totp {
                            Text(account.kind == .hotp ? "HOTP" : "Steam")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.primary.opacity(0.07))
                                )
                        }
                    }
                    if !account.secondaryName.isEmpty {
                        Text(account.secondaryName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Button(action: copy) {
                HStack(spacing: 6) {
                    AuthenticatorCodeBadge(account: account, animatesRing: false)
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(hoveringCode ? Color.accentColor : .secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(hoveringCode ? 0.1 : 0.05))
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hoveringCode = $0 }
            .help(text.copyAction)
            Menu {
                Button(text.copyAction, action: copy)
                Button(text.editTitle, action: edit)
                Button(text.showQR, action: showQR)
                Toggle(text.pinLabel, isOn: Binding(get: { account.pinned }, set: { _ in togglePin() }))
                Divider()
                Button(text.moveUp, action: moveUp)
                Button(text.moveDown, action: moveDown)
                Divider()
                Button(text.deleteButton, role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 1)
        .opacity(dragging == account ? 0.45 : 1)
        .contentShape(Rectangle())
        .onDrag {
            guard canDrag else { return NSItemProvider() }
            dragging = account
            return NSItemProvider(object: account.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: AccountDropDelegate(target: account,
                                                                 dragging: $dragging,
                                                                 moveHandler: moveHandler,
                                                                 persist: persist))
    }
}

/// Catches a drop that missed every row, so the order is still committed.
private struct AccountListDropDelegate: DropDelegate {
    let persist: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        persist()
        return true
    }
}

private struct AccountDropDelegate: DropDelegate {
    let target: OTPAccount
    @Binding var dragging: OTPAccount?
    let moveHandler: (OTPAccount, OTPAccount) -> Void
    let persist: () -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
            moveHandler(dragging, target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        persist()
        return true
    }
}

/// Add or edit one account. A new account asks for the key; editing keeps
/// the key where it is and changes only the names and parameters.
private struct AccountEditor: View {
    let text: AuthenticatorFeatureStrings
    @State var account: OTPAccount
    /// Nil while editing an existing account, whose key is not shown.
    @State var secretText: String?
    let isNew: Bool
    let save: (OTPEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = AuthenticatorService.shared
    @ObservedObject private var clock = AuthenticatorClock.shared

    private var secretData: Data? {
        guard let secretText else { return nil }
        return OneTimePassword.secretData(secretText, kind: account.kind)
    }

    private var duplicate: Bool {
        service.hasAccount(issuer: account.issuer.trimmingCharacters(in: .whitespaces),
                           label: account.label.trimmingCharacters(in: .whitespaces),
                           except: isNew ? nil : account.id)
    }

    /// A whole otpauth or Google transfer link pasted into the key field
    /// fills the form instead of being rejected as a bad key.
    private func acceptKeyInput(_ raw: String) {
        let lowered = raw.lowercased()
        if lowered.contains("otpauth"),
           let entry = OneTimePassword.entries(inText: raw).entries.first {
            let id = account.id
            account = entry.account
            account.id = id
            secretText = OneTimePassword.base32Encode(entry.secret)
            return
        }
        secretText = OneTimePassword.sanitizedSecret(raw, kind: account.kind)
    }

    private var secretInvalid: Bool {
        guard let secretText, !secretText.isEmpty else { return false }
        return secretData == nil
    }

    private var canSave: Bool {
        if isNew { return secretData != nil }
        return true
    }

    private var preview: String? {
        guard let secretData else { return nil }
        return OneTimePassword.grouped(OneTimePassword.code(for: account, secret: secretData, at: clock.now))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? text.newTitle : text.editTitle)
                .font(.headline)
            Form {
                TextField(text.issuerLabel, text: $account.issuer, prompt: Text(text.issuerPlaceholder))
                TextField(text.accountLabel, text: $account.label, prompt: Text(text.accountPlaceholder))
                if isNew {
                    TextField(text.secretLabel,
                              text: Binding(get: { secretText ?? "" },
                                            set: { acceptKeyInput($0) }),
                              prompt: Text(text.secretPlaceholder))
                        .font(.body.monospaced())
                    if secretInvalid {
                        Text(text.invalidSecret)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text(text.keyFieldHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if duplicate {
                    Text(text.duplicateWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Section(text.advancedSection) {
                    Picker(text.kindLabel, selection: $account.kind) {
                        Text(text.kindTOTP).tag(OTPAccount.Kind.totp)
                        Text(text.kindHOTP).tag(OTPAccount.Kind.hotp)
                        Text(text.kindSteam).tag(OTPAccount.Kind.steam)
                    }
                    if account.kind != .steam {
                        Picker(text.algorithmLabel, selection: $account.algorithm) {
                            ForEach(OTPAccount.Algorithm.allCases, id: \.self) {
                                Text($0.rawValue.uppercased()).tag($0)
                            }
                        }
                        Picker(text.digitsLabel, selection: $account.digits) {
                            ForEach(OTPAccount.digitChoices, id: \.self) { Text(String($0)).tag($0) }
                        }
                    }
                    if account.kind == .hotp {
                        TextField(text.counterLabel,
                                  value: $account.counter,
                                  format: .number)
                    } else {
                        TextField(text.periodLabel, value: $account.period, format: .number)
                    }
                }
                if let preview {
                    LabeledContent(text.previewLabel) {
                        Text(preview)
                            .font(.system(.body, design: .monospaced))
                            .monospacedDigit()
                    }
                }
            }
            .formStyle(.columns)
            HStack {
                Spacer()
                Button(l10n.s.uninstallerCancel) { dismiss() }
                Button(text.saveButton) {
                    var saved = account
                    saved.issuer = account.issuer.trimmingCharacters(in: .whitespaces)
                    saved.label = account.label.trimmingCharacters(in: .whitespaces)
                    saved.period = max(saved.period, 1)
                    if saved.kind == .steam {
                        saved.digits = OTPAccount.steamDigits
                        saved.algorithm = .sha1
                    }
                    save(OTPEntry(account: saved, secret: secretData ?? Data()))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(18)
        .frame(width: 440)
        .onAppear { AuthenticatorClock.shared.begin() }
        .onDisappear { AuthenticatorClock.shared.end() }
    }
}

/// One or several QR codes to scan with a phone, paged when there are
/// more than one.
private struct QRCodeSheet: View {
    let text: AuthenticatorFeatureStrings
    let sheet: QRSheet
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @State private var page = 0

    var body: some View {
        VStack(spacing: 12) {
            Text(sheet.title)
                .font(.headline)
            if let caption = sheet.caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            if let image = AuthenticatorService.qrImage(for: sheet.uris[page]) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 280, height: 280)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            if sheet.uris.count > 1 {
                HStack {
                    Button {
                        page = max(page - 1, 0)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(page == 0)
                    Text(String(format: text.qrBatchFormat, page + 1, sheet.uris.count))
                        .font(.caption)
                        .monospacedDigit()
                    Button {
                        page = min(page + 1, sheet.uris.count - 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(page == sheet.uris.count - 1)
                }
            }
            Button(l10n.s.uninstallerCancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(18)
        .frame(width: 360)
    }
}

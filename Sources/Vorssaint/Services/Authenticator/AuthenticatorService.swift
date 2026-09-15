// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import CoreImage
import LocalAuthentication

/// The authenticator: accounts, their codes, and the four ways a code
/// leaves the app (copied, typed, read by the Command Bar, shown in a
/// panel). Codes are computed when asked and never stored.
final class AuthenticatorService: ObservableObject {
    static let shared = AuthenticatorService()

    @Published private(set) var accounts: [OTPAccount] = []
    /// The Keychain refusal or unreadable file the settings page shows.
    @Published private(set) var storeProblem: String?
    /// With the unlock option on, codes stay hidden until Touch ID or the
    /// password has been given, and hide again after a quiet spell.
    @Published private(set) var isUnlocked = false

    private var store: AuthenticatorStore
    private var loaded = false
    /// Secrets read once per launch; a Keychain round trip per row per
    /// second would be wasteful while a list of codes is on screen.
    private var secretCache: [UUID: Data] = [:]
    /// Accounts whose secret could not be read this launch; asking the
    /// Keychain again on every tick would repeat its prompt endlessly.
    private var unavailable: Set<UUID> = []
    private var selection: ScreenshotSelectionController?
    private var clearClipboardWork: DispatchWorkItem?
    private var relockWork: DispatchWorkItem?
    /// The permission prompt fires at most once per launch; later attempts
    /// without Accessibility beep instead of nagging (PastePlain's pattern).
    private var promptedForAccessibility = false

    static let relockDelay: TimeInterval = 5 * 60

    private var strings: AuthenticatorFeatureStrings {
        FeatureStrings.authenticator(L10n.shared.language)
    }

    private init() {
        store = AuthenticatorStore(directoryURL: PrivateFileStore.containerURL,
                                   secrets: KeychainSecretStore())
    }

    func syncWithPreferences() {
        guard AppFeature.authenticator.isAvailable else {
            selection = nil
            return
        }
        loadIfNeeded()
        if !requiresUnlock { relock() }
    }

    func suspend() {
        selection = nil
    }

    // MARK: - Store

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        reload()
    }

    func reload() {
        secretCache = [:]
        unavailable = []
        do {
            try store.load()
            storeProblem = nil
        } catch {
            storeProblem = strings.storeUnreadable
        }
        accounts = store.accounts
    }

    func account(for id: UUID) -> OTPAccount? {
        accounts.first { $0.id == id }
    }

    /// Adds one entry; a refusal is returned as text ready for an alert.
    @discardableResult
    func add(_ entry: OTPEntry) -> String? {
        loadIfNeeded()
        do {
            try store.add(entry)
            accounts = store.accounts
            return nil
        } catch {
            return describe(error)
        }
    }

    @discardableResult
    func update(_ account: OTPAccount) -> String? {
        do {
            try store.update(account)
            accounts = store.accounts
            return nil
        } catch {
            return describe(error)
        }
    }

    @discardableResult
    func remove(id: UUID) -> String? {
        secretCache[id] = nil
        do {
            try store.remove(id: id)
            accounts = store.accounts
            return nil
        } catch {
            return describe(error)
        }
    }

    @discardableResult
    func reorder(_ ids: [UUID]) -> String? {
        do {
            try store.reorder(ids)
            accounts = store.accounts
            return nil
        } catch {
            return describe(error)
        }
    }

    func isDuplicate(_ entry: OTPEntry) -> Bool {
        loadIfNeeded()
        return store.isDuplicate(entry)
    }

    /// Whether another account already carries this service and name; the
    /// editor warns before a second copy is saved.
    func hasAccount(issuer: String, label: String, except id: UUID? = nil) -> Bool {
        accounts.contains {
            $0.id != id
                && $0.issuer.caseInsensitiveCompare(issuer) == .orderedSame
                && $0.label.caseInsensitiveCompare(label) == .orderedSame
        }
    }

    func entries(for ids: [UUID]? = nil) -> [OTPEntry] {
        loadIfNeeded()
        return store.entries(for: ids)
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case AuthenticatorStoreError.keychain(let status):
            return String(format: strings.keychainErrorFormat, Int(status))
        case AuthenticatorStoreError.unreadable, AuthenticatorStoreError.cannotSave:
            return strings.storeUnreadable
        default:
            return error.localizedDescription
        }
    }

    // MARK: - Lock

    var requiresUnlock: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.authenticatorRequiresUnlock)
    }

    var isLocked: Bool {
        requiresUnlock && !isUnlocked
    }

    /// Runs `action` once the person has authenticated, or straight away
    /// when the option is off or already satisfied. A Mac with no way to
    /// authenticate at all (no password set) is not locked out.
    func unlock(then action: @escaping () -> Void = {}) {
        guard isLocked else {
            action()
            return
        }
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            isUnlocked = true
            action()
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: strings.unlockReason) { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self, success else { return }
                self.isUnlocked = true
                self.scheduleRelock()
                action()
            }
        }
    }

    func relock() {
        relockWork?.cancel()
        relockWork = nil
        isUnlocked = false
    }

    private func scheduleRelock() {
        relockWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.relock() }
        relockWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.relockDelay, execute: work)
    }

    // MARK: - Codes

    /// Pinned first, then the saved order; the palette and panel read this.
    var orderedAccounts: [OTPAccount] {
        accounts.filter(\.pinned) + accounts.filter { !$0.pinned }
    }

    private func secret(for id: UUID) -> Data? {
        if let cached = secretCache[id] { return cached }
        guard !unavailable.contains(id) else { return nil }
        guard let secret = try? store.secret(for: id) else {
            unavailable.insert(id)
            return nil
        }
        secretCache[id] = secret
        return secret
    }

    /// Nil while locked, and for an account whose secret cannot be read.
    func code(for id: UUID, at date: Date = Date()) -> String? {
        guard !isLocked, let account = account(for: id), let secret = secret(for: id) else { return nil }
        return OneTimePassword.code(for: account, secret: secret, at: date)
    }

    func groupedCode(for id: UUID) -> String? {
        code(for: id).map(OneTimePassword.grouped)
    }

    func nextCode(for id: UUID, at date: Date = Date()) -> String? {
        guard !isLocked, let account = account(for: id), let secret = secret(for: id) else { return nil }
        return OneTimePassword.nextCode(for: account, secret: secret, at: date)
    }

    func secondsRemaining(for account: OTPAccount, at date: Date = Date()) -> Int {
        OneTimePassword.secondsRemaining(for: account, at: date)
    }

    /// The accounts whose issuer or label contains `query`, any case, any
    /// position.
    func matching(_ query: String) -> [OTPAccount] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return orderedAccounts }
        return orderedAccounts.filter {
            $0.issuer.localizedCaseInsensitiveContains(needle)
                || $0.label.localizedCaseInsensitiveContains(needle)
        }
    }

    // MARK: - Using a code

    /// Copies the current code, marked concealed so Clipboard History leaves
    /// it alone, and clears it again after the chosen delay if nothing else
    /// has been copied since.
    func copyCode(for id: UUID) {
        unlock { [weak self] in self?.copyNow(id) }
    }

    private func copyNow(_ id: UUID) {
        guard let code = code(for: id) else {
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType(
            ClipboardHistorySensitiveText.concealedPasteboardType))
        let changeCount = pasteboard.changeCount
        advanceCounterIfNeeded(id)
        QuickToolHUD.show(icon: "key.horizontal", message: strings.copied)

        clearClipboardWork?.cancel()
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: DefaultsKey.authenticatorClearsClipboard) else { return }
        let delay = max(defaults.integer(forKey: DefaultsKey.authenticatorClipboardClearDelay), 5)
        let work = DispatchWorkItem {
            guard NSPasteboard.general.changeCount == changeCount else { return }
            NSPasteboard.general.clearContents()
        }
        clearClipboardWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay), execute: work)
    }

    /// Types the current code into the frontmost app through the same
    /// synthesized keystrokes the snippet library uses, followed by Return
    /// when the option is on. Beeps when nothing can be typed: our own
    /// window in front, or Accessibility missing.
    func typeCode(for id: UUID) {
        unlock { [weak self] in self?.typeNow(id) }
    }

    private func typeNow(_ id: UUID) {
        guard let code = code(for: id) else {
            NSSound.beep()
            return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier
            == ProcessInfo.processInfo.processIdentifier {
            NSSound.beep()
            return
        }
        guard AXIsProcessTrusted() else {
            if promptedForAccessibility {
                NSSound.beep()
            } else {
                promptedForAccessibility = true
                Permissions.shared.requestAccessibility()
            }
            return
        }
        advanceCounterIfNeeded(id)
        let pressesReturn = UserDefaults.standard.bool(forKey: DefaultsKey.authenticatorPressesReturn)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.postWhenModifiersReleased(text: code, pressesReturn: pressesReturn, attempt: 0)
        }
    }

    private func advanceCounterIfNeeded(_ id: UUID) {
        guard account(for: id)?.kind == .hotp else { return }
        try? store.advanceCounter(id: id)
        accounts = store.accounts
    }

    /// Wait for a clean keyboard before typing: every 15 ms for up to
    /// ~1.5 s, plus a settle beat. Secure input means a password field,
    /// which is exactly where a code goes, so unlike snippets the secure
    /// case is allowed through.
    private func postWhenModifiersReleased(text: String, pressesReturn: Bool, attempt: Int) {
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
        if attempt >= 100 {
            NSSound.beep()
            return
        }
        guard held.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
                self?.postWhenModifiersReleased(text: text, pressesReturn: pressesReturn, attempt: attempt + 1)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            TextSnippetService.postExpansion(deleteCount: 0,
                                             text: text,
                                             trailingKeyCode: pressesReturn ? CGKeyCode(kVK_Return) : nil,
                                             trailingFlags: [])
        }
    }

    // MARK: - Importing

    /// What an import found, ready for the review window.
    struct ImportBatch: Identifiable {
        let id = UUID()
        var entries: [OTPEntry]
        var duplicates: Set<UUID>
        var failures: Int
    }

    func review(_ entries: [OTPEntry], failures: Int) {
        loadIfNeeded()
        guard !entries.isEmpty else {
            QuickToolHUD.show(icon: "key.horizontal", message: strings.importNothing)
            return
        }
        let duplicates = Set(entries.filter { store.isDuplicate($0) }.map(\.account.id))
        let batch = ImportBatch(entries: entries, duplicates: duplicates, failures: failures)
        AuthenticatorImportPanel.shared.show(batch) { [weak self] chosen in
            guard let self else { return }
            var added = 0
            for entry in chosen {
                if let failure = self.add(entry) {
                    self.report(failure)
                    break
                }
                added += 1
            }
            if added > 0 {
                QuickToolHUD.show(icon: "key.horizontal",
                                  message: String(format: self.strings.importedFormat, added))
            }
        }
    }

    func importText(_ text: String) {
        let found = OneTimePassword.entries(inText: text)
        review(found.entries, failures: found.failures)
    }

    func importImage(_ image: CGImage) {
        let payloads = BarcodeDetector.decode(image).map(\.payload)
        guard !payloads.isEmpty else {
            QuickToolHUD.show(icon: "qrcode.viewfinder", message: strings.noCodeFound)
            return
        }
        importText(payloads.joined(separator: "\n"))
    }

    func importClipboard() {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string),
           text.lowercased().contains("otpauth") {
            importText(text)
        } else if let image = NSImage(pasteboard: pasteboard),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            importImage(cgImage)
        } else {
            QuickToolHUD.show(icon: "key.horizontal", message: strings.importNothing)
        }
    }

    /// A file from another authenticator, this app's backup, a text export
    /// or a picture of a QR code; told apart by content, not by name.
    func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            report(strings.importNothing)
            return
        }
        switch AuthenticatorInterchange.detect(data) {
        case .aegis:
            importParsed { try AuthenticatorInterchange.aegisEntries(data) }
        case .twoFAS:
            importParsed { try AuthenticatorInterchange.twoFASEntries(data) }
        case .aegisEncrypted:
            report(String(format: strings.encryptedExportFormat, "Aegis"))
        case .twoFASEncrypted:
            report(String(format: strings.encryptedExportFormat, "2FAS"))
        case .backup:
            importBackup(data)
        case .otpauthText:
            importText(String(decoding: data, as: UTF8.self))
        case .none:
            if let image = NSImage(data: data),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                importImage(cgImage)
            } else {
                report(strings.importNothing)
            }
        }
    }

    private func importParsed(_ parse: () throws -> (entries: [OTPEntry], failures: Int)) {
        do {
            let found = try parse()
            review(found.entries, failures: found.failures)
        } catch {
            report(strings.importNothing)
        }
    }

    private func importBackup(_ data: Data) {
        guard let password = Self.askPassword(title: strings.backupPasswordTitle,
                                              message: strings.backupOpenMessage,
                                              confirm: false)
        else { return }
        do {
            review(try AuthenticatorInterchange.Backup.decrypt(data, password: password), failures: 0)
        } catch AuthenticatorInterchange.ImportError.wrongPassword {
            report(strings.wrongPassword)
        } catch {
            report(strings.importNothing)
        }
    }

    /// The person picks a region on the app's own capture surface, the same
    /// one Screen OCR uses, and any QR in it is read offline.
    func scanScreen() {
        guard AppFeature.authenticator.isAvailable else { return }
        guard Permissions.shared.screenRecording else {
            Permissions.shared.requestScreenRecording()
            return
        }
        guard selection == nil, !ScreenshotSelectionController.isSessionOnScreen else { return }
        let controller = ScreenshotSelectionController(freeze: false,
                                                       includePointer: false,
                                                       showLastRegion: false,
                                                       purpose: strings.scanScreen,
                                                       mode: .image)
        selection = controller
        controller.begin { [weak self, weak controller] outcome in
            guard let self, let controller, self.selection === controller else { return }
            self.selection = nil
            switch outcome {
            case .captured(let capture):
                self.importImage(capture.image)
            case .cancelled:
                break
            case .region, .scrollingRegion, .color, .failed:
                QuickToolHUD.show(icon: "qrcode.viewfinder", message: self.strings.noCodeFound)
            }
        }
    }

    /// Holds a phone up to the Mac's camera.
    func scanCamera() {
        guard AppFeature.authenticator.isAvailable else { return }
        AuthenticatorCameraScanner.shared.show { [weak self] payload in
            self?.importText(payload)
        }
    }

    // MARK: - Exporting

    static func qrImage(for text: String, side: CGFloat = 320) -> NSImage? {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(Data(text.utf8), forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter?.outputImage else { return nil }
        let scale = side / max(output.extent.width, 1)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }

    func exportText(for ids: [UUID]? = nil) -> String {
        entries(for: ids).map(OneTimePassword.uri(for:)).joined(separator: "\n") + "\n"
    }

    /// Asks for a password twice and seals the chosen accounts; nil when
    /// the person backed out.
    func exportBackup(for ids: [UUID]? = nil) -> Data? {
        guard let password = Self.askPassword(title: strings.backupPasswordTitle,
                                              message: strings.backupCreateMessage,
                                              confirm: true)
        else { return nil }
        return try? AuthenticatorInterchange.Backup.encrypt(entries(for: ids), password: password)
    }

    func migrationURIs(for ids: [UUID]? = nil) -> [String] {
        GoogleMigration.uris(for: entries(for: ids))
    }

    // MARK: - Prompts

    func report(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// A modal password field; with `confirm` a second field has to match.
    static func askPassword(title: String, message: String, confirm: Bool) -> String? {
        let strings = FeatureStrings.authenticator(L10n.shared.language)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: strings.exportContinue)
        alert.addButton(withTitle: L10n.shared.s.uninstallerCancel)
        let width: CGFloat = 260
        let field = NSSecureTextField(frame: NSRect(x: 0, y: confirm ? 30 : 0, width: width, height: 24))
        field.placeholderString = strings.passwordPlaceholder
        let repeatField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        repeatField.placeholderString = strings.passwordRepeatPlaceholder
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: width, height: confirm ? 54 : 24))
        accessory.addSubview(field)
        if confirm { accessory.addSubview(repeatField) }
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        while true {
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let password = field.stringValue
            if password.isEmpty { continue }
            if confirm, repeatField.stringValue != password {
                alert.informativeText = strings.passwordMismatch
                continue
            }
            return password
        }
    }

    // MARK: - Navigation

    func openSettings() {
        SettingsRouter.shared.page = .authenticator
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }
}

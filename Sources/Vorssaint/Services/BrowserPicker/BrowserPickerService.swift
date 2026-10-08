// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Receives the web links macOS hands to this app while it is the default
/// browser. A link a rule covers opens straight away; any other waits in the
/// picker at the pointer, and later ones that need it wait in order.
/// Main thread only, like the other services.
final class BrowserPickerService: ObservableObject {
    static let shared = BrowserPickerService()

    @Published private(set) var rules: [BrowserPickerRule]
    @Published private(set) var choices: [BrowserPickerChoice] = []
    /// Browsers whose profile list macOS kept from this app.
    @Published private(set) var withheldProfiles: [String] = []
    @Published private(set) var isDefaultBrowser = false
    @Published private(set) var isChangingDefault = false
    /// The link the picker is asking about, and how many wait behind it.
    @Published private(set) var pendingURL: URL?
    @Published private(set) var queuedCount = 0
    /// Why the picker is asking although a rule matched, or what went wrong.
    @Published private(set) var pickerNotice: String?
    @Published var highlighted = 0
    /// Set by the panel when there was no room below the pointer. The list
    /// then runs upward, so the first choice still sits next to the pointer.
    @Published var opensAbovePointer = false
    /// Arc's Spaces as last read, kept so the picker can offer them while Arc
    /// is closed, and whether reading them was refused.
    @Published private(set) var arcSpaces: [BrowserPickerArc.Space]
    @Published private(set) var arcAccess = BrowserPickerArc.Access.unknown

    private let defaults: UserDefaults
    private var queue: [(url: URL, notice: String?)] = []
    private var editorOpen = false
    /// Set from a choice until the browser takes the link, so a second click
    /// or key cannot open it twice.
    private var isOpening = false
    private var restoreAskedForStrayLinks = false
    private var knownProfiles: [String: Set<String>] = [:]
    /// Browsers this app just handed a link to, by when. Their coming to the
    /// front is the link arriving, not someone leaving the picker.
    private var recentlyOpened: [String: Date] = [:]
    private var discoveryInFlight = false
    private var discoveryAgain = false
    private lazy var panel = BrowserPickerPanel(service: self)
    private lazy var editorWindow = BrowserPickerEditorWindow()

    private var strings: BrowserPickerStrings { FeatureStrings.browserPicker(L10n.shared.language) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rules = BrowserPickerRules.decode(defaults.data(forKey: DefaultsKey.browserPickerRules))
        arcSpaces = (defaults.data(forKey: DefaultsKey.browserPickerArcSpaceList))
            .flatMap { try? JSONDecoder().decode([BrowserPickerArc.Space].self, from: $0) } ?? []
        isDefaultBrowser = BrowserPickerDefaultBrowser.isThisApp
    }

    // MARK: Lifecycle

    /// Nothing runs in the background: links only arrive while this app is the
    /// default browser. Uninstalling the feature from the hub gives the role
    /// back, so links do not keep going through a feature that is gone.
    func syncWithPreferences() {
        reloadRules()
        refreshDefaultState()
        // Nothing here asks macOS anything: profiles are read only once the
        // settings were opened, and Arc only while it runs and allows it.
        guard !AppFeature.browserPicker.isAvailable else {
            refreshChoices()
            return
        }
        dropPendingLinks()
        if isDefaultBrowser { setDefaultBrowser(false) }
    }

    func refreshDefaultState() {
        isDefaultBrowser = BrowserPickerDefaultBrowser.isThisApp
    }

    /// Asks macOS to send web links here, or back to the previous browser.
    func setDefaultBrowser(_ on: Bool) {
        guard !isChangingDefault else { return }
        isChangingDefault = true
        let finish: (Bool) -> Void = { [weak self] _ in
            guard let self else { return }
            self.isChangingDefault = false
            self.refreshDefaultState()
            // The feature may have been uninstalled while macOS was asking.
            if on, self.isDefaultBrowser, !AppFeature.browserPicker.isAvailable { self.setDefaultBrowser(false) }
        }
        if on {
            BrowserPickerDefaultBrowser.makeThisAppDefault(defaults: defaults, completion: finish)
        } else {
            BrowserPickerDefaultBrowser.restorePrevious(defaults: defaults, completion: finish)
        }
    }

    var previousBrowserName: String? {
        BrowserPickerDefaultBrowser.previousBrowser(defaults: defaults).map(BrowserPickerBrowsers.displayName(of:))
    }

    /// Browsers come and go rarely, so the list is read again in the
    /// background each time it is about to be shown; the picker never waits
    /// for it except on the very first link. Profiles are read once the
    /// settings have been opened, where macOS may first ask about them.
    func refreshChoices(openingSettings: Bool = false) {
        if openingSettings { defaults.set(true, forKey: DefaultsKey.browserPickerReadsProfiles) }
        guard !discoveryInFlight else {
            discoveryAgain = true
            return
        }
        discoveryInFlight = true
        let readingProfiles = defaults.bool(forKey: DefaultsKey.browserPickerReadsProfiles)
        let showingArcSpaces = arcSpacesEnabled
        let knownSpaces = arcSpaces
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let arc = showingArcSpaces ? Self.readArc() : (access: .unknown, spaces: nil)
            let spaces = (try? arc.spaces?.get()).flatMap { $0.isEmpty ? nil : $0 } ?? knownSpaces
            let found = BrowserPickerBrowsers.discover(readingProfiles: readingProfiles,
                                                      arcSpaces: showingArcSpaces ? spaces : [])
            DispatchQueue.main.async {
                guard let self else { return }
                self.discoveryInFlight = false
                self.noteArc(access: arc.access, spaces: arc.spaces)
                if found.withheldProfiles != self.withheldProfiles { self.withheldProfiles = found.withheldProfiles }
                self.knownProfiles = found.knownProfiles
                if found.choices != self.choices {
                    self.choices = found.choices
                    self.highlighted = min(self.highlighted, max(found.choices.count - 1, 0))
                }
                if self.discoveryAgain {
                    self.discoveryAgain = false
                    self.refreshChoices()
                }
            }
        }
    }

    // MARK: Arc Spaces

    var arcSpacesEnabled: Bool { defaults.bool(forKey: DefaultsKey.browserPickerArcSpaces) }

    func setArcSpaces(enabled: Bool) {
        defaults.set(enabled, forKey: DefaultsKey.browserPickerArcSpaces)
        objectWillChange.send()
        if enabled { requestArcAccess() } else { refreshChoices() }
    }

    /// Turning Spaces on, or refreshing them, is the moment macOS may ask
    /// whether this app can control Arc. It asks only about a running Arc,
    /// so a closed one is opened in the background first.
    func requestArcAccess() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = BrowserPickerArc.launchIfNeeded()
            let access = BrowserPickerArc.access(prompt: true)
            let spaces = access == .allowed ? BrowserPickerArc.spaces() : nil
            DispatchQueue.main.async {
                self?.noteArc(access: access, spaces: spaces)
                self?.refreshChoices()
            }
        }
    }

    /// The passive reading behind every refresh: never asks, never opens Arc.
    private static func readArc() -> (access: BrowserPickerArc.Access,
                                      spaces: Result<[BrowserPickerArc.Space], BrowserPickerArc.Failure>?) {
        guard BrowserPickerArc.isInstalled, BrowserPickerArc.isRunning else { return (.unknown, nil) }
        let access = BrowserPickerArc.access(prompt: false)
        return (access, access == .allowed ? BrowserPickerArc.spaces() : nil)
    }

    private func noteArc(access: BrowserPickerArc.Access,
                         spaces: Result<[BrowserPickerArc.Space], BrowserPickerArc.Failure>?) {
        if access != .unknown, access != arcAccess { arcAccess = access }
        // A window-less Arc reports no Spaces; keep what was read before.
        guard case .success(let list)? = spaces, !list.isEmpty, list != arcSpaces else { return }
        saveArcSpaces(list)
    }

    private func saveArcSpaces(_ list: [BrowserPickerArc.Space]) {
        arcSpaces = list
        defaults.set(try? JSONEncoder().encode(list), forKey: DefaultsKey.browserPickerArcSpaceList)
    }

    // MARK: Incoming links

    func receive(_ urls: [URL]) {
        let links = urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        guard !links.isEmpty else { return }
        guard AppFeature.browserPicker.isAvailable else {
            links.forEach(passThrough)
            // Links only arrive while this app is the default, which a settings
            // import can leave behind after removing the feature.
            if !restoreAskedForStrayLinks {
                restoreAskedForStrayLinks = true
                refreshDefaultState()
                if isDefaultBrowser { setDefaultBrowser(false) }
            }
            return
        }
        // A link that launched the app arrives before launching finishes;
        // it is handled on the next turn of the run loop.
        DispatchQueue.main.async { links.forEach(self.route) }
    }

    /// With the feature gone but this app still the default, links go to the
    /// browser that had them before rather than nowhere.
    private func passThrough(_ url: URL) {
        guard let browser = BrowserPickerDefaultBrowser.previousBrowser(defaults: defaults) else { return }
        NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration())
    }

    /// A link a rule covers opens at once, even while the picker asks about
    /// an earlier one; only links that need a choice wait their turn.
    private func route(_ url: URL) {
        if choices.isEmpty {
            choices = BrowserPickerBrowsers.discover(readingProfiles: false,
                                                     arcSpaces: arcSpacesEnabled ? arcSpaces : []).choices
        }
        switch BrowserPickerRoute.of(url, rules: rules, isInstalled: isInstalled) {
        case .open(let target):
            hand(url, to: target) { [weak self] result in
                guard let self, result != .opened else { return }
                self.ask(url, notice: self.notice(for: result, target: target))
            }
        case .ask(let missing):
            ask(url, notice: missing.map { String(format: strings.targetMissingFormat, label(for: $0)) })
        }
    }

    private func ask(_ url: URL, notice: String?) {
        queue.append((url, notice))
        showNext()
    }

    private func showNext() {
        defer { queuedCount = queue.count }
        guard pendingURL == nil, !queue.isEmpty else { return }
        let (url, notice) = queue.removeFirst()
        pendingURL = url
        pickerNotice = notice
        highlighted = 0
        refreshChoices()
        panel.show()
    }

    private func finishPending() {
        pendingURL = nil
        pickerNotice = nil
        panel.hide()
        showNext()
    }

    private func dropPendingLinks() {
        queue.removeAll()
        queuedCount = 0
        if pendingURL != nil {
            pendingURL = nil
            panel.hide()
        }
        editorWindow.close()
    }

    // MARK: Picker actions

    /// Opens the pending link in one choice. With `remember`, a rule for the
    /// link's site is added first, so the next link there opens directly.
    func choose(_ index: Int, remember: Bool = false) {
        guard let url = pendingURL, !isOpening, choices.indices.contains(index) else { return }
        let target = choices[index].target
        if remember {
            rules = BrowserPickerRules.remembering(target, for: url, in: rules).map { $0.targetName == nil ? named($0) : $0 }
            saveRules()
        }
        open(url, in: target)
    }

    func cancelPicker() {
        guard pendingURL != nil, !editorOpen, !isOpening else { return }
        finishPending()
    }

    func copyPendingLink() {
        guard let url = pendingURL, !isOpening else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        finishPending()
    }

    /// The editor replaces the picker until it closes. Saving opens the link
    /// with the new rule's target; cancelling brings the picker back.
    func addRuleForPendingLink() {
        guard let url = pendingURL, !isOpening else { return }
        let target = choices.indices.contains(highlighted) ? choices[highlighted].target : choices.first?.target
        let draft = BrowserPickerRuleDraft(site: BrowserPickerRules.suggestedSite(for: url) ?? "",
                                           path: "", target: target)
        editorOpen = true
        panel.hide()
        editorWindow.show(draft: draft, testURL: url, service: self) { [weak self] rule in
            guard let self else { return }
            self.editorOpen = false
            guard self.pendingURL == url else { return }
            if let rule {
                self.add(rule)
                self.open(url, in: rule.target)
            } else {
                self.panel.show()
            }
        }
    }

    /// The picker steps aside at once and comes back only if the browser
    /// could not take the link.
    private func open(_ url: URL, in target: BrowserPickerTarget) {
        isOpening = true
        panel.hide()
        hand(url, to: target) { [weak self] result in
            guard let self else { return }
            self.isOpening = false
            guard self.pendingURL == url else { return }
            if result == .opened {
                self.finishPending()
            } else {
                self.pickerNotice = self.notice(for: result, target: target)
                self.panel.show()
            }
        }
    }

    /// A browser that takes a while to start comes to the front only when it
    /// is done, so the time is noted at both ends.
    private func hand(_ url: URL, to target: BrowserPickerTarget,
                      completion: @escaping (BrowserPickerBrowsers.Opening) -> Void) {
        recentlyOpened[target.bundleID] = Date()
        BrowserPickerBrowsers.open(url, in: target) { [weak self] result in
            self?.recentlyOpened[target.bundleID] = Date()
            completion(result)
        }
    }

    /// Why a link did not open. A Space found gone leaves the cached list, and
    /// a withdrawn permission shows up in the settings.
    private func notice(for result: BrowserPickerBrowsers.Opening, target: BrowserPickerTarget) -> String {
        switch result {
        case .spaceMissing:
            if case .arcSpace(let id, _) = target { saveArcSpaces(arcSpaces.filter { $0.id != id }) }
            return String(format: strings.targetMissingFormat, label(for: target))
        case .arcNotAllowed:
            arcAccess = .denied
            return strings.arcNotAllowed
        case .opened, .failed:
            return String(format: strings.openFailedFormat, label(for: target))
        }
    }

    /// Switching to another app closes the picker, unless that app is a
    /// browser that just received a link from here.
    func otherAppDidActivate(_ bundleID: String?) {
        recentlyOpened = recentlyOpened.filter { $0.value.timeIntervalSinceNow > -5 }
        guard let bundleID, recentlyOpened[bundleID] == nil else { return }
        cancelPicker()
    }

    // MARK: Rules

    func add(_ rule: BrowserPickerRule) {
        rules.append(named(rule))
        saveRules()
    }

    func update(_ rule: BrowserPickerRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        var rule = named(rule)
        if rule.targetName == nil, rule.target == rules[index].target { rule.targetName = rules[index].targetName }
        rules[index] = rule
        saveRules()
    }

    private func named(_ rule: BrowserPickerRule) -> BrowserPickerRule {
        var rule = rule
        if BrowserPickerBrowsers.applicationURL(for: rule.target) != nil { rule.targetName = label(for: rule.target) }
        return rule
    }

    func delete(_ id: UUID) {
        rules.removeAll { $0.id == id }
        saveRules()
    }

    func setRules(_ reordered: [BrowserPickerRule]) {
        guard reordered.map(\.id).sorted(by: { $0.uuidString < $1.uuidString })
                == rules.map(\.id).sorted(by: { $0.uuidString < $1.uuidString }) else { return }
        rules = reordered
        saveRules()
    }

    private func saveRules() {
        defaults.set(BrowserPickerRules.encode(rules), forKey: DefaultsKey.browserPickerRules)
    }

    /// A settings import replaces the stored rules under the running service.
    func reloadRules() {
        rules = BrowserPickerRules.decode(defaults.data(forKey: DefaultsKey.browserPickerRules))
    }

    // MARK: Targets

    func isInstalled(_ target: BrowserPickerTarget) -> Bool {
        // A Space is offered only while the option is on and Arc may be
        // scripted, so a rule never brings up Arc's permission question.
        if case .arcSpace = target, !arcSpacesEnabled || arcAccess == .denied || arcAccess == .notAsked {
            return false
        }
        return BrowserPickerRules.isAvailable(target, appInstalled: BrowserPickerBrowsers.applicationURL(for: target) != nil,
                                              knownProfiles: knownProfiles,
                                              knownSpaces: arcSpaces.isEmpty ? nil : Set(arcSpaces.map(\.id)))
    }

    /// "Arc", or "Work · Google Chrome" for a profile.
    func label(for target: BrowserPickerTarget) -> String {
        if let choice = choices.first(where: { $0.target == target }) {
            return choice.subtitle.map { "\(choice.title) · \($0)" } ?? choice.title
        }
        guard let appURL = BrowserPickerBrowsers.applicationURL(for: target) else {
            return rules.first { $0.target == target && $0.targetName != nil }?.targetName ?? target.bundleID
        }
        let appName = BrowserPickerBrowsers.displayName(of: appURL)
        switch target {
        case .profile(_, _, let name), .arcSpace(_, let name): return "\(name) · \(appName)"
        case .application: return appName
        }
    }

    /// Every choice the editor can offer, including a rule's current target
    /// when it is no longer installed, so editing a rule never swaps it silently.
    func editorChoices(keeping target: BrowserPickerTarget?) -> [BrowserPickerTarget] {
        var targets = choices.map(\.target)
        // A browser with profiles is listed by its profiles in the picker,
        // but a rule may still open it without choosing one.
        for choice in choices {
            switch choice.target {
            case .profile, .arcSpace:
                let app = BrowserPickerTarget.application(bundleID: choice.target.bundleID)
                if !targets.contains(app) { targets.append(app) }
            case .application:
                break
            }
        }
        if let target, !targets.contains(target) { targets.append(target) }
        return targets
    }
}

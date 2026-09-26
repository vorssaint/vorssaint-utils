// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The AI page's options, under its row in the Dynamic Island settings.
struct NotchAgentsSettingsControls: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @AppStorage(DefaultsKey.notchAgentsClaude) private var claude = true
    @AppStorage(DefaultsKey.notchAgentsCodex) private var codex = true
    @AppStorage(DefaultsKey.notchAgentsCardOrder) private var cardOrder = ""
    @AppStorage(DefaultsKey.notchAgentsHiddenCards) private var hiddenCards = ""
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var limitDisplay = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLiveActivity) private var liveActivity = true
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsFinishAlert) private var finishAlert = true
    @AppStorage(DefaultsKey.notchAgentsFinishMinimum) private var finishMinimum = NotchAgentSupport.defaultFinishMinimum
    @AppStorage(DefaultsKey.notchAgentsLimitAlert) private var limitAlert = true
    @AppStorage(DefaultsKey.notchAgentsLimitThreshold) private var limitThreshold = NotchAgentSupport.defaultLimitThreshold
    @AppStorage(DefaultsKey.notchAgentsDailyBudget) private var dailyBudget = 0.0
    @AppStorage(DefaultsKey.notchAgentsPriceUpdates) private var priceUpdates = true
    @AppStorage(DefaultsKey.notchAgentsHideAccountNames) private var hidesAccountNames = false
    @State private var dragging: NotchAgentCard?
    @State private var roots: [AgentProvider: Bool] = [:]
    @State private var claudeApp: URL?
    /// Read from the file while the section is off and the service is idle.
    @State private var claudeAppFileCheck: Date?
    @State private var addingHub = false

    private var text: NotchAgentStrings { FeatureStrings.notchAgents(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }

    private var orderedCards: [NotchAgentCard] {
        let stored = cardOrder.split(separator: ",").compactMap { NotchAgentCard(rawValue: String($0)) }
        var seen = Set<NotchAgentCard>()
        return (stored + NotchAgentCard.allCases).filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text.settingsDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            providerRow(.claude, isOn: $claude)
            providerRow(.codex, isOn: $codex)

            Divider()
            hubs

            Divider()
            Text(text.cardsTitle).font(.subheadline.weight(.medium))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(orderedCards) { card in
                    PanelReorderableItem(item: card,
                                         order: Binding(get: { orderedCards },
                                                        set: { cardOrder = $0.map(\.rawValue).joined(separator: ",") }),
                                         dragging: $dragging) {
                        NotchEditorItem(symbol: card.symbol, title: text.card(card), included: cardBinding(card)) {
                            cardBinding(card).wrappedValue.toggle()
                        }
                        .accessibilityAction(named: FeatureStrings.clipboard(l10n.language).moveUp) { moveCard(card, by: -1) }
                        .accessibilityAction(named: FeatureStrings.clipboard(l10n.language).moveDown) { moveCard(card, by: 1) }
                    }
                }
            }
            Text(text.cardsHint).font(.caption).foregroundStyle(.secondary)
            SettingsChoiceRow(symbol: NotchAgentCard.limits.symbol, title: text.limitsAs, selection: $limitDisplay) {
                Text(text.remaining).tag(NotchAgentLimitDisplay.remaining.rawValue)
                Text(text.used).tag(NotchAgentLimitDisplay.used.rawValue)
            }

            Divider()
            Text(text.liveTitle).font(.subheadline.weight(.medium))
            switchRow("waveform.path.ecg", text.liveActivity, isOn: $liveActivity)
            if liveActivity {
                SettingsMenuRow(symbol: "camera.metering.center.weighted", title: text.readout, selection: $readout) {
                    ForEach(NotchAgentReadout.allCases) { option in
                        Text(text.readout(option)).tag(option.rawValue)
                    }
                }
                .padding(.leading, settingsRowTextInset)
                NotchAgentStripSample(readout: NotchAgentReadout(rawValue: readout) ?? .elapsed,
                                      display: NotchAgentLimitDisplay(rawValue: limitDisplay) ?? .remaining,
                                      provider: claude || !codex ? .claude : .codex)
                    .padding(.leading, settingsRowTextInset)
            }

            Divider()
            Text(text.alerts).font(.subheadline.weight(.medium))
            switchRow("checkmark.circle", text.finishAlert, isOn: $finishAlert)
            if finishAlert {
                SettingsMenuRow(symbol: "timer", title: text.finishAfter, selection: $finishMinimum) {
                    ForEach(NotchAgentSupport.finishMinimums, id: \.self) { seconds in
                        Text(seconds == 0 ? text.anyLength : AgentFormat.duration(seconds, locale: locale, style: .short))
                            .tag(seconds)
                    }
                }
                .padding(.leading, settingsRowTextInset)
            }
            switchRow("exclamationmark.triangle", text.limitAlert, isOn: $limitAlert)
            if limitAlert {
                SettingsMenuRow(symbol: "gauge.with.dots.needle.67percent", title: text.limitAt, selection: $limitThreshold) {
                    ForEach(NotchAgentSupport.limitThresholds, id: \.self) { value in
                        Text(text.usedShare(AgentFormat.percent(value / 100))).tag(value)
                    }
                }
                .padding(.leading, settingsRowTextInset)
            }
            SettingsMenuRow(symbol: "dollarsign.circle", title: text.budget, selection: $dailyBudget) {
                ForEach(NotchAgentSupport.budgets, id: \.self) { value in
                    Text(value == 0 ? text.off : AgentFormat.cost(value)).tag(value)
                }
            }
            Text(text.valueNote).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SettingsRow(symbol: "arrow.triangle.2.circlepath", title: text.priceUpdates, caption: priceCaption) {
                Toggle(text.priceUpdates, isOn: $priceUpdates).labelsHidden().toggleStyle(.switch)
            }

            if claude {
                Divider()
                Text(text.claudeLimitsTitle).font(.subheadline.weight(.medium))
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    claudeLimitsStatus(now: context.date)
                }
                Text(text.claudeLimitsPrivacy).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .sheet(isPresented: $addingHub) { NotchAgentHubSheet(text: text) }
        .onAppear {
            findRoots()
            // An agent turned off is not read at all, not even for its status.
            if claude { findClaudeApp() }
        }
        .onChange(of: claude) { _, on in if on { findClaudeApp() } }
        // Cards and agents set the page's height, and the live reading the
        // closed island's width, which the island follows.
        .onChange(of: [cardOrder, hiddenCards, String(claude), String(codex),
                       String(liveActivity), readout, limitDisplay]) { _, _ in
            NotchService.shared.syncWithPreferences()
        }
    }

    /// The CLIProxyAPI hubs whose accounts join the limits card.
    @ViewBuilder private var hubs: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.proxyHubsTitle).font(.subheadline.weight(.medium))
            Spacer(minLength: 8)
            Button(text.proxyAddHub) { addingHub = true }
        }
        Text(text.proxyHubsDescription).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        ForEach(usage.hubs) { hub in
            hubRow(hub)
            let accounts = usage.snapshot.accounts.filter { $0.hub == hub.id }
            if !accounts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(accounts) { account in
                        NotchAgentAccountNameRow(account: account, given: hub.names[account.index] ?? "",
                                                 hidesName: hidesAccountNames, text: text)
                    }
                }
                .padding(.leading, settingsRowTextInset)
            }
        }
        if !usage.hubs.isEmpty {
            SettingsRow(symbol: "eye.slash", title: text.proxyHideNames, caption: text.proxyHideNamesHint) {
                Toggle(text.proxyHideNames, isOn: $hidesAccountNames).labelsHidden().toggleStyle(.switch)
            }
        }
    }

    private func hubRow(_ hub: AgentHub) -> some View {
        let status = hubStatus(usage.hubStates[hub.id])
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(hub.name)
                if hub.name != hub.url {
                    Text(hub.url).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Label {
                    Text(status.text).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: status.symbol).foregroundStyle(status.tint)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(text.proxyRemoveHub) {
                usage.removeHub(hub.id)
                // Without a hub, the page needs one of this Mac's agents again.
                if usage.hubs.isEmpty, !claude, !codex { claude = true }
            }
        }
    }

    private func hubStatus(_ state: AgentHubState?) -> (text: String, symbol: String, tint: Color) {
        let warning = "exclamationmark.circle.fill"
        switch state {
        case nil: return (text.proxyHubOff, "pause.circle.fill", .secondary)
        case .checking: return (text.proxyHubChecking, "ellipsis.circle.fill", .secondary)
        case .ready(let count):
            return (text.proxyHubReady(count.formatted(.number.locale(locale))), "checkmark.circle.fill", .green)
        case .remoteDisabled: return (text.proxyHubRemoteDisabled, warning, .orange)
        case .wrongKey: return (text.proxyHubWrongKey, "xmark.circle.fill", .red)
        case .blocked: return (text.proxyHubBlocked, "xmark.circle.fill", .red)
        case .managementOff: return (text.proxyHubManagementOff, warning, .orange)
        case .insecure: return (text.proxyHubInsecure, warning, .orange)
        case .unreachable: return (text.proxyHubUnreachable, warning, .orange)
        case .failed(let status): return (text.proxyHubFailed(String(status)), warning, .orange)
        }
    }

    private var priceCaption: String {
        guard let day = usage.pricesUpdated else { return text.priceUpdatesHint }
        return text.priceUpdatesHint + " " + text.pricesFrom(AgentFormat.day(day, locale: locale))
    }

    /// Where Claude's plan limits stand, and the one step that brings them
    /// here when they are missing or old.
    @ViewBuilder private func claudeLimitsStatus(now: Date) -> some View {
        let checked = usage.claudeAppChecked ?? claudeAppFileCheck
        HStack(alignment: .top, spacing: 10) {
            if let checked, now.timeIntervalSince(checked) < AgentClaudeAppUsage.freshness {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(text.claudeLimitsCurrent(relative(checked, now: now)))
                Spacer(minLength: 0)
            } else if claudeApp == nil, checked == nil {
                Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                Text(text.claudeLimitsNoApp)
                Spacer(minLength: 8)
                Button(text.getClaude) { NSWorkspace.shared.open(AgentClaudeAppUsage.downloadURL) }
            } else {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    if let checked { Text(text.claudeLimitsStale(relative(checked, now: now))) }
                    Text(text.claudeLimitsMenuBar)
                }
                Spacer(minLength: 8)
                if let claudeApp {
                    Button(text.openClaude) {
                        NSWorkspace.shared.openApplication(at: claudeApp, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func relative(_ date: Date, now: Date) -> String {
        min(date, now).formatted(.relative(presentation: .named).locale(locale))
    }

    /// The app and the file are looked up when the page opens, off the main
    /// thread for the file, never on every draw.
    private func findClaudeApp() {
        claudeApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AgentClaudeAppUsage.bundleIdentifier)
        DispatchQueue.global(qos: .utility).async {
            let checked = AgentClaudeAppUsage.lastCheck()
            DispatchQueue.main.async { claudeAppFileCheck = checked }
        }
    }

    /// Laid out like every other row, with the agent's own mark for an icon.
    private func providerRow(_ provider: AgentProvider, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            NotchAgentMark(provider: provider, size: 13)
                .frame(width: 26, height: 26)
                .background(provider.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                Text(roots[provider] == true ? text.found : text.notFound)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            // One agent stays on unless a hub fills the page. Turning the
            // section off stops both.
            Toggle(provider.displayName, isOn: isOn).labelsHidden().toggleStyle(.switch)
                .disabled(isOn.wrappedValue && !(claude && codex) && usage.hubs.isEmpty)
        }
    }

    /// Where the logs live is checked when the page opens, not on every draw.
    private func findRoots() {
        let found = AgentLogRoot.all().filter(\.exists).map(\.provider)
        roots = Dictionary(uniqueKeysWithValues: AgentProvider.allCases.map { ($0, found.contains($0)) })
    }

    private func switchRow(_ symbol: String, _ title: String, isOn: Binding<Bool>) -> some View {
        SettingsRow(symbol: symbol, title: title) {
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }

    private func cardBinding(_ card: NotchAgentCard) -> Binding<Bool> {
        Binding {
            !hiddenCards.split(separator: ",").contains(Substring(card.rawValue))
        } set: { shown in
            var hidden = Set(hiddenCards.split(separator: ",").map(String.init))
            if shown { hidden.remove(card.rawValue) } else { hidden.insert(card.rawValue) }
            hiddenCards = hidden.sorted().joined(separator: ",")
        }
    }

    /// VoiceOver's way to reorder the cards, which otherwise only drag.
    private func moveCard(_ card: NotchAgentCard, by offset: Int) {
        var order = orderedCards
        guard let index = order.firstIndex(of: card), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        cardOrder = order.map(\.rawValue).joined(separator: ",")
    }
}

extension NotchAgentCard: PanelOrderItem {}

/// The closed island while an agent works, drawn small beside its option:
/// the mark on one side of the camera and the chosen reading on the other.
/// A turn in progress shows its own numbers; otherwise an example does.
private struct NotchAgentStripSample: View {
    let readout: NotchAgentReadout
    let display: NotchAgentLimitDisplay
    let provider: AgentProvider
    @ObservedObject private var usage = AgentUsageService.shared
    private static let camera: CGFloat = 64

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let working = usage.snapshot.live.first?.provider ?? provider
            HStack(spacing: 0) {
                NotchAgentGlyph(provider: working, size: 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: Self.camera)
                Text(reading(at: context.date))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(working.tint)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(width: Self.camera + 116, height: 24)
            .background(NotchShape(attached: true, radius: 9).fill(.black))
            .environment(\.colorScheme, .dark)
        }
        .accessibilityHidden(true)
    }

    private func reading(at now: Date) -> String {
        var snapshot = usage.snapshot
        if snapshot.live.isEmpty {
            snapshot.live = [AgentLiveSession(id: "example", provider: provider, started: now.addingTimeInterval(-754),
                                              lastActivity: now, model: "", project: "",
                                              tokens: AgentTokens(input: 1_180_000, cacheWrite: 0, cacheRead: 0, output: 20_000),
                                              cost: 4.56)]
        }
        return NotchAgentSupport.stripReading(snapshot, readout: readout, display: display, now: now)
    }
}


/// A hub account and the name the person gives it. The name saves when
/// they press Return or leave the field, so a space typed mid-name stays.
private struct NotchAgentAccountNameRow: View {
    let account: AgentHubAccount
    let given: String
    let hidesName: Bool
    let text: NotchAgentStrings
    @ObservedObject private var usage = AgentUsageService.shared
    @State private var name = ""
    @State private var revealed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            NotchAgentMark(provider: account.provider, size: 11)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            let hidden = hidesName && !revealed
            Text(hidden ? NotchAgentSupport.scrambled(account.name) : account.name)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .blur(radius: hidden ? 3.5 : 0)
                .onHover { inside in if hidesName { revealed = inside } }
            Spacer(minLength: 8)
            TextField(text.proxyCustomName, text: $name, prompt: Text(text.proxyCustomName))
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .focused($focused)
                .onSubmit(save)
                .onChange(of: focused) { _, now in if !now { save() } }
        }
        .onAppear { name = given }
        .onChange(of: given) { _, value in if !focused { name = value } }
    }

    private func save() {
        usage.renameAccount(hub: account.hub, index: account.index, to: name)
    }
}

/// The address, key and name of a new hub. The key field hides what the person types.
private struct NotchAgentHubSheet: View {
    let text: NotchAgentStrings
    @ObservedObject private var usage = AgentUsageService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var key = ""
    @State private var label = ""
    @State private var problem: String?

    private var complete: Bool {
        !url.trimmingCharacters(in: .whitespaces).isEmpty && !key.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text.proxyAddHubTitle).font(.headline)
            Text(text.proxyAddHubDescription).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField(text.proxyHubURL, text: $url, prompt: Text(verbatim: "https://hub.example.net:8310"))
                SecureField(text.proxyHubKey, text: $key)
                TextField(text.proxyHubLabel, text: $label, prompt: Text(text.proxyHubLabelPrompt))
            }
            .formStyle(.grouped)
            .autocorrectionDisabled()
            Text(problem ?? text.proxyHubKeyNote).font(.caption)
                .foregroundStyle(problem == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(text.proxyCancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(text.proxyAddHubButton, action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!complete)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func add() {
        guard AgentHub.normalizedURL(url) != nil else {
            problem = text.proxyHubInvalidURL
            return
        }
        guard usage.addHub(url: url, key: key, label: label) else {
            problem = text.proxyHubSaveFailed
            return
        }
        dismiss()
    }
}

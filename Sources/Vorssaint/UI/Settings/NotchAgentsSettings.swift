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
    @AppStorage(DefaultsKey.notchAgentsOpenCode) private var opencode = true
    @AppStorage(DefaultsKey.notchAgentsCopilot) private var copilot = true
    @AppStorage(DefaultsKey.notchAgentsCardOrder) private var cardOrder = ""
    @AppStorage(DefaultsKey.notchAgentsHiddenCards) private var hiddenCards = NotchAgentSupport.defaultHiddenCards
    @AppStorage(DefaultsKey.notchAgentsLimitDisplay) private var limitDisplay = NotchAgentLimitDisplay.remaining.rawValue
    @AppStorage(DefaultsKey.notchAgentsLimitFocus) private var limitFocus = NotchAgentLimitFocus.mostUsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsRestingLayout) private var restingLayout = NotchAgentRestingLayout.single.rawValue
    @AppStorage(DefaultsKey.notchAgentsRestingHidden) private var restingHidden = ""
    @AppStorage(DefaultsKey.notchAgentsLiveActivity) private var liveActivity = true
    @AppStorage(DefaultsKey.notchAgentsReadout) private var readout = NotchAgentReadout.elapsed.rawValue
    @AppStorage(DefaultsKey.notchAgentsFinishAlert) private var finishAlert = true
    @AppStorage(DefaultsKey.notchAgentsFinishMinimum) private var finishMinimum = NotchAgentSupport.defaultFinishMinimum
    @AppStorage(DefaultsKey.notchAgentsInputAlert) private var inputAlert = true
    @AppStorage(DefaultsKey.notchAgentsInputDelay) private var inputDelay = AgentAttentionPolicy.defaultDelay
    @AppStorage(DefaultsKey.notchAgentsInputRepeat) private var inputRepeat = true
    @AppStorage(DefaultsKey.notchAgentsInputInferred) private var inputInferred = false
    @AppStorage(DefaultsKey.notchAgentsInterruptAlert) private var interruptAlert = false
    @AppStorage(DefaultsKey.notchAgentsLimitAlert) private var limitAlert = true
    @AppStorage(DefaultsKey.notchAgentsLimitThreshold) private var limitThreshold = NotchAgentSupport.defaultLimitThreshold
    @AppStorage(DefaultsKey.notchAgentsDailyBudget) private var dailyBudget = 0.0
    @AppStorage(DefaultsKey.notchAgentsPriceUpdates) private var priceUpdates = true
    @AppStorage(DefaultsKey.notchAgentsClaudeBilling) private var claudeBilling = AgentClaudeBilling.automatic.rawValue
    @AppStorage(DefaultsKey.notchAgentsClaudeCredits) private var claudeCredits = 0.0
    @AppStorage(DefaultsKey.notchAgentsClaudeCreditsSince) private var claudeCreditsSince = 0.0
    /// The balance being typed, kept apart until it is saved.
    @State private var creditsDraft = ""
    @State private var dragging: NotchAgentCard?
    @State private var roots: [AgentProvider: Bool] = [:]
    @State private var claudeApp: URL?
    /// Read from the file while the section is off and the service is idle.
    @State private var claudeAppFileCheck: Date?

    private var text: NotchAgentStrings { FeatureStrings.notchAgents(l10n.language) }
    private var attention: AgentAttentionStrings { FeatureStrings.agentAttention(l10n.language) }
    private var billingText: ClaudeBillingStrings { FeatureStrings.claudeBilling(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }

    @AppStorage(DefaultsKey.notchAgentsClaudeSeats) private var claudeSeats = ""
    private var orderedCards: [NotchAgentCard] {
        NotchAgentSupport.orderedCards(cardOrder, claudeSeats: claude && !ClaudeSeatProfile.decode(claudeSeats).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text.settingsDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            providerRow(.claude, isOn: $claude)
            providerRow(.codex, isOn: $codex)
            providerRow(.opencode, isOn: $opencode)
            providerRow(.copilot, isOn: $copilot)
            if claude { ClaudeSeatsSettings() }
            if codex { CodexAccountsSettings() }
            NotchLimitVisibilitySettings(claude: claude, codex: codex)

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
            // The card that makes Codex ask the default account, said where it is chosen.
            if codex, cardBinding(.resets).wrappedValue {
                Text(text.resetsHelp).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsChoiceRow(symbol: NotchAgentCard.limits.symbol, title: text.limitsAs, selection: $limitDisplay) {
                Text(text.remaining).tag(NotchAgentLimitDisplay.remaining.rawValue)
                Text(text.used).tag(NotchAgentLimitDisplay.used.rawValue)
            }
            // The resting island shows this allowance whatever the live
            // reading, and the live reading uses it when it shows a limit.
            SettingsMenuRow(symbol: "rectangle.topthird.inset.filled", title: text.limitFocus, selection: $limitFocus) {
                ForEach(NotchAgentLimitFocus.allCases) { focus in
                    Text(text.limitFocus(focus)).tag(focus.rawValue)
                }
            }
            restingGroup

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
                                      focus: NotchAgentLimitFocus(rawValue: limitFocus) ?? .mostUsed,
                                      provider: claude ? .claude : codex ? .codex : opencode ? .opencode : .copilot)
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
            switchRow("hand.raised", attention.inputAlert, isOn: $inputAlert)
            if inputAlert {
                Group {
                    SettingsMenuRow(symbol: "timer", title: attention.inputAfter, selection: $inputDelay) {
                        ForEach(AgentAttentionPolicy.delays, id: \.self) { seconds in
                            Text(AgentFormat.duration(seconds, locale: locale, style: .short)).tag(seconds)
                        }
                    }
                    switchRow("bell.badge", attention.inputRepeat, isOn: $inputRepeat)
                    switchRow("questionmark.circle", attention.inputInferred, isOn: $inputInferred)
                }
                .padding(.leading, settingsRowTextInset)
            }
            switchRow("pause.circle", attention.interruptAlert, isOn: $interruptAlert)
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
                if usage.claudeAccountChecking { ProgressView().controlSize(.small) }
                Text(text.claudeLimitsPrivacy).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                claudeBillingGroup
            }
        }
        .toggleStyle(.switch)
        .onAppear {
            findRoots()
            // An agent turned off is not read at all, not even for its status.
            if claude { findClaudeApp() }
        }
        .onChange(of: claude) { _, on in if on { findClaudeApp() } }
        // Cards and agents set the page's height, and the live reading the
        // closed island's width, which the island follows.
        .onChange(of: [cardOrder, hiddenCards, String(claude), String(codex), String(opencode), String(copilot),
                       String(liveActivity), readout, limitDisplay, limitFocus, claudeBilling]) { _, _ in
            NotchService.shared.syncWithPreferences()
        }
    }

    /// Who pays for Claude Code, and the API key's balance when it does.
    @ViewBuilder private var claudeBillingGroup: some View {
        let detected = AgentClaudeBilling.detected(home: FileManager.default.homeDirectoryForCurrentUser)
        Text(billingText.billingTitle).font(.subheadline.weight(.medium)).padding(.top, 4)
        SettingsMenuRow(symbol: "creditcard", title: billingText.billsTo, selection: $claudeBilling) {
            ForEach(AgentClaudeBilling.allCases) { option in
                Text(billingText.billing(option, detectedAPI: detected)).tag(option.rawValue)
            }
        }
        Text(billingText.billingCaption).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        let _ = claudeBilling
        if AgentClaudeBilling.usesAPI() {
            SettingsRow(symbol: "dollarsign.circle", title: billingText.creditsTitle) {
                HStack(spacing: 6) {
                    TextField(billingText.balance, text: $creditsDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                        .multilineTextAlignment(.trailing)
                        .onSubmit(saveCredits)
                    Button(billingText.save, action: saveCredits)
                        .disabled(parsedCredits == nil)
                    if claudeCredits > 0 {
                        Button(billingText.clear) {
                            AgentClaudeCredits.clear()
                            creditsDraft = ""
                        }
                    }
                }
            }
            if let stored = AgentClaudeCredits.stored(), claudeCreditsSince > 0,
               let left = stored.remaining(days: usage.snapshot.days) {
                Text(billingText.creditsLeft(AgentFormat.cost(max(0, left)),
                                             since: stored.since.formatted(.relative(presentation: .named).locale(locale))))
                    .font(.callout)
                    .padding(.leading, settingsRowTextInset)
            }
            Text(billingText.creditsCaption).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The balance typed, in the reader's own way of writing numbers.
    private var parsedCredits: Double? {
        let trimmed = creditsDraft.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
        let value = (try? Double(trimmed, format: .number.locale(locale))) ?? Double(trimmed)
        return value.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
    }

    private func saveCredits() {
        guard let balance = parsedCredits else { return }
        AgentClaudeCredits.store(balance: balance, now: Date(), days: usage.snapshot.days)
        creditsDraft = ""
    }

    /// Agents switched on that report a plan allowance, the ones that can rest.
    private var restable: [AgentProvider] {
        let on: [AgentProvider: Bool] = [.claude: claude, .codex: codex, .opencode: opencode, .copilot: copilot]
        return AgentProvider.allCases.filter { on[$0] == true && $0.reportsLimits }
    }

    /// How the resting island shows the allowances: the layout, the agents
    /// that rest, and the strip as it will look. "Limit to show" above picks
    /// the limit each meter shows.
    @ViewBuilder private var restingGroup: some View {
        let layout = NotchAgentRestingLayout(rawValue: restingLayout) ?? .single
        Text(text.atRest).font(.subheadline.weight(.medium)).padding(.top, 4)
        SettingsMenuRow(symbol: "rectangle.split.3x1", title: text.restingLayout, selection: $restingLayout) {
            ForEach(NotchAgentRestingLayout.allCases) { option in
                Text(text.restingLayout(option)).tag(option.rawValue)
            }
        }
        Text(text.restingFocusCaption).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        if layout == .split, restable.filter({ !restingHiddenSet.contains($0) }).count > 2 {
            Text(text.restingSplitCaption).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !restable.isEmpty {
            Text(text.showAtRest).font(.callout).foregroundStyle(.secondary)
            ForEach(restable) { provider in
                HStack(spacing: 12) {
                    NotchAgentMark(provider: provider, size: 13)
                        .frame(width: 26, height: 26)
                        .background(provider.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .accessibilityHidden(true)
                    Text(provider.displayName)
                    Spacer(minLength: 12)
                    Toggle(provider.displayName, isOn: restingBinding(provider)).labelsHidden().toggleStyle(.switch)
                }
            }
        }
        NotchAgentRestingSample(sample: usage.snapshot.limits.keys.contains(where: restable.contains)
                                    ? nil : Self.sampleUsage(restable))
            .padding(.leading, settingsRowTextInset)
    }

    private var restingHiddenSet: Set<AgentProvider> { NotchAgentSupport.parseRestingHidden(restingHidden) }

    private func restingBinding(_ provider: AgentProvider) -> Binding<Bool> {
        Binding {
            !restingHiddenSet.contains(provider)
        } set: { shown in
            var hidden = restingHiddenSet
            if shown { hidden.remove(provider) } else { hidden.insert(provider) }
            restingHidden = hidden.map(\.rawValue).sorted().joined(separator: ",")
        }
    }

    /// Example allowances for the preview while no agent reports its own.
    private static func sampleUsage(_ providers: [AgentProvider]) -> AgentUsageSnapshot {
        let now = Date()
        let examples: [(session: Double, weekly: Double)] = [(28, 55), (62, 20), (40, 10)]
        var snapshot = AgentUsageSnapshot()
        for (index, provider) in (providers.isEmpty ? [.claude] : providers).enumerated() {
            let example = examples[index % examples.count]
            snapshot.limits[provider] = AgentLimits(provider: provider, windows: [
                AgentLimitWindow(id: "session", kind: .session, minutes: 300, scope: nil,
                                 usedPercent: example.session, resetsAt: now.addingTimeInterval(3600)),
                AgentLimitWindow(id: "weekly", kind: .weekly, minutes: 10_080, scope: nil,
                                 usedPercent: example.weekly, resetsAt: now.addingTimeInterval(86_400))],
                observedAt: now, source: .sessionLog)
        }
        return snapshot
    }

    private var priceCaption: String {
        guard let day = usage.pricesUpdated else { return text.priceUpdatesHint }
        return text.priceUpdatesHint + " " + text.pricesFrom(AgentFormat.day(day, locale: locale))
    }

    /// Where Claude's plan limits stand, and the one step that brings them
    /// here when they are missing or old. Without a recent reading from
    /// Claude Code, why its last check failed shows beneath.
    @ViewBuilder private func claudeLimitsStatus(now: Date) -> some View {
        let account = usage.snapshot.limits[.claude].flatMap { $0.source == .account ? $0.observedAt : nil }
        let checked = account ?? usage.claudeAppChecked ?? claudeAppFileCheck
        let failure = account.map { now.timeIntervalSince($0) < AgentClaudeAppUsage.freshness } == true ? nil
            : usage.claudeAccountFailure.map { text.claudeCode($0) }
        HStack(alignment: .top, spacing: 10) {
            if let account {
                Image(systemName: now.timeIntervalSince(account) < AgentClaudeAppUsage.freshness
                      ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(now.timeIntervalSince(account) < AgentClaudeAppUsage.freshness ? .green : .orange)
                explained(failure) { Text("Claude Code · " + text.updated(relative(account, now: now))) }
                Spacer(minLength: 0)
            } else if let checked, now.timeIntervalSince(checked) < AgentClaudeAppUsage.freshness {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                explained(failure) { Text(text.claudeLimitsCurrent(relative(checked, now: now))) }
                Spacer(minLength: 0)
            } else if claudeApp == nil, checked == nil {
                Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                explained(failure) { Text(text.claudeLimitsNoApp) }
                Spacer(minLength: 8)
                Button(text.getClaude) { NSWorkspace.shared.open(AgentClaudeAppUsage.downloadURL) }
            } else {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                explained(failure) {
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

    /// A status's words, and why Claude Code could not check when it failed.
    private func explained<Content: View>(_ failure: String?, @ViewBuilder _ status: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            status()
            if let failure { Text(failure).foregroundStyle(.secondary) }
        }
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
            // One agent stays on; turning the section off stops all.
            Toggle(provider.displayName, isOn: isOn).labelsHidden().toggleStyle(.switch)
                .disabled(isOn.wrappedValue && [claude, codex, opencode, copilot].filter { $0 }.count <= 1)
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
    let focus: NotchAgentLimitFocus
    let provider: AgentProvider
    @ObservedObject private var usage = AgentUsageService.shared
    private static let camera: CGFloat = 64

    var body: some View {
        NotchAgentReadoutTimeline(readout: readout) { date in
            // An example works in both places while nothing runs.
            let mark = NotchAgentWorkingLayout(usage.snapshot.live, budget: 16)
                ?? NotchAgentWorkingLayout(provider: provider, terminal: 1, app: 1, budget: 16)
            HStack(spacing: 0) {
                NotchAgentWorkingMark(layout: mark,
                                      window: NotchAgentSupport.focusedLimit(usage.snapshot.limits[mark.provider],
                                                                             focus: focus, now: date),
                                      used: display == .used)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: Self.camera)
                Text(reading(at: date))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
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
        return NotchAgentSupport.stripReading(snapshot, readout: readout, display: display, focus: focus, now: now)
    }
}

/// The resting island drawn small beside its options: the real wings around
/// a camera, with the person's allowances or an example of them.
private struct NotchAgentRestingSample: View {
    let sample: AgentUsageSnapshot?
    private static let camera: CGFloat = 64
    private static let wing: CGFloat = 44
    /// The wing's shoulder on a MacBook's 32-point strip.
    private static let inset: CGFloat = 11

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                Color.clear
                NotchAgentRestingWing(side: .leading, sample: sample).padding(.leading, Self.inset)
            }
            .frame(width: Self.wing)
            Color.clear.frame(width: Self.camera)
            ZStack(alignment: .leading) {
                Color.clear
                NotchAgentRestingWing(side: .trailing, sample: sample).padding(.trailing, Self.inset)
            }
            .frame(width: Self.wing)
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(width: Self.camera + Self.wing * 2, height: 32)
        .background(NotchShape(attached: true, radius: 10).fill(.black))
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Cursor page. With no chat yet, it stays on the connection flow.
struct NotchCursorView: View {
    let size: CGSize
    @ObservedObject private var cursor = CursorNotchService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var thinkingOpen = false
    @State private var replyOpen = false
    @State private var openEdits: Set<String> = []
    @State private var gaze = CGPoint.zero
    @State private var typedReplies: Set<String> = []
    @State private var stateBlur = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(DefaultsKey.notchCursorBuddy) private var buddy = true
    @AppStorage(DefaultsKey.notchCursorEyesFollow) private var eyesFollow = false
    @AppStorage(DefaultsKey.notchCursorTypewriter) private var typewriter = true

    private var text: NotchCursorViewStrings { FeatureStrings.notchCursorView(l10n.language) }
    private var title: String { FeatureStrings.notchCursor(l10n.language).title }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NotchCursorApprovalCard()
                if cursor.visibleSessions.isEmpty {
                    buddyMark(.wave)
                    CursorHookConnectControls(inNotch: true)
                    NotchCursorNewChat()
                } else if let session = cursor.focusedSession {
                    buddyMark(CursorBuddyPose.pose(for: session.state))
                    header(session)
                    liveCard(session)
                    timeline(session)
                    edits(session)
                    thinking(session)
                    reply(session)
                    NotchCursorComposer(session: session)
                    NotchCursorExperimentalControls(session: session)
                    NotchCursorPullRequestCard(session: session)
                    footer(session)
                    NotchCursorNewChat()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: size.width, height: size.height)
        .onAppear {
            cursor.pageVisible = true
            cursor.refreshGit()
        }
        .onDisappear {
            cursor.pageVisible = false
            cursor.refreshGit()
        }
        .onContinuousHover { phase in
            guard eyesFollow, cursor.pageVisible else { gaze = .zero; return }
            if case .active(let location) = phase {
                gaze = CGPoint(x: min(1, max(-1, location.x / max(size.width, 1) - 0.5)),
                               y: min(1, max(-1, location.y / max(size.height, 1) - 0.5)))
            } else {
                gaze = .zero
            }
        }
    }

    @ViewBuilder
    private func buddyMark(_ pose: CursorBuddyPose) -> some View {
        if buddy {
            NotchCursorBuddy(pose: pose, tint: CursorStateTint.color(pose == .wave ? .idle : cursor.focusedSession?.state ?? .idle,
                                                                     increaseContrast: contrast == .increased),
                             reduceMotion: reduceMotion, gaze: eyesFollow ? gaze : .zero)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
        }
    }

    private func header(_ session: CursorSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            chipRow
            HStack(spacing: 8) {
                NotchCursorMark(size: 18)
                    .foregroundStyle(CursorStateTint.color(session.state))
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.project)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let model = session.model, !model.isEmpty {
                            Text(model).lineLimit(1)
                        }
                        if let version = session.cursorVersion, !version.isEmpty {
                            Text(version).lineLimit(1)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title), \(session.project), \(text.stateName(session.state))")
            NotchCursorSessionActions(session: session)
        }
    }

    private var chipRow: some View {
        let groups = Dictionary(grouping: cursor.visibleSessions, by: \.project)
        let names = groups.keys.sorted { left, right in
            let leftDate = groups[left]?.map(\.lastEvent).max() ?? .distantPast
            let rightDate = groups[right]?.map(\.lastEvent).max() ?? .distantPast
            return leftDate > rightDate
        }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(names, id: \.self) { name in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(groups[name] ?? []) { session in
                            chip(session)
                        }
                    }
                }
            }
        }
    }

    private func chip(_ session: CursorSession) -> some View {
        let selected = session.id == cursor.focusedSession?.id
        return Button { cursor.select(session.id) } label: {
            HStack(spacing: 4) {
                Text(session.project)
                    .lineLimit(1)
                badge(session.source == .app ? text.app : text.terminal)
                if session.remote { badge(text.remote) }
                if session.background { badge(text.background) }
                if let mode = session.mode, !mode.isEmpty { badge(mode) }
            }
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(selected ? Color.white.opacity(0.16) : Color.white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(session.project), \(text.stateName(session.state))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func badge(_ label: String) -> some View {
        Text(label)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func liveCard(_ session: CursorSession) -> some View {
        let current = session.steps.last { $0.status == .running } ?? session.steps.last
        return VStack(alignment: .leading, spacing: 4) {
            Text(text.stateName(session.state))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CursorStateTint.color(session.state, increaseContrast: contrast == .increased))
                .blur(radius: reduceMotion ? 0 : (stateBlur ? 4 : 0))
                .id(session.state)
                .transition(reduceMotion ? .identity : .push(from: .bottom).combined(with: .opacity))
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: session.state)
                .onChange(of: session.state) { _, _ in
                    guard !reduceMotion else { return }
                    stateBlur = true
                    withAnimation(.easeOut(duration: 0.28)) { stateBlur = false }
                }
            if let current {
                Text(text.step(current.label, status: current.status))
                    .font(.system(size: 12))
                    .lineLimit(2)
            }
            if let prompt = session.prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(AgentFormat.clock(session.elapsed(at: context.date)))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .contentTransition(.numericText())
            }
            if let context = session.context, !context.isEmpty {
                contextMeter(context)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func contextMeter(_ meter: CursorContextMeter) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let percent = meter.percent {
                ProgressView(value: min(max(percent, 0), 100), total: 100)
                    .tint(.white.opacity(0.7))
            }
            Text(contextLabel(meter))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func contextLabel(_ meter: CursorContextMeter) -> String {
        var parts: [String] = []
        if let percent = meter.percent { parts.append("\(Int(percent.rounded()))%") }
        if let tokens = meter.tokens, let window = meter.window {
            parts.append("\(tokens) / \(window)")
        } else if let tokens = meter.tokens {
            parts.append("\(tokens)")
        }
        return parts.joined(separator: " · ")
    }

    private func timeline(_ session: CursorSession) -> some View {
        let rows = session.steps.suffix(6)
        return VStack(alignment: .leading, spacing: 4) {
            Text(text.timeline)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            ForEach(Array(rows)) { step in
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.step(step.label, status: step.status))
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .overlay { NotchCursorShimmer(active: step.status == .running && cursor.pageVisible) }
                    HStack(spacing: 6) {
                        if step.sandbox { badge(text.sandbox) }
                        if step.truncated { badge(text.truncated) }
                        if let mark = step.automatic {
                            badge(mark == .allowed
                                  ? FeatureStrings.notchCursorControl(l10n.language).autoAllowed
                                  : FeatureStrings.notchCursorControl(l10n.language).autoDenied)
                        }
                        if let duration = step.durationMS {
                            Text(AgentFormat.duration(TimeInterval(duration) / 1000,
                                                      locale: l10n.language.formattingLocale(), units: 1))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    if let output = step.output, !output.isEmpty {
                        Text(output)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(4)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func edits(_ session: CursorSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !session.edits.isEmpty {
                Text(text.edits)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            ForEach(session.edits) { edit in
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        if openEdits.contains(edit.id) { openEdits.remove(edit.id) } else { openEdits.insert(edit.id) }
                    } label: {
                        HStack {
                            Text(CursorSessionReducer.fileName(edit.path))
                                .lineLimit(1)
                            Text("+\(edit.added)  -\(edit.removed)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                            if edit.truncated { badge(text.truncated) }
                        }
                        .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(CursorSessionReducer.fileName(edit.path)), +\(edit.added), -\(edit.removed)")
                    if !session.remote, CursorAppBridge.applicationURL() != nil {
                        Button(FeatureStrings.notchCursorControl(l10n.language).openFile) {
                            _ = CursorAppBridge.open(file: edit.path)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if openEdits.contains(edit.id) {
                        NotchCursorDiffView(edit: edit)
                    }
                }
            }
        }
    }

    private func thinking(_ session: CursorSession) -> some View {
        Group {
            if let thought = session.thought, !thought.isEmpty {
                Button { thinkingOpen.toggle() } label: {
                    Text(text.thinkingTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
                if thinkingOpen {
                    NotchTypewriterText(text: thought, token: session.id + (session.thought ?? ""), dimmed: true,
                                         enabled: typewriter, pageVisible: cursor.pageVisible,
                                         alreadyShown: typedReplies.contains(session.id + (session.thought ?? "")),
                                         onFinish: { typedReplies.insert(session.id + (session.thought ?? "")) })
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func reply(_ session: CursorSession) -> some View {
        Group {
            if let reply = session.reply, !reply.isEmpty {
                Text(text.reply)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                NotchTypewriterText(text: shownReply(reply), token: session.id + reply, dimmed: false,
                                     enabled: typewriter && !replyOpen, pageVisible: cursor.pageVisible,
                                     alreadyShown: typedReplies.contains(session.id + reply),
                                     onFinish: { typedReplies.insert(session.id + reply) })
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(text.reply)
                if !replyOpen, reply.count > 600 {
                    Button(text.showMore) { replyOpen = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                }
                if !session.tokens.isEmpty {
                    Text(text.tokens(session.tokens))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    private func shownReply(_ reply: String) -> String {
        guard !replyOpen, reply.count > 600 else { return reply }
        return String(reply.prefix(600))
    }

    private func footer(_ session: CursorSession) -> some View {
        Text(text.summary(files: session.fileCount, commands: session.commandCount, failures: session.failureCount))
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.6))
            .accessibilityLabel(text.summary(files: session.fileCount, commands: session.commandCount,
                                              failures: session.failureCount))
    }
}

struct NotchCursorMark: View {
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: NotchModule.cursor.symbol)
            .font(.system(size: size, weight: .medium))
            .accessibilityHidden(true)
    }
}

/// A line diff for one edited file. The comparison stays off the main actor.
struct NotchCursorDiffView: View {
    let edit: CursorEdit
    @State private var lines: [CursorDiffLine] = []
    @State private var truncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text("\(line.sign) \(line.text)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(line.sign == "+" ? Color.green.opacity(0.85) : Color.red.opacity(0.85))
                    .lineLimit(1)
            }
            if truncated {
                Text(FeatureStrings.notchCursorView(L10n.shared.language).truncated)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .accessibilityHidden(lines.isEmpty)
        .task(id: "\(edit.added)-\(edit.removed)-\(edit.hunks.count)-\(edit.truncated)") {
            let hunks = edit.hunks
            let diff = await Task.detached(priority: .utility) {
                hunks.reduce(into: (lines: [CursorDiffLine](), truncated: false)) { partial, hunk in
                    let piece = CursorLineDiff.lines(old: hunk.oldText, new: hunk.newText,
                                                      limit: max(0, 200 - partial.lines.count))
                    partial.lines.append(contentsOf: piece.lines)
                    partial.truncated = partial.truncated || piece.truncated || hunk.truncated
                }
            }.value
            lines = diff.lines
            truncated = diff.truncated
        }
    }
}

enum CursorStateTint {
    static func color(_ state: CursorLiveState, increaseContrast: Bool = false) -> Color {
        if increaseContrast {
            switch state {
            case .thinking: return .purple
            case .reading, .searching: return .blue
            case .editing: return .teal
            case .running, .subagent: return .yellow
            case .waiting: return .orange
            case .done: return .green
            case .failed, .stopped: return .red
            case .idle, .sent, .quiet: return .white
            }
        }
        switch state {
        case .thinking: return Color(red: 0.62, green: 0.45, blue: 0.95)
        case .reading, .searching: return Color(red: 0.35, green: 0.55, blue: 0.98)
        case .editing: return Color(red: 0.20, green: 0.72, blue: 0.70)
        case .running, .subagent: return Color(red: 0.95, green: 0.62, blue: 0.20)
        case .waiting: return Color(red: 0.98, green: 0.50, blue: 0.18)
        case .done: return Color(red: 0.30, green: 0.78, blue: 0.45)
        case .failed, .stopped: return Color(red: 0.90, green: 0.32, blue: 0.32)
        case .idle, .sent, .quiet: return Color.white.opacity(0.6)
        }
    }
}

/// Closed island beside a camera. The mark takes the state color.
struct NotchCursorStrip: View {
    @ObservedObject var service: NotchService
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var cursor = CursorNotchService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    private var text: NotchCursorViewStrings { FeatureStrings.notchCursorView(l10n.language) }

    var body: some View {
        let textSize = NotchAgentSupport.stripTextSize(height: geometry.compactActivityContentHeight)
        let mark = min(14, max(8, textSize))
        let session = cursor.focusedSession
        let waiting = session?.state == .waiting && !cursor.paused
        Button { service.openActivity(.cursor) } label: {
            HStack(spacing: 0) {
                pulsingMark(size: mark, state: session?.state ?? .idle, waiting: waiting)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Color.clear.frame(width: geometry.compactActivityCameraGap)
                stripReading(session, size: textSize)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.white.opacity(0.9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityReading(session))
        .overlay { NotchCursorWorkingGlow(state: session?.state ?? .idle, paused: cursor.paused) }
    }

    @ViewBuilder
    private func stripReading(_ session: CursorSession?, size: CGFloat) -> some View {
        if CursorNotchService.readout() == .elapsed, let session, !cursor.paused {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(AgentFormat.clock(session.elapsed(at: context.date)))
                    .font(.system(size: size, weight: .semibold))
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        } else {
            Text(reading(session))
                .font(.system(size: size, weight: .semibold))
                .lineLimit(1)
        }
    }

    private func reading(_ session: CursorSession?) -> String {
        guard let session else { return FeatureStrings.notchCursor(l10n.language).title }
        switch CursorNotchService.readout() {
        case .state: return text.stateName(session.state)
        case .project: return session.project
        case .elapsed: return AgentFormat.clock(session.elapsed(at: Date()))
        }
    }

    private func accessibilityReading(_ session: CursorSession?) -> String {
        guard let session else { return FeatureStrings.notchCursor(l10n.language).title }
        return "\(session.project), \(text.stateName(session.state))"
    }

    @ViewBuilder
    private func pulsingMark(size: CGFloat, state: CursorLiveState, waiting: Bool) -> some View {
        let mark = NotchCursorMark(size: size)
            .foregroundStyle(CursorStateTint.color(state, increaseContrast: contrast == .increased))
        if waiting, !reduceMotion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            TimelineView(.animation(minimumInterval: 0.8, paused: false)) { context in
                let dim = Int(context.date.timeIntervalSinceReferenceDate / 0.8).isMultiple(of: 2)
                mark.opacity(dim ? 0.4 : 1)
            }
        } else {
            mark
        }
    }
}

/// The same mark in a floating capsule.
struct NotchCapsuleCursorStrip: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var cursor = CursorNotchService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorSchemeContrast) private var contrast

    private var text: NotchCursorViewStrings { FeatureStrings.notchCursorView(l10n.language) }

    var body: some View {
        let height = displayGeometry?.stripHeight ?? size.height
        let session = cursor.focusedSession
        Button { service.openActivity(.cursor) } label: {
            HStack(spacing: 6) {
                NotchCursorMark(size: min(12, max(8, height - 8)))
                    .foregroundStyle(CursorStateTint.color(session?.state ?? .idle,
                                                           increaseContrast: contrast == .increased))
                capsuleReading(session)
            }
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: size.width, height: size.height)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.map { "\($0.project), \(text.stateName($0.state))" }
                            ?? FeatureStrings.notchCursor(l10n.language).title)
        .overlay { NotchCursorWorkingGlow(state: session?.state ?? .idle, paused: cursor.paused) }
    }

    @ViewBuilder
    private func capsuleReading(_ session: CursorSession?) -> some View {
        if CursorNotchService.readout() == .elapsed, let session, !cursor.paused {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(AgentFormat.clock(session.elapsed(at: context.date)))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
        } else {
            Text(reading(session))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
    }

    private func reading(_ session: CursorSession?) -> String {
        guard let session else { return FeatureStrings.notchCursor(l10n.language).title }
        switch CursorNotchService.readout() {
        case .state: return text.stateName(session.state)
        case .project: return session.project
        case .elapsed: return AgentFormat.clock(session.elapsed(at: Date()))
        }
    }
}

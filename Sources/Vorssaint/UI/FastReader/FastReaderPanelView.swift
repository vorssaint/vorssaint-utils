// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The Fast Reader's floating surface: the current chunk flashed on a fixed
/// horizontal axis, with playback controls below it. Observes
/// `FastReaderSession.shared` directly rather than taking one as an
/// initializer argument, because `FastReaderService.ensurePanel()` builds
/// this type exactly the way it builds `ScratchpadView` and `CommandBarView`
/// — `NSHostingController(rootView: FastReaderPanelView())` — with no room
/// for a constructor argument.
struct FastReaderPanelView: View {
    @ObservedObject private var session = FastReaderSession.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme

    /// The session does not publish `ReaderOptions.focusPoint` — only
    /// playback state is `@Published`, by design, so the session can stay
    /// out of the test executable's presentation concerns. The panel reads
    /// the preference directly instead, the same way `ScratchpadView` reads
    /// `DefaultsKey.scratchpadBackgroundOpacity` on its own.
    @AppStorage(DefaultsKey.fastReaderFocusPoint) private var focusPointEnabled = true

    /// The speed the next reading starts at. A speed found while reading is
    /// the only setting anyone changes mid-session, and having to find it
    /// again on the next selection would make the buttons feel pointless,
    /// so the panel writes it back rather than keeping it to itself.
    @AppStorage(DefaultsKey.fastReaderWordsPerMinute) private var storedWordsPerMinute = 200

    /// Half of the reading row's fixed width, either side of the focus
    /// character. Constant, never derived from a chunk's text, which is
    /// what keeps the focus axis from drifting between chunks.
    private static let sideWidth: CGFloat = 170
    /// Width of the focus character's own slot. Generous enough that an
    /// unusually wide grapheme cluster (a Turkish dotted capital, a joined
    /// emoji) still fits without the slot itself needing to grow.
    private static let focusWidth: CGFloat = 34
    /// The faded neighbours sit outside the reading slots, in fixed widths of
    /// their own. Keeping them out here is what lets them exist at all: a
    /// neighbour sharing a slot with the current chunk would push the focus
    /// character off its axis as soon as either changed length.
    private static let contextWidth: CGFloat = 120
    private static let readingFontSize: CGFloat = 34
    private static let contextFontSize: CGFloat = 20
    /// How much a single nudge moves the speed, whichever way it is asked
    /// for. The arrow keys and the buttons share it so the two cannot drift.
    private static let speedStep = 25

    /// The whole row, including the faded neighbours. Every part is a
    /// constant, so the focus slot's centre lands on the same x on every
    /// flash no matter what any of the five zones happens to hold.
    private static var rowWidth: CGFloat { (Self.contextWidth + Self.sideWidth) * 2 + Self.focusWidth }

    /// The content size the panel is built at. The service reads this
    /// rather than carrying its own number, so the row's fixed geometry
    /// and the window that has to contain it cannot drift apart.
    static let preferredContentSize = NSSize(width: Self.rowWidth + 56, height: 260)

    /// The chunk before and after the one being read, if there is one either
    /// side. Read from the session's published state, so they advance with it.
    private var previousChunkText: String? {
        let i = session.index - 1
        guard session.chunks.indices.contains(i) else { return nil }
        return session.chunks[i].text
    }

    private var nextChunkText: String? {
        let i = session.index + 1
        guard session.chunks.indices.contains(i) else { return nil }
        return session.chunks[i].text
    }

    private var strings: FastReaderFeatureStrings { FeatureStrings.fastReader(l10n.language) }

    var body: some View {
        VStack(spacing: 16) {
            Text(strings.panelCaption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 18)
            readingArea
            controls
        }
        .frame(minWidth: Self.preferredContentSize.width,
               minHeight: Self.preferredContentSize.height)
        .background(HUDBackdrop(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 1)
        )
        .background(
            FastReaderKeyMonitor(
                onSpace: { session.toggle() },
                onStepBackward: { session.stepBackward() },
                onStepForward: { session.stepForward() },
                onSpeedUp: { nudgeSpeed(by: Self.speedStep) },
                onSpeedDown: { nudgeSpeed(by: -Self.speedStep) }
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(strings.pageTitle)
    }

    // MARK: - Reading area

    /// The whole point of the panel. A reader's eye recognizes a word
    /// fastest at one particular letter (the focus point), so every chunk
    /// is split into the text before that letter, the letter itself, and
    /// the text after it, and each of the three runs is laid out in its
    /// own fixed-width slot: the before-run trailing-aligned, the focus
    /// run centered, the after-run leading-aligned. Because the slot
    /// widths are constants rather than anything measured from the
    /// chunk's own text, the focus run's center — the axis — sits at the
    /// same screen position for every chunk, whether the word either side
    /// of it is one letter or twelve. `.fixedSize(horizontal:vertical:)`
    /// on each run lets a word wider than its slot overflow past it
    /// rather than truncating, so nothing is ever clipped, while the
    /// alignment still pins the one edge (or, for the focus run, the
    /// center) that must not move.
    private var readingArea: some View {
        VStack(spacing: 6) {
            axisMark(systemName: "arrowtriangle.down.fill")
            readingRow
            axisMark(systemName: "arrowtriangle.up.fill")
        }
    }

    private func axisMark(systemName: String) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.contextWidth + Self.sideWidth)
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.45))
                .frame(width: Self.focusWidth, alignment: .center)
            Color.clear.frame(width: Self.contextWidth + Self.sideWidth)
        }
    }

    @ViewBuilder
    private var readingRow: some View {
        if let chunk = session.currentChunk {
            HStack(spacing: 0) {
                // Truncated from its far edge, so the half nearest the word
                // being read is the half that survives a long neighbour.
                contextText(previousChunkText, truncating: .head, alignment: .trailing)

                if focusPointEnabled {
                    let runs = focusRuns(for: chunk)
                    // The focus character keeps its natural width and the two
                    // sides share what it leaves over, equally, which centres
                    // it on the axis without a slot of its own. A slot wide
                    // enough for the widest grapheme held a narrow one away
                    // from the letters either side, and the word read as
                    // three pieces instead of one.
                    Text(runs.before)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(runs.focus)
                        .foregroundStyle(PanelMetricColor.red(for: colorScheme))
                        .fixedSize(horizontal: true, vertical: false)
                    Text(runs.after)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // No focus letter to align, but the line still sits on the
                    // same axis: centred in the space the neighbours leave,
                    // rather than centred on whatever width this chunk
                    // happens to render at.
                    Text(chunk.text)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                contextText(nextChunkText, truncating: .tail, alignment: .leading)
            }
            .frame(width: Self.rowWidth)
            .font(.system(size: Self.readingFontSize, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
        } else {
            Color.clear.frame(width: Self.rowWidth, height: Self.readingFontSize * 1.2)
        }
    }

    /// Seconds as `m:ss`, or `h:mm:ss` once an hour of reading is left.
    private func clockText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// A neighbouring chunk, faded back so it reads as context rather than as
    /// something to be read. It is deliberately not allowed to overflow its
    /// slot: unlike the current chunk, a long neighbour must give way rather
    /// than reach toward the middle of the row.
    private func contextText(_ text: String?,
                             truncating: Text.TruncationMode,
                             alignment: Alignment) -> some View {
        Text(text ?? "")
            .font(.system(size: Self.contextFontSize, weight: .regular))
            .foregroundStyle(.secondary.opacity(0.35))
            .truncationMode(truncating)
            .lineLimit(1)
            .frame(width: Self.contextWidth, alignment: alignment)
            .padding(.horizontal, 0)
    }

    /// Splits a chunk's tokens into the text before the focus letter, the
    /// focus letter itself, and the text after it. `orpToken` names which
    /// token in the chunk carries the focus; that token's own `orpIndex`
    /// is a grapheme offset into its text, so the split walks characters
    /// (not UTF-16 or scalars) to keep a Turkish diacritic or an emoji
    /// cluster intact as the one letter it visually is.
    private func focusRuns(for chunk: ReaderChunk) -> (before: String, focus: String, after: String) {
        guard !chunk.tokens.isEmpty else { return ("", "", "") }
        let tokenIndex = min(max(chunk.orpToken, 0), chunk.tokens.count - 1)
        let target = chunk.tokens[tokenIndex]
        let leadingTokens = chunk.tokens[..<tokenIndex].map(\.text).joined(separator: " ")
        let trailingTokens = chunk.tokens[(tokenIndex + 1)...].map(\.text).joined(separator: " ")

        let characters = Array(target.text)
        guard !characters.isEmpty else { return (leadingTokens, "", trailingTokens) }
        let letterIndex = min(max(target.orpIndex, 0), characters.count - 1)
        let beforeInToken = String(characters[..<letterIndex])
        let focusLetter = String(characters[letterIndex])
        let afterInToken = String(characters[(letterIndex + 1)...])

        let before = leadingTokens.isEmpty ? beforeInToken : leadingTokens + " " + beforeInToken
        let after = trailingTokens.isEmpty ? afterInToken : afterInToken + " " + trailingTokens
        return (before, focusLetter, after)
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 10) {
            progressBar
            controlRow
            if session.isFinished {
                finishedRow
            }
            Text(strings.closeHint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: session.progress)
                .progressViewStyle(.linear)
                .tint(PanelMetricColor.cyan(for: colorScheme))
            HStack(spacing: 8) {
                Text(String(format: strings.progressFormat, session.index + 1, session.chunks.count))
                // Clock digits rather than a worded duration: they read the
                // same in all thirteen languages and need no string of their
                // own. At the first chunk this is the whole read, and after
                // that it answers the more useful question anyway.
                Text(clockText(session.remainingSeconds))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 10, design: .rounded))
            .foregroundStyle(.secondary)
        }
    }

    private var controlRow: some View {
        HStack(spacing: 16) {
            Button { session.stepBackward() } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.plain)

            Button { session.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: session.isPlaying ? "pause.fill" : "play.fill")
                    Text(session.isPlaying ? strings.pauseAction : strings.playAction)
                }
            }
            .buttonStyle(.plain)

            Button { session.stepForward() } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.plain)

            Button { session.restart() } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(strings.restartAction)

            Spacer()

            speedControl
        }
        .font(.system(size: 13))
    }

    /// The speed, adjustable from the panel itself. It was a readout before,
    /// which meant the one setting worth changing while reading was the one
    /// thing the window could not do without the keyboard.
    private var speedControl: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(strings.speedTitle)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            HStack(spacing: 8) {
                speedButton(systemName: "minus", by: -Self.speedStep)
                Text("\(session.wordsPerMinute)")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(minWidth: 38)
                speedButton(systemName: "plus", by: Self.speedStep)
            }
        }
    }

    private func speedButton(systemName: String, by delta: Int) -> some View {
        // Held at the ends of the range rather than silently doing nothing:
        // the session clamps anyway, and a button that still looks live at
        // the limit reads as a fault in the reader.
        let blocked = Self.clampSpeed(session.wordsPerMinute + delta) == session.wordsPerMinute
        return Button { nudgeSpeed(by: delta) } label: {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(blocked)
        .foregroundStyle(blocked ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.secondary))
    }

    private func nudgeSpeed(by delta: Int) {
        let value = Self.clampSpeed(session.wordsPerMinute + delta)
        session.setWordsPerMinute(value)
        storedWordsPerMinute = value
    }

    private static func clampSpeed(_ value: Int) -> Int {
        min(max(value, FastReaderEngine.wordsPerMinuteRange.lowerBound),
            FastReaderEngine.wordsPerMinuteRange.upperBound)
    }

    private var finishedRow: some View {
        HStack(spacing: 8) {
            Text(strings.finishedCaption)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Button(strings.restartAction) { session.restart() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PanelMetricColor.cyan(for: colorScheme))
        }
    }
}

/// Wires space, the arrow keys and Escape... except Escape, which
/// `FastReaderService` already owns with its own window-scoped monitor so
/// the panel closes no matter which control inside it currently has focus.
/// This one handles only what the service's own doc comment calls "the
/// view's concern": space, the step keys and the speed keys. It is a
/// window-scoped local `NSEvent` monitor rather than SwiftUI's
/// `onKeyPress`, following the same pattern `SettingsView`'s
/// `SearchKeyMonitor` uses, so the keys work as soon as the panel is key —
/// which `FastReaderService.showFloatingPanel()` makes it via
/// `panel.makeKey()` on a `.nonactivatingPanel` — without the host app
/// ever needing to become active. The monitor reads `view.window` inside
/// the event handler rather than at install time, since the view has no
/// window yet at `makeNSView`.
private struct FastReaderKeyMonitor: NSViewRepresentable {
    var onSpace: () -> Void
    var onStepBackward: () -> Void
    var onStepForward: () -> Void
    var onSpeedUp: () -> Void
    var onSpeedDown: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSpace = onSpace
        context.coordinator.onStepBackward = onStepBackward
        context.coordinator.onStepForward = onStepForward
        context.coordinator.onSpeedUp = onSpeedUp
        context.coordinator.onSpeedDown = onSpeedDown
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSpace: onSpace, onStepBackward: onStepBackward,
                    onStepForward: onStepForward, onSpeedUp: onSpeedUp, onSpeedDown: onSpeedDown)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator: NSObject {
        var onSpace: () -> Void
        var onStepBackward: () -> Void
        var onStepForward: () -> Void
        var onSpeedUp: () -> Void
        var onSpeedDown: () -> Void
        private var monitor: Any?

        init(onSpace: @escaping () -> Void, onStepBackward: @escaping () -> Void,
             onStepForward: @escaping () -> Void, onSpeedUp: @escaping () -> Void,
             onSpeedDown: @escaping () -> Void) {
            self.onSpace = onSpace
            self.onStepBackward = onStepBackward
            self.onStepForward = onStepForward
            self.onSpeedUp = onSpeedUp
            self.onSpeedDown = onSpeedDown
        }

        func install(for view: NSView) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak view] event in
                guard let self, let view, let window = view.window, event.window === window else {
                    return event
                }
                switch Int(event.keyCode) {
                case kVK_Space:
                    self.onSpace()
                    return nil
                case kVK_LeftArrow:
                    self.onStepBackward()
                    return nil
                case kVK_RightArrow:
                    self.onStepForward()
                    return nil
                case kVK_UpArrow:
                    self.onSpeedUp()
                    return nil
                case kVK_DownArrow:
                    self.onSpeedDown()
                    return nil
                default:
                    return event
                }
            }
        }

        func removeMonitor() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

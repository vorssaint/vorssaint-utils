// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchTeleprompterView: View {
    @ObservedObject private var service = TeleprompterService.shared
    @ObservedObject private var recognizer = TeleprompterService.shared.speechRecognizer
    @ObservedObject private var previewPlayback = TeleprompterService.shared.previewPlayback
    @ObservedObject private var l10n = L10n.shared
    var size: CGSize

    @State private var showingPageCards: Bool = false
    @State private var dragStartHeight: Double = -1

    private var previewScript: String { TeleprompterService.previewPages[previewPlayback.pageIndex] }

    private var showsPrompterSurface: Bool { service.isRunning || service.isPreviewingInNotch }
    private var displayedWords: [String] {
        service.isPreviewingInNotch && !service.isRunning ? splitTextIntoWords(previewScript) : service.currentWords
    }
    private var previewWordProgress: Double { previewPlayback.wordProgress }
    private var previewCharCount: Int {
        let wordCount = min(displayedWords.count, max(0, Int(previewWordProgress)))
        return displayedWords.prefix(wordCount).joined(separator: " ").count
    }

    private var pagesList: [String] {
        if service.pages.isEmpty {
            return [service.text]
        }
        return service.pages
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsPrompterSurface && (!showingPageCards || service.isPreviewingInNotch) {
                activePrompterView
            } else {
                pageCardsStudioView
            }
            if service.isRunning { resizeHandle }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .notchBand(leading: {
            HStack(spacing: 7) {
                NotchIconButton(symbol: "arrow.uturn.backward", title: l10n.s.obBack, action: backFromTeleprompter)
                if service.isPreviewingInNotch && !service.isRunning {
                    HStack(spacing: 5) {
                        Text("Preview")
                        if service.guidanceMode != .wordTracking {
                            Text("·")
                            Text(String(format: "%.1fx", locale: l10n.language.formattingLocale(), service.scrollSpeed))
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                } else if !service.isRunning {
                    Text("Script Pages")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                } else if service.guidanceMode != .wordTracking {
                    Text(String(format: "%.1fx", locale: l10n.language.formattingLocale(), service.scrollSpeed))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .accessibilityLabel("Scroll speed")
                        .accessibilityValue(String(format: "%.1fx", locale: l10n.language.formattingLocale(), service.scrollSpeed))
                }
            }
        }, trailing: {
            HStack(spacing: 6) {
                if showsPrompterSurface && service.showElapsedTime { elapsedTimeBadge }
                if (!showsPrompterSurface || showingPageCards) && !service.isPreviewingInNotch { addPageButton }
                if !service.isRunning && !service.isPreviewingInNotch { teleprompterSettingsButton }
            }
        })
    }

    private var resizeHandle: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 2)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.35))
                .frame(width: 36, height: 4)
            Spacer().frame(height: 4)
        }
        .frame(height: 10)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartHeight < 0 {
                        dragStartHeight = Double(service.windowHeight)
                    }
                    let newHeight = dragStartHeight + Double(value.translation.height)
                    let heightRange = TeleprompterService.notchWindowHeightRange
                    service.windowHeight = min(
                        heightRange.upperBound,
                        max(heightRange.lowerBound, newHeight)
                    )
                }
                .onEnded { _ in
                    dragStartHeight = -1
                    service.savePreferences()
                }
        )
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func backFromTeleprompter() {
        if service.isPreviewingInNotch {
            service.closeNotchPreview()
            return
        }
        NotchService.shared.backFromTeleprompter()
    }

    // MARK: - 1. Page Cards Studio View (When stopped or toggled)

    private var pageCardsStudioView: some View {
        VStack(spacing: 8) {
            // If currently running in background, allow jumping back to live view.
            if service.isRunning {
                HStack {
                    Spacer()
                    Button {
                        showingPageCards = false
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("Live")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.2))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
            }

            // Scrollable List of Pages (Calendar / Agenda Card Style)
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 8) {
                    ForEach(pagesList.indices, id: \.self) { idx in
                        pageCard(index: idx, content: pagesList[idx])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func pageCard(index: Int, content: String) -> some View {
        let isSelected = index == service.currentPageIndex
        let snippet = previewSnippet(content)

        return HStack(spacing: 12) {
            Button {
                service.jumpToPage(index: index)
                triggerHaptic()
            } label: {
                HStack(spacing: 10) {
                    Text(String(format: "%02d", index + 1))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? service.highlightColor.color : .white.opacity(0.55))
                        .frame(width: 34, height: 34)
                        .background(isSelected ? service.highlightColor.color.opacity(0.16) : Color.white.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Page \(index + 1)")
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.8))
                        Text(snippet.isEmpty ? "Empty page" : snippet)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Action Buttons: Edit and Play/Start
            HStack(spacing: 7) {
                if !service.isRunning {
                    Button {
                        openEditor(for: index)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit Page \(index + 1)")
                }

                // Start / Play button
                Button {
                    service.jumpToPage(index: index)
                    if !service.isRunning {
                        service.start()
                    } else if service.isPaused {
                        service.resume()
                    }
                    showingPageCards = false
                    triggerHaptic()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 26, height: 26)
                        .background(service.highlightColor.color)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Start Prompter from Page \(index + 1)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? service.highlightColor.color.opacity(0.38) : Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - 2. Active Prompter View (While speaking/scrolling)

    private var activePrompterView: some View {
        VStack(spacing: 8) {
            // Prompter Script Display with Live Real-time Appearance Updates
            SpeechScrollView(
                words: displayedWords,
                highlightedCharCount: service.isPreviewingInNotch && !service.isRunning
                    ? previewCharCount : recognizer.recognizedCharCount,
                font: service.fontFamily.nsFont(ofSize: service.fontSize.pointSize),
                highlightColor: service.highlightColor.color,
                cueColor: service.cueColor.color,
                cueUnreadOpacity: service.cueBrightness.alpha * 0.35,
                cueReadOpacity: service.cueBrightness.alpha,
                onWordTap: { charOffset in
                    if service.isRunning { service.jumpTo(charOffset: charOffset) }
                },
                smoothScroll: service.guidanceMode != .wordTracking,
                smoothWordProgress: service.isPreviewingInNotch && !service.isRunning
                    ? previewWordProgress : service.timerWordProgress,
                isListening: (service.isRunning && !service.isPaused)
                    || (service.isPreviewingInNotch && !service.isRunning),
                paragraphBreakBeforeWordIndices: service.showParagraphDividers
                    ? paragraphBreakWordIndices(in: service.isPreviewingInNotch && !service.isRunning ? previewScript : service.currentScript) : [],
                readingPosition: service.readingPosition,
                showLastSpokenWords: service.showLastSpokenWords
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .frame(height: max(70, size.height - 55))

            // Footer bar
            HStack(spacing: 12) {
                if (service.isRunning && !service.isPaused && (recognizer.isStarting || recognizer.isListening))
                    || (service.isPreviewingInNotch && !service.isRunning && !previewPlayback.isPaused
                        && previewPlayback.isSpeaking) {
                    liveWaveform
                }

                if service.autoNextPage
                    && ((service.isRunning && pagesList.count > 1) || service.isPreviewingInNotch) {
                    Button {
                        if service.isPreviewingInNotch && !service.isRunning {
                            service.previousPreviewPage()
                        } else {
                            service.previousPage()
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isPreviewingInNotch && !service.isRunning
                              ? previewPlayback.pageIndex == 0 : service.currentPageIndex == 0)

                    Button {
                        if service.isPreviewingInNotch && !service.isRunning {
                            service.nextPreviewPage()
                        } else {
                            service.nextPage()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isPreviewingInNotch && !service.isRunning
                              ? previewPlayback.pageIndex >= TeleprompterService.previewPages.count - 1
                              : service.currentPageIndex >= pagesList.count - 1)
                }

                Spacer()

                if service.isRunning, let err = recognizer.error {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.9))
                        .lineLimit(1)
                }

                if service.isRunning || service.isPreviewingInNotch {
                    let isPaused = service.isRunning ? service.isPaused : previewPlayback.isPaused
                    Button {
                        if service.isRunning {
                            service.toggle()
                        } else {
                            service.togglePreviewPause()
                        }
                        triggerHaptic()
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 14))
                    .help(isPaused ? FeatureStrings.teleprompter(l10n.language).resume
                                   : FeatureStrings.teleprompter(l10n.language).pause)
                    .accessibilityLabel(isPaused ? FeatureStrings.teleprompter(l10n.language).resume
                                                 : FeatureStrings.teleprompter(l10n.language).pause)

                    Button {
                        if service.isRunning {
                            service.stop()
                            showingPageCards = true
                        } else {
                            backFromTeleprompter()
                        }
                        triggerHaptic()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red.opacity(0.9))
                            .frame(width: 28, height: 28)
                            .background(Color.red.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 14))
                    .help(service.isRunning ? FeatureStrings.teleprompter(l10n.language).stop : "Close Preview")
                    .accessibilityLabel(service.isRunning ? FeatureStrings.teleprompter(l10n.language).stop : "Close Preview")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    private var liveWaveform: some View {
        let previewIsActive = service.isPreviewingInNotch && !service.isRunning
            && previewPlayback.isSpeaking
        return TeleprompterWaveformView(levels: previewIsActive ? [] : recognizer.audioLevels,
                                        color: service.highlightColor.color,
                                        isActive: previewIsActive || recognizer.isStarting || recognizer.isListening)
            .frame(width: 58, height: 18)
            .accessibilityLabel(FeatureStrings.teleprompter(l10n.language).listening)
    }

    // MARK: - Helpers

    /// The add action lives in the island's top row like the timer's Start
    /// capsule, so the page keeps its own toolbar clear and familiar.
    private var addPageButton: some View {
        Button {
            NotchService.shared.collapse()
            service.pendingAddPageInSettings = true
            SettingsRouter.shared.request(AppFeature.teleprompter.settingsDestination)
            (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
            triggerHaptic()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("Page")
                    .font(.system(size: NotchTimerSupport.StartButton.labelSize, weight: .semibold))
            }
            .lineLimit(1)
            .padding(.horizontal, NotchTimerSupport.StartButton.padding)
            .frame(height: NotchLayout.timerStartHeight)
            .foregroundStyle(service.highlightColor.color)
            .background(service.highlightColor.color.opacity(0.18), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: NotchLayout.timerStartHeight / 2))
        .help("Add New Page")
    }

    private var teleprompterSettingsButton: some View {
        NotchIconButton(symbol: "gearshape", title: "Teleprompter Settings", action: openTeleprompterSettings)
    }

    private func openTeleprompterSettings() {
        NotchService.shared.collapse()
        SettingsRouter.shared.request(AppFeature.teleprompter.settingsDestination)
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
        triggerHaptic()
    }

    /// The elapsed reading takes the page action's top-row position while
    /// running, and follows the user's elapsed-time preference.
    private var elapsedTimeBadge: some View {
        Text(service.isRunning ? service.formattedElapsedTime : "00:42")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 6)
            .frame(height: NotchLayout.timerStartHeight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(FeatureStrings.notchActivities(l10n.language).stopwatch)
            .accessibilityValue(service.isRunning ? service.formattedElapsedTime : "00:42")
    }

    private func previewSnippet(_ text: String) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count > 80 {
            return String(clean.prefix(80)) + "..."
        }
        return clean
    }

    private func openEditor(for index: Int) {
        guard index < pagesList.count else { return }
        NotchService.shared.collapse()
        service.pendingEditPageIndexInSettings = index
        SettingsRouter.shared.request(AppFeature.teleprompter.settingsDestination)
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
        triggerHaptic()
    }

    private func addNewPage() {
        if service.pages.isEmpty {
            service.pages = [service.text]
        }
        let newPageIndex = service.pages.count
        service.pages.append("")
        service.currentPageIndex = newPageIndex
        service.savePreferences()
        openEditor(for: newPageIndex)
    }

    private func triggerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
}

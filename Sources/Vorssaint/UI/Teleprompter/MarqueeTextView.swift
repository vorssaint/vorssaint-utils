// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Based on Textream by Fatih Kadir Akın (MIT License)

import AppKit
import SwiftUI

private let paragraphDividerExtraSpacing: CGFloat = 14
private let paragraphDividerDotSize: CGFloat = 3
private let paragraphDividerDotSpacing: CGFloat = 5
private let paragraphDividerDotOpacity: Double = 0.16

// MARK: - Paragraph Breaks

func paragraphBreakWordIndices(in text: String) -> Set<Int> {
    let normalized = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)

    var result = Set<Int>()
    var wordCount = 0
    var hasContent = false
    var hasPendingBreak = false

    for (index, line) in lines.enumerated() {
        let lineWords = splitTextIntoWords(String(line))
        if !lineWords.isEmpty {
            if hasContent && hasPendingBreak {
                result.insert(wordCount)
            }
            wordCount += lineWords.count
            hasContent = true
            hasPendingBreak = false
        }
        if index < lines.count - 1, hasContent {
            hasPendingBreak = true
        }
    }
    return result
}

// MARK: - Word Item Model

struct WordItem: Identifiable {
    let id: Int
    let word: String
    let charOffset: Int
    let isAnnotation: Bool
}

// MARK: - Preference Key

struct WordYPreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Speech Scroll View

struct SpeechScrollView: View {
    let words: [String]
    let highlightedCharCount: Int
    var font: NSFont = .systemFont(ofSize: 18, weight: .semibold)
    var highlightColor: Color = .yellow
    var cueColor: Color = .white
    var cueUnreadOpacity: Double = 0.25
    var cueReadOpacity: Double = 0.5
    var onWordTap: ((Int) -> Void)? = nil
    var smoothScroll: Bool = false
    var smoothWordProgress: Double = 0
    var isListening: Bool = true
    var paragraphBreakBeforeWordIndices: Set<Int> = []
    var readingPosition: TeleprompterReadingPosition = .centered
    var showLastSpokenWords: Bool = true

    @State private var scrollOffset: CGFloat = 0
    @State private var manualOffset: CGFloat = 0
    @State private var wordYPositions: [Int: CGFloat] = [:]
    @State private var containerHeight: CGFloat = 0
    @State private var allowsNextBackwardTrackingUpdate = false
    @State private var hasAppliedTrackingTarget = false
    @State private var anchoredLayoutWidth: CGFloat = 0
    @State private var anchoredParagraphBreakBeforeWordIndices: Set<Int> = []

    private var readingAnchorRatio: CGFloat {
        switch readingPosition {
        case .nearTop: return 0.25
        case .centered: return 0.45
        }
    }

    private var scrollOffsetAnimation: Animation? {
        smoothScroll ? .linear(duration: 1.0 / 60.0) : .easeOut(duration: 0.45)
    }

    var body: some View {
        GeometryReader { geo in
            WordFlowLayout(
                words: words,
                highlightedCharCount: highlightedCharCount,
                font: font,
                highlightColor: highlightColor,
                cueColor: cueColor,
                cueUnreadOpacity: cueUnreadOpacity,
                cueReadOpacity: cueReadOpacity,
                highlightWords: !smoothScroll,
                showLastSpokenWords: showLastSpokenWords,
                paragraphBreakBeforeWordIndices: paragraphBreakBeforeWordIndices,
                containerWidth: geo.size.width,
                viewportHeight: geo.size.height,
                scrollOffset: scrollOffset + manualOffset,
                onWordTap: { charOffset in
                    let tappedWordIndex = wordIndex(at: charOffset)
                    manualOffset = 0
                    if charOffset < highlightedCharCount {
                        allowsNextBackwardTrackingUpdate = true
                    }
                    onWordTap?(charOffset)
                    repositionTracking(toWordIndex: tappedWordIndex)
                }
            )
            .onPreferenceChange(WordYPreferenceKey.self) { positions in
                let wasEmpty = wordYPositions.isEmpty
                let widthChanged = abs(anchoredLayoutWidth - geo.size.width) > 0.5
                let paragraphLayoutChanged = anchoredParagraphBreakBeforeWordIndices != paragraphBreakBeforeWordIndices
                if widthChanged || paragraphLayoutChanged {
                    hasAppliedTrackingTarget = false
                }
                wordYPositions = positions
                if (wasEmpty || widthChanged || paragraphLayoutChanged), !positions.isEmpty {
                    anchoredLayoutWidth = geo.size.width
                    anchoredParagraphBreakBeforeWordIndices = paragraphBreakBeforeWordIndices
                    recalculateTracking(containerHeight: containerHeight, force: true)
                }
            }
            .offset(y: scrollOffset + manualOffset)
            .animation(scrollOffsetAnimation, value: scrollOffset)
            .animation(.easeOut(duration: 0.15), value: manualOffset)
            .onChange(of: geo.size.height) { _, newHeight in
                containerHeight = newHeight
                hasAppliedTrackingTarget = false
                if highlightedCharCount == 0 && smoothWordProgress == 0 {
                    let lineHeight = font.pointSize * 1.4
                    scrollOffset = newHeight * readingAnchorRatio - lineHeight * 0.5
                } else {
                    recalculateTracking(containerHeight: newHeight, force: true)
                }
            }
            .onChange(of: readingPosition) { _, _ in
                manualOffset = 0
                hasAppliedTrackingTarget = false
                recalculateTracking(containerHeight: containerHeight, force: true)
            }
            .onChange(of: highlightedCharCount) { _, _ in
                if isListening && !smoothScroll {
                    manualOffset = 0
                    recalculateTracking(containerHeight: containerHeight)
                }
            }
            .onChange(of: smoothWordProgress) { _, _ in
                if isListening && smoothScroll {
                    manualOffset = 0
                    recalculateTracking(containerHeight: containerHeight)
                }
            }
            .onChange(of: isListening) { _, listening in
                if listening {
                    manualOffset = 0
                    recalculateTracking(containerHeight: containerHeight)
                }
            }
            .onChange(of: words) { _, _ in
                let lineHeight = font.pointSize * 1.4
                scrollOffset = containerHeight * readingAnchorRatio - lineHeight * 0.5
                manualOffset = 0
                wordYPositions = [:]
                allowsNextBackwardTrackingUpdate = false
                hasAppliedTrackingTarget = false
                anchoredLayoutWidth = 0
                anchoredParagraphBreakBeforeWordIndices = []
            }
            .onAppear {
                containerHeight = geo.size.height
                let lineHeight = font.pointSize * 1.4
                scrollOffset = containerHeight * readingAnchorRatio - lineHeight * 0.5
            }
        }
        .clipped()
    }

    private func recalculateTracking(containerHeight: CGFloat, force: Bool = false) {
        guard containerHeight > 0 else { return }
        let anchor = containerHeight * readingAnchorRatio

        if smoothScroll {
            let wordIdx = Int(smoothWordProgress)
            let fraction = smoothWordProgress - Double(wordIdx)
            let clampedIdx = max(0, min(wordIdx, words.count - 1))
            guard let wordY = wordYPositions[clampedIdx] else { return }
            let nextY = wordYPositions[clampedIdx + 1] ?? wordY
            let interpolatedY = wordY + (nextY - wordY) * CGFloat(fraction)
            applyTrackingTarget(anchor - interpolatedY, force: force)
        } else {
            let wordIdx = activeWordIndex()
            if let wordY = wordYPositions[wordIdx] {
                applyTrackingTarget(anchor - wordY, force: force)
            }
        }
    }

    private func repositionTracking(toWordIndex wordIndex: Int) {
        guard let wordY = wordYPositions[wordIndex] else { return }
        let anchor = containerHeight * readingAnchorRatio
        applyTrackingTarget(anchor - wordY, force: true)
    }

    /// Normal reading progress may only move the text upward. Brief backward
    /// corrections from speech recognition must not produce a down/up bounce.
    /// Explicit taps and manual scrolling opt into one backward reposition.
    private func applyTrackingTarget(_ target: CGFloat, force: Bool = false) {
        if !hasAppliedTrackingTarget
            || target < scrollOffset - 1
            || allowsNextBackwardTrackingUpdate
            || force {
            scrollOffset = target
        }
        hasAppliedTrackingTarget = true
        allowsNextBackwardTrackingUpdate = false
    }

    private func wordIndex(at charOffset: Int) -> Int {
        var offset = 0
        for (index, word) in words.enumerated() {
            let end = offset + word.count
            if charOffset <= end { return index }
            offset = end + 1
        }
        return max(0, words.count - 1)
    }

    private func activeWordIndex() -> Int {
        var offset = 0
        for (i, word) in words.enumerated() {
            let end = offset + word.count
            if highlightedCharCount <= end { return i }
            offset = end + 1
        }
        return max(0, words.count - 1)
    }
}

// MARK: - Word Flow Layout

struct WordFlowLayout: View {
    let words: [String]
    let highlightedCharCount: Int
    var font: NSFont
    var highlightColor: Color
    var cueColor: Color
    var cueUnreadOpacity: Double
    var cueReadOpacity: Double
    var highlightWords: Bool = true
    var showLastSpokenWords: Bool = true
    var paragraphBreakBeforeWordIndices: Set<Int> = []
    var containerWidth: CGFloat
    var viewportHeight: CGFloat
    var scrollOffset: CGFloat
    var onWordTap: ((Int) -> Void)?

    private var lineSpacing: CGFloat {
        let intrinsicHeight = font.ascender - font.descender + font.leading
        let ratio = intrinsicHeight / font.pointSize
        return ratio > 1.5 ? 2 : 8
    }

    private struct LayoutCacheKey: Equatable {
        let words: [String]
        let fontName: String
        let fontSize: CGFloat
        let width: Int
        let paragraphBreaks: [Int]
    }

    private static var _cacheKey: LayoutCacheKey?
    private static var _cachedItems: [WordItem] = []
    private static var _cachedLines: [[WordItem]] = []

    private func cachedLayout() -> ([WordItem], [[WordItem]]) {
        let key = LayoutCacheKey(
            words: words,
            fontName: font.fontName,
            fontSize: font.pointSize,
            width: Int(containerWidth),
            paragraphBreaks: paragraphBreakBeforeWordIndices.sorted()
        )
        if key == Self._cacheKey {
            return (Self._cachedItems, Self._cachedLines)
        }
        let items = buildItems()
        let lines = buildLines(items: items)
        Self._cacheKey = key
        Self._cachedItems = items
        Self._cachedLines = lines
        return (items, lines)
    }

    private func nextWordIndex(items: [WordItem]) -> Int {
        for item in items {
            if item.isAnnotation { continue }
            let charsIntoWord = highlightedCharCount - item.charOffset
            let litCount = max(0, min(item.word.count, charsIntoWord))
            let letterCount = max(1, item.word.filter { $0.isLetter || $0.isNumber }.count)
            if litCount < letterCount {
                return item.id
            }
        }
        return -1
    }

    private func buildItems() -> [WordItem] {
        var items: [WordItem] = []
        var charOffset = 0
        let annotationFlags = SpeechTextAlignment.annotationFlags(for: words)

        for (index, word) in words.enumerated() {
            let isAnnotation = annotationFlags.indices.contains(index)
                ? annotationFlags[index]
                : (word.hasPrefix("[") && word.hasSuffix("]"))
            items.append(WordItem(
                id: index,
                word: word,
                charOffset: charOffset,
                isAnnotation: isAnnotation
            ))
            charOffset += word.count + 1
        }
        return items
    }

    private func buildLines(items: [WordItem]) -> [[WordItem]] {
        guard containerWidth > 0 else { return [items] }
        var lines: [[WordItem]] = []
        var currentLine: [WordItem] = []
        var lineWidth: CGFloat = 0

        let spaceWidth = (" " as NSString).size(withAttributes: [.font: font]).width

        for item in items {
            let wordWidth = (item.word as NSString).size(withAttributes: [.font: font]).width
            let isParagraphBreak = paragraphBreakBeforeWordIndices.contains(item.id)

            if isParagraphBreak && !currentLine.isEmpty {
                lines.append(currentLine)
                currentLine = [item]
                lineWidth = wordWidth + spaceWidth
                continue
            }

            if lineWidth + wordWidth > containerWidth && !currentLine.isEmpty {
                lines.append(currentLine)
                currentLine = [item]
                lineWidth = wordWidth + spaceWidth
            } else {
                currentLine.append(item)
                lineWidth += wordWidth + spaceWidth
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        return lines
    }

    var body: some View {
        let (items, lines) = cachedLayout()
        let nextIdx = nextWordIndex(items: items)

        VStack(alignment: .leading, spacing: lineSpacing) {
            ForEach(lines.indices, id: \.self) { lineIdx in
                let line = lines[lineIdx]
                let beginsParagraph = line.first.map { paragraphBreakBeforeWordIndices.contains($0.id) } ?? false

                HStack(spacing: 0) {
                    ForEach(line) { item in
                        wordView(for: item, isNextWord: item.id == nextIdx)
                    }
                }
                .padding(.top, beginsParagraph ? paragraphDividerExtraSpacing : 0)
            }
        }
        .frame(width: containerWidth, alignment: .leading)
        .coordinateSpace(name: "flowLayout")
    }

    @ViewBuilder
    private func wordView(for item: WordItem, isNextWord: Bool) -> some View {
        let cueFont = Font(font.withSize(font.pointSize * 0.8)).italic()
        let wordLen = item.word.count
        let charsIntoWord = highlightedCharCount - item.charOffset
        let litCount = max(0, min(wordLen, charsIntoWord))
        let letterCount = max(1, item.word.filter { $0.isLetter || $0.isNumber }.count)
        let isFullyLit = litCount >= letterCount
        let isCurrentWord = isNextWord || (charsIntoWord >= 0 && !isFullyLit)

        if !highlightWords {
            let uniformColor: Color = item.isAnnotation
                ? cueColor.opacity(cueUnreadOpacity)
                : highlightColor

            Text(item.word + " ")
                .font(item.isAnnotation ? cueFont : Font(font))
                .foregroundStyle(uniformColor)
                .background(
                    GeometryReader { wordGeo in
                        Color.clear.preference(
                            key: WordYPreferenceKey.self,
                            value: [item.id: wordGeo.frame(in: .named("flowLayout")).midY]
                        )
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onWordTap?(item.charOffset)
                }
        } else if item.isAnnotation {
            let annotationColor: Color = isFullyLit
                ? cueColor.opacity(cueReadOpacity)
                : cueColor.opacity(cueUnreadOpacity)

            Text(item.word + " ")
                .font(cueFont)
                .foregroundStyle(annotationColor)
                .background(
                    GeometryReader { wordGeo in
                        Color.clear.preference(
                            key: WordYPreferenceKey.self,
                            value: [item.id: wordGeo.frame(in: .named("flowLayout")).midY]
                        )
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onWordTap?(item.charOffset)
                }
        } else {
            let dimColor: Color = isCurrentWord
                ? highlightColor.opacity(0.85)
                : highlightColor.opacity(0.35)

            let wordColor: Color = isFullyLit
                ? (showLastSpokenWords ? highlightColor.opacity(0.4) : highlightColor.opacity(0.06))
                : dimColor

            Text(item.word + " ")
                .font(Font(font))
                .foregroundStyle(isCurrentWord ? highlightColor : wordColor)
                .underline(isCurrentWord, color: highlightColor)
                .background(
                    GeometryReader { wordGeo in
                        Color.clear.preference(
                            key: WordYPreferenceKey.self,
                            value: [item.id: wordGeo.frame(in: .named("flowLayout")).midY]
                        )
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onWordTap?(item.charOffset)
                }
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The Insert/Edit date-time popover: picks a Type and Style (or a raw
/// custom pattern) and an optional specific timezone, then hands the
/// caller the literal {{...}} token text to splice into a snippet.
struct DateVariableBuilder: View {
    let text: SnippetFeatureStrings
    let cancelLabel: String
    let locale: Locale
    let initial: TextSnippetSupport.DetectedDateToken?
    let confirm: (String) -> Void
    let cancel: () -> Void

    @State private var kind: TextSnippetSupport.DateVariableKind
    @State private var style: TextSnippetSupport.DateVariableStyle
    @State private var timeZoneIdentifier: String?
    @State private var customPattern: String
    @State private var timeZoneQuery = ""

    init(text: SnippetFeatureStrings,
         cancelLabel: String,
         locale: Locale,
         initial: TextSnippetSupport.DetectedDateToken?,
         confirm: @escaping (String) -> Void,
         cancel: @escaping () -> Void) {
        self.text = text
        self.cancelLabel = cancelLabel
        self.locale = locale
        self.initial = initial
        self.confirm = confirm
        self.cancel = cancel
        let resolvedKind = initial?.kind ?? .datetime
        _kind = State(initialValue: resolvedKind)
        _timeZoneIdentifier = State(initialValue: initial?.timeZoneIdentifier)
        if let initial,
           let matchedStyle = Self.matchingStyle(pattern: initial.pattern, kind: resolvedKind, locale: locale) {
            _style = State(initialValue: matchedStyle)
            _customPattern = State(initialValue: matchedStyle == .custom ? initial.pattern : "")
        } else {
            _style = State(initialValue: .iso8601)
            _customPattern = State(initialValue: "")
        }
    }

    /// Reconstructs which Style an already-built pattern came from, by
    /// comparing it against what each style would resolve to right now.
    /// Falls back to Custom when nothing matches (e.g. a hand-typed
    /// pattern, or a system style whose OS-resolved text has since
    /// changed).
    private static func matchingStyle(pattern: String,
                                      kind: TextSnippetSupport.DateVariableKind,
                                      locale: Locale) -> TextSnippetSupport.DateVariableStyle? {
        let candidates: [TextSnippetSupport.DateVariableStyle] = [.iso8601, .short, .medium, .long, .full]
        for candidate in candidates {
            if TextSnippetSupport.resolvedDatePattern(kind: kind, style: candidate,
                                                      customPattern: "", locale: locale) == pattern {
                return candidate
            }
        }
        return .custom
    }

    private var showsTimeZonePicker: Bool { kind != .date }

    /// Lowercased with underscores folded to spaces, so "New_York" and
    /// "new york" compare equal: identifiers spell city names with
    /// underscores, but nobody types a timezone query that way.
    private static func normalizedTimeZoneText(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "_", with: " ")
    }

    private var timeZoneMatches: [String] {
        guard !timeZoneQuery.isEmpty else { return [] }
        let query = Self.normalizedTimeZoneText(timeZoneQuery)
        let byName = TimeZone.knownTimeZoneIdentifiers
            .filter { Self.normalizedTimeZoneText($0).contains(query) }
        let byAbbreviation = TimeZone.abbreviationDictionary
            .filter { Self.normalizedTimeZoneText($0.key).contains(query) }
            .map { $0.value }
        return Array(Set(byName + byAbbreviation)).sorted().prefix(50).map { $0 }
    }

    /// The canonical identifier the typed text exactly names, if any: lets
    /// the search field show live validity feedback and confirm on Return
    /// without requiring a click into the suggestion list below. Matches
    /// both a full identifier (e.g. "America/New_York") and a common
    /// abbreviation (e.g. "PST", resolved to its canonical identifier via
    /// TimeZone.abbreviationDictionary), not a raw UTC offset: several
    /// cities can share one offset, and daylight saving makes the mapping
    /// depend on the date, so an offset alone doesn't name one timezone.
    private var typedTimeZoneMatch: String? {
        guard !timeZoneQuery.isEmpty else { return nil }
        let query = Self.normalizedTimeZoneText(timeZoneQuery)
        if let identifier = TimeZone.knownTimeZoneIdentifiers.first(where: {
            Self.normalizedTimeZoneText($0) == query
        }) {
            return identifier
        }
        if let abbreviation = TimeZone.abbreviationDictionary.first(where: {
            Self.normalizedTimeZoneText($0.key) == query
        }) {
            return abbreviation.value
        }
        return nil
    }

    private func confirmTypedTimeZone() {
        guard let match = typedTimeZoneMatch else { return }
        timeZoneIdentifier = match
        timeZoneQuery = ""
    }

    private var previewText: String {
        TextSnippetSupport.dateVariablePreview(kind: kind, style: style, customPattern: customPattern,
                                               timeZoneIdentifier: timeZoneIdentifier, date: Date(),
                                               locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(text.dateTimeTypeLabel, selection: $kind) {
                Text(text.dateTimeKindDate).tag(TextSnippetSupport.DateVariableKind.date)
                Text(text.dateTimeKindTime).tag(TextSnippetSupport.DateVariableKind.time)
                Text(text.dateTimeKindDateTime).tag(TextSnippetSupport.DateVariableKind.datetime)
            }
            .pickerStyle(.segmented)
            .onChange(of: kind) { _, newKind in
                if newKind == .date { timeZoneIdentifier = nil }
            }

            Picker(text.dateTimeStyleLabel, selection: $style) {
                Text(text.dateTimeStyleShort).tag(TextSnippetSupport.DateVariableStyle.short)
                Text(text.dateTimeStyleMedium).tag(TextSnippetSupport.DateVariableStyle.medium)
                Text(text.dateTimeStyleLong).tag(TextSnippetSupport.DateVariableStyle.long)
                Text(text.dateTimeStyleFull).tag(TextSnippetSupport.DateVariableStyle.full)
                Text(text.dateTimeStyleISO8601).tag(TextSnippetSupport.DateVariableStyle.iso8601)
                Text(text.dateTimeStyleCustom).tag(TextSnippetSupport.DateVariableStyle.custom)
            }

            if showsTimeZonePicker {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.dateTimeTimezoneLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let timeZoneIdentifier {
                        HStack {
                            Text(timeZoneIdentifier)
                                .font(.body.monospaced())
                            Spacer()
                            Button {
                                self.timeZoneIdentifier = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Text(text.dateTimeTimezoneDeviceDefault)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField(text.dateTimeTimezoneSearchPlaceholder, text: $timeZoneQuery)
                            .onSubmit { confirmTypedTimeZone() }
                        if !timeZoneQuery.isEmpty {
                            Image(systemName: typedTimeZoneMatch != nil ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(typedTimeZoneMatch != nil ? .green : .red)
                        }
                    }
                    if !timeZoneMatches.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(timeZoneMatches, id: \.self) { identifier in
                                    Button {
                                        timeZoneIdentifier = identifier
                                        timeZoneQuery = ""
                                    } label: {
                                        Text(identifier)
                                            .font(.body.monospaced())
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .frame(height: 140)
                    }
                }
            }

            if style == .custom {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.dateTimePatternLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(text.dateTimePatternLabel, text: $customPattern)
                        .font(.body.monospaced())
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(text.dateTimePreviewLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(previewText)
                    .font(.body.monospaced())
            }

            HStack {
                Spacer()
                Button(cancelLabel, action: cancel)
                Button(initial == nil ? text.dateTimeConfirmInsert : text.dateTimeConfirmUpdate) {
                    confirm(TextSnippetSupport.dateVariableText(kind: kind, style: style,
                                                                customPattern: customPattern,
                                                                timeZoneIdentifier: timeZoneIdentifier,
                                                                locale: locale))
                }
                .buttonStyle(.borderedProminent)
                .disabled(style == .custom && customPattern.isEmpty)
            }
        }
        .padding(16)
    }
}

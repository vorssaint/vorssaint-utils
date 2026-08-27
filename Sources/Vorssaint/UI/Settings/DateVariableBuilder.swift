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
        if let initial {
            let matchedStyle = TextSnippetSupport.matchingDateStyle(pattern: initial.pattern,
                                                                     kind: resolvedKind, locale: locale)
            _style = State(initialValue: matchedStyle)
            _customPattern = State(initialValue: matchedStyle == .custom ? initial.pattern : "")
        } else {
            _style = State(initialValue: .iso8601)
            _customPattern = State(initialValue: "")
        }
    }

    /// The suggestion list and the live checkmark/X both come from one
    /// search, computed once per render: it scans the whole timezone
    /// database and the field re-renders on every keystroke.
    private var timeZoneSearch: (matches: [String], typed: String?) {
        let matches = TextSnippetSupport.matchingTimeZoneIdentifiers(for: timeZoneQuery)
        return (matches,
                TextSnippetSupport.resolvedTimeZoneIdentifier(for: timeZoneQuery, matches: matches))
    }

    private func confirmTypedTimeZone() {
        guard let match = timeZoneSearch.typed else { return }
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

            Picker(text.dateTimeStyleLabel, selection: $style) {
                Text(text.dateTimeStyleShort).tag(TextSnippetSupport.DateVariableStyle.short)
                Text(text.dateTimeStyleMedium).tag(TextSnippetSupport.DateVariableStyle.medium)
                Text(text.dateTimeStyleLong).tag(TextSnippetSupport.DateVariableStyle.long)
                Text(text.dateTimeStyleFull).tag(TextSnippetSupport.DateVariableStyle.full)
                Text(text.dateTimeStyleISO8601).tag(TextSnippetSupport.DateVariableStyle.iso8601)
                Text(text.dateTimeStyleCustom).tag(TextSnippetSupport.DateVariableStyle.custom)
            }

            // The named styles resolve to the current locale's pattern and
            // that pattern is what gets saved, so say so: the labels on
            // their own read as if the token would follow the language.
            if TextSnippetSupport.DateVariableStyle.localeDependent.contains(style) {
                Text(text.dateTimeStyleLocaleNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Offered for every type, Date included: the calendar date
            // itself differs across zones, and the captions teach the
            // -tz(...) syntax with a date example.
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
                        .help(text.dateTimeTimezoneClear)
                        .accessibilityLabel(text.dateTimeTimezoneClear)
                    }
                } else {
                    Text(text.dateTimeTimezoneDeviceDefault)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                let search = timeZoneSearch
                HStack {
                    TextField(text.dateTimeTimezoneSearchPlaceholder, text: $timeZoneQuery)
                        .onSubmit { confirmTypedTimeZone() }
                    // Marked only when the query has actually settled one
                    // way or the other. A query that still matches several
                    // zones is not wrong, and a red X above a list of valid
                    // suggestions reads as though it were.
                    if !timeZoneQuery.isEmpty, search.typed != nil || search.matches.isEmpty {
                        let valid = search.typed != nil
                        Image(systemName: valid ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(valid ? .green : .red)
                            .accessibilityLabel(valid
                                ? text.dateTimeTimezoneValid
                                : text.dateTimeTimezoneInvalid)
                    }
                }
                if !search.matches.isEmpty {
                    let matches = search.matches
                    ScrollView {
                        // Lazy: a broad query like "america" matches well
                        // over a hundred zones, and the list is no longer
                        // capped.
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(matches, id: \.self) { identifier in
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
                    .frame(height: min(140, CGFloat(matches.count) * 22))
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

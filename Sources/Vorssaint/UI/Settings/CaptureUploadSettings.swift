// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// One destination serves both screenshots and recordings, so the section
/// appears under either tool and edits the same address and rows; only the
/// choice about copying the answered link belongs to the selected tool.
struct CaptureUploadSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.captureUploadEnabled) private var enabled = false
    @AppStorage(DefaultsKey.captureUploadDestination) private var raw = ""
    @AppStorage private var copiesLink: Bool
    @State private var showsMoreOptions = false
    @FocusState private var addressFocused: Bool

    private let kind: CaptureUploadSupport.Kind

    init(kind: CaptureUploadSupport.Kind) {
        self.kind = kind
        _copiesLink = AppStorage(wrappedValue: true, kind.copyLinkDefaultsKey)
    }

    private var strings: CaptureUploadStrings {
        FeatureStrings.captureUpload(l10n.language)
    }

    private var recorderStrings: RecorderFeatureStrings {
        FeatureStrings.recorder(l10n.language)
    }

    /// Clearing every row lands back on the empty registered default.
    private var destination: Binding<CaptureUploadSupport.Destination> {
        Binding(get: { CaptureUploadSupport.Destination.decoded(raw) },
                set: { raw = $0.encoded() })
    }

    var body: some View {
        Section {
            Toggle(strings.enabledToggle, isOn: $enabled)
            if enabled {
                Text(kind == .recording ? strings.recordingCaption : strings.screenshotCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                addressRow
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(strings.copyLinkToggle, isOn: $copiesLink)
                    Text(strings.replyCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DisclosureHeaderRow(isExpanded: $showsMoreOptions) {
                    Text(recorderStrings.moreOptions)
                    Spacer()
                }
                if showsMoreOptions {
                    Group {
                        fieldRows(title: strings.parametersTitle,
                                  fields: destination.queryItems,
                                  addTitle: strings.addParameter,
                                  headers: false)
                        fieldRows(title: strings.headersTitle,
                                  fields: destination.headers,
                                  addTitle: strings.addHeader,
                                  headers: true)
                        Text(String(format: strings.fileNameCaptionFormat,
                                    CaptureUploadSupport.fileNamePlaceholder))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: strings.valuesStayCaptionFormat,
                                    CaptureUploadSupport.fileNamePlaceholder))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .disclosureIndent()
                }
            }
        } header: {
            Text(strings.sectionTitle)
        }
        .onDisappear { liftAddressQuery(showingRows: false) }
    }

    private var addressRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(strings.addressLabel)
                    .lineLimit(1)
                TextField("", text: destination.url,
                          prompt: Text(verbatim: "https://example.com/upload"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .autocorrectionDisabled()
                    .accessibilityLabel(strings.addressLabel)
                    .focused($addressFocused)
                    .onSubmit { liftAddressQuery(showingRows: true) }
                    .onChange(of: addressFocused) { _, focused in
                        if !focused { liftAddressQuery(showingRows: true) }
                    }
            }
            if addressNeedsAttention {
                Text(strings.addressInvalid)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// A query in the address becomes rows, and More options opens so they
    /// show right below it and the move is not a surprise. Leaving the page
    /// moves it quietly.
    private func liftAddressQuery(showingRows: Bool) {
        guard let lifted = CaptureUploadSupport.liftingAddressQuery(destination.wrappedValue) else {
            return
        }
        destination.wrappedValue = lifted
        guard showingRows else { return }
        withAnimation(.easeInOut(duration: 0.18)) { showsMoreOptions = true }
    }

    /// Reads the address the way an upload does. An empty field is simply no
    /// destination and says nothing.
    private var addressNeedsAttention: Bool {
        let current = destination.wrappedValue
        return !current.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && CaptureUploadSupport.endpoint(CaptureUploadSupport.sendable(current)) == nil
    }

    private func fieldRows(title: String,
                           fields: Binding<[CaptureUploadSupport.Field]>,
                           addTitle: String,
                           headers: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            ForEach(fields) { $field in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        TextField("", text: $field.name, prompt: Text(strings.namePlaceholder))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .autocorrectionDisabled()
                            .accessibilityLabel(strings.namePlaceholder)
                            .frame(maxWidth: 180)
                        TextField("", text: $field.value, prompt: Text(strings.valuePlaceholder))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .autocorrectionDisabled()
                            .accessibilityLabel(strings.valuePlaceholder)
                        Button {
                            fields.wrappedValue.removeAll { $0.id == field.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(strings.removeRow)
                        .accessibilityLabel(strings.removeRow)
                    }
                    // A name the request would leave out is said so here, next
                    // to the row, rather than found out from a server later.
                    if headers, !field.name.trimmingCharacters(in: .whitespaces).isEmpty,
                       !CaptureUploadSupport.isUsableHeaderName(field.name) {
                        Text(strings.headerNameInvalid)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Button {
                fields.wrappedValue.append(CaptureUploadSupport.Field())
            } label: {
                Label(addTitle, systemImage: "plus")
            }
            .disabled(fields.wrappedValue.count >= CaptureUploadSupport.maximumFields)
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Author: naveenkrdy
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The websites Selection Actions never offers itself on, matched against
/// the frontmost browser's current page (best effort — see
/// `BrowserURLReader`). Shaped like `AppBundleList` so the two exclusion
/// lists read as one family of setting.
struct SelectionActionsExcludedDomainsList: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.selectionActionsExcludedDomains) private var domainsRaw = ""
    @State private var isExpanded = false
    @State private var draft = ""

    private var text: SelectionActionsStrings { FeatureStrings.selectionActions(l10n.language) }

    private var domains: [String] { SelectionActionsExcludedDomains.decode(domainsRaw) }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(domains, id: \.self) { domain in
                HStack(spacing: 9) {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(domain)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button {
                        remove(domain)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(text.excludedDomainsRemoveButton)
                }
            }
            HStack(spacing: 8) {
                TextField(text.excludedDomainsPlaceholder, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button(text.excludedDomainsAddButton, action: add)
                    .controlSize(.small)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text(text.excludedDomainsCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text(text.excludedDomainsTitle)
                Spacer()
                if !domains.isEmpty {
                    Text("\(domains.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .onAppear { isExpanded = !domains.isEmpty }
    }

    private func add() {
        let domain = draft.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        guard !domain.isEmpty, !domains.contains(domain) else { return }
        draft = ""
        domainsRaw = SelectionActionsExcludedDomains.encode(domains + [domain])
    }

    private func remove(_ domain: String) {
        domainsRaw = SelectionActionsExcludedDomains.encode(domains.filter { $0 != domain })
    }
}

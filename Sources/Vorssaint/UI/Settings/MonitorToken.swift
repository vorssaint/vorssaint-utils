// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A compact label for one monitor item, checked and tinted while it is
/// shown. Labels fill their grid column so a group reads as one table. An item
/// with its own settings carries them in a second half that names what is on
/// and opens them, so they read as that item's and not the page's.
struct MonitorToken: View {
    let symbol: String
    let title: String
    @Binding var included: Bool
    var available = true
    var selected = false
    var options: AnyView? = nil
    var optionsSummary = ""
    /// Taller labels for the panel, whose items are whole blocks.
    var large = false
    /// Clicking the name does this instead of showing or hiding the item;
    /// the checkmark always shows or hides it.
    var select: (() -> Void)? = nil
    @State private var showsOptions = false

    private var on: Bool { included && available }

    var body: some View {
        // The summary shows only while it fits beside the name on one line;
        // otherwise the name may take two lines and the options keep a chevron.
        ViewThatFits(in: .horizontal) {
            row(showsSummary: true)
            row(showsSummary: false)
        }
        .font(.system(size: large ? 13 : 12, weight: large ? .medium : .regular))
        .imageScale(large ? .large : .medium)
        .frame(maxWidth: .infinity, minHeight: large ? 40 : 28)
        .background(on ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: large ? 10 : 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: large ? 10 : 8, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
        }
        .popover(isPresented: $showsOptions, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol).font(.headline)
                options
            }
            .padding(14)
            .frame(width: 250, alignment: .leading)
            .toggleStyle(.switch)
        }
        .opacity(available ? 1 : 0.5)
        .disabled(!available)
        .help(title)
    }

    private func row(showsSummary: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Button { included.toggle() } label: {
                    Image(systemName: included ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(on ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(included ? .isSelected : [])
                Button { if let select { select() } else { included.toggle() } } label: {
                    Label(title, systemImage: symbol)
                        .lineLimit(showsSummary ? 1 : 2)
                        .minimumScaleFactor(showsSummary ? 1 : 0.8)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(on ? .primary : .secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(select == nil)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            if options != nil {
                Divider().frame(height: 14)
                Button { showsOptions = true } label: {
                    HStack(spacing: 3) {
                        if showsSummary {
                            Text(optionsSummary).lineLimit(1).fixedSize()
                        }
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(on ? Color.accentColor : .secondary)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!on)
                .accessibilityLabel("\(title): \(optionsSummary)")
            }
        }
    }
}

/// One switch in an item's options.
struct MonitorTokenOption: View {
    let symbol: String
    let title: String
    var tint: Color? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 16)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}

/// Wide enough for a label with its options half, so every label in a group
/// takes the same column width.
let monitorTokenColumns = [GridItem(.adaptive(minimum: 196), spacing: 8)]
let monitorLargeTokenColumns = [GridItem(.adaptive(minimum: 210), spacing: 10)]

extension View {
    /// The inset box that holds one group of labels.
    func monitorTokenGroup() -> some View {
        padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

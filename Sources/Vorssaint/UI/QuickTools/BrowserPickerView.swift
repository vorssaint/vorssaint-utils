// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct BrowserPickerView: View {
    @AppStorage(DefaultsKey.browserPickerShowNumbers) private var showNumbers = true
    @ObservedObject var service: BrowserPickerService
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Group {
            if service.visibleBrowsers.isEmpty {
                Text(service.browsers.isEmpty
                     ? FeatureStrings.browserPicker(l10n.language).empty
                     : FeatureStrings.browserPickerOptions(l10n.language).noneEnabled)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: BrowserPickerSupport.itemSpacing) {
                            ForEach(Array(service.visibleBrowsers.enumerated()), id: \.element.id) { index, browser in
                                browserButton(browser, index: index)
                                    .id(index)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: service.selection) { _, index in proxy.scrollTo(index) }
                }
            }
        }
        .padding(.horizontal, BrowserPickerSupport.horizontalPadding)
        .padding(.vertical, BrowserPickerSupport.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .bottom) {
            if let error = service.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(1).help(error)
                    .padding(.horizontal, 20).padding(.bottom, 3)
            }
        }
    }

    private func browserButton(_ browser: PickerBrowser, index: Int) -> some View {
        Button { service.choose(index) } label: {
            VStack(spacing: 5) {
                Image(nsImage: browser.icon)
                    .resizable()
                    .frame(width: service.selection == index ? BrowserPickerSupport.selectedIconSize : BrowserPickerSupport.iconSize,
                           height: service.selection == index ? BrowserPickerSupport.selectedIconSize : BrowserPickerSupport.iconSize)
                    .frame(width: BrowserPickerSupport.selectedIconSize,
                           height: BrowserPickerSupport.selectedIconSize, alignment: .bottom)
                Text(browser.name)
                    .font(.system(size: 11, weight: service.selection == index ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 6)
                    .frame(height: 14)
            }
            .frame(width: BrowserPickerSupport.itemWidth, height: BrowserPickerSupport.itemHeight)
            .background(service.selection == index ? Color.accentColor.opacity(0.25) : .clear,
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(service.selection == index ? Color.accentColor : .clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if showNumbers && index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .frame(width: 16, height: 16)
                        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.primary.opacity(0.3)))
                        .padding(4)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(service.isOpening)
        .help(browser.name)
        .accessibilityLabel(browser.name)
        .accessibilityAddTraits(service.selection == index ? .isSelected : [])
        .onHover { hovering in if hovering { service.selection = index } }
    }
}

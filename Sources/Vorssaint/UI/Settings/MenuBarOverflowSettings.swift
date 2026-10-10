// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import SwiftUI

struct MenuBarOverflowSettings: View {
    @ObservedObject private var overflow = MenuBarOverflowController.shared
    @AppStorage(DefaultsKey.menuBarOverflowBundles) private var selectedBundles = ""
    @AppStorage(DefaultsKey.menuBarOverflowEnabled) private var enabled = false

    @AppStorage(DefaultsKey.menuBarOverflowLayout) private var layout = "dropdown"

    @AppStorage(DefaultsKey.menuBarOverflowMonochrome) private var monochrome = true

    private var chooserItems: [MenuBarOverflowController.OverflowItem] {
        let selected = Set(overflow.items.map(\.id))
        return overflow.items + overflow.availableItems.filter { !selected.contains($0.id) }
    }

    var body: some View {
        SettingsCard(title: "Icon Drawer") {
            SettingsRow(symbol: "chevron.down", title: "Menu bar icons",
                        caption: "Keep less-used icons under one arrow.") {
                Toggle("Icon Drawer", isOn: $enabled)
                    .labelsHidden().toggleStyle(.switch)
            }
            if enabled {
                HStack {
                    Text("Layout").font(.callout)
                    Spacer()
                    Picker("Icon Drawer layout", selection: $layout) {
                        Text("Dropdown").tag("dropdown")
                        Text("Menu bar").tag("menuBar")
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 250)
                }

                if #available(macOS 27, *) {
                    Text("macOS hides the Focus icon and some other system icons while Icon Drawer is enabled. Focus remains available in Control Center. Disable Icon Drawer to restore these icons.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Monochrome icons", isOn: $monochrome)
                    .toggleStyle(.checkbox).font(.callout)
                DisclosureGroup(isExpanded: $overflow.isChoosingIcons) {
                    VStack(spacing: 6) {
                        ForEach(chooserItems) { item in
                            HStack(spacing: 8) {
                                Image(nsImage: item.icon).resizable().scaledToFit()
                                    .frame(width: 18, height: 18)
                                Toggle(item.name, isOn: Binding(
                                    get: { selectedBundles.split(separator: ",").contains(Substring(item.bundle)) },
                                    set: { overflow.setIncluded(item.bundle, included: $0) }
                                )).toggleStyle(.checkbox).lineLimit(1).help(item.name)
                                Spacer(minLength: 8)
                                if let index = overflow.items.firstIndex(where: { $0.id == item.id }) {
                                    Button { overflow.moveItem(item.id, offset: -1) } label: {
                                        Image(systemName: "chevron.up")
                                    }.disabled(index == 0).help("Move earlier in Icon Drawer")
                                    Button { overflow.moveItem(item.id, offset: 1) } label: {
                                        Image(systemName: "chevron.down")
                                    }.disabled(index == overflow.items.count - 1).help("Move later in Icon Drawer")
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.font(.callout).padding(.vertical, 8)
                } label: {
                    HStack {
                        Text("Choose icons")
                        Spacer()
                        if overflow.isBusy && overflow.availableItems.isEmpty { ProgressView().controlSize(.small) }
                        else {
                            Text("\(selectedBundles.split(separator: ",").count) selected")
                                .foregroundStyle(.secondary)
                        }
                    }.font(.callout)
                }
                HStack {
                    Button("Open Icon Drawer") { overflow.showDrawer() }
                }.font(.caption)
                if let message = overflow.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: overflow.isChoosingIcons) { _, expanded in
            if expanded && enabled { overflow.loadAvailableIcons() }
        }
        .onAppear {
            if enabled && overflow.isChoosingIcons { overflow.loadAvailableIcons() }
        }
    }
}

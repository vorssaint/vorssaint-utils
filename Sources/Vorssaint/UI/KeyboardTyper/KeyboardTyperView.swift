// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The keyboard typer card: the scratchpad's look, one plain editor, and a
/// footer with the delay between keys and Send.
struct KeyboardTyperView: View {
    @ObservedObject private var service = KeyboardTyperService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.keyboardTyperSnippetsShown) private var snippetsShown = false
    private var text: KeyboardTyperFeatureStrings { FeatureStrings.keyboardTyper(l10n.language) }
    private static let editorInset = NSSize(width: 7, height: 2)

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    editor
                    footer
                }
                if snippetsShown {
                    // The divider counts inside the panel's width, so the
                    // window grows by exactly what the text side gives up.
                    HStack(spacing: 0) {
                        Divider().opacity(0.45)
                        KeyboardTyperSnippetPanel()
                            .padding(10)
                    }
                    .frame(width: KeyboardTyperService.snippetsWidth)
                }
            }
        }
        .frame(minWidth: KeyboardTyperService.baseMinimumWidth, minHeight: 220)
        .background { HUDBackdrop(cornerRadius: 14) }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .overlay(ScratchpadResizeOverlay())
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(text.pageTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .overlay(ScratchpadDragHandle())
            SnippetsToggle()
            Button {
                service.hide()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(l10n.s.menuClose)
            .accessibilityLabel(l10n.s.menuClose)
        }
        .padding(.trailing, 12)
        .frame(height: 34)
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
    }

    private var editor: some View {
        PlainTextEditor(text: $service.text,
                        textColor: .labelColor,
                        textContainerInset: Self.editorInset,
                        onCommandReturn: { service.send() },
                        onCreate: { KeyboardTyperService.shared.registerTextView($0) })
            .overlay(alignment: .topLeading) {
                if service.text.isEmpty {
                    // NSTextView has no placeholder of its own; this sits on the
                    // first line and never takes clicks.
                    Text(text.placeholder)
                        .font(.system(size: PlainTextEditor.defaultFontSize))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, Self.editorInset.width + PlainTextEditor.lineFragmentPadding)
                        .padding(.trailing, 12)
                        .padding(.top, Self.editorInset.height)
                        .allowsHitTesting(false)
                }
            }
    }

    private var footer: some View {
        KeyboardTyperControls()
            .padding(.horizontal, 12)
            .frame(height: 36)
    }
}

/// Shows or hides the snippet panel, in the pad's header and the island's row.
struct SnippetsToggle: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.keyboardTyperSnippetsShown) private var snippetsShown = false

    var body: some View {
        let title = FeatureStrings.keyboardTyper(l10n.language).snippetsTitle
        Button {
            KeyboardTyperService.shared.toggleSnippets()
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(snippetsShown ? Color.accentColor : Color.secondary)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(snippetsShown ? .isSelected : [])
    }
}

/// The delay between keys, the destination layout and Send: the floating
/// pad's footer and the row under the island's page.
struct KeyboardTyperControls: View {
    @ObservedObject private var service = KeyboardTyperService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.keyboardTyperDelayMs) private var delay = KeyboardTyperSupport.defaultDelay
    @AppStorage(DefaultsKey.keyboardTyperFavoriteLayouts) private var favoritesRaw = ""
    @AppStorage(DefaultsKey.keyboardTyperLayout) private var selectedLayout = ""
    @AppStorage(DefaultsKey.keyboardTyperCountdownSeconds) private var countdown = KeyboardTyperSupport.defaultCountdown
    @AppStorage(DefaultsKey.keyboardTyperMethod) private var methodRaw = KeyboardTyperMethod.characters.rawValue

    private var text: KeyboardTyperFeatureStrings { FeatureStrings.keyboardTyper(l10n.language) }

    var body: some View {
        let seconds = KeyboardTyperSupport.sanitizedCountdown(countdown)
        // The buttons always keep their size: the layout menu gives way
        // first, then the delay's label.
        HStack(spacing: 6) {
            Text(text.delayLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(-1)
            TextField(text.delayLabel, value: $delay, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .labelsHidden()
                .onChange(of: delay) { _, value in
                    let clamped = KeyboardTyperSupport.sanitizedDelay(value)
                    if clamped != value { delay = clamped }
                }
            Text(text.msUnit)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 0)
            destinationMenu
            Button {
                service.send(afterCountdown: true)
            } label: {
                Label(String(format: text.secondsFormat, seconds), systemImage: "timer")
            }
            .controlSize(.small)
            .fixedSize()
            .help(String(format: text.sendDelayedFormat, seconds))
            .accessibilityLabel(String(format: text.sendDelayedFormat, seconds))
            .disabled(service.text.isEmpty || service.isTyping)
            Button {
                service.send()
            } label: {
                Label(text.send, systemImage: "keyboard")
            }
            .controlSize(.small)
            .fixedSize()
            .help(text.send + " (⌘↩)")
            .disabled(service.text.isEmpty || service.isTyping)
        }
    }

    /// One menu for where the text goes, and the only place the typing method
    /// is chosen: the method first, then the system layout and the favorites
    /// starred in Settings. Its
    /// label is the method's icon and the layout's name. A layout that stopped
    /// being a favorite reads as the system layout, as Send does.
    private var destinationMenu: some View {
        let favorites = KeyboardTyperSupport.favorites(from: favoritesRaw)
        let layoutID = KeyboardTyperSupport.destinationLayoutID(selected: selectedLayout, favorites: favorites)
        let method = KeyboardTyperMethod.sanitized(methodRaw)
        let methodTitle = method == .characters ? text.methodCharacters : text.methodKeyPositions
        return Menu {
            Picker(text.methodTitle, selection: Binding(get: { method }, set: { methodRaw = $0.rawValue })) {
                Label(text.methodCharacters, systemImage: KeyboardTyperMethod.characters.symbolName)
                    .tag(KeyboardTyperMethod.characters)
                Label(text.methodKeyPositions, systemImage: KeyboardTyperMethod.keyPositions.symbolName)
                    .tag(KeyboardTyperMethod.keyPositions)
            }
            .pickerStyle(.inline)
            Divider()
            Picker(text.layoutsTitle, selection: Binding(get: { layoutID ?? "" }, set: { selectedLayout = $0 })) {
                Text(text.systemLayout).tag("")
                ForEach(favorites, id: \.self) { id in
                    Text(service.layoutName(id)).tag(id)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(layoutID.map(service.layoutName) ?? text.systemLayout, systemImage: method.symbolName)
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .controlSize(.small)
        .frame(minWidth: 70, maxWidth: 140)
        .layoutPriority(-2)
        .help(methodTitle + " · " + (layoutID.map(service.layoutName) ?? text.systemLayout))
        .accessibilityLabel(text.layoutsTitle)
        .accessibilityValue(methodTitle + ", " + (layoutID.map(service.layoutName) ?? text.systemLayout))
    }
}

/// Settings' list of every layout macOS ships, each with a star that puts it
/// in the menu next to Send.
struct KeyboardTyperLayoutList: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.keyboardTyperFavoriteLayouts) private var favoritesRaw = ""
    @State private var query = ""

    private var text: KeyboardTyperFeatureStrings { FeatureStrings.keyboardTyper(l10n.language) }

    var body: some View {
        let favorites = KeyboardTyperSupport.favorites(from: favoritesRaw)
        let layouts = KeyboardTyperService.shared.layouts.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
        }
        VStack(alignment: .leading, spacing: 6) {
            TextField(text.searchLayouts, text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: 0) {
                    // The favorites again on top, in the order starred, so they
                    // are found without scrolling; the full list keeps them too.
                    let starred = favorites.compactMap { id in layouts.first { $0.id == id } }
                    if !starred.isEmpty {
                        ForEach(starred) { layout in
                            row(layout, isFavorite: true, favorites: favorites)
                        }
                        Divider().padding(.vertical, 4)
                    }
                    ForEach(layouts) { layout in
                        row(layout, isFavorite: favorites.contains(layout.id), favorites: favorites)
                    }
                }
            }
            .frame(height: 200)
        }
    }

    private func row(_ layout: KeyboardTyperLayout, isFavorite: Bool, favorites: [String]) -> some View {
        Button {
            favoritesRaw = KeyboardTyperSupport.toggling(layout.id, in: favorites).joined(separator: ",")
        } label: {
            HStack {
                Text(layout.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout.name)
        .accessibilityAddTraits(isFavorite ? .isSelected : [])
        .accessibilityHint(isFavorite ? text.unfavorite : text.favorite)
        .help(isFavorite ? text.unfavorite : text.favorite)
    }
}

/// The saved texts beside the editor, in the floating pad and the island
/// alike: a name to save the current text under, then the list. A row reads
/// as its name, or its first line without one; a click puts its text back in
/// the editor, and the bin at its end deletes it.
struct KeyboardTyperSnippetPanel: View {
    @ObservedObject private var service = KeyboardTyperService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var name = ""
    @State private var hoveredID: UUID?

    private var text: KeyboardTyperFeatureStrings { FeatureStrings.keyboardTyper(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text.snippetsTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField(text.snippetNamePlaceholder, text: $name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .onSubmit(save)
                Button(action: save) {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(service.text.isEmpty)
                .help(text.saveSnippet)
                .accessibilityLabel(text.saveSnippet)
            }
            if service.snippets.isEmpty {
                Text(text.snippetsEmpty)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(service.snippets) { snippet in row(snippet) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { service.loadSnippetsIfNeeded() }
    }

    private func save() {
        service.saveSnippet(name: name)
        name = ""
    }

    private func row(_ snippet: KeyboardTyperSnippet) -> some View {
        let title = KeyboardTyperSupport.title(of: snippet)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return HStack(spacing: 4) {
            Button {
                service.useSnippet(snippet)
            } label: {
                Text(title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            Button {
                service.deleteSnippet(snippet.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(text.deleteSnippet)
            .accessibilityLabel(text.deleteSnippet + ", " + title)
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .padding(.vertical, 3)
        // Each saved text reads as its own line, and the one under the
        // pointer stands out.
        .background(Color.primary.opacity(hoveredID == snippet.id ? 0.14 : 0.06), in: shape)
        .contentShape(shape)
        .onHover { hoveredID = $0 ? snippet.id : (hoveredID == snippet.id ? nil : hoveredID) }
    }
}

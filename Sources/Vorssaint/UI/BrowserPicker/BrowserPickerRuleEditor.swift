// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// One editor for a new rule, an existing one, and a rule made from a link
/// waiting in the picker, where `testURL` is that link.
struct BrowserPickerRuleEditor: View {
    @ObservedObject var service: BrowserPickerService
    @ObservedObject private var l10n = L10n.shared
    @State var draft: BrowserPickerRuleDraft
    var testURL: URL?
    let onDone: (BrowserPickerRule?) -> Void

    private var strings: BrowserPickerStrings { FeatureStrings.browserPicker(l10n.language) }

    var body: some View {
        VStack(spacing: 0) {
            // The window from the picker has a title bar; the settings sheet does not.
            if testURL == nil {
                Text(draft.id == nil ? strings.newRuleTitle : draft.site)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding([.horizontal, .top], 20)
            }
            Form {
                Section {
                    TextField(strings.siteLabel, text: $draft.site, prompt: Text(verbatim: "example.com"))
                    TextField(strings.pathLabel, text: $draft.path, prompt: Text(strings.pathPlaceholder))
                    Picker(strings.openInLabel, selection: $draft.target) {
                        if draft.target == nil {
                            Text(strings.chooseBrowser).tag(BrowserPickerTarget?.none)
                        }
                        ForEach(service.editorChoices(keeping: draft.target), id: \.self) { target in
                            targetLabel(target).tag(BrowserPickerTarget?.some(target))
                        }
                    }
                } footer: {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Spacer()
                Button(strings.cancel) { onDone(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(testURL == nil ? strings.save : strings.saveAndOpen) { onDone(draft.rule) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.rule == nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func targetLabel(_ target: BrowserPickerTarget) -> some View {
        let appURL = BrowserPickerBrowsers.applicationURL(for: target)
        let installed = service.isInstalled(target)
        return Label {
            Text(installed ? service.label(for: target)
                           : String(format: strings.unavailableTargetFormat, service.label(for: target)))
        } icon: {
            Image(nsImage: appURL.map { BrowserPickerIcons.menuIcon(for: $0) } ?? NSImage())
        }
    }

    /// What the rule will do, in one line, checked against the waiting link.
    private var summary: String {
        guard !draft.site.trimmingCharacters(in: .whitespaces).isEmpty else { return strings.siteHint }
        guard let parsed = BrowserPickerRules.normalizedSite(draft.site) else { return strings.invalidSite }
        let typedPath = BrowserPickerRules.normalizedPath(draft.path)
        let scope = BrowserPickerRule(site: parsed.site, path: typedPath.isEmpty ? parsed.path : typedPath,
                                      target: .application(bundleID: ""))
        var text = scope.path.isEmpty
            ? String(format: strings.coversSiteFormat, scope.site)
            : String(format: strings.coversPathFormat, scope.site, scope.path.removingPercentEncoding ?? scope.path)
        if let testURL, let host = BrowserPickerRules.host(of: testURL) {
            let matches = BrowserPickerRules.covers(scope, host: host, path: testURL.path(percentEncoded: true))
            text += " " + (matches ? strings.linkMatches : strings.linkDoesNotMatch)
        }
        return text
    }
}

/// Shows the editor on its own when the picker asks for it: there is no
/// Settings window to attach a sheet to.
final class BrowserPickerEditorWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var completion: ((BrowserPickerRule?) -> Void)?

    func show(draft: BrowserPickerRuleDraft, testURL: URL, service: BrowserPickerService,
              completion: @escaping (BrowserPickerRule?) -> Void) {
        close()
        self.completion = completion
        let editor = BrowserPickerRuleEditor(service: service, draft: draft, testURL: testURL) { [weak self] rule in
            self?.finish(rule)
        }
        let host = NSHostingController(rootView: editor)
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable]
        window.title = FeatureStrings.browserPicker(L10n.shared.language).newRuleTitle
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        let visible = NSScreen.pointerVisibleFrame
        window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2,
                                      y: visible.midY - window.frame.height / 2))
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        finish(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard window != nil else { return }
        window = nil
        let completion = self.completion
        self.completion = nil
        completion?(nil)
    }

    private func finish(_ rule: BrowserPickerRule?) {
        let completion = self.completion
        self.completion = nil
        let window = self.window
        self.window = nil
        window?.delegate = nil
        window?.close()
        completion?(rule)
    }
}

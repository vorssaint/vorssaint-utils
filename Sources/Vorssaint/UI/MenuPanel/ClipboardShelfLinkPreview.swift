// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import WebKit

struct ClipboardShelfLinkPreview: View {
    let url: URL
    let snapshot: ClipboardShelfLinkSnapshot?
    let strings: ClipboardShelfStrings
    let openInBrowser: String
    let onSnapshot: (ClipboardShelfLinkSnapshot) -> Void

    @AppStorage(DefaultsKey.clipboardShelfLinkPreviews) private var enabled = false
    @State private var loadedURL: URL?
    @State private var state: LoadState

    private enum LoadState {
        case idle, loading, displaying, failed
    }

    init(url: URL, snapshot: ClipboardShelfLinkSnapshot?, strings: ClipboardShelfStrings, openInBrowser: String,
         loadImmediately: Bool, onSnapshot: @escaping (ClipboardShelfLinkSnapshot) -> Void) {
        self.url = url
        self.snapshot = snapshot
        self.strings = strings
        self.openInBrowser = openInBrowser
        self.onSnapshot = onSnapshot
        _state = SwiftUI.State(initialValue: loadImmediately ? .loading : .idle)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if enabled && (state == .loading || state == .displaying) {
                page
            } else {
                placeholder
            }
        }
        .onChange(of: enabled) { _, isEnabled in
            if !isEnabled { state = .idle }
        }
    }

    private var header: some View {
        let visibleURL = enabled ? loadedURL ?? snapshot?.url ?? url : url
        return HStack(spacing: 10) {
            Image(systemName: "globe").foregroundStyle(.secondary).accessibilityHidden(true)
            Text(visibleURL.absoluteString)
                .font(.system(.subheadline, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSWorkspace.shared.open(visibleURL)
            } label: {
                Label(openInBrowser, systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(white: 0.23), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(Color.white)
        .background(Color(white: 0.13))
    }

    private var page: some View {
        ClipboardShelfWebView(url: url) { snapshot in
            loadedURL = snapshot.url
            state = .displaying
            onSnapshot(snapshot)
        } onFailure: {
            state = .failed
        }
        .overlay {
            if state == .loading {
                ProgressView().accessibilityLabel(strings.loadLinkPreview)
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            if enabled, let image = snapshot?.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)
            }
            VStack(spacing: 8) {
                if state == .failed {
                    Text(strings.linkPreviewUnavailable).foregroundStyle(.secondary)
                } else {
                    Text((enabled ? snapshot?.title : nil) ?? url.host ?? url.absoluteString)
                        .font(.headline)
                }
                if enabled { loadButton }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadButton: some View {
        Button(strings.loadLinkPreview) { state = .loading }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .help(strings.linkPreviewsCaption)
    }
}

struct ClipboardShelfThumbnail: View {
    let url: URL
    let onFinish: (ClipboardShelfLinkSnapshot?) -> Void

    @State private var started = false

    var body: some View {
        Color.clear
            .overlay { renderer }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                started = true

                try? await Task.sleep(for: .seconds(15))
                if !Task.isCancelled { onFinish(nil) }
            }
    }

    @ViewBuilder
    private var renderer: some View {
        if started {
            ClipboardShelfWebView(url: url) { onFinish($0) } onFailure: { onFinish(nil) }
                .frame(width: 720, height: 450)
                .opacity(0.001)
        }
    }
}

private struct ClipboardShelfWebView: NSViewRepresentable {
    let url: URL
    let onSnapshot: (ClipboardShelfLinkSnapshot) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSnapshot: onSnapshot, onFailure: onFailure)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpShouldHandleCookies = false
        request.attribution = .user
        webView.load(request)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.cancelled = true
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onSnapshot: (ClipboardShelfLinkSnapshot) -> Void
        let onFailure: () -> Void
        private var displaying = false
        var cancelled = false

        init(onSnapshot: @escaping (ClipboardShelfLinkSnapshot) -> Void, onFailure: @escaping () -> Void) {
            self.onSnapshot = onSnapshot
            self.onFailure = onFailure
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let allowed = !displaying && action.targetFrame?.isMainFrame == true
                && action.navigationType == .other && !action.shouldPerformDownload
                && action.request.url.map(ClipboardShelfWebAddress.canPreview) == true
            decisionHandler(allowed ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(response.canShowMIMEType ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            let isTLS = challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
            completionHandler(isTLS ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url, ClipboardShelfWebAddress.canPreview(url) else {
                onFailure()
                return
            }
            displaying = true
            let config = WKSnapshotConfiguration()
            config.snapshotWidth = 420
            webView.takeSnapshot(with: config) { [weak self, weak webView] image, _ in
                guard let self, !self.cancelled else { return }
                let title = webView?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = title.flatMap { $0.isEmpty ? nil : String($0.prefix(300)) } ?? url.host ?? ""
                self.onSnapshot(ClipboardShelfLinkSnapshot(url: url, title: label, image: image))
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if !displaying { onFailure() }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if !displaying { onFailure() }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onFailure()
        }
    }
}

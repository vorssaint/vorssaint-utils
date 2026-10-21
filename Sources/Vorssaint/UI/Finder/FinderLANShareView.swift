// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import CoreImage.CIFilterBuiltins

struct FinderLANShareView: View {
    @ObservedObject var session: FinderLANShareSession
    let selection: [URL]
    @ObservedObject private var l10n = L10n.shared
    @State private var started = false
    private var text: FinderLANShareStrings { .localized(l10n.language.rawValue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text.title).font(.title2.bold())
            Text(text.description).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(selection, id: \.self) { Text($0.lastPathComponent) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 100)
            if let url = session.url {
                if let qr = qrCode(url) { Image(nsImage: qr).interpolation(.none).resizable().frame(width: 200, height: 200) }
                Text(url.absoluteString).font(.caption.monospaced()).textSelection(.enabled)
                Button(l10n.s.menuCopy) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            } else if session.stopped { Text(text.stopped) }
            else if started { ProgressView() }
            if let error = session.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Spacer()
            HStack {
                Spacer()
                if !started {
                    Button(text.start) { started = true; session.start(selection) }.buttonStyle(.borderedProminent)
                } else if !session.stopped {
                    Button(text.stop) { session.stop() }
                }
            }
        }.padding(22).frame(minWidth: 520, minHeight: 480)
    }

    private func qrCode(_ url: URL) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

final class FinderLANShareWindow: NSWindowController, NSWindowDelegate {
    private let session: FinderLANShareSession

    init(selection: [URL]) {
        let session = FinderLANShareSession()
        self.session = session
        let window = NSWindow(contentViewController: NSHostingController(rootView: FinderLANShareView(session: session, selection: selection)))
        window.styleMask = [.titled, .closable, .resizable]
        window.title = FinderLANShareStrings.localized(L10n.shared.language.rawValue).title
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    required init?(coder: NSCoder) { nil }
    func windowWillClose(_ notification: Notification) { session.stop() }
}

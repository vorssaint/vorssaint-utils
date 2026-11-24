// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#if VORSSAINT_DEVELOPMENT
import AppKit
import SwiftUI

enum DictationPresentationProbe {
    static func runAndExit() -> Never {
        guard DictationService.verifiesEmptyOutcome() else { print("Empty recognition must collapse without an error"); exit(1) }
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .darkAqua)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/dictation-previews")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for phase in [DictationPhase.recording, .processing, .completed, .failed] {
            let height: CGFloat = phase == .failed ? 188 : phase == .completed ? 154 : 150
            let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 32, cameraWidth: 210)
            let shape = NotchShape.island(height: height, geometry: geometry)
            let view = NotchDictationView(topInset: 32, speech: .presentationFixture(phase))
                .frame(width: 400, height: height).foregroundStyle(.white).background(Color.black)
                .clipShape(shape).padding(24).background(Color(red: 0.12, green: 0.14, blue: 0.17))
                .environment(\.colorScheme, .dark)
            capture(view, size: CGSize(width: 448, height: height + 48), to: directory.appendingPathComponent(phase.rawValue + ".png"))
        }
        print("DICTATION PRESENTATION SNAPSHOTS OK: \(directory.path)")
        exit(0)
    }

    private static func capture<V: View>(_ view: V, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: .darkAqua)
        window.alphaValue = 0
        window.orderFrontRegardless()
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { print("Snapshot allocation failed"); exit(1) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { print("PNG encoding failed"); exit(1) }
        do { try png.write(to: url) } catch { print(error); exit(1) }
        window.orderOut(nil)
    }
}
#endif

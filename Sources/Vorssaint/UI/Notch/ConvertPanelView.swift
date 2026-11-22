// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The island's file page. Tiles for what the files can become, what can be
/// done to them and quick actions; choosing one slides to its options; running
/// shows a live ring and bar; finishing bursts into a check with the results.
struct ConvertPanelView: View {
    @ObservedObject var service: ConvertService
    @ObservedObject private var runner = JobRunner.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var jobsFinished: Bool { !runner.jobs.isEmpty && runner.jobs.allSatisfy { $0.status.isFinished } }

    var body: some View {
        if let session = service.session {
            VStack(spacing: ConvertLayout.spacing) {
                ConvertHeader(session: session, service: service)
                    .frame(height: ConvertLayout.headerHeight)
                ZStack {
                    switch service.stage {
                    case .tiles:
                        ConvertTileGrid(service: service)
                            .id(service.mode)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: -28)),
                                                    removal: .opacity.combined(with: .offset(x: -28))))
                    case .options(let format):
                        ConvertOptionsPane(session: session, format: format, service: service)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 28)),
                                                    removal: .opacity.combined(with: .offset(x: 28))))
                    case .tool(let tool):
                        ConvertToolPane(session: session, tool: tool, service: service)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 28)),
                                                    removal: .opacity.combined(with: .offset(x: 28))))
                    case .running:
                        if jobsFinished {
                            ConvertDoneView(service: service, runner: runner)
                                .transition(.scale(scale: 0.92).combined(with: .opacity))
                        } else {
                            ConvertProgressView(runner: runner)
                                .transition(.scale(scale: 0.96).combined(with: .opacity))
                        }
                    }
                    if let note = service.note {
                        Text(note).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 30)
                            .background(Capsule().fill(Color(red: 0.2, green: 0.6, blue: 0.35)))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.84), value: service.stage)
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.84), value: jobsFinished)
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: service.note)
            }
            // The pointer on the island holds the countdown that puts it back to normal.
            .contentShape(Rectangle())
            .onHover { service.setPointerInside($0) }
        }
    }
}

// MARK: Header

private struct ConvertHeader: View {
    let session: ConvertService.Session
    @ObservedObject var service: ConvertService
    @State private var appeared = false
    @Namespace private var tab

    var body: some View {
        HStack(spacing: 12) {
            fileStack
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if service.stage == .tiles { modeTabs.transition(.opacity.combined(with: .scale(scale: 0.9))) }
            Button { service.close() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24).background(.white.opacity(0.1), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.75))
            .help("Close")
        }
        .foregroundStyle(.white)
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { appeared = true } }
    }

    private var title: String {
        session.urls.count == 1 ? session.urls[0].lastPathComponent : "\(session.urls.count) files"
    }

    private var subtitle: String {
        guard session.sources.count == session.urls.count else { return "Files" }
        let kinds = Set(session.sources.map(\.displayName)).sorted().joined(separator: ", ")
        return "\(session.category.title) · \(kinds)"
    }

    /// Convert, Tools and Actions: one capsule slides between them.
    private var modeTabs: some View {
        HStack(spacing: 2) {
            ForEach(ConvertService.Mode.allCases) { mode in
                let selected = service.mode == mode
                let enabled = service.modeHasTiles(mode)
                Button { withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { service.setMode(mode) } } label: {
                    Image(systemName: mode.symbol).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? .black : .white.opacity(enabled ? 0.8 : 0.3))
                        .frame(width: 30, height: 24)
                        .background { if selected { Capsule().fill(.white).matchedGeometryEffect(id: "tab", in: tab) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain).disabled(!enabled).help(mode.title)
            }
        }
        .padding(2).background(.white.opacity(0.08), in: Capsule())
    }

    /// Up to three file icons fanned like a hand of cards, landing with a spring.
    private var fileStack: some View {
        ZStack {
            ForEach(Array(session.urls.prefix(3).enumerated().reversed()), id: \.offset) { index, url in
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().interpolation(.high)
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(appeared ? Double(index) * 9 - 4 : 0))
                    .offset(x: appeared ? CGFloat(index) * 7 : 0, y: appeared ? CGFloat(index) * -2 : 8)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .frame(width: 44, height: 36, alignment: .leading)
    }
}

// MARK: Tiles

private struct ConvertTileGrid: View {
    @ObservedObject var service: ConvertService
    @State private var shown = false

    var body: some View {
        GeometryReader { proxy in
            let tiles = service.tiles
            ZStack(alignment: .topLeading) {
                ForEach(Array(tiles.enumerated()), id: \.element) { index, tile in
                    let frame = ConvertLayout.frame(index: index, count: tiles.count, width: proxy.size.width)
                    ConvertTile(tile: tile, delay: Double(index) * 0.03, shown: shown, lit: service.hoverTile == tile) { service.choose(tile) }
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .onAppear { shown = true }
    }
}

/// One choice: a rounded plate with a light that follows the pointer, lifting
/// on hover and settling on press.
private struct ConvertTile: View {
    let tile: ConvertService.Tile
    let delay: Double
    let shown: Bool
    var lit = false
    let action: () -> Void
    @State private var pointerInside = false
    @State private var pressed = false
    @State private var pointer = CGPoint(x: 0.5, y: 0.5)
    private var hovering: Bool { pointerInside || lit }

    private var tint: Color { Self.tint(for: tile) }

    private var info: (symbol: String, title: String, caption: String) {
        switch tile {
        case .format(let format): return (format.category.symbol, format.displayName, format.category.title)
        case .tool(let tool): return (tool.symbol, tool.title, "")
        case .action(let action): return (action.symbol, action.title, "")
        }
    }

    var body: some View {
        let info = info
        let isFormat: Bool = { if case .format = tile { return true } else { return false } }()
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: info.symbol)
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(tint)
                    .scaleEffect(hovering ? 1.12 : 1)
                Text(info.title)
                    .font(.system(size: isFormat ? 14 : 10.5, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                if !info.caption.isEmpty { Text(info.caption).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45)) }
            }
            .padding(.horizontal, 4)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                GeometryReader { proxy in
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(hovering ? 0.12 : 0.06))
                        RadialGradient(colors: [tint.opacity(hovering ? 0.38 : 0), .clear],
                                       center: UnitPoint(x: pointer.x, y: pointer.y), startRadius: 0, endRadius: proxy.size.width * 0.7)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [tint.opacity(hovering ? 0.9 : 0.25), .white.opacity(0.08)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    }
                    .onContinuousHover { phase in
                        if case .active(let location) = phase {
                            pointer = CGPoint(x: location.x / max(1, proxy.size.width), y: location.y / max(1, proxy.size.height))
                        }
                    }
                }
            }
            .scaleEffect(pressed ? 0.94 : (hovering ? 1.04 : 1))
            .offset(y: hovering ? -2 : 0)
            .shadow(color: tint.opacity(hovering ? 0.35 : 0), radius: 10, y: 4)
        }
        .buttonStyle(ConvertPressStyle(pressed: $pressed))
        .onHover { pointerInside = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .animation(.spring(response: 0.2, dampingFraction: 0.65), value: pressed)
        // The cascade: each tile rises, sharpens and lands in turn.
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 14)
        .blur(radius: shown ? 0 : 6)
        .animation(.spring(response: 0.5, dampingFraction: 0.78).delay(delay), value: shown)
    }

    static func tint(for tile: ConvertService.Tile) -> Color {
        switch tile {
        case .format(let format): return tint(for: format.category)
        case .tool(let tool): return tint(for: tool.categories.first ?? .document)
        case .action: return Color(red: 0.6, green: 0.85, blue: 0.7)
        }
    }

    static func tint(for category: FormatCategory) -> Color {
        switch category {
        case .image: return Color(red: 1.0, green: 0.62, blue: 0.25)
        case .audio: return Color(red: 0.55, green: 0.55, blue: 1.0)
        case .video: return Color(red: 0.95, green: 0.35, blue: 0.5)
        case .document: return Color(red: 0.35, green: 0.8, blue: 0.95)
        case .subtitle: return Color(red: 0.6, green: 0.9, blue: 0.5)
        case .archive: return Color(red: 0.85, green: 0.75, blue: 0.4)
        }
    }
}

private struct ConvertPressStyle: ButtonStyle {
    @Binding var pressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { _, new in pressed = new }
    }
}

// MARK: Tool options

/// A tool's fields, from its catalog entry, then its run button.
private struct ConvertToolPane: View {
    let session: ConvertService.Session
    let tool: ToolID
    @ObservedObject var service: ConvertService

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { service.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26).background(.white.opacity(0.1), in: Circle()).contentShape(Circle())
                }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8)).help("Back")
                Image(systemName: tool.symbol).foregroundStyle(ConvertTile.tint(for: .tool(tool)))
                Text(tool.title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ConvertTools.fields(for: tool, formats: session.sources)) { field in fieldView(field) }
                }
                .padding(.vertical, 2)
            }
            ConvertGoButton(title: "Run") { service.runTool(tool) }
        }
    }

    @ViewBuilder private func fieldView(_ field: ToolField) -> some View {
        switch field.kind {
        case .chips(let choices, _):
            ConvertChips(title: field.title, options: choices.map { ($0.0, Optional($0.1)) }, selection: Binding(
                get: { service.toolValues.s[field.id] }, set: { service.toolValues.s[field.id] = $0 }), allowsNone: false)
        case .slider(let range, _, let unit, _):
            ConvertSlider(title: field.title, value: Binding(get: { service.toolValues.n[field.id] ?? range.lowerBound },
                                                             set: { service.toolValues.n[field.id] = $0 }),
                          range: range, label: { range.upperBound <= 3 ? String(format: "%.2f", $0) : "\(Int($0))\(unit)" })
        case .number(let unit, _):
            VStack(alignment: .leading, spacing: 6) {
                Text(field.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                HStack(spacing: 6) {
                    TextField("", value: Binding(get: { service.toolValues.n[field.id] ?? 0 }, set: { service.toolValues.n[field.id] = $0 }),
                              format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.plain).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                        .padding(.horizontal, 10).frame(width: 96, height: 30).background(.white.opacity(0.09), in: Capsule())
                    Text(unit).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
            }
        case .toggle:
            ConvertToggle(title: field.title, isOn: Binding(get: { service.toolValues.b[field.id] ?? false }, set: { service.toolValues.b[field.id] = $0 }))
        case .text(let placeholder):
            VStack(alignment: .leading, spacing: 6) {
                Text(field.title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                TextField(placeholder, text: Binding(get: { service.toolValues.s[field.id] ?? "" }, set: { service.toolValues.s[field.id] = $0 }))
                    .textFieldStyle(.plain).font(.system(size: 12, design: .rounded))
                    .padding(.horizontal, 12).frame(height: 30).background(.white.opacity(0.09), in: Capsule())
            }
        }
    }
}

// MARK: Options

private struct ConvertOptionsPane: View {
    let session: ConvertService.Session
    let format: FileFormat
    @ObservedObject var service: ConvertService

    private var category: FormatCategory { session.category }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { service.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26).background(.white.opacity(0.1), in: Circle()).contentShape(Circle())
                }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.8)).help("Back")
                Text("To \(format.displayName)").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) { controls }.padding(.vertical, 2)
            }
            ConvertGoButton(title: "Convert \(session.urls.count > 1 ? "\(session.urls.count) files" : "")".trimmingCharacters(in: .whitespaces)) {
                service.run(format)
            }
        }
    }

    @ViewBuilder private var controls: some View {
        if category == .image {
            if ConvertOptionCatalog.lossyImages.contains(format) {
                ConvertSlider(title: "Quality", value: Binding(get: { service.options.quality ?? AppSettings.shared.jpegQuality },
                                                               set: { service.options.quality = $0 }),
                              range: 0.2...1, label: { "\(Int($0 * 100))%" })
            }
            ConvertChips(title: "Longest side", options: [("Original", nil), ("4096", 4096), ("2048", 2048), ("1080", 1080), ("512", 512)],
                         selection: $service.options.maxLongEdge)
        } else if category == .video {
            if format == .gif {
                ConvertChips(title: "Frames per second", options: [("8", 8), ("12", 12), ("15", 15), ("24", 24)], selection: Binding(
                    get: { service.options.gifFPS }, set: { service.options.gifFPS = $0 ?? 12 }), allowsNone: false)
                ConvertChips(title: "Width", options: [("320", 320), ("480", 480), ("640", 640), ("800", 800)], selection: Binding(
                    get: { service.options.gifWidth }, set: { service.options.gifWidth = $0 ?? 640 }), allowsNone: false)
            } else if format == .mp3 {
                audioBitrate
            } else {
                ConvertChips(title: "Quality", options: [("High", 18), ("Balanced", 23), ("Small", 28)], selection: $service.options.videoCRF)
                ConvertChips(title: "Resolution", options: [("Original", nil), ("1080p", 1080), ("720p", 720), ("480p", 480)],
                             selection: $service.options.maxHeight)
                ConvertToggle(title: "Remove audio", isOn: $service.options.removeAudio)
            }
        } else if category == .audio {
            audioBitrate
        }
    }

    private var audioBitrate: some View {
        ConvertChips(title: "Bitrate", options: [("96k", 96_000), ("128k", 128_000), ("192k", 192_000), ("256k", 256_000), ("320k", 320_000)],
                     selection: $service.options.audioBitrate)
    }
}

/// A choice among a few values. The highlight is one capsule that slides to
/// the chosen chip. A nil value reads as "leave it as it is".
private struct ConvertChips<Value: Hashable>: View {
    let title: String
    let options: [(String, Value?)]
    @Binding var selection: Value?
    var allowsNone = true
    @Namespace private var highlight

    init(title: String, options: [(String, Value?)], selection: Binding<Value?>, allowsNone: Bool = true) {
        self.title = title; self.options = options; self._selection = selection; self.allowsNone = allowsNone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 4) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    let selected = option.1 == selection
                    Button { withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { selection = option.1 } } label: {
                        Text(option.0).font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(selected ? .black : .white.opacity(0.85))
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background {
                                if selected { Capsule().fill(.white).matchedGeometryEffect(id: "chip", in: highlight) }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(.white.opacity(0.07), in: Capsule())
        }
    }
}

private extension ConvertChips where Value: Hashable {
    /// A chip row whose value is not optional.
    init(title: String, options: [(String, Value?)], selection: Binding<Value>, allowsNone: Bool) {
        self.init(title: title, options: options, selection: Binding<Value?>(get: { selection.wrappedValue }, set: { new in if let new { selection.wrappedValue = new } }),
                  allowsNone: allowsNone)
    }
}

private struct ConvertSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
                Text(label(value)).font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            GeometryReader { proxy in
                let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.25), Color(red: 1, green: 0.4, blue: 0.5)],
                                                  startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, proxy.size.width * fraction))
                    Circle().fill(.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                        .offset(x: max(0, min(proxy.size.width - 16, proxy.size.width * fraction - 8)))
                }
                .frame(height: 16)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let f = max(0, min(1, drag.location.x / max(1, proxy.size.width)))
                    withAnimation(.interactiveSpring()) { value = range.lowerBound + f * (range.upperBound - range.lowerBound) }
                })
            }
            .frame(height: 16)
        }
    }
}

private struct ConvertToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { isOn.toggle() } } label: {
            HStack {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 0)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? Color(red: 1, green: 0.55, blue: 0.3) : .white.opacity(0.15)).frame(width: 38, height: 22)
                    Circle().fill(.white).frame(width: 18, height: 18).padding(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The run button: a capsule with a slow shimmer passing over it.
private struct ConvertGoButton: View {
    let title: String
    let action: () -> Void
    @State private var sweep = false

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background {
                    ZStack {
                        Capsule().fill(LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.4), Color(red: 1, green: 0.52, blue: 0.42)],
                                                      startPoint: .leading, endPoint: .trailing))
                        GeometryReader { proxy in
                            Capsule().fill(LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing))
                                .frame(width: proxy.size.width * 0.35)
                                .offset(x: sweep ? proxy.size.width : -proxy.size.width * 0.4)
                        }
                        .clipShape(Capsule())
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false).delay(0.4)) { sweep = true } }
    }
}

// MARK: Progress

private struct ConvertProgressView: View {
    @ObservedObject var runner: JobRunner

    private var average: Double {
        guard !runner.jobs.isEmpty else { return 0 }
        return runner.jobs.map(\.progress).reduce(0, +) / Double(runner.jobs.count)
    }

    var body: some View {
        HStack(spacing: 18) {
            ConvertRing(progress: average)
                .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 8) {
                Text(runner.jobs.count > 1 ? "Converting \(runner.jobs.count) files" : "Converting")
                    .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 7) {
                        ForEach(runner.jobs) { job in ConvertJobRow(job: job, runner: runner) }
                    }
                }
            }
        }
    }
}

/// A ring that fills as work completes, with a comet of light chasing its end.
private struct ConvertRing: View {
    let progress: Double

    var body: some View {
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 7)
                Circle().trim(from: 0, to: max(0.02, progress))
                    .stroke(AngularGradient(colors: [Color(red: 1, green: 0.78, blue: 0.4), Color(red: 1, green: 0.4, blue: 0.5)],
                                            center: .center), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                // Waiting for the first reading, a short arc circles instead.
                if progress < 0.02 {
                    Circle().trim(from: 0, to: 0.18)
                        .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(turn * 360 - 90))
                }
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .animation(.easeOut(duration: 0.4), value: progress)
        }
    }
}

private struct ConvertJobRow: View {
    @ObservedObject var job: Job
    let runner: JobRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(job.detail).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                Spacer(minLength: 0)
                statusText
                if !job.status.isFinished {
                    Button { runner.cancel(job) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain).help("Cancel")
                }
            }
            ConvertBar(progress: job.progress, failed: { if case .failed = job.status { return true } else { return false } }(),
                       waiting: job.status == .waiting)
        }
    }

    @ViewBuilder private var statusText: some View {
        switch job.status {
        case .waiting: Text("Waiting").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        case .running: Text("\(Int(job.progress * 100))%").font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
        case .done: Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
        case .cancelled: Text("Cancelled").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(.orange)
        }
    }
}

/// The progress bar: a track, a gradient fill that eases to each reading and
/// a gleam that travels along it while work is under way.
private struct ConvertBar: View {
    let progress: Double
    let failed: Bool
    let waiting: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                if !waiting {
                    Capsule()
                        .fill(failed ? AnyShapeStyle(Color.orange)
                                     : AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.4), Color(red: 1, green: 0.4, blue: 0.5)],
                                                                    startPoint: .leading, endPoint: .trailing)))
                        .frame(width: max(5, proxy.size.width * progress))
                        .overlay(alignment: .trailing) {
                            if progress < 1, !failed { Circle().fill(.white.opacity(0.9)).frame(width: 5, height: 5).blur(radius: 1.5) }
                        }
                }
            }
            .animation(.easeOut(duration: 0.35), value: progress)
        }
        .frame(height: 5)
    }
}

// MARK: Done

private struct ConvertDoneView: View {
    @ObservedObject var service: ConvertService
    @ObservedObject var runner: JobRunner
    @State private var landed = false

    private var failures: [Job] { runner.jobs.filter { if case .failed = $0.status { return true } else { return false } } }
    private var outputs: [URL] { runner.jobs.flatMap(\.outputs) }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                if failures.isEmpty { ConvertBurst().frame(width: 130, height: 130) }
                Circle().fill(failures.isEmpty ? Color.green.opacity(0.18) : Color.orange.opacity(0.18)).frame(width: 78, height: 78)
                Image(systemName: failures.isEmpty ? "checkmark" : "exclamationmark")
                    .font(.system(size: 32, weight: .bold)).foregroundStyle(failures.isEmpty ? .green : .orange)
                    .scaleEffect(landed ? 1 : 0.3).opacity(landed ? 1 : 0)
            }
            .frame(width: 100, height: 100)
            VStack(alignment: .leading, spacing: 8) {
                Text(failures.isEmpty ? "Done" : "\(failures.count) failed")
                    .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                if let message = failures.first.flatMap({ job -> String? in if case .failed(let text) = job.status { return text } else { return nil } }) {
                    Text(message).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(3)
                } else {
                    Text(savedText).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                }
                HStack(spacing: 6) {
                    pill("Show file", "folder", prominent: true) { service.showFile(outputs) }.disabled(outputs.isEmpty)
                    if outputs.count == 1, outputs[0].hasDirectoryPath == false { pill("Open", "arrow.up.forward.app") { service.open(outputs[0]) } }
                    pill("Again", "arrow.counterclockwise") { service.again() }
                }
            }
        }
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.55).delay(0.08)) { landed = true } }
    }

    /// Where the results went, in words: beside the original unless the person chose elsewhere.
    private var savedText: String {
        guard let first = outputs.first else { return "Copied to the clipboard" }
        let folder = first.deletingLastPathComponent()
        let source = service.session?.urls.first?.deletingLastPathComponent()
        let place = folder.standardizedFileURL == source?.standardizedFileURL ? "beside the original" : "in \(folder.lastPathComponent)"
        let name = outputs.count == 1 ? first.lastPathComponent : "\(outputs.count) files"
        return "\(name), saved \(place)"
    }

    private func pill(_ title: String, _ symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(prominent ? .black : .white)
                .padding(.horizontal, 10).frame(height: 28)
                .background(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.12)), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A one-shot burst of sparks around the check.
private struct ConvertBurst: View {
    @State private var start = Date()
    private static let sparks: [(angle: Double, speed: Double, size: CGFloat, hue: Double)] = (0..<26).map { index in
        let angle = Double(index) / 26 * 2 * .pi + Double((index * 7) % 5) * 0.07
        return (angle, 0.55 + Double((index * 13) % 7) / 9, CGFloat(2 + (index * 3) % 3), Double((index * 11) % 10) / 40 + 0.08)
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = min(1, context.date.timeIntervalSince(start) / 0.9)
            Canvas { gc, size in
                guard t < 1 else { return }
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let ease = 1 - pow(1 - t, 3)
                for spark in Self.sparks {
                    let distance = 20 + ease * 52 * spark.speed
                    let point = CGPoint(x: center.x + cos(spark.angle) * distance, y: center.y + sin(spark.angle) * distance + t * t * 10)
                    let radius = spark.size * (1 - t * 0.7)
                    gc.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                            with: .color(Color(hue: spark.hue, saturation: 0.75, brightness: 1).opacity(1 - t)))
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { start = Date() }
    }
}

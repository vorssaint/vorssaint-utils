// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import MapKit
import SwiftUI

/// RainViewer's last two hours of frames drawn over a map centred on the
/// forecast's place. It loads only while it is visible, and the map keeps
/// whatever the person panned or zoomed to as frames advance.
struct WeatherRadarView: View {
    let location: WeatherLocation
    var compact = false

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var radar = WeatherRadarService.shared
    @State private var selectedPath: String?
    @State private var isPlaying = false
    @State private var playbackTask: Task<Void, Never>?
    @State private var loadTask: Task<Void, Never>?

    private var strings: WeatherStrings { FeatureStrings.weather(l10n.language) }
    private var locale: Locale { l10n.language.formattingLocale() }
    private var frames: [WeatherRadarFrame] { radar.maps?.frames ?? [] }

    private var mapHeight: CGFloat { compact ? 200 : 280 }
    private var stateHeight: CGFloat { compact ? 180 : 280 }

    var body: some View {
        content
        .onAppear {
            loadTask = Task { await radar.load() }
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
            stopPlayback()
        }
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        if let maps = radar.maps {
            if frames.isEmpty {
                emptyState
            } else {
                radarContent(maps)
            }
        } else if radar.errorMessage != nil {
            failureState
        } else {
            loadingState
        }
    }

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(strings.loading)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: stateHeight)
    }

    private var failureState: some View {
        VStack(spacing: 10) {
            Label(strings.loadFailed, systemImage: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .semibold))
            Button(strings.retry) {
                Task { await radar.load(force: true) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: stateHeight)
    }

    private var emptyState: some View {
        Text(strings.radarUnavailable)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: stateHeight)
    }

    private func radarContent(_ maps: WeatherRadarMaps) -> some View {
        VStack(spacing: compact ? 8 : 12) {
            WeatherRadarMapView(
                coordinate: CLLocationCoordinate2D(latitude: location.latitude,
                                                   longitude: location.longitude),
                host: maps.host,
                frame: currentFrame
            )
            .frame(height: mapHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            controls
            HStack(spacing: 4) {
                Text(strings.dataSourceTitle)
                Link("RainViewer", destination: WeatherRadarSupport.attributionURL)
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: Timeline

    /// Newest frame by default: a nil selection falls back to the last one.
    private var currentIndex: Int {
        guard !frames.isEmpty else { return 0 }
        if let selectedPath,
           let index = frames.firstIndex(where: { $0.path == selectedPath }) {
            return index
        }
        return frames.count - 1
    }

    private var currentFrame: WeatherRadarFrame? {
        frames.indices.contains(currentIndex) ? frames[currentIndex] : nil
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .help(isPlaying ? l10n.s.actionPause : l10n.s.actionPlay)
            .accessibilityLabel(isPlaying ? l10n.s.actionPause : l10n.s.actionPlay)
            .disabled(frames.count < 2)

            Slider(value: sliderValue,
                   in: 0...Double(max(frames.count - 1, 1)),
                   step: 1)
                .disabled(frames.count < 2)
                .accessibilityLabel(strings.radarTitle)
                .accessibilityValue(frameTimeLabel)

            Text(frameTimeLabel)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private var sliderValue: Binding<Double> {
        Binding {
            Double(currentIndex)
        } set: { value in
            let index = min(max(Int(value.rounded()), 0), max(frames.count - 1, 0))
            guard frames.indices.contains(index) else { return }
            selectedPath = frames[index].path
        }
    }

    /// Frames are absolute times; they read in the forecast place's clock.
    private var frameTimeLabel: String {
        guard let time = currentFrame?.time else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: location.timezoneIdentifier) ?? .current
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        return formatter.string(from: time)
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
            return
        }
        guard frames.count > 1 else { return }
        isPlaying = true
        playbackTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                advanceFrame()
            }
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    private func advanceFrame() {
        guard !frames.isEmpty else { return }
        selectedPath = frames[(currentIndex + 1) % frames.count].path
    }
}

/// The map itself. The region is set once in `makeNSView`, and only the tile
/// overlay is swapped when the selected frame changes.
private struct WeatherRadarMapView: NSViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let host: String
    let frame: WeatherRadarFrame?

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(MKCoordinateRegion(center: coordinate,
                                         span: MKCoordinateSpan(latitudeDelta: 3,
                                                                longitudeDelta: 3)),
                      animated: false)
        let marker = MKPointAnnotation()
        marker.coordinate = coordinate
        map.addAnnotation(marker)
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        context.coordinator.show(frame: frame, host: host, on: map)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private var overlay: WeatherRadarTileOverlay?
        private var key: String?

        func show(frame: WeatherRadarFrame?, host: String, on map: MKMapView) {
            guard let frame else { return }
            let key = "\(host)|\(frame.path)"
            guard key != self.key else { return }
            if let overlay { map.removeOverlay(overlay) }
            let tile = WeatherRadarTileOverlay(host: host, path: frame.path)
            map.addOverlay(tile, level: .aboveLabels)
            overlay = tile
            self.key = key
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tile = overlay as? MKTileOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKTileOverlayRenderer(tileOverlay: tile)
            renderer.alpha = 0.7
            return renderer
        }
    }
}

/// A RainViewer frame as a tile set; every request goes through the pure URL
/// builder so the tile format has one definition.
private final class WeatherRadarTileOverlay: MKTileOverlay {
    private let host: String
    private let path: String

    init(host: String, path: String) {
        self.host = host
        self.path = path
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: 256, height: 256)
        maximumZ = WeatherRadarSupport.maximumZoom
        canReplaceMapContent = false
    }

    override func url(forTilePath tilePath: MKTileOverlayPath) -> URL {
        WeatherRadarSupport.tileURL(host: host, path: path,
                                    z: tilePath.z, x: tilePath.x, y: tilePath.y)
            ?? URL(string: "about:blank")!
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct FanControlCurveEditor: View {
    let strings: FanControlFeatureStrings
    @Binding var curves: [FanControlCurve]
    let temperatures: [FanControlTemperatureReading]
    let temperatureUnit: TemperatureUnit
    let disabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(curves.indices, id: \.self) { index in
                curveRule(at: index)
                if index < curves.count - 1 { Divider().opacity(0.55) }
            }

            if let source = nextAvailableSource {
                Button {
                    curves.append(FanControlCurve(
                        sensor: source,
                        points: FanControlConfiguration.defaultCurve.points
                    ))
                } label: {
                    Label(strings.addSensor, systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(disabled)
            }
        }
    }

    @ViewBuilder
    private func curveRule(at curveIndex: Int) -> some View {
        let curve = curveBinding(at: curveIndex)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Picker(strings.sensor, selection: curve.sensor) {
                    ForEach(sourceOptions(at: curveIndex)) { source in
                        Text(sourceName(source)).tag(source)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .disabled(disabled)

                Spacer(minLength: 4)

                if let temperature = temperature(for: curve.wrappedValue.sensor) {
                    Text(formattedTemperature(temperature))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if curves.count > 1 {
                    Button {
                        curves.remove(at: curveIndex)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(strings.removeSensor)
                    .accessibilityLabel(strings.removeSensor)
                    .disabled(disabled)
                }
            }

            FanControlCurveGraph(points: curve.points,
                                 accessibilityLabel: strings.curveGraph,
                                 disabled: disabled)
                .frame(height: 92)

            HStack {
                Text(strings.temperature)
                Spacer()
                Text(strings.fanSpeed)
                Spacer().frame(width: 20)
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.secondary)

            ForEach(curve.wrappedValue.points.indices, id: \.self) { pointIndex in
                pointRow(curveIndex: curveIndex, pointIndex: pointIndex)
            }

            if curve.wrappedValue.points.count < FanControlPolicy.maximumCurvePointCount,
               nextPoint(for: curve.wrappedValue.points) != nil {
                Button {
                    guard let point = nextPoint(for: curves[curveIndex].points) else { return }
                    curves[curveIndex].points.append(point)
                    curves[curveIndex].points.sort { $0.temperature < $1.temperature }
                } label: {
                    Label(strings.addPoint, systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .disabled(disabled)
            }
        }
    }

    private func pointRow(curveIndex: Int, pointIndex: Int) -> some View {
        let point = curves[curveIndex].points[pointIndex]
        return HStack(spacing: 5) {
            Text(formattedTemperature(Double(point.temperature)))
                .font(.system(size: 10).monospacedDigit())
                .frame(width: 42, alignment: .trailing)
            Stepper(strings.temperature,
                    value: temperatureBinding(curveIndex: curveIndex,
                                              pointIndex: pointIndex),
                    in: temperatureRange(curveIndex: curveIndex, pointIndex: pointIndex))
                .labelsHidden()
                .controlSize(.mini)
                .accessibilityValue(formattedTemperature(Double(point.temperature)))
                .disabled(disabled)

            Spacer(minLength: 4)

            Text("\(point.coolingLevel)%")
                .font(.system(size: 10).monospacedDigit())
                .frame(width: 34, alignment: .trailing)
            Stepper(strings.fanSpeed,
                    value: levelBinding(curveIndex: curveIndex,
                                        pointIndex: pointIndex),
                    in: levelRange(curveIndex: curveIndex, pointIndex: pointIndex),
                    step: FanControlPolicy.coolingLevelStep)
                .labelsHidden()
                .controlSize(.mini)
                .accessibilityValue("\(point.coolingLevel)%")
                .disabled(disabled)

            Button {
                curves[curveIndex].points.remove(at: pointIndex)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(width: 16)
            .help(strings.removePoint)
            .accessibilityLabel(strings.removePoint)
            .disabled(disabled
                      || curves[curveIndex].points.count <= FanControlPolicy.minimumCurvePointCount)
        }
    }

    private func curveBinding(at index: Int) -> Binding<FanControlCurve> {
        Binding(
            get: { curves[index] },
            set: { curves[index] = $0 }
        )
    }

    private func temperatureBinding(curveIndex: Int, pointIndex: Int) -> Binding<Int> {
        Binding(
            get: { curves[curveIndex].points[pointIndex].temperature },
            set: { curves[curveIndex].points[pointIndex].temperature = $0 }
        )
    }

    private func levelBinding(curveIndex: Int, pointIndex: Int) -> Binding<Int> {
        Binding(
            get: { curves[curveIndex].points[pointIndex].coolingLevel },
            set: { curves[curveIndex].points[pointIndex].coolingLevel = $0 }
        )
    }

    private func temperatureRange(curveIndex: Int, pointIndex: Int) -> ClosedRange<Int> {
        let points = curves[curveIndex].points
        let lower = pointIndex == 0
            ? FanControlPolicy.minimumCurveTemperature
            : points[pointIndex - 1].temperature + 1
        let upper = pointIndex == points.count - 1
            ? FanControlPolicy.maximumCurveTemperature
            : points[pointIndex + 1].temperature - 1
        return lower...upper
    }

    private func levelRange(curveIndex: Int, pointIndex: Int) -> ClosedRange<Int> {
        let points = curves[curveIndex].points
        let lower = pointIndex == 0
            ? FanControlPolicy.minimumCoolingLevel
            : points[pointIndex - 1].coolingLevel
        let upper = pointIndex == points.count - 1
            ? FanControlPolicy.maximumCoolingLevel
            : points[pointIndex + 1].coolingLevel
        return lower...upper
    }

    private func sourceOptions(at index: Int) -> [FanControlTemperatureSource] {
        let current = curves[index].sensor
        let detected = Set(temperatures.map(\.source))
        let base = detected.isEmpty ? Set(FanControlTemperatureSource.allCases) : detected
        let used = Set(curves.enumerated().compactMap { $0.offset == index ? nil : $0.element.sensor })
        return FanControlTemperatureSource.allCases.filter {
            ($0 == current || (base.contains($0) && !used.contains($0)))
        }
    }

    private var nextAvailableSource: FanControlTemperatureSource? {
        let used = Set(curves.map(\.sensor))
        let detected = Set(temperatures.map(\.source))
        let candidates = detected.isEmpty ? FanControlTemperatureSource.allCases
                                          : FanControlTemperatureSource.allCases.filter(detected.contains)
        return candidates.first { !used.contains($0) }
    }

    private func temperature(for source: FanControlTemperatureSource) -> Double? {
        temperatures.first { $0.source == source }?.celsius
    }

    private func formattedTemperature(_ celsius: Double) -> String {
        MetricFormat.temperature(celsius, unit: temperatureUnit)
    }

    private func sourceName(_ source: FanControlTemperatureSource) -> String {
        switch source {
        case .averageSoC: return strings.averageSoC
        case .hottestSoC: return strings.hottestSoC
        case .averageCPU: return strings.averageCPU
        case .hottestCPU: return strings.hottestCPU
        case .hottestGPU: return strings.hottestGPU
        }
    }

    private func nextPoint(for points: [FanControlCurvePoint]) -> FanControlCurvePoint? {
        guard let first = points.first, let last = points.last else { return nil }
        var best: (index: Int, gap: Int)?
        for index in 1..<points.count {
            let gap = points[index].temperature - points[index - 1].temperature
            if gap > 1, gap > (best?.gap ?? 0) { best = (index, gap) }
        }
        if let best {
            let lower = points[best.index - 1]
            let upper = points[best.index]
            let temperature = lower.temperature + best.gap / 2
            let rawLevel = Double(lower.coolingLevel + upper.coolingLevel) / 2
            let level = Int((rawLevel / Double(FanControlPolicy.coolingLevelStep)).rounded())
                * FanControlPolicy.coolingLevelStep
            return FanControlCurvePoint(temperature: temperature, coolingLevel: level)
        }
        if last.temperature < FanControlPolicy.maximumCurveTemperature {
            return FanControlCurvePoint(
                temperature: min(FanControlPolicy.maximumCurveTemperature, last.temperature + 10),
                coolingLevel: last.coolingLevel
            )
        }
        if first.temperature > FanControlPolicy.minimumCurveTemperature {
            return FanControlCurvePoint(
                temperature: max(FanControlPolicy.minimumCurveTemperature, first.temperature - 10),
                coolingLevel: first.coolingLevel
            )
        }
        return nil
    }
}

private struct FanControlCurveGraph: View {
    @Binding var points: [FanControlCurvePoint]
    let accessibilityLabel: String
    let disabled: Bool
    @State private var draggedPoint: Int?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.035))

                ForEach(0..<5, id: \.self) { index in
                    let fraction = CGFloat(index) / 4
                    Path { path in
                        path.move(to: CGPoint(x: 6, y: 6 + fraction * (geometry.size.height - 12)))
                        path.addLine(to: CGPoint(x: geometry.size.width - 6,
                                                 y: 6 + fraction * (geometry.size.height - 12)))
                    }
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 0.5)
                }

                Path { path in
                    for (index, point) in points.enumerated() {
                        let position = position(for: point, in: geometry.size)
                        index == 0 ? path.move(to: position) : path.addLine(to: position)
                    }
                }
                .stroke(Color.cyan,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                ForEach(points.indices, id: \.self) { index in
                    Circle()
                        .fill(Color.cyan)
                        .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1))
                        .frame(width: draggedPoint == index ? 10 : 8,
                               height: draggedPoint == index ? 10 : 8)
                        .position(position(for: points[index], in: geometry.size))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if draggedPoint == nil {
                        draggedPoint = nearestPoint(to: value.location, in: geometry.size)
                    }
                    guard let draggedPoint else { return }
                    movePoint(at: draggedPoint, to: value.location, in: geometry.size)
                }
                .onEnded { _ in draggedPoint = nil })
            .allowsHitTesting(!disabled)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func position(for point: FanControlCurvePoint, in size: CGSize) -> CGPoint {
        let width = max(1, size.width - 12)
        let height = max(1, size.height - 12)
        let x = Double(point.temperature - FanControlPolicy.minimumCurveTemperature)
            / Double(FanControlPolicy.maximumCurveTemperature
                     - FanControlPolicy.minimumCurveTemperature)
        let y = 1 - Double(point.coolingLevel) / Double(FanControlPolicy.maximumCoolingLevel)
        return CGPoint(x: 6 + CGFloat(x) * width, y: 6 + CGFloat(y) * height)
    }

    private func nearestPoint(to location: CGPoint, in size: CGSize) -> Int? {
        points.indices.min { left, right in
            squaredDistance(position(for: points[left], in: size), location)
                < squaredDistance(position(for: points[right], in: size), location)
        }
    }

    private func squaredDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let x = lhs.x - rhs.x
        let y = lhs.y - rhs.y
        return x * x + y * y
    }

    private func movePoint(at index: Int, to location: CGPoint, in size: CGSize) {
        guard points.indices.contains(index) else { return }
        let width = max(1, size.width - 12)
        let height = max(1, size.height - 12)
        let x = min(1, max(0, (location.x - 6) / width))
        let y = min(1, max(0, (location.y - 6) / height))
        let temperatureRange = FanControlPolicy.maximumCurveTemperature
            - FanControlPolicy.minimumCurveTemperature
        var temperature = FanControlPolicy.minimumCurveTemperature
            + Int((x * CGFloat(temperatureRange)).rounded())
        var level = Int(((1 - y) * CGFloat(FanControlPolicy.maximumCoolingLevel)
                         / CGFloat(FanControlPolicy.coolingLevelStep)).rounded())
            * FanControlPolicy.coolingLevelStep

        if index > 0 {
            temperature = max(temperature, points[index - 1].temperature + 1)
            level = max(level, points[index - 1].coolingLevel)
        }
        if index + 1 < points.count {
            temperature = min(temperature, points[index + 1].temperature - 1)
            level = min(level, points[index + 1].coolingLevel)
        }
        temperature = min(FanControlPolicy.maximumCurveTemperature,
                          max(FanControlPolicy.minimumCurveTemperature, temperature))
        level = min(FanControlPolicy.maximumCoolingLevel,
                    max(FanControlPolicy.minimumCoolingLevel, level))
        points[index] = FanControlCurvePoint(temperature: temperature, coolingLevel: level)
    }
}

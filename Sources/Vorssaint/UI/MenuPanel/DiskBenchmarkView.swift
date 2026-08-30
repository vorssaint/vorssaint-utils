// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

internal struct DiskBenchmarkView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service: DiskBenchmarkService
    @Environment(\.colorScheme) private var colorScheme
    @State private var mode = DiskBenchmarkMode.quick

    private let disk: DiskDeviceReading

    internal init(disk: DiskDeviceReading, service: DiskBenchmarkService) {
        self.disk = disk
        self._service = ObservedObject(wrappedValue: service)
    }

    internal var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            Text(l10n.s.diskSpeedDescription)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let progress = activeProgress {
                progressView(progress)
            } else {
                if let result = service.lastResult(for: disk) {
                    resultView(result)
                }
                controls
            }

            if disk.isBenchmarkReadOnly {
                failureText(l10n.s.diskSpeedReadOnly)
            } else if let failure = activeFailure {
                failureText(message(for: failure))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(l10n.s.diskSpeedTest, systemImage: "gauge.with.dots.needle.67percent")
                .font(.system(size: 10.5, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Picker(l10n.s.diskSpeedTest, selection: $mode) {
                Text(l10n.s.diskSpeedQuick).tag(DiskBenchmarkMode.quick)
                Text(l10n.s.diskSpeedStandard).tag(DiskBenchmarkMode.standard)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: 150)
            .disabled(service.isRunning)
            .accessibilityLabel(l10n.s.diskSpeedTest)
        }
    }

    private var controls: some View {
        HStack(spacing: 7) {
            Button {
                service.start(disk: disk, mode: mode)
            } label: {
                Label(service.lastResult(for: disk) == nil ? l10n.s.speedTestRun : l10n.s.speedTestAgain,
                      systemImage: "play.fill")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(service.isRunning || disk.isBenchmarkReadOnly)
            Spacer(minLength: 0)
        }
    }

    private func progressView(_ progress: DiskBenchmarkProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                if progress.phase == .preparing || progress.phase == .flushing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: .infinity)
                }
                Text(phaseLabel(progress.phase))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                if progress.phase == .writing || progress.phase == .reading {
                    Text(MetricFormat.percent(progress.fraction))
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(phaseLabel(progress.phase))
            .accessibilityValue(MetricFormat.percent(progress.fraction))

            Button(l10n.s.mediaCancel) {
                service.cancel()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func resultView(_ result: DiskBenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                resultMetric(label: l10n.s.diskRead,
                             value: MetricFormat.diskBenchmarkRate(result.readBytesPerSecond),
                             systemImage: "arrow.down")
                resultMetric(label: l10n.s.diskWrite,
                             value: MetricFormat.diskBenchmarkRate(result.writeBytesPerSecond),
                             systemImage: "arrow.up")
            }
            Text("\(l10n.s.diskSpeedLastTest) · \(modeLabel(result.mode)) · "
                 + result.measuredAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private func resultMetric(label: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func failureText(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 9.5))
            .foregroundStyle(PanelMetricColor.red(for: colorScheme))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var activeProgress: DiskBenchmarkProgress? {
        guard case let .running(diskID, _, progress) = service.state,
              diskID == disk.id else { return nil }
        return progress
    }

    private var activeFailure: DiskBenchmarkFailure? {
        guard case let .failed(diskID, failure) = service.state,
              diskID == disk.id else { return nil }
        return failure
    }

    private func phaseLabel(_ phase: DiskBenchmarkPhase) -> String {
        switch phase {
        case .preparing: return l10n.s.diskSpeedPreparing
        case .writing: return l10n.s.diskWrite
        case .flushing: return l10n.s.diskSpeedFlushing
        case .reading: return l10n.s.diskRead
        }
    }

    private func modeLabel(_ mode: DiskBenchmarkMode) -> String {
        switch mode {
        case .quick: return l10n.s.diskSpeedQuick
        case .standard: return l10n.s.diskSpeedStandard
        }
    }

    private func message(for failure: DiskBenchmarkFailure) -> String {
        switch failure {
        case let .insufficientSpace(required, _):
            return String(format: l10n.s.diskSpeedNeedsSpace, MetricFormat.diskBytes(required))
        case .readOnly:
            return l10n.s.diskSpeedReadOnly
        case .cancelled:
            return l10n.s.mediaCancel
        case .targetUnavailable, .volumeIdentityUnavailable, .volumeMismatch,
             .unavailableCapacity, .cacheControl, .memoryAllocation, .io:
            return l10n.s.diskSpeedUnavailable
        }
    }
}

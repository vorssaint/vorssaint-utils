// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum RecordingShareError: Error {
    case invalidArtifact
    case invalidEndpoint
    case unavailable
    case rejected
    case invalidResponse
    case localStorage
}

@MainActor
final class RecordingShareService: ObservableObject {
    static let shared = RecordingShareService()

    @Published private(set) var records: [RecordingShareRecord] = []

    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var expiryRefresh: DispatchWorkItem?
    private var removedRecordIDs = Set<String>()

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
        refresh()
    }

    var endpoint: URL {
        RecordingSharingSupport.endpoint(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            developerOverride: UserDefaults.standard.string(
                forKey: DefaultsKey.screenshotSharingDeveloperEndpoint))
    }

    func refresh(now: Date = Date()) {
        guard let stored = try? loadRecords() else {
            records = normalizedRecords(records, now: now)
            scheduleExpiryRefresh(now: now)
            return
        }
        let active = normalizedRecords(stored + records, now: now)
        if active != stored {
            guard (try? saveRecords(active)) != nil else {
                records = active
                scheduleExpiryRefresh(now: now)
                return
            }
        }
        removedRecordIDs.removeAll()
        records = active
        scheduleExpiryRefresh(now: now)
    }

    func createLink(artifact: RecorderExporter.ShareArtifact,
                    duration: RecordingShareDuration) async throws -> RecordingShareRecord {
        defer { artifact.discard() }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.recorderSharingEnabled) else {
            throw RecordingShareError.unavailable
        }
        let file = artifact.fileURL
        guard let values = try? file.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let bytes = values.fileSize,
              bytes > 0,
              bytes <= RecordingSharingSupport.maximumUploadBytes
        else { throw RecordingShareError.invalidArtifact }

        let serviceEndpoint = endpoint
        guard let url = RecordingSharingSupport.uploadURL(endpoint: serviceEndpoint,
                                                          duration: duration)
        else { throw RecordingShareError.invalidEndpoint }

        do {
            try saveRecords(normalizedRecords(try loadRecords() + records))
        } catch {
            throw RecordingShareError.localStorage
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(String(bytes), forHTTPHeaderField: "Content-Length")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, fromFile: file)
        } catch {
            throw RecordingShareError.unavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw RecordingShareError.invalidResponse
        }
        guard http.statusCode == 201 else {
            throw http.statusCode == 429 || http.statusCode == 503 || http.statusCode == 507
                ? RecordingShareError.unavailable
                : RecordingShareError.rejected
        }
        guard data.count <= 64 * 1_024,
              let decoded = try? decoder.decode(RecordingShareResponse.self, from: data),
              let record = RecordingSharingSupport.record(response: decoded,
                                                           endpoint: serviceEndpoint)
        else { throw RecordingShareError.invalidResponse }

        removedRecordIDs.remove(record.id)
        let updated = normalizedRecords(records + [record])
        do {
            try saveRecords(updated)
        } catch {
            if (try? await deleteRemote(record)) != nil {
                removedRecordIDs.insert(record.id)
                throw RecordingShareError.localStorage
            }
        }
        records = updated
        scheduleExpiryRefresh()
        return record
    }

    func delete(_ record: RecordingShareRecord) async throws {
        if record.expiresAt > Date() {
            try await deleteRemote(record)
        }
        removedRecordIDs.insert(record.id)
        let stored = try? loadRecords()
        let remaining = normalizedRecords((stored ?? []) + records)
        records = remaining
        scheduleExpiryRefresh()
        if stored != nil, (try? saveRecords(remaining)) != nil {
            removedRecordIDs.remove(record.id)
        }
    }

    @discardableResult
    func copy(_ url: URL) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(url.absoluteString, forType: .string)
    }

    private func deleteRemote(_ record: RecordingShareRecord) async throws {
        let url = record.endpoint.appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent("recordings", isDirectory: true)
            .appendingPathComponent(record.id, isDirectory: false)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(record.deleteToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw RecordingShareError.unavailable
        }
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 204 || http.statusCode == 404
        else { throw RecordingShareError.unavailable }
    }

    private var storageDirectory: URL? {
        PrivateFileStore.containerURL?
            .appendingPathComponent("TemporaryRecordingLinks", isDirectory: true)
    }

    private func loadRecords() throws -> [RecordingShareRecord] {
        guard let file = storageDirectory?.appendingPathComponent("records.json") else {
            throw RecordingShareError.localStorage
        }
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        do {
            let data = try Data(contentsOf: file)
            return try decoder.decode([RecordingShareRecord].self, from: data)
        } catch {
            throw RecordingShareError.localStorage
        }
    }

    private func saveRecords(_ records: [RecordingShareRecord]) throws {
        guard let directory = storageDirectory else {
            throw RecordingShareError.localStorage
        }
        guard PrivateFileStore.createDirectory(at: directory),
              let data = try? encoder.encode(records),
              PrivateFileStore.write(data, to: directory.appendingPathComponent("records.json"))
        else { throw RecordingShareError.localStorage }
    }

    private func normalizedRecords(_ candidates: [RecordingShareRecord],
                                   now: Date = Date()) -> [RecordingShareRecord] {
        var byID: [String: RecordingShareRecord] = [:]
        for record in candidates
        where record.expiresAt > now && !removedRecordIDs.contains(record.id) {
            if let existing = byID[record.id], existing.expiresAt >= record.expiresAt {
                continue
            }
            byID[record.id] = record
        }
        return byID.values.sorted { $0.expiresAt < $1.expiresAt }
    }

    private func scheduleExpiryRefresh(now: Date = Date()) {
        expiryRefresh?.cancel()
        expiryRefresh = nil
        guard let expiration = records.first?.expiresAt else { return }
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        expiryRefresh = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(0.1, expiration.timeIntervalSince(now) + 0.1),
            execute: item)
    }
}

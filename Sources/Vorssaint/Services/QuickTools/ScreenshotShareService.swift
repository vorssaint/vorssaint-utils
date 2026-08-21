// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum ScreenshotShareError: Error {
    case invalidImage
    case invalidEndpoint
    case unavailable
    case rejected
    case invalidResponse
    case localStorage
}

@MainActor
final class ScreenshotShareService: ObservableObject {
    static let shared = ScreenshotShareService()

    @Published private(set) var records: [ScreenshotShareRecord] = []

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
        configuration.timeoutIntervalForRequest = 75
        configuration.timeoutIntervalForResource = 90
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
        refresh()
    }

    var endpoint: URL {
        ScreenshotSharingSupport.endpoint(
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

    func createLink(pngData: Data,
                    duration: ScreenshotShareDuration) async throws -> ScreenshotShareRecord {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.screenshotSharingEnabled) else {
            throw ScreenshotShareError.unavailable
        }
        guard !pngData.isEmpty,
              pngData.count <= ScreenshotSharingSupport.maximumUploadBytes,
              pngData.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
        else { throw ScreenshotShareError.invalidImage }
        let serviceEndpoint = endpoint
        guard let url = ScreenshotSharingSupport.uploadURL(endpoint: serviceEndpoint,
                                                           duration: duration)
        else { throw ScreenshotShareError.invalidEndpoint }

        // Do not create a link unless its private deletion token has a place
        // to live. A successful upload must never disappear from the app just
        // because local persistence was already unavailable.
        do {
            try saveRecords(normalizedRecords(try loadRecords() + records))
        } catch {
            throw ScreenshotShareError.localStorage
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: pngData)
        } catch {
            throw ScreenshotShareError.unavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw ScreenshotShareError.invalidResponse
        }
        guard http.statusCode == 201 else {
            throw http.statusCode == 429 || http.statusCode == 503 || http.statusCode == 507
                ? ScreenshotShareError.unavailable
                : ScreenshotShareError.rejected
        }
        guard data.count <= 64 * 1_024,
              let decoded = try? decoder.decode(ScreenshotShareResponse.self, from: data),
              let record = ScreenshotSharingSupport.record(response: decoded,
                                                            endpoint: serviceEndpoint)
        else { throw ScreenshotShareError.invalidResponse }

        removedRecordIDs.remove(record.id)
        let updated = normalizedRecords(records + [record])
        do {
            try saveRecords(updated)
        } catch {
            // The preflight succeeded, so this is a narrow race. Revoke the
            // new link when possible instead of leaving its deletion token
            // only in memory. If revocation also fails, keep the record visible
            // so it can still be copied or deleted from Settings this session.
            if (try? await deleteRemote(record)) != nil {
                removedRecordIDs.insert(record.id)
                throw ScreenshotShareError.localStorage
            }
        }
        records = updated
        scheduleExpiryRefresh()
        return record
    }

    func delete(_ record: ScreenshotShareRecord) async throws {
        if record.expiresAt > Date() {
            try await deleteRemote(record)
        }
        removedRecordIDs.insert(record.id)
        let stored = try? loadRecords()
        let remaining = normalizedRecords((stored ?? []) + records)
        records = remaining
        scheduleExpiryRefresh()
        // Remote deletion already succeeded (or expiration already removed
        // the image), so a local cleanup problem must not report a false
        // deletion failure to the person.
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

    private func deleteRemote(_ record: ScreenshotShareRecord) async throws {
        let url = record.endpoint.appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent("screenshots", isDirectory: true)
            .appendingPathComponent(record.id, isDirectory: false)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(record.deleteToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw ScreenshotShareError.unavailable
        }
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 204 || http.statusCode == 404
        else { throw ScreenshotShareError.unavailable }
    }

    private var storageDirectory: URL? {
        PrivateFileStore.containerURL?
            .appendingPathComponent("TemporaryScreenshotLinks", isDirectory: true)
    }

    private func loadRecords() throws -> [ScreenshotShareRecord] {
        guard let file = storageDirectory?.appendingPathComponent("records.json") else {
            throw ScreenshotShareError.localStorage
        }
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        do {
            let data = try Data(contentsOf: file)
            return try decoder.decode([ScreenshotShareRecord].self, from: data)
        } catch {
            throw ScreenshotShareError.localStorage
        }
    }

    private func saveRecords(_ records: [ScreenshotShareRecord]) throws {
        guard let directory = storageDirectory else {
            throw ScreenshotShareError.localStorage
        }
        guard PrivateFileStore.createDirectory(at: directory),
              let data = try? encoder.encode(records),
              PrivateFileStore.write(data, to: directory.appendingPathComponent("records.json"))
        else { throw ScreenshotShareError.localStorage }
    }

    private func normalizedRecords(_ candidates: [ScreenshotShareRecord],
                                   now: Date = Date()) -> [ScreenshotShareRecord] {
        var byID: [String: ScreenshotShareRecord] = [:]
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

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Sends a finished screenshot or recording to the configured server. Unlike
/// the temporary link services it keeps no account of what was sent; the one
/// thing kept is the link the reply named, on the clipboard. No state of its
/// own to guard, so it is not tied to the main actor.
final class CaptureUploadService {
    static let shared = CaptureUploadService()

    enum Failure: Error, Equatable {
        case invalidArtifact
        case invalidDestination
        case unavailable
        case rejected(Int)
    }

    struct Outcome {
        let kind: CaptureUploadSupport.Kind
        let host: String
        let link: URL?
    }

    private let configuration: URLSessionConfiguration

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        // A recording can take long over a slow connection, so the limit is on
        // silence between bytes rather than on the whole transfer.
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 6 * 60 * 60
        configuration.waitsForConnectivity = false
        self.configuration = configuration
    }

    /// Read once when the person asks for an upload and handed to it, so a
    /// change made while the file is prepared never redirects that upload.
    var destination: CaptureUploadSupport.Destination {
        CaptureUploadSupport.sendable(CaptureUploadSupport.Destination.decoded(
            UserDefaults.standard.string(forKey: DefaultsKey.captureUploadDestination)))
    }

    /// A hidden button is not a gate on its own, so the request path asks
    /// the switch again. Turning uploads off stops one still being prepared.
    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.captureUploadEnabled)
    }

    func upload(pngData: Data,
                to destination: CaptureUploadSupport.Destination) async throws -> Outcome {
        guard !pngData.isEmpty,
              pngData.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
        else { throw Failure.invalidArtifact }
        guard isEnabled,
              let host = CaptureUploadSupport.host(destination),
              let request = CaptureUploadSupport.request(
                  destination: destination,
                  kind: .screenshot,
                  contentLength: pngData.count,
                  fileName: ScreenshotSupport.fileName(
                      prefix: FeatureStrings.screenshot(L10n.shared.language).fileNamePrefix,
                      date: Date()))
        else { throw Failure.invalidDestination }
        let (data, response) = try await CaptureUploadTransfer.send(
            request, body: .data(pngData), configuration: configuration)
        return try outcome(kind: .screenshot, host: host, data: data, response: response)
    }

    func upload(recordingAt file: URL,
                to destination: CaptureUploadSupport.Destination) async throws -> Outcome {
        guard let values = try? file.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let bytes = values.fileSize,
              bytes > 0
        else { throw Failure.invalidArtifact }
        guard isEnabled,
              let host = CaptureUploadSupport.host(destination),
              let request = CaptureUploadSupport.request(
                  destination: destination,
                  kind: .recording,
                  contentLength: bytes,
                  fileName: ScreenshotSupport.fileName(
                      prefix: FeatureStrings.recorder(L10n.shared.language).fileNamePrefix,
                      date: Date(), fileExtension: "mp4"))
        else { throw Failure.invalidDestination }
        let (data, response) = try await CaptureUploadTransfer.send(
            request, body: .file(file), configuration: configuration)
        return try outcome(kind: .recording, host: host, data: data, response: response)
    }

    /// The link goes to the clipboard when that kind of upload asks for it:
    /// that is what the person would do with it next anyway.
    func announce(_ outcome: Outcome) {
        if let link = outcome.link,
           UserDefaults.standard.bool(forKey: outcome.kind.copyLinkDefaultsKey) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if pasteboard.setString(link.absoluteString, forType: .string) {
                QuickToolHUD.show(icon: "link",
                                  message: FeatureStrings.screenshot(L10n.shared.language).sharedHUD)
                return
            }
        }
        QuickToolHUD.show(icon: "icloud.and.arrow.up",
                          message: String(format: strings.uploadedFormat, outcome.host))
    }

    /// A refusal names the status, which is what the person needs to look at
    /// their server with; everything else is one plain failure.
    func announce(failure: Failure) {
        let message: String
        switch failure {
        case let .rejected(status):
            message = String(format: strings.rejectedFormat, status)
        case .invalidArtifact, .invalidDestination, .unavailable:
            message = strings.failedHUD
        }
        QuickToolHUD.show(icon: "icloud.and.arrow.up", message: message)
        NSSound.beep()
    }

    private var strings: CaptureUploadStrings {
        FeatureStrings.captureUpload(L10n.shared.language)
    }

    private func outcome(kind: CaptureUploadSupport.Kind,
                         host: String,
                         data: Data,
                         response: HTTPURLResponse) throws -> Outcome {
        guard (200...299).contains(response.statusCode) else {
            throw Failure.rejected(response.statusCode)
        }
        return Outcome(kind: kind, host: host, link: CaptureUploadSupport.link(in: data))
    }
}

/// One upload on a session of its own, so the reply can be bounded while it
/// arrives. Redirects are refused: the file and the header values reach only
/// the address the person set, and a POST never turns into a GET that some
/// other page answers with success. A refusal comes back as its 3xx status.
private final class CaptureUploadTransfer: NSObject, URLSessionDataDelegate {
    enum Body {
        case data(Data)
        case file(URL)
    }

    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var response: HTTPURLResponse?
    private var reply = Data()
    /// Set once the reply is no longer read: a refusal needs no body, and one
    /// too long to name a link is left unread.
    private var stopped = false

    /// Throws CancellationError when the calling task is cancelled, which
    /// also cancels the request.
    static func send(_ request: URLRequest,
                     body: Body,
                     configuration: URLSessionConfiguration) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let transfer = CaptureUploadTransfer()
        let session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: nil)
        let task: URLSessionUploadTask
        switch body {
        case .data(let data): task = session.uploadTask(with: request, from: data)
        case .file(let file): task = session.uploadTask(with: request, fromFile: file)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                transfer.continuation = continuation
                task.resume()
                session.finishTasksAndInvalidate()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response as? HTTPURLResponse
        stopped = self.response.map { !(200...299).contains($0.statusCode) } ?? true
            || response.expectedContentLength > Int64(CaptureUploadSupport.maximumResponseBytes)
        completionHandler(stopped ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard !stopped else { return }
        guard chunk.count <= CaptureUploadSupport.maximumResponseBytes - reply.count else {
            stopped = true
            reply = Data()
            dataTask.cancel()
            return
        }
        reply.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if error == nil || stopped, let response {
            continuation.resume(returning: (stopped ? Data() : reply, response))
        } else if !stopped, (error as? URLError)?.code == .cancelled {
            continuation.resume(throwing: CancellationError())
        } else {
            continuation.resume(throwing: CaptureUploadService.Failure.unavailable)
        }
    }
}

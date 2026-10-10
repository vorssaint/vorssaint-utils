// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO

/// Uploading a capture to a server: what the request carries, what a reply
/// may give back, and what a settings backup does with the keys to that server.
enum CaptureUploadTests {
    static func run(_ suite: TestSuite) {
        typealias Field = CaptureUploadSupport.Field
        typealias Destination = CaptureUploadSupport.Destination

        // MARK: Address

        suite.expect(CaptureUploadSupport.sanitizedEndpoint(" https://example.com/upload?dir=shots ")?
                .absoluteString == "https://example.com/upload?dir=shots",
               "an https address keeps its path and its own query")
        suite.expect(CaptureUploadSupport.sanitizedEndpoint("HTTPS://example.com")?.absoluteString
                == "https://example.com",
               "the scheme is read whatever its case")
        suite.expect(CaptureUploadSupport.sanitizedEndpoint("https://user:secret@example.com/upload")?
                .absoluteString == "https://example.com/upload",
               "a user name and password never reach the URL a request is sent to")
        for rejected in ["", "example.com/upload", "http://example.com/upload",
                         "https://example.com/upload#part", "https:///upload",
                         "https://a%3Ab:pw@example.com/", "https://a%FF:pw@example.com/",
                         "https://user:p%FF@example.com/", "ftp://example.com"] {
            suite.expect(CaptureUploadSupport.sanitizedEndpoint(rejected) == nil,
                   "an address an upload cannot use is refused: \(rejected)")
        }
        suite.expect(CaptureUploadSupport.host(Destination(url: "https://files.example.com/api/upload"))
                == "files.example.com"
                && CaptureUploadSupport.host(Destination()) == nil,
               "the menu names the server, and nothing while no address is set")

        // MARK: Request

        let destination = Destination(
            url: "https://example.com/upload?dir=shots",
            queryItems: [Field(name: " folder ", value: "a b&c+d"),
                         Field(name: "", value: "nameless"),
                         Field(name: "flag", value: "")],
            headers: [Field(name: "Authorization", value: " Bearer token "),
                      Field(name: "Content-Length", value: "1"),
                      Field(name: "bad name", value: "x"),
                      Field(name: "X-Note", value: "line one\nline two"),
                      Field(name: "Content-Type", value: "application/octet-stream")])
        let request = CaptureUploadSupport.request(destination: destination,
                                                   kind: .screenshot,
                                                   contentLength: 12_345,
                                                   fileName: "Screenshot 2026-09-23 at 10.00.00.png")
        suite.expect(request?.url?.absoluteString
                == "https://example.com/upload?dir=shots&folder=a%20b%26c%2Bd&flag=",
               "query parameters follow the address's own, encoded so any character survives")
        suite.expect(request?.httpMethod == "POST",
               "the file is sent with a POST")
        suite.expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer token",
               "a header row is sent with its value trimmed")
        suite.expect(request?.value(forHTTPHeaderField: "Content-Length") == "12345",
               "the transport keeps its own Content-Length")
        suite.expect(request?.value(forHTTPHeaderField: "bad name") == nil,
               "a header name that is not a token is left out")
        suite.expect(request?.value(forHTTPHeaderField: "X-Note") == "line one line two",
               "a header value cannot start a new line of the request")
        suite.expect(request?.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream",
               "a header row can replace the content type a server will not accept")
        suite.expect(request?.value(forHTTPHeaderField: "X-File-Name") == nil,
               "the file's name is sent only where a row asks for it")
        suite.expect(CaptureUploadSupport.headerValue(forFileName: "Bildschirmfoto Ä 1%.png")
                == "Bildschirmfoto %C3%84 1%25.png"
                && CaptureUploadSupport.headerValue(forFileName: "a\r\nb.png") == "a%0D%0Ab.png",
               "a file name keeps its ASCII and percent-encodes the rest, line breaks included")
        var fresh = Destination.initial
        fresh.url = "https://example.com/u"
        suite.expect(CaptureUploadSupport.request(destination: fresh, kind: .recording,
                                                  contentLength: 1, fileName: "Recording 1.mp4")?
                .value(forHTTPHeaderField: "X-File-Name") == "Recording 1.mp4",
               "a fresh setup sends the file's name in X-File-Name")
        let named = Destination(url: "https://example.com/u",
                                queryItems: [Field(name: "name", value: "%filename%"),
                                             Field(name: "path", value: "shots/%FileName%")],
                                headers: [Field(name: "X-Name", value: "%filename%"),
                                          Field(name: "X-Path", value: "shots/%filename%"),
                                          Field(name: "%filename%", value: "kept")])
        let namedRequest = CaptureUploadSupport.request(destination: named, kind: .screenshot,
                                                        contentLength: 1,
                                                        fileName: "Bildschirmfoto Ä 1.png")
        suite.expect(namedRequest?.url?.absoluteString == "https://example.com/u"
                + "?name=Bildschirmfoto%20%C3%84%201.png&path=shots%2FBildschirmfoto%20%C3%84%201.png",
               "%filename% in a parameter value becomes the name, encoded like any value, whatever its case")
        suite.expect(namedRequest?.value(forHTTPHeaderField: "X-Name") == "Bildschirmfoto %C3%84 1.png"
                && namedRequest?.value(forHTTPHeaderField: "X-Path") == "shots/Bildschirmfoto %C3%84 1.png",
               "%filename% in a header value becomes the name, percent-encoded outside ASCII")
        suite.expect(namedRequest?.value(forHTTPHeaderField: "%filename%") == "kept",
               "a row's name is never expanded")
        let plain = Destination(url: "https://example.com/u")
        suite.expect(CaptureUploadSupport.request(destination: plain, kind: .screenshot,
                                                  contentLength: 1, fileName: "a.png")?
                .value(forHTTPHeaderField: "Content-Type") == "image/png"
                && CaptureUploadSupport.request(destination: plain, kind: .recording,
                                                contentLength: 1, fileName: "a.mp4")?
                .value(forHTTPHeaderField: "Content-Type") == "video/mp4",
               "a screenshot is sent as a PNG and a recording as an MP4")
        suite.expect(CaptureUploadSupport.request(destination: Destination(url: "https://example.com"),
                                                  kind: .screenshot, contentLength: 1,
                                                  fileName: "a.png")?
                .url?.absoluteString == "https://example.com",
               "an address without rows is sent as typed")
        suite.expect(CaptureUploadSupport.request(destination: Destination(url: "http://example.com/u"),
                                                  kind: .screenshot, contentLength: 1,
                                                  fileName: "a.png") == nil,
               "no request is built for an address an upload cannot use")
        let crowded = Destination(url: "https://example.com/u",
                                  queryItems: (0..<30).map { Field(name: "p\($0)", value: "\($0)") })
        suite.expect(CaptureUploadSupport.uploadURL(destination: crowded, fileName: "a.png")?.query?
                .components(separatedBy: "&").count == CaptureUploadSupport.maximumFields,
               "the rows a request carries are capped")
        suite.expect(!CaptureUploadSupport.isUsableHeaderName("Host")
                && !CaptureUploadSupport.isUsableHeaderName("x y")
                && !CaptureUploadSupport.isUsableHeaderName("")
                && CaptureUploadSupport.isUsableHeaderName(" X-Api-Key "),
               "the settings page flags the header names a request would leave out")

        // MARK: Picture

        func picture(width: Int, height: Int, translucentPixel: Bool) -> CGImage? {
            guard let context = CGContext(data: nil, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            for x in 0..<width {
                context.setFillColor(CGColor(red: CGFloat(x) / CGFloat(width), green: 0.4,
                                             blue: 1 - CGFloat(x) / CGFloat(width), alpha: 1))
                context.fill(CGRect(x: x, y: 0, width: 1, height: height))
            }
            if translucentPixel {
                context.clear(CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return context.makeImage()
        }
        func decoded(_ data: Data?) -> CGImage? {
            guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        /// Nil when there is no picture to look at, so a failed decode fails.
        func hasAlpha(_ image: CGImage?) -> Bool? {
            guard let alphaInfo = image?.alphaInfo else { return nil }
            switch alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast: return false
            default: return true
            }
        }
        if let opaque = picture(width: 64, height: 16, translucentPixel: false),
           let translucent = picture(width: 64, height: 16, translucentPixel: true) {
            let compact = ScreenshotRenderer.compactPNGData(from: opaque, scale: 2)
            let plain = ScreenshotRenderer.pngData(from: opaque, scale: 2)
            suite.expect(compact?.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) == true
                    && hasAlpha(decoded(compact)) == false && hasAlpha(decoded(plain)) == true
                    && (compact?.count ?? .max) <= (plain?.count ?? 0),
                   "an opaque screenshot uploads as a PNG without the alpha channel it never used")
            suite.expect(hasAlpha(decoded(ScreenshotRenderer.compactPNGData(from: translucent, scale: 2))) == true,
                   "a screenshot with a translucent pixel keeps its alpha channel")
        } else {
            suite.expect(false, "test pictures could be drawn")
        }

        // MARK: Reply

        func link(_ text: String) -> String? {
            CaptureUploadSupport.link(in: Data(text.utf8))?.absoluteString
        }
        suite.expect(link(#"{"url":"https://example.com/s/abc","id":"abc"}"#)
                == "https://example.com/s/abc",
               "a JSON reply with a url is the link")
        suite.expect(link(#"{"link":"https://example.com/s/abc"}"#) == "https://example.com/s/abc",
               "a JSON reply may call it link instead")
        suite.expect(link(#""https://example.com/s/abc""#) == "https://example.com/s/abc",
               "a JSON string on its own is the link")
        suite.expect(link("https://example.com/s/abc\n") == "https://example.com/s/abc",
               "a plain text reply that is nothing but a URL is the link")
        suite.expect(link(#"{"success":true,"data":{"fileId":"x","size":1,"sha256":"y","url":"https://example.com/f/x"}}"#)
                == "https://example.com/f/x",
               "a url inside a data object is found")
        suite.expect(link(#"{"meta":{"link":"https://example.com/deep"},"url":"https://example.com/top"}"#)
                == "https://example.com/top"
                && link(#"{"a":{"b":{"url":"https://example.com/deep"}},"data":{"url":"https://example.com/near"}}"#)
                == "https://example.com/near",
               "the link nearest the top of the reply wins")
        suite.expect(link(#"{"b":{"url":"https://example.com/b"},"a":{"url":"https://example.com/a"}}"#)
                == "https://example.com/a",
               "between siblings the first by name wins, whatever order the reply lists them")
        suite.expect(link(#"{"files":[{"url":"https://example.com/first"},{"url":"https://example.com/second"}]}"#)
                == "https://example.com/first",
               "a list of files gives its first link")
        suite.expect(link(#"{"data":{"URL":"https://example.com/x"}}"#) == "https://example.com/x",
               "a field name matches whatever its case")
        suite.expect(link(#"{"data":{"url":"not a link"},"url":"https://example.com/top"}"#)
                == "https://example.com/top"
                && link(#"{"data":{"url":"not a link"}}"#) == nil,
               "a url field that holds no address is passed over")
        func nested(_ depth: Int) -> String {
            String(repeating: #"{"a":"#, count: depth) + #"{"url":"https://example.com/x"}"#
                + String(repeating: "}", count: depth)
        }
        suite.expect(link(nested(CaptureUploadSupport.maximumLinkDepth - 1)) == "https://example.com/x"
                && link(nested(CaptureUploadSupport.maximumLinkDepth)) == nil,
               "the search stops at a fixed depth")
        for none in ["", "ok", #"{"url":5}"#, #"{"data":{"fileId":"x"}}"#, #"[1,2,3]"#,
                     "ftp://example.com/s/abc", "https://example.com/a b",
                     "saved https://example.com/s/abc"] {
            suite.expect(link(none) == nil, "a reply without a usable link yields none: \(none)")
        }
        suite.expect(CaptureUploadSupport.link(in: Data(
                repeating: UInt8(ascii: "a"),
                count: CaptureUploadSupport.maximumResponseBytes + 1)) == nil,
               "an oversized reply is not searched for a link")

        // MARK: Storage

        suite.expect(Destination.initial.encoded() == "" && Destination.decoded("") == .initial
                && Destination.decoded("not json") == .initial
                && Destination.initial.headers.map(\.name) == ["X-File-Name"]
                && Destination.initial.headers.map(\.value) == [CaptureUploadSupport.fileNamePlaceholder],
               "a fresh setup stores as the empty registered default and starts with an X-File-Name row")
        suite.expect(Destination().encoded() != ""
                && Destination.decoded(Destination().encoded()) == Destination(),
               "deleting the X-File-Name row is remembered rather than undone")
        suite.expect(Destination.decoded(destination.encoded()) == destination,
               "a destination survives the trip through its stored form")
        let handEdited = Destination.decoded(
            #"{"url":"https://example.com/u","headers":[{"name":"X-Api-Key","value":"k"}]}"#)
        suite.expect(handEdited.url == "https://example.com/u"
                && handEdited.headers.map(\.name) == ["X-Api-Key"]
                && handEdited.queryItems.isEmpty,
               "rows without ids and missing lists still read")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.captureUploadDestination] as? String == "",
               "the destination ships empty")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.captureUploadEnabled] as? Bool == false
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.captureUploadEnabled),
               "uploads ship switched off, and the switch travels in backups")
        let stored = Destination(url: "https://files.example.com/u").encoded()
        suite.expect(CaptureUploadSupport.host(raw: stored, enabled: true) == "files.example.com"
                && CaptureUploadSupport.host(raw: stored, enabled: false) == nil
                && CaptureUploadSupport.host(raw: "", enabled: true) == nil,
               "a button appears only while uploads are on and the address is usable")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.captureUploadCopyScreenshotLink] as? Bool == true
                && Defaults.registeredDefaults[DefaultsKey.captureUploadCopyRecordingLink] as? Bool == true,
               "an answered link is copied for both kinds until switched off")
        suite.expect(CaptureUploadSupport.Kind.screenshot.copyLinkDefaultsKey
                    == DefaultsKey.captureUploadCopyScreenshotLink
                && CaptureUploadSupport.Kind.recording.copyLinkDefaultsKey
                    == DefaultsKey.captureUploadCopyRecordingLink
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.captureUploadCopyScreenshotLink)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.captureUploadCopyRecordingLink),
               "each kind of upload has its own copy choice, and both travel in backups")

        // MARK: Backup

        let portable = CaptureUploadSupport.portable(destination)
        suite.expect(portable.url == "https://example.com/upload"
                && portable.headers.map(\.name) == destination.headers.map(\.name)
                && portable.queryItems.map(\.name) == destination.queryItems.map(\.name)
                && portable.headers.allSatisfy { $0.value.isEmpty }
                && portable.queryItems.allSatisfy { $0.value.isEmpty },
               "a backup carries the address and the names, not the values")
        let templated = Destination(url: "https://example.com/u",
                                    queryItems: [Field(name: "name", value: "%filename%")],
                                    headers: [Field(name: "X-File-Name", value: "%filename%"),
                                              Field(name: "Authorization", value: "Bearer %filename%")])
        suite.expect(CaptureUploadSupport.portable(templated).queryItems.map(\.value) == ["%filename%"]
                && CaptureUploadSupport.portable(templated).headers.map(\.value) == ["%filename%", ""],
               "a value that is only %filename% travels in a backup, and one that also holds text does not")
        let keyed = Destination(url: " https://user:pw@example.com/u?token=secret&dir=a#top ",
                                headers: [Field(name: "Authorization", value: "Bearer x")])
        suite.expect(CaptureUploadSupport.portable(keyed).url == "https://example.com/u"
                && CaptureUploadSupport.portable(Destination(url: "not an address")).url == "",
               "a backup leaves out the query and credentials an address carries")
        suite.expect(CaptureUploadSupport.restored(CaptureUploadSupport.portable(keyed), local: keyed)
                == keyed,
               "restoring on the same Mac gives the address its query back")
        suite.expect(CaptureUploadSupport.restored(
                CaptureUploadSupport.portable(keyed),
                local: Destination(url: "https://other.example.com/u?token=secret")).url
                == "https://example.com/u",
               "a query belongs to one server and is not carried to another address")
        let pasted = Destination(url: " https://example.com/u?token=a%20b&q=1+2&empty= ",
                                 queryItems: [Field(name: "kept", value: "1")])
        let lifted = CaptureUploadSupport.liftingAddressQuery(pasted)
        suite.expect(lifted?.url == "https://example.com/u"
                && lifted?.queryItems.map(\.name) == ["token", "q", "empty", "kept"]
                && lifted?.queryItems.map(\.value) == ["a b", "1 2", "", "1"],
               "a query pasted into the address becomes parameter rows ahead of the existing ones")
        let mixed = CaptureUploadSupport.liftingAddressQuery(
            Destination(url: "https://example.com/index.php?/api/upload&token=a&flag&=x&+=y&pad=+z&raw=%FF"))
        suite.expect(mixed?.url
                    == "https://example.com/index.php?/api/upload&flag&=x&+=y&pad=+z&raw=%FF"
                && mixed?.queryItems.map(\.name) == ["token"]
                && mixed.flatMap {
                    CaptureUploadSupport.uploadURL(destination: $0, fileName: "a.png")
                }?.query == "/api/upload&flag&=x&+=y&pad=+z&raw=%FF&token=a",
               "a query part that is not a name and value pair stays in the address as typed")
        suite.expect(CaptureUploadSupport.liftingAddressQuery(Destination(url: "https://example.com/u")) == nil
                && CaptureUploadSupport.liftingAddressQuery(Destination(url: "https://example.com/upload?abc123")) == nil
                && CaptureUploadSupport.liftingAddressQuery(Destination(url: "https://example.com/index.php?/api/upload")) == nil
                && CaptureUploadSupport.liftingAddressQuery(Destination(
                    url: "https://example.com/u?a=1",
                    queryItems: (0..<CaptureUploadSupport.maximumFields).map { Field(name: "p\($0)") })) == nil,
               "an address without a pair to move, or with more rows than fit, stays as typed")
        let oldToken = Field(name: " token ", value: "old")
        let replaced = CaptureUploadSupport.liftingAddressQuery(Destination(
            url: "https://example.com/u?token=new&dir=a",
            queryItems: [Field(name: "kept", value: "1"), oldToken,
                         Field(name: "token", value: "older")]))?.queryItems
        suite.expect(replaced?.map(\.name) == ["dir", "kept", " token "]
                && replaced?.map(\.value) == ["a", "1", "new"]
                && replaced?[2].id == oldToken.id,
               "a pasted name replaces the rows by that name where the first of them stands")
        let repeated = CaptureUploadSupport.liftingAddressQuery(Destination(
            url: "https://example.com/u?a=1&a=2",
            queryItems: [Field(name: "a", value: "old"), Field(name: "b", value: "2")]))?.queryItems
        suite.expect(repeated?.map(\.name) == ["a", "a", "b"]
                && repeated?.map(\.value) == ["1", "2", "2"],
               "a name pasted twice keeps both values in place of the old row")
        let full = (0..<CaptureUploadSupport.maximumFields).map { Field(name: "p\($0)", value: "old") }
        suite.expect(CaptureUploadSupport.liftingAddressQuery(Destination(
                    url: "https://example.com/u?p0=new", queryItems: full))?
                .queryItems.first?.value == "new",
               "replacing a row fits even when every row is taken")
        let bareKey = Destination(url: "https://example.com/upload?abc123")
        suite.expect(CaptureUploadSupport.portable(bareKey).url == "https://example.com/upload"
                && CaptureUploadSupport.portable(bareKey).queryItems.isEmpty
                && CaptureUploadSupport.restored(CaptureUploadSupport.portable(bareKey), local: bareKey)
                    == bareKey,
               "a bare key left in the address is kept out of backups and restored on the same Mac")
        let credentialed = Destination(url: "https://user:p%40ss@example.com/u")
        let basic = CaptureUploadSupport.request(destination: credentialed, kind: .screenshot,
                                                 contentLength: 1, fileName: "a.png")
        suite.expect(CaptureUploadSupport.liftingAddressQuery(credentialed) == nil
                && CaptureUploadSupport.host(raw: credentialed.encoded(), enabled: true) == "example.com"
                && basic?.url?.absoluteString == "https://example.com/u"
                && basic?.value(forHTTPHeaderField: "Authorization")
                    == "Basic " + Data("user:p@ss".utf8).base64EncodedString(),
               "a user name and password stay in the address and are sent as an Authorization: Basic header")
        suite.expect(CaptureUploadSupport.request(
                    destination: Destination(url: "https://:pw@example.com/"), kind: .screenshot,
                    contentLength: 1, fileName: "a.png")?.value(forHTTPHeaderField: "Authorization")
                    == "Basic " + Data(":pw".utf8).base64EncodedString()
                && CaptureUploadSupport.request(
                    destination: Destination(url: "https://@example.com/"), kind: .screenshot,
                    contentLength: 1, fileName: "a.png")?.value(forHTTPHeaderField: "Authorization") == nil,
               "a password alone is sent, and an empty user name sends no header")
        suite.expect(CaptureUploadSupport.request(
                    destination: Destination(url: "https://user:pw@example.com/",
                                             headers: [Field(name: "authorization", value: "Bearer x")]),
                    kind: .screenshot, contentLength: 1, fileName: "a.png")?
                .value(forHTTPHeaderField: "Authorization") == "Bearer x",
               "an Authorization row takes the place of the address's credentials, as in curl")
        suite.expect(CaptureUploadSupport.portable(.initial).encoded() == "",
               "an untouched setup backs up as the registered default")
        suite.expect(CaptureUploadSupport.restored(portable, local: destination) == destination,
               "restoring where the backup was written keeps the values already there")
        suite.expect(CaptureUploadSupport.restored(
                portable,
                local: Destination(url: "https://other.example.com/u",
                                   headers: destination.headers)) == portable,
               "a value belongs to one server and is not carried to another address")
        var edited = portable
        edited.headers[0].value = "Bearer newer"
        suite.expect(CaptureUploadSupport.restored(edited, local: destination)
                .headers[0].value == "Bearer newer",
               "a value the backup does carry wins over the local one")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.captureUploadDestination),
               "the upload destination travels with settings backup")
        let payload = SettingsBackupSupport.payload(appVersion: "test") { key in
            key == DefaultsKey.captureUploadDestination ? destination.encoded() : nil
        }
        let exported = (payload[SettingsBackupSupport.settingsKey] as? [String: Any])?[
            DefaultsKey.captureUploadDestination] as? String
        suite.expect(Destination.decoded(exported) == portable,
               "the exported file holds the portable destination")
        let imported = SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: SettingsBackupSupport.formatVersion,
            SettingsBackupSupport.settingsKey: [
                DefaultsKey.captureUploadDestination: destination.encoded(),
            ],
        ])?[DefaultsKey.captureUploadDestination] as? String
        suite.expect(Destination.decoded(imported) == portable,
               "a file that does carry values is imported without them")
        suite.expect(Destination.decoded(SettingsBackupSupport.restoredUploadDestination(
                restored: portable.encoded(), local: destination.encoded())) == destination
                && SettingsBackupSupport.restoredUploadDestination(
                    restored: nil, local: destination.encoded()) == "",
               "the restore keeps local values for the same server and clears when the file has none")

        // MARK: Settings

        suite.expect(SettingsSearchSupport.screenCaptureKeywords(Strings.enUS, language: .enUS)
                .contains(FeatureStrings.captureUpload(.enUS).sectionTitle),
               "the upload section is findable through Settings search")
        suite.expect(FeatureStrings.captureUpload(.enUS).menuItemFormat.contains("%@")
                && FeatureStrings.captureUpload(.enUS).rejectedFormat.contains("%d"),
               "the menu names the server and a refusal names the status")
    }
}

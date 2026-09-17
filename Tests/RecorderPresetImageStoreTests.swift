// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO

enum RecorderPresetImageStoreTests {
    static func run(expect: (Bool, String) -> Void) {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("recorder-preset-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }
        do {
            let sourceTake = RecorderTakeStore.Take(id: UUID(), folder: root.appendingPathComponent("source"))
            let targetTake = RecorderTakeStore.Take(id: UUID(), folder: root.appendingPathComponent("target"))
            try manager.createDirectory(at: sourceTake.folder, withIntermediateDirectories: true)
            try manager.createDirectory(at: targetTake.folder, withIntermediateDirectories: true)
            let originalURL = sourceTake.folder.appendingPathComponent("Logo.png ")
            guard let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = context.makeImage(),
                  let destination = CGImageDestinationCreateWithURL(originalURL as CFURL,
                                                                     "public.png" as CFString, 1, nil)
            else { expect(false, "preset image fixture can be created"); return }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                expect(false, "preset image fixture can be written")
                return
            }
            let bytes = try Data(contentsOf: originalURL)
            let overlay = RecorderImageOverlay(path: originalURL.path, start: 3, end: 4,
                                               anchor: .topTrailing, size: 0.31, opacity: 0.63)
            let store = RecorderPresetImageStore(directory: root.appendingPathComponent("presets"))
            guard let captured = store.capture([overlay]), captured.count == 1 else {
                expect(false, "preset captures its image independently")
                return
            }
            let storedURL = URL(fileURLWithPath: captured[0].path)
            expect(storedURL != originalURL && (try? Data(contentsOf: storedURL)) == bytes,
                   "saving a preset creates an independent image with identical pixels")
            expect(storedURL.lastPathComponent == originalURL.lastPathComponent,
                   "preset copies preserve the picked image's filename")
            let attributes = try manager.attributesOfItem(atPath: storedURL.path)
            expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                   "preset images are private files")

            let saved = RecorderEditPreset(name: "Corner logo",
                                           document: RecorderEditDocument(images: captured))
            let encoded = try JSONEncoder().encode([saved])
            let indexURL = root.appendingPathComponent("presets.json")
            try encoded.write(to: indexURL)
            RecorderTakeStore.shared.delete(sourceTake)
            let decoded = try JSONDecoder().decode([RecorderEditPreset].self,
                                                   from: Data(contentsOf: indexURL))[0]
            let reopened = RecorderPresetImageStore(directory: store.directory)
            guard let restored = reopened.restore(decoded.images ?? [], into: targetTake, duration: 37),
                  restored.count == 1 else {
                expect(false, "a reloaded preset restores its image after the original recording is gone")
                return
            }
            expect(restored[0].start == 0 && restored[0].end == 37,
                   "preset pictures span the whole destination video, not the original interval")
            expect(restored[0].anchor == .topTrailing && restored[0].size == 0.31
                    && restored[0].opacity == 0.63,
                   "preset image position, size and transparency survive save and reload")
            expect(restored[0].path != captured[0].path && restored[0].id != captured[0].id
                    && (try? Data(contentsOf: URL(fileURLWithPath: restored[0].path))) == bytes,
                   "each applied picture has its own identity and private copy for export and undo")
            let shorter = reopened.restore(decoded.images ?? [], into: targetTake, duration: 0.8)
            expect(shorter?.first?.start == 0 && shorter?.first?.end == 0.8,
                   "a picture from late in the original also appears in a much shorter video")

            var prepared = decoded
            prepared.images = restored
            let current = RecorderEditDocument(trimStart: 1, trimEnd: 8, keepsSystemAudio: false,
                                               texts: [RecorderTextOverlay(text: "Keep", start: 1, end: 3)])
            let applied = prepared.applying(to: current).sanitized(duration: 37)
            expect(applied.images == restored && applied.trimStart == 1 && applied.trimEnd == 8
                    && applied.texts == current.texts && !applied.keepsSystemAudio,
                   "applying preset images leaves cuts, captions and audio choices with the recording")
            expect(prepared.applying(to: applied).images.count == 1,
                   "reapplying a preset replaces its pictures instead of duplicating them")

            var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
            legacy.removeValue(forKey: "images")
            let oldPreset = try JSONDecoder().decode(RecorderEditPreset.self,
                from: JSONSerialization.data(withJSONObject: legacy))
            expect(oldPreset.images == nil && oldPreset.applying(to: applied).images == restored,
                   "presets saved before picture support still load and preserve existing pictures")
            expect(RecorderEditPreset(name: "No picture", document: RecorderEditDocument())
                .applying(to: applied).images.isEmpty,
                   "a newly saved image-free preset deliberately restores an image-free look")

            let backup = SettingsBackupSupport.payload(appVersion: "3.3.4") {
                $0 == DefaultsKey.recorderEditorPresets ? encoded : nil
            }
            let portableSettings = backup[SettingsBackupSupport.settingsKey] as? [String: Any]
            let portableData = portableSettings?[DefaultsKey.recorderEditorPresets] as? Data
            let portable = try portableData.map { try JSONDecoder().decode([RecorderEditPreset].self, from: $0) }
            expect(portable?.first?.id == saved.id && portable?.first?.images == nil,
                   "settings backups keep preset style without exporting local picture paths")
            if let portableData {
                let carried = SettingsBackupSupport.preservingLocalPresetImages(restored: portableData, local: encoded)
                expect(try JSONDecoder().decode([RecorderEditPreset].self, from: carried).first?.images == captured,
                       "restoring settings on this Mac keeps matching presets' private images")
                expect(SettingsBackupSupport.preservingLocalPresetImages(restored: portableData, local: nil)
                        == portableData,
                       "another Mac cannot acquire local image access from a settings backup")
            }

            let beforeFailure = try manager.contentsOfDirectory(atPath: targetTake.folder.path).sorted()
            var missing = captured[0]
            missing.path = storedURL.deletingLastPathComponent().appendingPathComponent("missing.png").path
            expect(reopened.restore([captured[0], missing], into: targetTake, duration: 5) == nil
                    && (try? manager.contentsOfDirectory(atPath: targetTake.folder.path).sorted()) == beforeFailure,
                   "a missing preset image rolls back partial copies without changing an existing edit")
            expect(reopened.restore([overlay], into: targetTake, duration: 5) == nil,
                   "a preset cannot import a path outside its private image store")
            let outside = root.appendingPathComponent("outside")
            try manager.createDirectory(at: outside, withIntermediateDirectories: true)
            try bytes.write(to: outside.appendingPathComponent("Logo.png"))
            let link = store.directory!.appendingPathComponent(UUID().uuidString)
            try manager.createSymbolicLink(at: link, withDestinationURL: outside)
            var escaped = captured[0]
            escaped.path = link.appendingPathComponent("Logo.png").path
            expect(reopened.restore([escaped], into: targetTake, duration: 5) == nil,
                   "a linked preset folder never imports images from outside the store")
            reopened.remove([escaped])
            expect(manager.fileExists(atPath: outside.appendingPathComponent("Logo.png").path),
                   "preset cleanup never follows a linked folder into somebody else's files")

            reopened.remove(captured)
            expect(!manager.fileExists(atPath: storedURL.path)
                    && (try? Data(contentsOf: URL(fileURLWithPath: restored[0].path))) == bytes,
                   "removing or replacing a preset leaves applied images available for export and undo")
            RecorderTakeStore.shared.delete(targetTake)
            expect(reopened.restore(captured, into: targetTake, duration: 5) == nil
                    && !manager.fileExists(atPath: targetTake.folder.path),
                   "an apply finishing after the editor closes never recreates its recording")
        } catch {
            expect(false, "preset image round-trip failed: \(error)")
        }
    }
}

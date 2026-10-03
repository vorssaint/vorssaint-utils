// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum GeminiLiveTests {
    static func run(_ suite: TestSuite) {
        suite.expect(GeminiLiveSupport.endpoint(apiKey: "  \n ") == nil,
                     "blank credentials cannot start a Gemini connection")
        let endpoint = GeminiLiveSupport.endpoint(apiKey: " key&extra=secret+/? ")!
        let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        suite.expect(components.host == "generativelanguage.googleapis.com"
                     && components.queryItems == [URLQueryItem(name: "key", value: "key&extra=secret+/?")],
                     "credential characters remain a single encoded query value")
        let setup = GeminiLiveSupport.setup["setup"] as! [String: Any]
        let realtime = setup["realtimeInputConfig"] as? [String: Any]
        let detection = realtime?["automaticActivityDetection"] as? [String: Bool]
        suite.expect(realtime?["activityHandling"] as? String == "START_OF_ACTIVITY_INTERRUPTS"
                     && detection?["disabled"] == false,
                     "speech detection is enabled and new speech interrupts the model response")
        suite.expect(setup["tools"] == nil && setup["thinkingConfig"] == nil,
                     "screen conversation does not grant computer-control tools or unsupported thinking config")
        let audio = Data([0, 0, 255, 127])
        let image = Data([255, 216, 255, 217])
        for (bytes, video, mime) in [(audio, false, "audio/pcm;rate=16000"), (image, true, "image/jpeg")] {
            let envelope = GeminiLiveSupport.realtime(bytes, video: video)["realtimeInput"] as! [String: Any]
            let blob = envelope[video ? "video" : "audio"] as! [String: String]
            suite.expect(blob["mimeType"] == mime && Data(base64Encoded: blob["data"]!) == bytes,
                         "real-time media preserves PCM or JPEG bytes with the correct format")
        }
        let content: [String: Any] = ["serverContent": [
            "inputTranscription": ["text": "What is this?"],
            "outputTranscription": ["text": "A red square."],
            "turnComplete": true,
            "modelTurn": ["parts": [
                ["text": "ignored reasoning"],
                ["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": audio.base64EncodedString()]],
                ["inlineData": ["mimeType": "image/jpeg", "data": image.base64EncodedString()]],
                ["inlineData": ["mimeType": "audio/pcm;rate=24000", "data": audio.base64EncodedString()]],
                ["inlineData": ["mimeType": "audio/pcm", "data": "not base64"]],
                ["inlineData": ["mimeType": "audio/pcm", "data": Data([1]).base64EncodedString()]]
            ]]
        ]]
        do {
            let event = try GeminiLiveSupport.decode(JSONSerialization.data(withJSONObject: content))
            suite.expect(event.audio == [audio, audio] && event.inputText == "What is this?"
                         && event.outputText == "A red square." && event.turnComplete,
                         "mixed server events deliver every audio part and both transcripts while rejecting malformed audio")
            var interrupted = content
            var turn = content["serverContent"] as! [String: Any]
            turn["interrupted"] = true
            interrupted["serverContent"] = turn
            let interruption = try GeminiLiveSupport.decode(JSONSerialization.data(withJSONObject: interrupted))
            suite.expect(interruption.interrupted && interruption.audio.isEmpty,
                         "interrupted events cannot revive discarded speech")
            let ready = try GeminiLiveSupport.decode(Data(#"{"setupComplete":{}}"#.utf8))
            let ended = try GeminiLiveSupport.decode(Data(#"{"goAway":{"timeLeft":"10s"}}"#.utf8))
            let failed = try GeminiLiveSupport.decode(Data(#"{"error":{"code":403}}"#.utf8))
            suite.expect(ready.ready && ended.ended && failed.failed,
                         "setup, connection expiry and API errors remain distinct lifecycle events")
        } catch { suite.expect(false, "valid Live API messages decode successfully") }
        do {
            _ = try GeminiLiveSupport.decode(Data("[]".utf8))
            suite.expect(false, "invalid server envelope is rejected")
        } catch { suite.expect(true, "invalid server envelope is rejected") }
        suite.expect(!AppFeature.geminiLive.installedByDefault
                     && AppFeature.geminiLive.permissions == [.screenRecording, .microphone]
                     && FeatureVisibilitySupport.features(for: .geminiLive) == [.geminiLive],
                     "Gemini is opt-in and its page and capture permissions follow feature availability")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.geminiLive(language)
            suite.expect(!strings.privacy.isEmpty && !strings.connectionFailed.isEmpty && !strings.microphoneDenied.isEmpty
                         && !strings.talk.isEmpty && !strings.end.isEmpty && !strings.listening.isEmpty
                         && !strings.ready.isEmpty,
                         "Gemini consent and errors cover \(language.rawValue)")
        }
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.panelUtilityGeminiLive),
                     "Gemini row visibility participates in portable settings")
    }
}

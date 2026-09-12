// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

// generate_sources.py appends these checks to the real HUD source. No panel is
// created: layout and animation configuration run on an offscreen content view.
extension QuitProtectionHUD {
    static func progressChecks(_ suite: TestSuite) {
        let content = ContentView(frame: CGRect(origin: .zero, size: minimumSize))
        let strings = FeatureStrings.quitProtection(.enUS)
        let title = String(format: strings.holdHUDFormat, "⌘Q")

        func layout(title: String, detail: String, progress: Bool) {
            content.update(title: title, detail: detail, showsProgress: progress)
            content.setFrameSize(fittingSize(content))
            content.layoutSubtreeIfNeeded()
        }

        layout(title: title, detail: strings.cancelHint, progress: false)
        let plainHeight = content.frame.height
        layout(title: title, detail: strings.cancelHint, progress: true)
        let labels = content.subviews.compactMap { $0 as? NSTextField }
        guard let textBottom = labels.map({ $0.frame.minY }).min(),
              let track = content.layer?.sublayers?.first(where: {
                  $0.frame.maxY < textBottom && !($0.sublayers ?? []).isEmpty
              }),
              let fill = track.sublayers?.first else {
            suite.expect(false, "hold confirmation has a progress track below its labels")
            return
        }
        suite.expect(!track.isHidden && content.frame.height > plainHeight,
                     "hold confirmation reserves visible space for progress")
        suite.expect(content.bounds.contains(track.frame) && track.bounds.contains(fill.frame),
                     "progress stays inside the HUD and its track")
        suite.expect(fill.anchorPoint.x == 0, "hold progress fills from the left edge")

        for milliseconds in [QuitProtectionSupport.holdDurationRange.lowerBound,
                             QuitProtectionSupport.defaultHoldDurationMilliseconds,
                             QuitProtectionSupport.holdDurationRange.upperBound] {
            layout(title: title, detail: strings.cancelHint, progress: true)
            let seconds = milliseconds / 1_000
            let deadline = Date().addingTimeInterval(seconds)
            content.animateProgress(until: deadline)
            let animations = (fill.animationKeys() ?? []).compactMap {
                fill.animation(forKey: $0) as? CABasicAnimation
            }
            guard let animation = animations.first(where: { $0.keyPath == "transform.scale.x" }) else {
                suite.expect(false, "a fresh hold animates its progress fill")
                continue
            }
            suite.expect(animation.duration >= deadline.timeIntervalSinceNow
                            && animation.duration <= seconds,
                         "progress uses the remaining confirmation deadline for \(milliseconds) ms")
            suite.expect((animation.fromValue as? NSNumber)?.doubleValue == 0
                            && (animation.toValue as? NSNumber)?.doubleValue == 1
                            && animation.timingFunction == CAMediaTimingFunction(name: .linear),
                         "hold progress advances linearly from empty to full")
            suite.expect(fill.transform.m11 == 1,
                         "the fill remains full when the animation completes")
            content.stopProgress()
            suite.expect(track.isHidden && (fill.animationKeys() ?? []).isEmpty,
                         "cancelling a hold hides progress and removes its animation")
        }

        layout(title: title, detail: strings.cancelHint, progress: true)
        content.animateProgress(until: Date().addingTimeInterval(2))
        layout(title: String(format: strings.doubleHUDFormat, "⌘Q"),
               detail: strings.cancelHint, progress: false)
        suite.expect(track.isHidden && (fill.animationKeys() ?? []).isEmpty
                        && content.frame.height == plainHeight,
                     "a non-hold prompt clears previous progress and restores its original height")

        for deadline in [nil, Date().addingTimeInterval(-1)] as [Date?] {
            layout(title: title, detail: strings.cancelHint, progress: deadline != nil)
            content.animateProgress(until: deadline)
            suite.expect((fill.animationKeys() ?? []).isEmpty,
                         "missing or expired deadlines do not start an animation")
        }

        for language in AppLanguage.allCases {
            let localized = FeatureStrings.quitProtection(language)
            layout(title: String(format: localized.holdHUDFormat, "⌘Q"),
                   detail: localized.cancelHint, progress: true)
            suite.expect(labels.allSatisfy { $0.frame.width >= $0.fittingSize.width },
                         "\(language.rawValue) hold labels fit their measured width")
            suite.expect(content.bounds.contains(track.frame)
                            && labels.allSatisfy { !track.frame.intersects($0.frame) },
                         "\(language.rawValue) progress fits without overlapping text")
        }
    }
}

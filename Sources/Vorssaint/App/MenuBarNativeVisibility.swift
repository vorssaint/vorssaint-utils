// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin

@objc private protocol MenuBarAssessment: AnyObject {
    @objc(activateWithConfiguration:completionHandler:)
    func activate(configuration: AnyObject, completion: @escaping (NSError?) -> Void)
    func invalidate()
}

/// macOS 27 no longer supports the off-screen status-item technique. Resolve
/// its visibility service at runtime so older systems never load the framework.
/// System items are always allowed; third-party controls are scoped by bundle.
final class MenuBarNativeVisibility {
    enum Failure: Error { case unavailable, activation, applicationLocation }
    private var active: MenuBarAssessment?
    private var pending: MenuBarAssessment?
    private var generation = 0
    private var hiddenBundles = Set<String>()
    private var timer: Timer?
    private var allowedBundles = Set<String>()
    private var menuBarOwners: [NSRunningApplication] = []

    private static let runtime: (NSObject.Type, NSObject.Type)? = {
        guard dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore",
                     RTLD_NOW | RTLD_LOCAL) != nil,
              let assertion = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type,
              let configuration = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
              assertion.instancesRespond(to: #selector(MenuBarAssessment.activate(configuration:completion:))),
              assertion.instancesRespond(to: #selector(MenuBarAssessment.invalidate)),
              configuration.instancesRespond(to: NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:"))
        else { return nil }
        return (assertion, configuration)
    }()

    func apply(hiddenBundles: Set<String>, menuBarOwners: [NSRunningApplication],
               completion: @escaping (Error?) -> Void) {
        self.menuBarOwners = menuBarOwners
        let running = Set((NSWorkspace.shared.runningApplications + menuBarOwners)
            .filter { !$0.isTerminated }.compactMap(\.bundleIdentifier))
        if hiddenBundles.isDisjoint(with: running) {
            release()
            completion(nil)
            return
        }
        // MenuBarAgent resolves allow-listed apps through LaunchServices. A
        // second build with the same bundle ID can hide even its own recovery
        // arrow when another installed copy is the registered application.
        guard let identifier = Bundle.main.bundleIdentifier,
              MenuBarItemSupport.canKeepRecoveryIcon(bundleURL: Bundle.main.bundleURL,
                  registeredURL: NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier))
        else { completion(Failure.applicationLocation); return }
        guard Self.runtime != nil else { completion(Failure.unavailable); return }
        self.hiddenBundles = hiddenBundles
        if active != nil, pending == nil, currentAllowedBundles() == allowedBundles {
            completion(nil)
            return
        }
        generation += 1
        activate(completion)
    }

    func release() {
        generation += 1
        timer?.invalidate()
        timer = nil
        pending?.invalidate()
        pending = nil
        active?.invalidate()
        active = nil
        hiddenBundles = []
        allowedBundles = []
        menuBarOwners = []
    }

    private func currentAllowedBundles() -> Set<String> {
        MenuBarOrganizerRules.allowedBundles(
            running: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)),
            menuBarOwners: Set(menuBarOwners.filter { !$0.isTerminated }.compactMap(\.bundleIdentifier)),
            hidden: hiddenBundles, ownBundleID: Bundle.main.bundleIdentifier ?? "com.vorssaint.utils")
    }

    private func activate(_ completion: @escaping (Error?) -> Void) {
        let allowed = currentAllowedBundles()
        guard let (assertionType, configurationType) = Self.runtime,
              let allocation = (configurationType as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let configuration = allocation.perform(
                NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:"),
                with: (0..<64).map { NSNumber(value: $0) } as NSArray,
                with: Array(allowed) as NSArray)?.takeRetainedValue()
        else { completion(Failure.unavailable); return }
        pending?.invalidate()
        let assertion = unsafeBitCast(assertionType.init(), to: MenuBarAssessment.self)
        pending = assertion
        let request = generation
        var finished = false
        func finish(_ error: Error?) {
            guard !finished else { return }
            finished = true
            guard self.generation == request, self.pending === assertion else {
                assertion.invalidate()
                return
            }
            self.pending = nil
            if let error {
                assertion.invalidate()
                completion(error)
            } else {
                let previous = self.active
                self.active = assertion
                self.allowedBundles = allowed
                previous?.invalidate()
                if self.timer == nil {
                    self.timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                        // Include newly launched apps instead of hiding unknown owners.
                        guard let self, self.pending == nil else { return }
                        let current = self.currentAllowedBundles()
                        if current != self.allowedBundles { self.activate { _ in } }
                    }
                }
                completion(nil)
            }
        }
        assertion.activate(configuration: configuration) { error in
            DispatchQueue.main.async { finish(error) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish(Failure.activation) }
    }

}

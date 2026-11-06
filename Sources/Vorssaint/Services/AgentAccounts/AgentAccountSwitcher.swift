// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Makes a saved login the one its provider's tool uses. Everything happens
/// on disk and in the Keychain, inside the provider's locks, and nothing
/// waits on the network: the tool's own sessions queue behind those locks.
struct AgentAccountSwitcher {
    enum Outcome: Equatable {
        case switched
        /// The tool already uses that login; nothing was written.
        case alreadyActive
    }

    enum SwitchFailure: Error, Equatable {
        /// The provider's tool held its locks the whole time.
        case busy
        /// The tool is signed in with something that has no plan to swap,
        /// such as an API key, which is not replaced.
        case unsupported
        /// A copy or the tool's own files could not be read or written; the
        /// text is for logs and support. Nothing changed, or it was put back.
        case copyUnavailable(String)
        case targetMissing
        /// The saved login is dead until the person signs in again.
        case needsLogin
    }

    let store: AgentAccountStore
    let adapters: [AgentProvider: AgentLoginAdapter]
    var now: () -> Date = Date.init

    func `switch`(to id: AgentAccount.ID) -> Result<Outcome, SwitchFailure> {
        guard let target = store.account(id), let adapter = adapters[target.provider] else { return .failure(.targetMissing) }
        if (try? adapter.readLive())?.id == id { return .success(.alreadyActive) }
        guard !target.needsLogin else { return .failure(.needsLogin) }
        do {
            return try adapter.withLocks {
                // Read again now that the tool cannot write: this is the
                // login to keep. A signed-out tool has none, so the swap
                // signs it in and no copy is touched.
                if let live = try adapter.readLive() {
                    if live.id == id { return .success(.alreadyActive) }
                    // The tool rotates its tokens while it runs. A copy from the
                    // day the login was saved would swap back to a dead one.
                    if store.account(live.id) != nil { try store.capture(live, now: now()) }
                }
                guard let copy = try store.credential(for: id) else {
                    return .failure(.copyUnavailable("the saved login has no copy"))
                }
                try adapter.activate(copy, identity: target.identity)
                return .success(.switched)
            }
        } catch AgentLoginError.busy {
            return .failure(.busy)
        } catch AgentLoginError.unsupported {
            return .failure(.unsupported)
        } catch AgentLoginError.unreadable(let message) {
            return .failure(.copyUnavailable(message))
        } catch {
            return .failure(.copyUnavailable("\(error)"))
        }
    }
}

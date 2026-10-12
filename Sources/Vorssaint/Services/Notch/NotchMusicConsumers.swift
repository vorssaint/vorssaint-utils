// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// A surface owns a demand, not the shared adapter's entire lifecycle.
/// Repeated syncs are idempotent, and closing one surface cannot stop another.
enum NotchMusicConsumer: Hashable { case island, lockScreen, dock }
struct NotchMusicConsumers {
    private(set) var owners = Set<NotchMusicConsumer>()
    mutating func acquire(_ owner: NotchMusicConsumer) { owners.insert(owner) }
    /// True exactly when the adapter no longer has a consumer.
    mutating func release(_ owner: NotchMusicConsumer) -> Bool { owners.remove(owner); return owners.isEmpty }
}

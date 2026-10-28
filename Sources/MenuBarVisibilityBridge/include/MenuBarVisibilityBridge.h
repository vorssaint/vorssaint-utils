// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Whether this macOS build exposes the menu bar assessment mode: the private
/// framework loads and both classes answer every selector the bridge sends.
BOOL VSMenuBarVisibilityAvailable(void);

/// Hides every menu bar item whose bundle or system item id is not listed.
/// `completion` always runs on the main queue, with either a handle that keeps
/// the restriction alive or an error. Both lists must be arrays; the system
/// raises on a set.
void VSMenuBarVisibilityActivate(NSArray<NSString *> *allowedBundles,
                                 NSArray<NSNumber *> *allowedSystemItems,
                                 void (^completion)(id _Nullable handle, NSError * _Nullable error));

/// Lifts the restriction a handle holds. Safe with any object and never raises.
void VSMenuBarVisibilityRelease(id handle);

NS_ASSUME_NONNULL_END

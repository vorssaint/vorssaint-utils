// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
BOOL VSMenuBarVisibilityAvailable(void);
void VSMenuBarVisibilityActivate(NSArray<NSString *> *allowedBundles, NSArray<NSNumber *> *allowedSystemItems,
    void (^completion)(id _Nullable handle, NSError * _Nullable error));
void VSMenuBarVisibilityRelease(id handle);
NS_ASSUME_NONNULL_END

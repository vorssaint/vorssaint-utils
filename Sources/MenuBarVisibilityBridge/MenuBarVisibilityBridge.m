// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
#import "include/MenuBarVisibilityBridge.h"
#import <dlfcn.h>
#import <objc/message.h>

// macOS 27 no longer supports oversized status-item spacers. Resolve the
// menu-bar-only visibility assertion at runtime; missing APIs fail open.
// This assertion also suppresses unallowlistable extras such as Focus.
// Explain this OS limitation in settings rather than impersonating their icons.
// API discovery: Hidden Bar's NativeVisibilityEngine (dwarvesf/hidden).
static NSError *unavailable(NSString *reason) {
    return [NSError errorWithDomain:@"Vorssaint.MenuBarOverflow" code:1
        userInfo:@{NSLocalizedDescriptionKey: reason}];
}
BOOL VSMenuBarVisibilityAvailable(void) {
    static void *framework;
    if (!framework) framework = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore", RTLD_LAZY | RTLD_LOCAL);
    Class config = NSClassFromString(@"MBAssessmentModeConfiguration");
    Class assertion = NSClassFromString(@"MBAssessmentModeAssertion");
    return framework && config && assertion
        && [config instancesRespondToSelector:NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:")]
        && [assertion instancesRespondToSelector:NSSelectorFromString(@"activateWithConfiguration:completionHandler:")]
        && [assertion instancesRespondToSelector:NSSelectorFromString(@"invalidate")];
}
void VSMenuBarVisibilityActivate(NSArray<NSString *> *allowedBundles, NSArray<NSNumber *> *allowedSystemItems,
    void (^completion)(id, NSError *)) {
    void (^finish)(id, NSError *) = ^(id handle, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(handle, error); });
    };
    if (!VSMenuBarVisibilityAvailable()) {
        finish(nil, unavailable(@"This macOS version does not provide menu bar hiding."));
        return;
    }
    @try {
        id config = ((id (*)(id, SEL, id, id))objc_msgSend)(
            [NSClassFromString(@"MBAssessmentModeConfiguration") alloc],
            NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:"),
            allowedSystemItems, allowedBundles);
        id handle = [[NSClassFromString(@"MBAssessmentModeAssertion") alloc] init];
        if (!config || !handle) {
            finish(nil, unavailable(@"Could not create the menu bar visibility control."));
            return;
        }
        ((void (*)(id, SEL, id, id))objc_msgSend)(handle,
            NSSelectorFromString(@"activateWithConfiguration:completionHandler:"), config,
            ^(NSError *error) {
                if (error) VSMenuBarVisibilityRelease(handle);
                finish(error ? nil : handle, error);
            });
    } @catch (NSException *exception) {
        finish(nil, unavailable(exception.reason ?: @"Menu bar hiding failed."));
    }
}
void VSMenuBarVisibilityRelease(id handle) {
    @try {
        SEL selector = NSSelectorFromString(@"invalidate");
        if ([handle respondsToSelector:selector])
            ((void (*)(id, SEL))objc_msgSend)(handle, selector);
    } @catch (NSException *exception) {
        NSLog(@"Vorssaint menu bar release: %@", exception.reason);
    }
}

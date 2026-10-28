// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
#import "include/MenuBarVisibilityBridge.h"
#import <dlfcn.h>
#import <objc/message.h>

// macOS 27 composites the menu bar in MenuBarAgent, so an oversized spacer
// item no longer pushes icons off screen. The only way left to hide them is
// the assessment mode in the private MenuBarClientCore framework. Everything
// is resolved at runtime and guarded, so a macOS build that renames or drops
// any part of it leaves the menu bar alone instead of crashing the app.

static NSString *const VSErrorDomain = @"Vorssaint.MenuBarVisibility";

static Class VSConfigurationClass;
static Class VSAssertionClass;
static SEL VSConfigureSelector;
static SEL VSActivateSelector;
static SEL VSInvalidateSelector;
static BOOL VSResolved;

static void VSResolve(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // The framework lives in the dyld shared cache; loading it by path
        // needs no entitlement.
        void *framework = dlopen(
            "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore",
            RTLD_LAZY | RTLD_LOCAL);
        if (framework == NULL) return;
        VSConfigurationClass = NSClassFromString(@"MBAssessmentModeConfiguration");
        VSAssertionClass = NSClassFromString(@"MBAssessmentModeAssertion");
        VSConfigureSelector = NSSelectorFromString(@"initWithAllowedSystemItems:allowedBundleIdentifiers:");
        VSActivateSelector = NSSelectorFromString(@"activateWithConfiguration:completionHandler:");
        VSInvalidateSelector = NSSelectorFromString(@"invalidate");
        VSResolved = VSConfigurationClass != Nil && VSAssertionClass != Nil
            && [VSConfigurationClass instancesRespondToSelector:VSConfigureSelector]
            && [VSAssertionClass instancesRespondToSelector:VSActivateSelector]
            && [VSAssertionClass instancesRespondToSelector:VSInvalidateSelector];
    });
}

static NSError *VSError(NSInteger code, NSString *reason) {
    return [NSError errorWithDomain:VSErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: reason}];
}

BOOL VSMenuBarVisibilityAvailable(void) {
    VSResolve();
    return VSResolved;
}

void VSMenuBarVisibilityActivate(NSArray<NSString *> *allowedBundles,
                                 NSArray<NSNumber *> *allowedSystemItems,
                                 void (^completion)(id _Nullable, NSError * _Nullable)) {
    // The system answers on a queue of its own, and may answer more than once
    // or after raising; the caller hears exactly one result, on the main queue.
    __block BOOL reported = NO;
    void (^report)(id, NSError *) = ^(id handle, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (reported) return;
            reported = YES;
            completion(handle, error);
        });
    };
    if (!VSMenuBarVisibilityAvailable()) {
        report(nil, VSError(1, @"This macOS version does not provide menu bar hiding."));
        return;
    }
    id assertion = nil;
    @try {
        id (*configure)(id, SEL, NSArray *, NSArray *) = (void *)objc_msgSend;
        id configuration = configure([VSConfigurationClass alloc], VSConfigureSelector,
                                     [allowedSystemItems copy], [allowedBundles copy]);
        assertion = [[VSAssertionClass alloc] init];
        if (configuration == nil || assertion == nil) {
            report(nil, VSError(2, @"Could not create the menu bar visibility control."));
            return;
        }
        id handle = assertion;
        void (*activate)(id, SEL, id, void (^)(NSError *)) = (void *)objc_msgSend;
        activate(assertion, VSActivateSelector, configuration, ^(NSError *error) {
            if (error) VSMenuBarVisibilityRelease(handle);
            report(error ? nil : handle, error);
        });
    } @catch (NSException *exception) {
        // A half-activated assertion must not outlive the failure.
        if (assertion) VSMenuBarVisibilityRelease(assertion);
        report(nil, VSError(3, exception.reason ?: @"Menu bar hiding failed."));
    }
}

void VSMenuBarVisibilityRelease(id handle) {
    VSResolve();
    if (handle == nil || VSInvalidateSelector == NULL) return;
    @try {
        if ([handle respondsToSelector:VSInvalidateSelector]) {
            void (*invalidate)(id, SEL) = (void *)objc_msgSend;
            invalidate(handle, VSInvalidateSelector);
        }
    } @catch (NSException *exception) {
        NSLog(@"Vorssaint menu bar visibility release: %@", exception.reason);
    }
}

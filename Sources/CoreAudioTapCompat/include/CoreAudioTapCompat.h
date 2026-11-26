// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#ifndef VORSSAINT_CORE_AUDIO_TAP_COMPAT_H
#define VORSSAINT_CORE_AUDIO_TAP_COMPAT_H

#import <Foundation/Foundation.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, VorssaintTapMode) {
    VorssaintTapModeStereoMixdown,
    VorssaintTapModeStereoGlobalExcluding,
    VorssaintTapModeDeviceStream,
};

// Early Sonoma lacks the Swift convenience initializers, even though the SDK
// marks them available in 14.0. Keep the class lookup and its ObjC messages
// inside the feature's 14.4 path so dyld can still load the executable.
static inline CATapDescription * _Nullable VorssaintPrivateTapDescription(
    VorssaintTapMode mode, NSArray<NSNumber *> *processes, NSString * _Nullable deviceUID,
    NSString * _Nullable name, CATapMuteBehavior muteBehavior)
    API_AVAILABLE(macos(14.4)) {
    Class tapClass = NSClassFromString(@"CATapDescription");
    CATapDescription *description = nil;
    switch (mode) {
        case VorssaintTapModeStereoMixdown:
            description = [[tapClass alloc] initStereoMixdownOfProcesses:processes];
            break;
        case VorssaintTapModeStereoGlobalExcluding:
            description = [[tapClass alloc] initStereoGlobalTapButExcludeProcesses:processes];
            break;
        case VorssaintTapModeDeviceStream:
            if (!deviceUID) return nil;
            description = [[tapClass alloc] initWithProcesses:processes andDeviceUID:deviceUID withStream:0];
            break;
    }

    if (name) description.name = name;
    description.privateTap = YES;
    description.muteBehavior = muteBehavior;
    return description;
}

static inline NSUUID * _Nullable VorssaintCreatePrivateTap(
    VorssaintTapMode mode, NSArray<NSNumber *> *processes, NSString * _Nullable deviceUID,
    NSString * _Nullable name, CATapMuteBehavior muteBehavior, AudioObjectID *tapID)
    NS_SWIFT_NAME(createPrivateAudioTap(_:processes:deviceUID:name:muteBehavior:id:))
    API_AVAILABLE(macos(14.4)) {
    CATapDescription *description = VorssaintPrivateTapDescription(mode, processes, deviceUID, name, muteBehavior);
    NSUUID *uuid = description.UUID;
    if (!uuid) return nil;
    AudioObjectID tap = kAudioObjectUnknown;
    if (AudioHardwareCreateProcessTap(description, &tap) != noErr || tap == kAudioObjectUnknown) return nil;
    *tapID = tap;
    return uuid;
}

/// Runs `block` inside an Objective-C `@try/@catch` and returns the exception
/// description if one was raised (for example `AVAudioEngine.inputNode`
/// throwing an NSException mid device-switch TOCTOU). Returns `nil` on success.
static inline NSString * _Nullable VorssaintCatchNSException(void (NS_NOESCAPE ^block)(void))
    NS_SWIFT_NAME(catchNSException(_:)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return exception.description ?: exception.name;
    }
}

NS_ASSUME_NONNULL_END

#endif

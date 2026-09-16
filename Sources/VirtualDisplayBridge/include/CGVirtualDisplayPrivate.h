// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// CGVirtualDisplayPrivate.h
// Vorssaint / VirtualDisplayBridge
//
// Private API declarations for Apple CoreGraphics CGVirtualDisplay functionality.
// Provides virtual screen / dummy display creation on macOS without external kernel extensions.
//

#ifndef CGVirtualDisplayPrivate_h
#define CGVirtualDisplayPrivate_h

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class CGVirtualDisplayDescriptor;

/// Represents a display mode configuration for the virtual display
@interface CGVirtualDisplayMode : NSObject

@property(readonly, nonatomic) CGFloat refreshRate;
@property(readonly, nonatomic) NSUInteger width;
@property(readonly, nonatomic) NSUInteger height;

- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(CGFloat)refreshRate;

@end

/// Settings that can be applied to a virtual display
@interface CGVirtualDisplaySettings : NSObject

@property(retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property(nonatomic) unsigned int hiDPI;

- (instancetype)init;

@end

/// The main virtual display object
@interface CGVirtualDisplay : NSObject

@property(readonly, nonatomic) NSArray *modes;
@property(readonly, nonatomic) unsigned int hiDPI;
@property(readonly, nonatomic) CGDirectDisplayID displayID;
@property(readonly, nonatomic, nullable) id terminationHandler;
@property(readonly, nonatomic, nullable) dispatch_queue_t queue;
@property(readonly, nonatomic) unsigned int maxPixelsHigh;
@property(readonly, nonatomic) unsigned int maxPixelsWide;
@property(readonly, nonatomic) CGSize sizeInMillimeters;
@property(readonly, nonatomic, nullable) NSString *name;
@property(readonly, nonatomic) unsigned int serialNum;
@property(readonly, nonatomic) unsigned int productID;
@property(readonly, nonatomic) unsigned int vendorID;

- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;

@end

/// Configuration descriptor for creating a virtual display
@interface CGVirtualDisplayDescriptor : NSObject

@property(retain, nonatomic, nullable) dispatch_queue_t queue;
@property(retain, nonatomic, nullable) NSString *name;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;
@property(copy, nonatomic, nullable) void (^terminationHandler)(id, CGVirtualDisplay*);

- (instancetype)init;
- (nullable dispatch_queue_t)dispatchQueue;
- (void)setDispatchQueue:(dispatch_queue_t)queue;

@end

NS_ASSUME_NONNULL_END

#endif /* CGVirtualDisplayPrivate_h */

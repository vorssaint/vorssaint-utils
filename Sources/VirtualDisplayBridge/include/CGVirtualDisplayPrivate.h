// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

#ifndef CGVirtualDisplayPrivate_h
#define CGVirtualDisplayPrivate_h

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class CGVirtualDisplayDescriptor;

@interface CGVirtualDisplayMode : NSObject
@property(readonly, nonatomic) double refreshRate;
@property(readonly, nonatomic) unsigned int width;
@property(readonly, nonatomic) unsigned int height;
- (instancetype)initWithWidth:(unsigned int)width
                       height:(unsigned int)height
                  refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property(strong, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property(nonatomic) unsigned int hiDPI;
@property(nonatomic) unsigned int rotation;
- (instancetype)init;
@end

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
@property(readonly, nonatomic) unsigned int serialNumber;
@property(readonly, nonatomic) unsigned int productID;
@property(readonly, nonatomic) unsigned int vendorID;
- (nullable instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property(strong, nonatomic, nullable) dispatch_queue_t queue;
@property(strong, nonatomic, nullable) NSString *name;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int serialNumber;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;
@property(copy, nonatomic, nullable) void (^terminationHandler)(id, CGVirtualDisplay *);
- (instancetype)init;
- (nullable dispatch_queue_t)dispatchQueue;
- (void)setDispatchQueue:(dispatch_queue_t)queue;
@end

NS_ASSUME_NONNULL_END
#endif

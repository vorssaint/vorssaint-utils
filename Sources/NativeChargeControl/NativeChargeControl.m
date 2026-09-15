// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "NativeChargeControl.h"

// Runtime-checked private PowerUI interface. All calls are serialized by the
// app's charge-control probe queue; unsupported systems fail closed.
@interface NSObject (VSNativeChargeControl)
- (id)initWithClientName:(NSString *)name;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (NSArray *)availableChargeLimitsWithError:(NSError **)error;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
@end

static id VSClient(void) {
    static id client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_LAZY)) return;
        Class cls=NSClassFromString(@"PowerUISmartChargeClient");
        if (![cls instancesRespondToSelector:@selector(initWithClientName:)] ||
            ![cls instancesRespondToSelector:@selector(getMCLLimitWithError:)] ||
            ![cls instancesRespondToSelector:@selector(availableChargeLimitsWithError:)] ||
            ![cls instancesRespondToSelector:@selector(setMCLLimit:error:)]) return;
        client=[[cls alloc] initWithClientName:@"com.vorssaint.charge-control"];
    });
    return client;
}

int VSNativeChargeLimit(void) { @autoreleasepool {
    id client=VSClient();
    if (!client) return -1;
    NSError *error=nil;
    unsigned char limit=[client getMCLLimitWithError:&error];
    return error || limit < 80 || limit > 100 ? -1 : limit;
} }

bool VSNativeSetChargeLimit(int percent) { @autoreleasepool {
    id client=VSClient();
    if (!client || percent < 80 || percent > 100) return false;
    NSError *error=nil;
    NSArray *limits=[client availableChargeLimitsWithError:&error];
    if (error || ![limits containsObject:@(percent)]) return false;
    int current=VSNativeChargeLimit();
    if (current < 0) return false;
    if (current == percent) return true;
    // PowerUI can retain a lower drain target while the adapter is inhibited.
    // Release that token once when raising the cap, before installing the new
    // target. Never repeat this for an unchanged request or a lower target.
    if (current < percent && percent < 100) {
        if (![client setMCLLimit:100 error:&error] || error) return false;
    }
    if (![client setMCLLimit:(unsigned char)percent error:&error] || error) return false;
    return VSNativeChargeLimit() == percent;
} }

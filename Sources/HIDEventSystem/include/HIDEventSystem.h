#include <IOKit/hid/IOHIDUsageTables.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/hidsystem/IOHIDServiceClient.h>

// Temperature events are exported by IOKit but absent from the public SDK.
typedef struct CF_BRIDGED_TYPE(id) __IOHIDEvent *IOHIDEventRef;
IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator) CF_RETURNS_RETAINED;
void IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type,
                                        int32_t options, int64_t timeout) CF_RETURNS_RETAINED;
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

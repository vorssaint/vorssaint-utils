// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint Audio contributors
// GPL BlackHole supplies the HAL object and loopback implementation.
#define kDriver_Name "VorssaintAudio"
#define kHas_Driver_Name_Format false
#define kDevice_Name "Vorssaint Audio"
#define kPlugIn_BundleID "com.vorssaint.utils.software-volume.driver"
#define kPlugIn_Icon "AppIcon.icns"
#define kManufacturer_Name "Vorssaint Audio"
#define kDevice_HasInput false
#define kDevice_HasOutput true
#define kDevice2_Name "Vorssaint Audio Loopback"
#define kDevice2_IsHidden true
#define kDevice2_HasInput false
#define kDevice2_HasOutput false
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-extra-args"
#include "../../ThirdParty/BlackHole/BlackHole.c"
#pragma clang diagnostic pop
#include <signal.h>
#include <errno.h>
#include <time.h>
#include "CallerTrust.h"
#include "../SoftwareVolumePCM/PCM.h"
static VSQueue afPCM;
static _Atomic uint64_t afGeneration=1;
static uint8_t afCapability[32];

static pthread_mutex_t afOwnerMutex = PTHREAD_MUTEX_INITIALIZER;
static pid_t afOwner = 0;
static double afHeartbeat = 0;
static dispatch_source_t afWatchdog;
static double VorssaintAudioNow(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC_RAW, &now);
    return now.tv_sec + now.tv_nsec / 1e9;
}
static Boolean afCustom(AudioObjectID object, const AudioObjectPropertyAddress *address) {
    return object == kObjectID_Device && address
        && address->mScope == kAudioObjectPropertyScopeGlobal
        && address->mElement == kAudioObjectPropertyElementMain
        && (address->mSelector == 'vown' || address->mSelector == 'vact' || address->mSelector == 'vpcm' || address->mSelector == 'vkey');
}
static Boolean afDeviceList(AudioObjectID object, const AudioObjectPropertyAddress *address) {
    return address && ((object==kObjectID_PlugIn && address->mSelector==kAudioPlugInPropertyDeviceList)
        || (object==kObjectID_Box && address->mSelector==kAudioBoxPropertyDeviceList));
}
static Boolean afInfo(AudioObjectID object, const AudioObjectPropertyAddress *address) {
    return object == kObjectID_Device && address
        && address->mScope == kAudioObjectPropertyScopeGlobal
        && address->mSelector == kAudioObjectPropertyCustomPropertyInfoList;
}
static const AudioServerPlugInCustomPropertyInfo afProperties[] = {
    {'vown', kAudioServerPlugInCustomPropertyDataTypeCFPropertyList, kAudioServerPlugInCustomPropertyDataTypeNone},
    {'vact', kAudioServerPlugInCustomPropertyDataTypeCFPropertyList, kAudioServerPlugInCustomPropertyDataTypeNone},
    {'vpcm', kAudioServerPlugInCustomPropertyDataTypeCFPropertyList, kAudioServerPlugInCustomPropertyDataTypeCFPropertyList},
    {'vkey', kAudioServerPlugInCustomPropertyDataTypeCFPropertyList, kAudioServerPlugInCustomPropertyDataTypeNone}
};
static Boolean afIsActive(void) {
    pthread_mutex_lock(&afOwnerMutex);
    Boolean active = afOwner > 0;
    pthread_mutex_unlock(&afOwnerMutex);
    return active;
}
static void afNotify(void) {
    if (!gPlugIn_Host) return;
    AudioObjectPropertyAddress changes[] = {
        {'vact', kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
        {kAudioDevicePropertyIsHidden, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
        {kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain},
        {kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain},
        {kAudioDevicePropertyDeviceCanBeDefaultSystemDevice, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain}
    };
    gPlugIn_Host->PropertiesChanged(gPlugIn_Host, kObjectID_Device, 5, changes);

    AudioObjectPropertyAddress devices = {kAudioPlugInPropertyDeviceList, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    gPlugIn_Host->PropertiesChanged(gPlugIn_Host, kObjectID_PlugIn, 1, &devices);
}
static void VorssaintAudioExpireOwner(double now) {
    pthread_mutex_lock(&afOwnerMutex);
    Boolean expired = afOwner > 0 && (now-afHeartbeat > 5 || (kill(afOwner,0) != 0 && errno == ESRCH));
    if (expired) { afOwner = 0; afHeartbeat = 0; afGeneration++; memset(afCapability,0,sizeof(afCapability));vs_ack(&afPCM,vs_written(&afPCM)); }
    pthread_mutex_unlock(&afOwnerMutex);
    if (expired) afNotify();
}
static OSStatus AFInitialize(AudioServerPlugInDriverRef driver, AudioServerPlugInHostRef host) {
    OSStatus result = BlackHole_Initialize(driver,host);
    afLoadCallerRequirement();
    if (result == noErr && !afWatchdog) {
        gBox_Name = CFSTR("Vorssaint Audio");
        afWatchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
        dispatch_source_set_timer(afWatchdog,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC,NSEC_PER_SEC/10);
        dispatch_source_set_event_handler(afWatchdog,^{ VorssaintAudioExpireOwner(VorssaintAudioNow()); });
        dispatch_resume(afWatchdog);
    }
    return result;
}
static Boolean AFHas(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t pid, const AudioObjectPropertyAddress *address) {
    if (driver != gAudioServerPlugInDriverRef || !address) return false;
    return afInfo(object,address) || afCustom(object,address) || BlackHole_HasProperty(driver,object,pid,address);
}
static OSStatus AFSettable(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t pid, const AudioObjectPropertyAddress *address, Boolean *value) {
    if (driver != gAudioServerPlugInDriverRef || !value || !address) return kAudioHardwareIllegalOperationError;
    if (afInfo(object,address)) { *value=false; return noErr; }
    if (afCustom(object,address)) { *value=address->mSelector=='vown'; return noErr; }
    return BlackHole_IsPropertySettable(driver,object,pid,address,value);
}
static OSStatus AFSize(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t pid, const AudioObjectPropertyAddress *address, UInt32 qualifierSize, const void *qualifier, UInt32 *size) {
    if (driver != gAudioServerPlugInDriverRef || !size || !address) return kAudioHardwareIllegalOperationError;
    if (afDeviceList(object,address)) { *size=gBox_Acquired ? sizeof(AudioObjectID):0;return noErr; }
    if (afInfo(object,address)) { *size=sizeof(afProperties); return noErr; }
    if (afCustom(object,address)) { *size=sizeof(CFPropertyListRef); return noErr; }
    return BlackHole_GetPropertyDataSize(driver,object,pid,address,qualifierSize,qualifier,size);
}
static OSStatus AFGet(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t pid, const AudioObjectPropertyAddress *address, UInt32 qualifierSize, const void *qualifier, UInt32 capacity, UInt32 *size, void *data) {
    if (driver != gAudioServerPlugInDriverRef || !data || !size || !address) return kAudioHardwareIllegalOperationError;
    if (afDeviceList(object,address)) {
        *size=gBox_Acquired && capacity>=sizeof(AudioObjectID) ? sizeof(AudioObjectID):0;
        if(*size) *(AudioObjectID*)data=kObjectID_Device;return noErr;
    }
    if (afInfo(object,address)) {
        if (capacity < sizeof(afProperties)) return kAudioHardwareBadPropertySizeError;
        memcpy(data,afProperties,sizeof(afProperties)); *size=sizeof(afProperties); return noErr;
    }
    if (afCustom(object,address) && address->mSelector=='vkey') {
        if(capacity<sizeof(CFPropertyListRef))return kAudioHardwareBadPropertySizeError;
        if(!afCallerTrusted(pid))return kAudioDevicePermissionsError;
        pthread_mutex_lock(&afOwnerMutex);
        if(pid<=0 || pid!=afOwner) {pthread_mutex_unlock(&afOwnerMutex);return kAudioDevicePermissionsError;}
        CFDataRef key=CFDataCreate(NULL,afCapability,sizeof(afCapability));
        pthread_mutex_unlock(&afOwnerMutex);
        if(!key)return kAudioHardwareUnspecifiedError;
        *(CFPropertyListRef*)data=key;*size=sizeof(CFPropertyListRef);return noErr;
    }
    if (afCustom(object,address) && address->mSelector=='vpcm') {
        if (capacity<sizeof(CFPropertyListRef) || qualifierSize!=sizeof(CFPropertyListRef) || !qualifier) return kAudioHardwareBadPropertySizeError;
        CFPropertyListRef payload=*(const CFPropertyListRef*)qualifier;
        if(!payload || CFGetTypeID(payload)!=CFDataGetTypeID() || CFDataGetLength(payload)!=sizeof(VSRequest)) return kAudioHardwareIllegalOperationError;
        VSRequest request;memcpy(&request,CFDataGetBytePtr(payload),sizeof(request));
        if(request.magic!=VS_MAGIC || request.version!=VS_VERSION || request.maxFrames>VS_PACKET_FRAMES || request.reserved) return kAudioHardwareIllegalOperationError;
        pthread_mutex_lock(&afOwnerMutex);
        unsigned difference=0;for(unsigned i=0;i<32;i++)difference|=request.key[i]^afCapability[i];
        if(pid<=0 || pid!=afOwner || difference) {pthread_mutex_unlock(&afOwnerMutex);return kAudioHardwareIllegalOperationError;}
        uint64_t cursor=request.cursor;
        if(!request.generation && !request.maxFrames) {cursor=vs_written(&afPCM);vs_ack(&afPCM,cursor);}
        else if(request.generation!=afGeneration || !vs_ack(&afPCM,cursor)) {pthread_mutex_unlock(&afOwnerMutex);return kAudioHardwareIllegalOperationError;}
        VSPacket packet={.magic=VS_MAGIC,.version=VS_VERSION,.channels=2,.generation=afGeneration,.cursor=cursor,.nonce=request.nonce};
        pthread_mutex_lock(&gPlugIn_StateMutex);
        packet.rate=gDevice_SampleRate;packet.gain=atomic_load(&gVolume_Master_Value);packet.muted=gMute_Master_Value;
        pthread_mutex_unlock(&gPlugIn_StateMutex);
        float samples[VS_PACKET_FRAMES*2];packet.frames=vs_copy_generation(&afPCM,cursor,samples,request.maxFrames,packet.generation);packet.next=cursor+packet.frames;
        CFMutableDataRef response=CFDataCreateMutable(NULL,sizeof(packet)+packet.frames*8);
        if(response) {CFDataAppendBytes(response,(const UInt8*)&packet,sizeof(packet));CFDataAppendBytes(response,(const UInt8*)samples,packet.frames*8);}
        pthread_mutex_unlock(&afOwnerMutex);
        if(!response) return kAudioHardwareUnspecifiedError;
        *(CFPropertyListRef*)data=response;*size=sizeof(CFPropertyListRef);return noErr;
    }
    if (afCustom(object,address)) {
        if (capacity < sizeof(CFPropertyListRef)) return kAudioHardwareBadPropertySizeError;
        *(CFPropertyListRef*)data=CFRetain(afIsActive() ? kCFBooleanTrue : kCFBooleanFalse);
        *size=sizeof(CFPropertyListRef); return noErr;
    }
    Boolean isDevice=object==kObjectID_Device || object==kObjectID_Device2;
    Boolean state = isDevice && (address->mSelector==kAudioDevicePropertyIsHidden || address->mSelector==kAudioDevicePropertyDeviceIsAlive
        || address->mSelector==kAudioDevicePropertyDeviceCanBeDefaultDevice || address->mSelector==kAudioDevicePropertyDeviceCanBeDefaultSystemDevice);
    if (state) {
        if (capacity<sizeof(UInt32)) return kAudioHardwareBadPropertySizeError;
        UInt32 active=afIsActive();
        if ((address->mSelector==kAudioDevicePropertyDeviceCanBeDefaultDevice
            || address->mSelector==kAudioDevicePropertyDeviceCanBeDefaultSystemDevice)
            && (object!=kObjectID_Device || address->mScope!=kAudioObjectPropertyScopeOutput)) active=0;
        *(UInt32*)data=address->mSelector==kAudioDevicePropertyIsHidden ? (object==kObjectID_Device2 || !active) : active;
        *size=sizeof(UInt32); return noErr;
    }
    return BlackHole_GetPropertyData(driver,object,pid,address,qualifierSize,qualifier,capacity,size,data);
}
static OSStatus AFSet(AudioServerPlugInDriverRef driver, AudioObjectID object, pid_t pid, const AudioObjectPropertyAddress *address, UInt32 qualifierSize, const void *qualifier, UInt32 size, const void *data) {
    if (driver != gAudioServerPlugInDriverRef || !data || !address) return kAudioHardwareIllegalOperationError;
    if (afCustom(object,address)) {
        if (address->mSelector!='vown') return kAudioHardwareIllegalOperationError;
        if (size!=sizeof(CFPropertyListRef)) return kAudioHardwareBadPropertySizeError;
        CFPropertyListRef payload=*(const CFPropertyListRef*)data;
        if (!payload || CFGetTypeID(payload)!=CFBooleanGetTypeID() || pid<=0) return kAudioHardwareIllegalOperationError;
        UInt32 value=CFBooleanGetValue(payload);
        if(value && !afCallerTrusted(pid)) return kAudioDevicePermissionsError;
        VorssaintAudioExpireOwner(VorssaintAudioNow());
        pthread_mutex_lock(&afOwnerMutex);
        if (afOwner && afOwner!=pid) { pthread_mutex_unlock(&afOwnerMutex); return kAudioHardwareIllegalOperationError; }
        Boolean changed=(afOwner>0)!=value;
        if(changed) {afGeneration++;if(value)arc4random_buf(afCapability,sizeof(afCapability));else memset(afCapability,0,sizeof(afCapability));vs_ack(&afPCM,vs_written(&afPCM));}
        afOwner=value ? pid : 0; afHeartbeat=value ? VorssaintAudioNow() : 0;
        pthread_mutex_unlock(&afOwnerMutex);
        if (changed) afNotify();
        return noErr;
    }
    // Upstream's conversions accept NaN; reject malformed control writes.
    if ((object==kObjectID_Volume_Output_Master || object==kObjectID_Volume_Input_Master)
        && (address->mSelector==kAudioLevelControlPropertyScalarValue || address->mSelector==kAudioLevelControlPropertyDecibelValue)) {
        if (size!=sizeof(Float32)) return kAudioHardwareBadPropertySizeError;
        if (!isfinite(*(const Float32*)data)) return kAudioHardwareIllegalOperationError;
    }
    return BlackHole_SetPropertyData(driver,object,pid,address,qualifierSize,qualifier,size,data);
}
static OSStatus AFWillDoIO(AudioServerPlugInDriverRef driver, AudioObjectID object, UInt32 client, UInt32 operation, Boolean *willDo, Boolean *inPlace) {
    if ((operation==kAudioServerPlugInIOOperationReadInput)
        || (object==kObjectID_Device2 && operation==kAudioServerPlugInIOOperationWriteMix)) {
        if (willDo) *willDo=false;
        if (inPlace) *inPlace=true;
        return noErr;
    }
    return BlackHole_WillDoIOOperation(driver,object,client,operation,willDo,inPlace);
}
static OSStatus AFDoIO(AudioServerPlugInDriverRef driver, AudioObjectID object, AudioObjectID stream, UInt32 client, UInt32 operation, UInt32 frames, const AudioServerPlugInIOCycleInfo *cycle, void *main, void *secondary) {
    if ((operation==kAudioServerPlugInIOOperationReadInput && object!=kObjectID_Device2)
        || (operation==kAudioServerPlugInIOOperationWriteMix && object!=kObjectID_Device)) return kAudioHardwareIllegalOperationError;
    if(operation==kAudioServerPlugInIOOperationReadInput) return kAudioHardwareIllegalOperationError;
    if(operation==kAudioServerPlugInIOOperationWriteMix) {
        if(driver!=gAudioServerPlugInDriverRef || !main || frames>VS_CAPACITY) return kAudioHardwareIllegalOperationError;
        vs_write_generation(&afPCM,main,frames,atomic_load_explicit(&afGeneration,memory_order_acquire));return noErr;
    }
    return BlackHole_DoIOOperation(driver,object,stream,client,operation,frames,cycle,main,secondary);
}
void *VorssaintAudio_Create(CFAllocatorRef allocator, CFUUIDRef type) {
    gAudioServerPlugInDriverInterface.Initialize=AFInitialize;
    gAudioServerPlugInDriverInterface.HasProperty=AFHas;
    gAudioServerPlugInDriverInterface.IsPropertySettable=AFSettable;
    gAudioServerPlugInDriverInterface.GetPropertyDataSize=AFSize;
    gAudioServerPlugInDriverInterface.GetPropertyData=AFGet;
    gAudioServerPlugInDriverInterface.SetPropertyData=AFSet;
    gAudioServerPlugInDriverInterface.WillDoIOOperation=AFWillDoIO;
    gAudioServerPlugInDriverInterface.DoIOOperation=AFDoIO;
    return BlackHole_Create(allocator,type);
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint Audio contributors
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <unistd.h>
#if __has_include("../Sources/SoftwareVolumeDriver/Driver.c")
#include "../Sources/SoftwareVolumeDriver/Driver.c"
#define CreateDriver VorssaintAudio_Create
#else
#include "../ThirdParty/BlackHole/BlackHole.c"
#define CreateDriver BlackHole_Create
#endif
static int failures = 0, checks = 0;
#define CHECK(test) do { checks++; if (!(test)) { fprintf(stderr,"FAIL %d: %s\n", __LINE__, #test); failures++; } } while (0)
static OSStatus changed(AudioServerPlugInHostRef host, AudioObjectID object, UInt32 count, const AudioObjectPropertyAddress addresses[]) { return noErr; }
static AudioServerPlugInHostInterface host = { .PropertiesChanged = changed };
static AudioObjectPropertyAddress prop(UInt32 selector) { return (AudioObjectPropertyAddress){selector,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain}; }
static OSStatus get32(AudioServerPlugInDriverRef driver, AudioObjectID object, UInt32 selector, UInt32 *value) {
 AudioObjectPropertyAddress address=prop(selector); UInt32 size=0;
 if (selector=='vact' || selector=='vown') {
  CFPropertyListRef payload=NULL;
  OSStatus status=(*driver)->GetPropertyData(driver,object,getpid(),&address,0,NULL,sizeof(payload),&size,&payload);
  if (status==noErr && payload) { *value=CFBooleanGetValue(payload); CFRelease(payload); }
  return status;
 }
 return (*driver)->GetPropertyData(driver,object,getpid(),&address,0,NULL,sizeof(*value),&size,value);
}
static OSStatus owner(AudioServerPlugInDriverRef driver, pid_t pid, UInt32 value, UInt32 size) {
 AudioObjectPropertyAddress address=prop('vown');
 CFPropertyListRef payload=value==0 ? kCFBooleanFalse : value==1 ? (CFPropertyListRef)kCFBooleanTrue : (CFPropertyListRef)CFNumberCreate(NULL,kCFNumberSInt32Type,&value);
 OSStatus status=(*driver)->SetPropertyData(driver,kObjectID_Device,pid,&address,0,NULL,size,&payload);
 if (value>1) CFRelease(payload);
 return status;
}
int main(void) {
 AudioServerPlugInDriverRef driver=CreateDriver(NULL,kAudioServerPlugInTypeUUID);
 CHECK(driver != NULL); gPlugIn_Host=&host;
 CHECK(owner(driver,getpid(),1,sizeof(CFPropertyListRef))==kAudioDevicePermissionsError); // no installed signer policy => denied
 CHECK(SecRequirementCreateWithString(CFSTR("identifier \"com.vorssaint.utils.pcm-tests\""),kSecCSDefaultFlags,&afTrustedRequirement)==errSecSuccess);
 CFStringRef uid=CFSTR("VorssaintAudio_UID"); AudioObjectID translated=0; UInt32 translatedSize=0;
 AudioObjectPropertyAddress translation=prop(kAudioPlugInPropertyTranslateUIDToDevice);
 CHECK((*driver)->GetPropertyData(driver,kObjectID_PlugIn,getpid(),&translation,sizeof(uid),&uid,sizeof(translated),&translatedSize,&translated)==noErr && translated==kObjectID_Device);
 CHECK((*driver)->GetPropertyData(driver,kObjectID_PlugIn,getpid(),&translation,1,&uid,sizeof(translated),&translatedSize,&translated)==kAudioHardwareBadPropertySizeError);
 AudioServerPlugInCustomPropertyInfo info[4]; UInt32 infoSize=0;
 AudioObjectPropertyAddress custom=prop(kAudioObjectPropertyCustomPropertyInfoList);
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,getpid(),&custom,0,NULL,sizeof(info),&infoSize,info)==noErr
  && infoSize==sizeof(info) && info[0].mPropertyDataType==kAudioServerPlugInCustomPropertyDataTypeCFPropertyList);
 UInt32 value=99;
 CHECK(get32(driver,kObjectID_Device,kAudioDevicePropertyIsHidden,&value)==noErr && value==1);
 CHECK(get32(driver,kObjectID_Device,kAudioDevicePropertyDeviceIsAlive,&value)==noErr && value==0);
 CHECK(owner(driver,getpid(),1,sizeof(UInt16))==kAudioHardwareBadPropertySizeError);
 CHECK(owner(driver,getpid(),2,sizeof(CFPropertyListRef))==kAudioHardwareIllegalOperationError);
 CHECK(owner(driver,getpid(),1,sizeof(CFPropertyListRef))==noErr);
 CHECK(get32(driver,kObjectID_Device,'vact',&value)==noErr && value==1);
 CHECK(get32(driver,kObjectID_Device,kAudioDevicePropertyIsHidden,&value)==noErr && value==0);
 CHECK(get32(driver,kObjectID_Device,kAudioDevicePropertyDeviceIsAlive,&value)==noErr && value==1);
 AudioObjectPropertyAddress inputDefault=prop(kAudioDevicePropertyDeviceCanBeDefaultDevice);
 inputDefault.mScope=kAudioObjectPropertyScopeInput;
 UInt32 outSize=0;
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,getpid(),&inputDefault,0,NULL,sizeof(value),&outSize,&value)==noErr && value==0);
 AudioObjectPropertyAddress streams=prop(kAudioDevicePropertyStreams);
 streams.mScope=kAudioObjectPropertyScopeInput;
 UInt32 streamBytes=99;
 CHECK((*driver)->GetPropertyDataSize(driver,kObjectID_Device,getpid(),&streams,0,NULL,&streamBytes)==noErr && streamBytes==0);
 CHECK((*driver)->GetPropertyDataSize(driver,kObjectID_Device2,getpid(),&streams,0,NULL,&streamBytes)==noErr && streamBytes==0); // No hidden microphone-like loopback input.
 streams.mScope=kAudioObjectPropertyScopeOutput;
 CHECK((*driver)->GetPropertyDataSize(driver,kObjectID_Device2,getpid(),&streams,0,NULL,&streamBytes)==noErr && streamBytes==0);
 CHECK(get32(driver,kObjectID_Device2,kAudioDevicePropertyIsHidden,&value)==noErr && value==1);
 AudioObjectPropertyAddress deviceList=prop(kAudioPlugInPropertyDeviceList);
 UInt32 deviceBytes=0;
 CHECK((*driver)->GetPropertyDataSize(driver,kObjectID_PlugIn,getpid(),&deviceList,0,NULL,&deviceBytes)==noErr && deviceBytes==sizeof(AudioObjectID));
 CHECK(get32(driver,kObjectID_Device2,kAudioDevicePropertyDeviceIsAlive,&value)==noErr && value==1);
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device2,getpid(),&inputDefault,0,NULL,sizeof(value),&outSize,&value)==noErr && value==0);
 Boolean willDo=true, inPlace=false;
 CHECK((*driver)->WillDoIOOperation(driver,kObjectID_Device,0,kAudioServerPlugInIOOperationReadInput,&willDo,&inPlace)==noErr && !willDo);
 CHECK(owner(driver,getppid(),1,sizeof(CFPropertyListRef))==kAudioDevicePermissionsError);
 CHECK(owner(driver,getppid(),0,sizeof(CFPropertyListRef))==kAudioHardwareIllegalOperationError);
 CHECK(owner(driver,getpid(),1,sizeof(CFPropertyListRef))==noErr);
 CHECK(owner(driver,getpid(),0,sizeof(CFPropertyListRef))==noErr);
 CHECK(get32(driver,kObjectID_Device,'vact',&value)==noErr && value==0);
 // Standard output controls must round-trip and reject non-finite values.
 AudioObjectPropertyAddress scalar=prop(kAudioLevelControlPropertyScalarValue);
 Float32 requested=0.35f, actual=0; UInt32 controlSize=0;
 CHECK((*driver)->SetPropertyData(driver,kObjectID_Volume_Output_Master,getpid(),&scalar,0,NULL,sizeof(requested),&requested)==noErr);
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Volume_Output_Master,getpid(),&scalar,0,NULL,sizeof(actual),&controlSize,&actual)==noErr && fabsf(actual-requested)<1e-5f);
 requested=NAN;
 CHECK((*driver)->SetPropertyData(driver,kObjectID_Volume_Output_Master,getpid(),&scalar,0,NULL,sizeof(requested),&requested)==kAudioHardwareIllegalOperationError);
 // Exercise mixed output transfer through qualified, repeatable HAL reads.
 CHECK(owner(driver,getpid(),1,sizeof(CFPropertyListRef))==noErr);
 VSRequest request={.magic=VS_MAGIC,.version=VS_VERSION,.nonce=1};
 AudioObjectPropertyAddress keyAddress=prop('vkey');CFDataRef key=NULL;
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,getpid(),&keyAddress,0,NULL,sizeof(key),&outSize,&key)==noErr && CFDataGetLength(key)==32);
 memcpy(request.key,CFDataGetBytePtr(key),32);CFRelease(key);
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,getppid(),&keyAddress,0,NULL,sizeof(key),&outSize,&key)==kAudioDevicePermissionsError);
 AudioObjectPropertyAddress pcm=prop('vpcm');
 CFDataRef qualifier=CFDataCreate(NULL,(const UInt8*)&request,sizeof(request));CFDataRef response=NULL;
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,getpid(),&pcm,sizeof(qualifier),&qualifier,sizeof(response),&outSize,&response)==noErr);
 VSPacket packet;memcpy(&packet,CFDataGetBytePtr(response),sizeof(packet));CFRelease(response);CFRelease(qualifier);
 request.generation=packet.generation;request.cursor=packet.next;request.maxFrames=4;request.nonce++;
 Float32 data[8]={.4f,.2f,.4f,.2f,.4f,.2f,.4f,.2f};
 AudioServerPlugInIOCycleInfo cycle={0};gVolume_Master_Value=.5f;gMute_Master_Value=false;
 CHECK((*driver)->DoIOOperation(driver,kObjectID_Device,kObjectID_Stream_Output,0,kAudioServerPlugInIOOperationWriteMix,4,&cycle,data,NULL)==noErr);
 qualifier=CFDataCreate(NULL,(const UInt8*)&request,sizeof(request));
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,getppid(),&pcm,sizeof(qualifier),&qualifier,sizeof(response),&outSize,&response)==kAudioHardwareIllegalOperationError);
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,0,&pcm,sizeof(qualifier),&qualifier,sizeof(response),&outSize,&response)==kAudioHardwareIllegalOperationError);
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,getpid(),&pcm,sizeof(qualifier),&qualifier,sizeof(response),&outSize,&response)==noErr);
 memcpy(&packet,CFDataGetBytePtr(response),sizeof(packet));
 CHECK(packet.frames==4 && packet.gain==.5f && packet.nonce==request.nonce && packet.next==request.cursor+4);
 CHECK(((const Float32*)(CFDataGetBytePtr(response)+sizeof(packet)))[0]==.4f); // raw PCM, gain applied once at final render
 CFDataRef retry=NULL;
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,getpid(),&pcm,sizeof(qualifier),&qualifier,sizeof(retry),&outSize,&retry)==noErr && CFEqual(response,retry));
 CFRelease(response);CFRelease(retry);CFRelease(qualifier);
 CHECK((*driver)->DoIOOperation(driver,kObjectID_Device2,kObjectID_Stream_Input,0,kAudioServerPlugInIOOperationReadInput,4,&cycle,data,NULL)==kAudioHardwareIllegalOperationError);
#if __has_include("../Sources/SoftwareVolumeDriver/Driver.c")
 // A new session revokes the previous capability, even for the same PID.
 CHECK(owner(driver,getpid(),0,sizeof(CFPropertyListRef))==noErr);
 CHECK(owner(driver,getpid(),1,sizeof(CFPropertyListRef))==noErr);
 qualifier=CFDataCreate(NULL,(const UInt8*)&request,sizeof(request));
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,getpid(),&pcm,sizeof(qualifier),&qualifier,sizeof(response),&outSize,&response)==kAudioHardwareIllegalOperationError);
 CFRelease(qualifier);
 // Deterministic timeout uses the same expiry function as the timer.
 CHECK(owner(driver,getpid(),1,sizeof(CFPropertyListRef))==noErr);
 VorssaintAudioExpireOwner(VorssaintAudioNow()+6);
 CHECK(get32(driver,kObjectID_Device,kAudioDevicePropertyDeviceIsAlive,&value)==noErr && value==0);
 CHECK(get32(driver,kObjectID_Device,kAudioDevicePropertyIsHidden,&value)==noErr && value==1);
#endif
 printf("VORSSAINT AUDIO DRIVER: %d checks, %d failures\n",checks,failures); return failures ? 1 : 0;
}

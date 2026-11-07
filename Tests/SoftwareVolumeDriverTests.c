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
static dispatch_semaphore_t configurationDone;
static OSStatus configurationStatus;
static OSStatus configure(AudioServerPlugInHostRef host, AudioObjectID object, UInt64 action, void *info) {
    configurationStatus = (*gAudioServerPlugInDriverRef)->PerformDeviceConfigurationChange(gAudioServerPlugInDriverRef, object, action, info);
    dispatch_semaphore_signal(configurationDone);
    return noErr;
}
#define CHECK(test) do { checks++; if (!(test)) { fprintf(stderr,"FAIL %d: %s\n", __LINE__, #test); failures++; } } while (0)
static OSStatus changed(AudioServerPlugInHostRef host, AudioObjectID object, UInt32 count, const AudioObjectPropertyAddress addresses[]) { return noErr; }
static AudioServerPlugInHostInterface host = { .PropertiesChanged = changed, .RequestDeviceConfigurationChange = configure };
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
static void check_channel_pcm(AudioServerPlugInDriverRef driver, unsigned channels) {
 AudioObjectPropertyAddress keyAddress = prop('vkey'), pcm = prop('vpcm');
 CFDataRef key = NULL; UInt32 size = 0;
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,getpid(),&keyAddress,0,NULL,sizeof(key),&size,&key)==noErr);
 VSRequest request = vs_request(0,0,1,0,CFDataGetBytePtr(key)); CFRelease(key);
 CFDataRef qualifier = CFDataCreate(NULL,(const UInt8 *)&request,sizeof(request)), response = NULL;
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,getpid(),&pcm,sizeof(qualifier),&qualifier,sizeof(response),&size,&response)==noErr);
 VSPacket header; memcpy(&header,CFDataGetBytePtr(response),sizeof(header));
 CHECK(header.channels==channels && header.frames==0);
 CFRelease(response); CFRelease(qualifier);
 unsigned frames = channels == VS_MAX_CHANNELS ? VS_PACKET_FRAMES : 4;
 request.generation=header.generation; request.cursor=header.next; request.nonce=2; request.maxFrames=frames;
 float *input=malloc(frames*channels*sizeof(float)); assert(input);
 for(unsigned i=0;i<frames*channels;i++) input[i]=(i+1)*0.01f;
 AudioServerPlugInIOCycleInfo cycle={0};
 CHECK((*driver)->DoIOOperation(driver,kObjectID_Device,kObjectID_Stream_Output,0,kAudioServerPlugInIOOperationWriteMix,frames,&cycle,input,NULL)==noErr);
 qualifier=CFDataCreate(NULL,(const UInt8 *)&request,sizeof(request));
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,getpid(),&pcm,sizeof(qualifier),&qualifier,sizeof(response),&size,&response)==noErr);
 memcpy(&header,CFDataGetBytePtr(response),sizeof(header));
 CHECK(header.channels==channels && header.frames==frames && CFDataGetLength(response)==sizeof(header)+sizeof(float)*channels*frames
       && memcmp(CFDataGetBytePtr(response)+sizeof(header),input,sizeof(float)*channels*frames)==0);
 CFRelease(response); CFRelease(qualifier);
 free(input);
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
 AudioServerPlugInCustomPropertyInfo info[5]; UInt32 infoSize=0;
 AudioObjectPropertyAddress custom=prop(kAudioObjectPropertyCustomPropertyInfoList);
 CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,getpid(),&custom,0,NULL,sizeof(info),&infoSize,info)==noErr
  && infoSize==sizeof(info) && info[0].mPropertyDataType==kAudioServerPlugInCustomPropertyDataTypeCFPropertyList);
 UInt32 value=99;
 CHECK(get32(driver,kObjectID_Device,kAudioDevicePropertyIsHidden,&value)==noErr && value==1);
 CHECK(get32(driver,kObjectID_Device,kAudioDevicePropertyDeviceIsAlive,&value)==noErr && value==0);
 CHECK(owner(driver,getpid(),1,sizeof(UInt16))==kAudioHardwareBadPropertySizeError);
 CHECK(owner(driver,getpid(),2,sizeof(CFPropertyListRef))==kAudioHardwareIllegalOperationError);
 CHECK(owner(driver,getpid(),1,sizeof(CFPropertyListRef))==noErr);
 configurationDone = dispatch_semaphore_create(0);
 unsigned layouts[] = {32,16,12,8,7,6,5,4,3,2};
 for (unsigned index = 0; index < sizeof(layouts)/sizeof(layouts[0]); index++) {
  unsigned channels = layouts[index];
  VSOutputFormat format = vs_format_default(channels);
  if (channels > 3) format.descriptions[3].mChannelLabel = kAudioChannelLabel_LFEScreen;
  AudioObjectPropertyAddress address = prop('vcfg');
  CFDataRef data = CFDataCreate(NULL, (const UInt8 *)&format, sizeof(format));
  CHECK((*driver)->SetPropertyData(driver,kObjectID_Device,getppid(),&address,0,NULL,sizeof(data),&data)==kAudioDevicePermissionsError);
  CHECK((*driver)->SetPropertyData(driver,kObjectID_Device,getpid(),&address,0,NULL,sizeof(data),&data)==noErr);
  CHECK(dispatch_semaphore_wait(configurationDone,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0);
  CHECK(configurationStatus==noErr);
  CFRelease(data);
  AudioStreamBasicDescription streamFormat = {0}; UInt32 formatSize = 0;
  address = prop(kAudioStreamPropertyVirtualFormat);
  CHECK((*driver)->GetPropertyData(driver,kObjectID_Stream_Output,getpid(),&address,0,NULL,sizeof(streamFormat),&formatSize,&streamFormat)==noErr
        && streamFormat.mChannelsPerFrame==channels && streamFormat.mBytesPerFrame==channels*sizeof(float));
  struct { AudioChannelLayoutTag tag; AudioChannelBitmap bitmap; UInt32 count; AudioChannelDescription descriptions[VS_MAX_CHANNELS]; } layout = {0};
  address = prop(kAudioDevicePropertyPreferredChannelLayout); address.mScope = kAudioObjectPropertyScopeOutput;
  CHECK((*driver)->GetPropertyData(driver,kObjectID_Device,getpid(),&address,0,NULL,sizeof(layout),&formatSize,&layout)==noErr
        && layout.count==channels && memcmp(layout.descriptions,format.descriptions,channels*sizeof(AudioChannelDescription))==0);
  AudioObjectPropertyAddress input = prop(kAudioDevicePropertyStreams); input.mScope = kAudioObjectPropertyScopeInput;
  UInt32 inputBytes = 99;
  CHECK((*driver)->GetPropertyDataSize(driver,kObjectID_Device,getpid(),&input,0,NULL,&inputBytes)==noErr && inputBytes==0);
  check_channel_pcm(driver,channels);
 }
 for (unsigned rate = 48000; rate <= 192000; rate *= 2) {
  uint64_t generation = afGeneration;
  gDevice_RequestedSampleRate = rate;
  CHECK((*driver)->PerformDeviceConfigurationChange(driver,kObjectID_Device,ChangeAction_SetSampleRate,NULL)==noErr
        && gDevice_SampleRate==rate && afGeneration!=generation);
 }
 gDevice_RequestedSampleRate = 48000;
 CHECK((*driver)->PerformDeviceConfigurationChange(driver,kObjectID_Device,ChangeAction_SetSampleRate,NULL)==noErr);
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

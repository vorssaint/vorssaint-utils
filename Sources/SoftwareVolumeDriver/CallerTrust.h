// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef VORSSAINT_CALLER_TRUST_H
#define VORSSAINT_CALLER_TRUST_H
#include <Security/Security.h>
#include <CommonCrypto/CommonDigest.h>
// A driver is installed by an administrator. Only the main/developer app
// signed by THAT driver's leaf certificate may request the PCM transport.
// Ad-hoc/unknown signers fail closed; no bundle-id-only production fallback.
static SecRequirementRef afTrustedRequirement;
static void afLoadCallerRequirement(void) {
    CFBundleRef bundle=CFBundleGetBundleWithIdentifier(CFSTR(kPlugIn_BundleID));
    if(!bundle) return;
    CFURLRef url=CFBundleCopyBundleURL(bundle);
    SecStaticCodeRef code=NULL; CFDictionaryRef info=NULL;
    if(url && SecStaticCodeCreateWithPath(url,kSecCSDefaultFlags,&code)==errSecSuccess
        && SecCodeCopySigningInformation(code,kSecCSSigningInformation,&info)==errSecSuccess) {
        CFArrayRef certs=CFDictionaryGetValue(info,kSecCodeInfoCertificates);
        if(certs && CFArrayGetCount(certs)>0) {
            CFDataRef certificate=SecCertificateCopyData((SecCertificateRef)CFArrayGetValueAtIndex(certs,0));
            if(certificate) {
                unsigned char digest[CC_SHA1_DIGEST_LENGTH]; char hex[41];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                CC_SHA1(CFDataGetBytePtr(certificate),(CC_LONG)CFDataGetLength(certificate),digest);
#pragma clang diagnostic pop
                for(unsigned i=0;i<20;i++) snprintf(hex+i*2,3,"%02x",digest[i]);
                CFStringRef text=CFStringCreateWithFormat(NULL,NULL,
                    CFSTR("(identifier \"com.vorssaint.utils\" or identifier \"com.vorssaint.utils.dev\") and certificate leaf = H\"%s\""),hex);
                if(text) {SecRequirementCreateWithString(text,kSecCSDefaultFlags,&afTrustedRequirement);CFRelease(text);}
                CFRelease(certificate);
            }
        }
    }
    if(info)CFRelease(info);if(code)CFRelease(code);if(url)CFRelease(url);
}
static Boolean afCallerTrusted(pid_t pid) {
    if(pid<=0 || !afTrustedRequirement) return false;
    CFNumberRef number=CFNumberCreate(NULL,kCFNumberIntType,&pid);
    const void *keys[]={kSecGuestAttributePid},*values[]={number};
    CFDictionaryRef attrs=CFDictionaryCreate(NULL,keys,values,1,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    SecCodeRef code=NULL;
    Boolean trusted=SecCodeCopyGuestWithAttributes(NULL,attrs,kSecCSDefaultFlags,&code)==errSecSuccess
        && SecCodeCheckValidity(code,kSecCSDefaultFlags,afTrustedRequirement)==errSecSuccess;
    if(code)CFRelease(code);CFRelease(attrs);CFRelease(number);return trusted;
}
#endif

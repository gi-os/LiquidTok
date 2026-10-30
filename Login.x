#import "LiquidTok.h"

// Let Giovanni log into his own account. A resigned + tweak-injected TikTok is not a clean App Store
// install, and TikTok checks that: its anti-tamper SDK (the "Singularity"/MS security) and its
// App-Store-origin checks flag the ad-hoc signature and the injected dylib, so ByteDance's servers won't
// register the device and every login attempt is rejected (which eventually shows "Maximum number of
// attempts reached"). These hooks make the app report itself as a normal App Store install so device
// registration and login work, exactly as the public BHTikTok/TweakiTok tweaks do on this same base.
// Nothing here is a toggle — without it the app can't be logged into. Device/install-ID registration
// itself is left untouched; it just needs to pass these checks to run.

// MARK: - Looks like an App Store install

%group AppStoreEnv
%hook GULAppEnvironmentUtil
+ (bool)isFromAppStore { return YES; }
+ (bool)isAppStoreReceiptSandbox { return NO; }
+ (bool)isAppExtension { return YES; }
%end
%end

%group APMSign
%hook AWEAPMManager
+ (id)signInfo { return @"AppStore"; }
%end
%end

%group FBDebug
%hook FBSDKAppEventsUtility
+ (bool)isDebugBuild { return NO; }
%end
%end

// The app is signed and installed under its own id (com.gios.liquidtok) so it can carry Giovanni's
// certificate and sit next to the App Store app, but ByteDance's device registration rejects an unknown
// bundle id. The real signed id can't change (iOS validates it at launch), so TikTok's own reads of it are
// answered with the genuine TikTok id, which is what the server expects. The community tweaks don't need
// this only because they keep the original id when they sign in place.
static NSString *const LTRealBundleID = @"com.zhiliaoapp.musically";

%hook NSBundle
- (NSString *)bundleIdentifier {
    return self == [NSBundle mainBundle] ? LTRealBundleID : %orig;
}
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (self == [NSBundle mainBundle] && [key isEqualToString:@"CFBundleIdentifier"]) return LTRealBundleID;
    return %orig;
}
// The embedded ad-hoc provisioning profile is the tell that it's sideloaded; hide it from lookups.
- (id)pathForResource:(id)name ofType:(id)ext {
    if ([ext isKindOfClass:NSString.class] && [ext caseInsensitiveCompare:@"mobileprovision"] == NSOrderedSame)
        return nil;
    return %orig;
}
%end

// MARK: - Anti-tamper SDK neutralised

// The security SDK that collects integrity signals and detects the injection; its mode setters return an
// empty stand-in (matching TweakiTok's proven stubs for this base) so it reports nothing.
%group Security
%hook AWESecurity
- (void)resetCollectMode { return; }
%end
%end

%group MSManager
%hook MSManagerOV
- (id)setMode { return ^{ }; }
%end
%end

%group MSConfig
%hook MSConfigOV
- (id)setMode { return ^{ }; }
%end
%end

// MARK: - Jailbreak checks answer honestly (the device isn't), via the paths TikTok probes

%group JB_BDADevice
%hook BDADeviceHelper
+ (bool)isJailBroken { return NO; }
%end
%end

%group JB_UIDevice
%hook UIDevice
+ (bool)btd_isJailBroken { return NO; }
%end
%end

%group JB_TTInstall
%hook TTInstallUtil
+ (bool)isJailBroken { return NO; }
%end
%end

%group JB_IESLive
%hook IESLiveDeviceInfo
+ (bool)isJailBroken { return NO; }
%end
%end

%group JB_BDInstallNet
%hook BDInstallNetworkUtility
+ (bool)isJailBroken { return NO; }
%end
%end

%group JB_AdSplash
%hook TTAdSplashDeviceHelper
+ (bool)isJailBroken { return NO; }
%end
%end

%group JB_AppsFlyer
%hook AppsFlyerUtils
+ (bool)isJailbrokenWithSkipAdvancedJailbreakValidation:(bool)skip { return NO; }
%end
%end

%ctor {
    %init;   // NSBundle, always present
    if (objc_getClass("GULAppEnvironmentUtil")) %init(AppStoreEnv);
    if (objc_getClass("AWEAPMManager")) %init(APMSign);
    if (objc_getClass("FBSDKAppEventsUtility")) %init(FBDebug);
    if (objc_getClass("AWESecurity")) %init(Security);
    if (objc_getClass("MSManagerOV")) %init(MSManager);
    if (objc_getClass("MSConfigOV")) %init(MSConfig);
    if (objc_getClass("BDADeviceHelper")) %init(JB_BDADevice);
    if (objc_getClass("UIDevice")) %init(JB_UIDevice);
    if (objc_getClass("TTInstallUtil")) %init(JB_TTInstall);
    if (objc_getClass("IESLiveDeviceInfo")) %init(JB_IESLive);
    if (objc_getClass("BDInstallNetworkUtility")) %init(JB_BDInstallNet);
    if (objc_getClass("TTAdSplashDeviceHelper")) %init(JB_AdSplash);
    if (objc_getClass("AppsFlyerUtils")) %init(JB_AppsFlyer);
}

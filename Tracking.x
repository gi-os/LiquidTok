#import "LiquidTok.h"

// No tracking: ByteDance's event log (BDTrackerProtocol's eventV3 family, TTTracker) and its performance
// telemetry (Heimdallr's HMDTTMonitor), AppsFlyer, Firebase Analytics and Facebook's app events all log
// nothing; the advertising identifier reads as zeros and App Tracking Transparency as denied, without the
// prompt. Likes, follows, comments and saves are API calls, not events, so they still reach TikTok, but For
// You no longer learns from watch time and skips. Off in the Duo sidebar's menu
// (liquidtok_block_tracking) if For You gets worse than that's worth.

#define LTLetThrough (!LTOn(LTKeyTracking))

@interface ASIdentifierManager : NSObject @end
@interface ATTrackingManager : NSObject @end

// TikTok swizzles eventV3 itself (hookEventV3, swizzle_eventV3:params: and kin); whichever order the
// swizzles land in, the call ends here.
%group ByteDanceEvents
%hook BDTrackerProtocol
+ (void)eventV3:(id)event params:(id)params { if (LTLetThrough) %orig; }
+ (void)eventV3:(id)event params:(id)params isDoubleSending:(BOOL)twice { if (LTLetThrough) %orig; }
+ (void)eventV3:(id)event params:(id)params needAvoid:(BOOL)avoid { if (LTLetThrough) %orig; }
+ (void)eventV3:(id)event params:(id)params isDoubleSending:(BOOL)twice needAvoid:(BOOL)avoid { if (LTLetThrough) %orig; }
+ (void)trackLogDataEvent:(id)data { if (LTLetThrough) %orig; }
+ (void)trackItemImpressionEvent:(id)event { if (LTLetThrough) %orig; }
+ (void)trackCustomKey:(id)key withEvent:(id)event { if (LTLetThrough) %orig; }
%end
%end

%group ByteDanceV1
%hook TTTracker
+ (void)event:(id)event { if (LTLetThrough) %orig; }
+ (void)event:(id)event label:(id)label { if (LTLetThrough) %orig; }
+ (void)event:(id)event label:(id)label value:(id)value extValue:(id)ext extValue2:(id)ext2 { if (LTLetThrough) %orig; }
+ (void)event:(id)event label:(id)label value:(id)value extValue:(id)ext extValue2:(id)ext2 dict:(id)dict { if (LTLetThrough) %orig; }
+ (void)eventData:(id)data { if (LTLetThrough) %orig; }
+ (void)eventData:(id)data isV3Format:(BOOL)v3 { if (LTLetThrough) %orig; }
+ (void)eventData:(id)data policy:(long long)policy isV3Format:(BOOL)v3 { if (LTLetThrough) %orig; }
%end
%end

%group Heimdallr
%hook HMDTTMonitor
+ (void)trackService:(id)service metrics:(id)metrics dimension:(id)dimension extra:(id)extra { if (LTLetThrough) %orig; }
+ (void)trackService:(id)service metrics:(id)metrics dimension:(id)dimension extra:(id)extra syncWrite:(BOOL)sync { if (LTLetThrough) %orig; }
- (void)hmdTrackService:(id)service value:(id)value extra:(id)extra { if (LTLetThrough) %orig; }
- (void)hmdTrackService:(id)service status:(long long)status extra:(id)extra { if (LTLetThrough) %orig; }
- (void)hmdTrackService:(id)service attributes:(id)attributes { if (LTLetThrough) %orig; }
- (void)hmdTrackService:(id)service metric:(id)metric category:(id)category extra:(id)extra { if (LTLetThrough) %orig; }
- (void)hmdTrackService:(id)service metric:(id)metric category:(id)category extra:(id)extra syncWrite:(BOOL)sync { if (LTLetThrough) %orig; }
- (void)hmdTrackService:(id)service metric:(id)metric category:(id)category extra:(id)extra storeType:(unsigned long long)type { if (LTLetThrough) %orig; }
- (void)hmdUploadImmediatelyTrackService:(id)service metric:(id)metric category:(id)category extra:(id)extra { if (LTLetThrough) %orig; }
- (void)hmdUploadImmediatelyIfNeedTrackService:(id)service metric:(id)metric category:(id)category extra:(id)extra { if (LTLetThrough) %orig; }
- (void)hmdTrackData:(id)data type:(long long)type { if (LTLetThrough) %orig; }
- (void)hmdTrackData:(id)data logTypeStr:(id)type { if (LTLetThrough) %orig; }
- (void)trackAppLogWithTag:(id)tag label:(id)label { if (LTLetThrough) %orig; }
- (void)trackAppLogWithTag:(id)tag label:(id)label extraValue:(id)extra { if (LTLetThrough) %orig; }
%end
%end

// Install attribution. Purchases' receipt validation is left alone.
%group AppsFlyer
%hook AppsFlyerLib
- (void)start { if (LTLetThrough) %orig; }
- (void)startWithCompletionHandler:(id)completion { if (LTLetThrough) %orig; }
- (void)logEvent:(id)name withValues:(id)values { if (LTLetThrough) %orig; }
- (void)logEventWithEventName:(id)name eventValues:(id)values completionHandler:(id)completion { if (LTLetThrough) %orig; }
- (void)logAdRevenue:(id)revenue additionalParameters:(id)parameters { if (LTLetThrough) %orig; }
- (void)logLocation:(double)longitude latitude:(double)latitude { if (LTLetThrough) %orig; }
%end
%end

%group Firebase
%hook FIRAnalytics
+ (void)logEventWithName:(id)name parameters:(id)parameters { if (LTLetThrough) %orig; }
+ (void)logEventWithOrigin:(id)origin isPublicEvent:(BOOL)isPublic name:(id)name parameters:(id)parameters
                 timestamp:(double)timestamp ignoreEnabled:(BOOL)ignoreEnabled ignoreInterceptor:(BOOL)ignoreInterceptor {
    if (LTLetThrough) %orig;
}
+ (void)setDefaultEventParameters:(id)parameters { if (LTLetThrough) %orig; }
%end
%end

// Every public logEvent/logPurchase lands in one of these.
%group Facebook
%hook FBSDKAppEvents
- (void)logEvent:(id)name valueToSum:(id)value parameters:(id)parameters isImplicitlyLogged:(BOOL)implicit accessToken:(id)token {
    if (LTLetThrough) %orig;
}
- (void)logImplicitEvent:(id)name valueToSum:(id)value parameters:(id)parameters accessToken:(id)token { if (LTLetThrough) %orig; }
- (void)logInternalEvent:(id)name valueToSum:(id)value parameters:(id)parameters isImplicitlyLogged:(BOOL)implicit accessToken:(id)token {
    if (LTLetThrough) %orig;
}
%end
%end

%group AdvertisingID
%hook ASIdentifierManager
- (NSUUID *)advertisingIdentifier {
    return LTLetThrough ? %orig : [[NSUUID alloc] initWithUUIDString:@"00000000-0000-0000-0000-000000000000"];
}
- (BOOL)isAdvertisingTrackingEnabled { return LTLetThrough ? %orig : NO; }
%end
%end

// ATTrackingManagerAuthorizationStatusDenied, and no prompt.
%group TrackingPrompt
%hook ATTrackingManager
+ (NSUInteger)trackingAuthorizationStatus { return LTLetThrough ? %orig : 2; }
+ (void)requestTrackingAuthorizationWithCompletionHandler:(void (^)(NSUInteger))completion {
    if (LTLetThrough) { %orig; return; }
    if (completion) completion(2);
}
%end
%end

%ctor {
    if (objc_getClass("BDTrackerProtocol")) %init(ByteDanceEvents);
    if (objc_getClass("TTTracker")) %init(ByteDanceV1);
    if (objc_getClass("HMDTTMonitor")) %init(Heimdallr);
    if (objc_getClass("AppsFlyerLib")) %init(AppsFlyer);
    if (objc_getClass("FIRAnalytics")) %init(Firebase);
    if (objc_getClass("FBSDKAppEvents")) %init(Facebook);
    if (objc_getClass("ASIdentifierManager")) %init(AdvertisingID);
    if (objc_getClass("ATTrackingManager")) %init(TrackingPrompt);
}

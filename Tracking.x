#import "LiquidTok.h"

// No tracking: AppsFlyer, Firebase Analytics and Facebook's app events log nothing; the advertising
// identifier reads as zeros and App Tracking Transparency as denied, without the prompt. This blocks the
// third-party data brokers and the cross-app ad ID — the bulk of the tracking that leaves the app.
//
// ByteDance's own first-party telemetry (BDTrackerProtocol eventV3, TTTracker, Heimdallr) is deliberately
// left running: TikTok's device registration and anti-fraud ride on that pipeline, so silencing it blocked
// sign-in on every method. The public BHTikTok/TweakiTok tweaks leave it alone for the same reason. A
// surgical first-party block that spares the login/device paths could be revisited once signed in.

#define LTLetThrough (!LTOn(LTKeyTracking))

@interface ASIdentifierManager : NSObject @end
@interface ATTrackingManager : NSObject @end

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
    if (objc_getClass("AppsFlyerLib")) %init(AppsFlyer);
    if (objc_getClass("FIRAnalytics")) %init(Firebase);
    if (objc_getClass("FBSDKAppEvents")) %init(Facebook);
    if (objc_getClass("ASIdentifierManager")) %init(AdvertisingID);
    if (objc_getClass("ATTrackingManager")) %init(TrackingPrompt);
}

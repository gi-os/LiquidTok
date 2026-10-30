#import "LiquidTok.h"

// What the feed doesn't show, decided on TikTok's own post model (AWEAwemeModel, a Mantle model): a post
// that's an ad, sponsored, selling something or labelled AI-generated comes back nil from
// -initWithDictionary:error:, so no feed, profile grid or search result gets it (BHTikTok's ad filter,
// widened). And TikTok Shop's tab, top tab and entrances are taken out of the tab configs TikTok builds its
// bars from. Class and property names are from TikTok 47.5's ObjC metadata (scripts/objc_dump.py).

// MARK: - Switches

static NSArray<NSString *> *LTKeys(void) {
    return @[LTKeyAds, LTKeySponsored, LTKeyProducts, LTKeyAI, LTKeyShop, LTKeyTracking];
}

// Read on TikTok's parsing and logging threads, so cached as plain BOOLs and refreshed when the defaults
// change (the sidebar's menu).
static volatile BOOL gLTFlags[6];

static void LTRefreshFlags(void) {
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSArray *keys = LTKeys();
    for (NSUInteger i = 0; i < keys.count; i++) gLTFlags[i] = [d boolForKey:keys[i]];
}

BOOL LTOn(NSString *key) {
    NSUInteger i = [LTKeys() indexOfObject:key];
    return i != NSNotFound && gLTFlags[i];
}

// MARK: - Posts

typedef NS_ENUM(NSInteger, LTReason) { LTKeep, LTAd, LTSponsored, LTProduct, LTAI, LTReasonCount };
static volatile long gLTHidden[LTReasonCount];

NSString *LTFilterSummary(void) {
    return [NSString stringWithFormat:@"hidden so far: %ld ads, %ld sponsored, %ld selling, %ld AI",
            gLTHidden[LTAd], gLTHidden[LTSponsored], gLTHidden[LTProduct], gLTHidden[LTAI]];
}

static LTReason LTReasonFor(id post) {
    if (LTOn(LTKeyAds)) {
        // Feed ads (TopView, in-feed, search), and ad copies of organic posts.
        if (LTBool(post, @"isAds") || LTBool(post, @"isAdsOrPseudoAds") || LTBool(post, @"isBiddingAdVideo") ||
            LTBool(post, @"isCPCAd"))
            return LTAd;
        id commerce = LTObj(post, @"commerceModel");
        if (LTBool(commerce, @"isPseudoAd") || LTBool(commerce, @"isContextualAd")) return LTAd;
    }
    if (LTOn(LTKeySponsored)) {
        // "Paid partnership" (branded content), Spark Ads' soft ads, and Promote's "Promoted".
        if (LTBool(post, @"isSoftAds")) return LTSponsored;
        if (LTInt(LTObj(post, @"commerceModel"), @"brandedContentType") > 0) return LTSponsored;
        if (LTCount(LTObj(post, @"brandedContentAccounts"))) return LTSponsored;
        if (LTBool(LTObj(post, @"promoteTagInfo"), @"isPromoteAdLabel")) return LTSponsored;
    }
    if (LTOn(LTKeyProducts)) {
        // A TikTok Shop product link (the cart anchor), product photos, shopping ads and product cards.
        if (LTCount(LTObj(post, @"productInfo")) || LTCount(LTObj(post, @"ecImageProductListMap")) ||
            LTCount(LTObj(post, @"goodsSeedingModels")))
            return LTProduct;
        if ([LTObj(LTObj(post, @"productData"), @"productID") length] ||
            [LTObj(LTObj(post, @"outflowProductData"), @"productID") length])
            return LTProduct;
        if (LTBool(post, @"hasProductsOfVSA") || LTBool(post, @"isLiveHasProducts")) return LTProduct;
        if (LTObj(post, @"feedProductSelectionCardProductInfoModel")) return LTProduct;
        id anchors = LTObj(post, @"i18nAnchors");
        if ([anchors isKindOfClass:NSArray.class])
            for (id anchor in anchors)
                if ([LTObj(anchor, @"mostRelevantProductId") length]) return LTProduct;
    }
    if (LTOn(LTKeyAI)) {
        // TikTok's AI-generated label, the creator's or its own (TTKAIGCInfoModel, TTKModerationAIGCInfoModel).
        id aigc = LTObj(post, @"aigcInfoModel");
        if (LTInt(aigc, @"aigcLabelType") > 0 || LTBool(aigc, @"createByAI")) return LTAI;
        if (LTInt(LTObj(post, @"moderationAigcInfoModel"), @"moderationAigcLabelType") > 0) return LTAI;
    }
    return LTKeep;
}

%hook AWEAwemeModel
- (id)initWithDictionary:(id)dictionary error:(id *)error {
    id post = %orig;
    if (!post) return post;
    LTReason reason = LTKeep;
    @try { reason = LTReasonFor(post); } @catch (__unused NSException *e) {}
    if (reason == LTKeep) return post;
    __atomic_fetch_add(&gLTHidden[reason], 1, __ATOMIC_RELAXED);
    return nil;
}
// The in-feed "Search · <keyword>" teaser card comes from this; drop it.
- (id)smartSearchTeaData { return nil; }
%end

// MARK: - Overlay info cards

// The cards TikTok lays over a video above the username — "TV show · …", a location/POI, a music or
// other content anchor. The feed's anchor element decides whether to show one; force it off.
%group InfoCards
%hook AWEPlayInteractionAnchorElement
- (BOOL)shouldShowAnchorView { return NO; }
- (BOOL)shouldShowAnchorViewWithoutCondition { return NO; }
%end
%end

// MARK: - Splash ads

// TikTok's own "skip this splash" switch, and the ad SDK's decision to show one.
%group Splash
%hook AWESplashManager
- (BOOL)forceIgnoreCurrentShow { return LTOn(LTKeyAds) || %orig; }
%end
%end

%group BDASplash
%hook BDASplashManager
- (BOOL)shouldShowSplashAccordingToUDP { return LTOn(LTKeyAds) ? NO : %orig; }
- (BOOL)shouldShowSplashAccordingToUDPAndPreloadData:(id)data { return LTOn(LTKeyAds) ? NO : %orig; }
%end
%end

// MARK: - TikTok Shop

// An entry in one of TikTok's tab configs: a key string, a model with a key, or a dictionary.
static BOOL LTIsShopEntry(id entry) {
    if ([entry isKindOfClass:NSString.class]) return LTIsShopKey(entry);
    NSArray *keys = @[@"topTabKey", @"itemKey", @"entranceKey", @"tabKey", @"key", @"name", @"tabName", @"identifier"];
    for (NSString *k in keys) {
        id v = [entry isKindOfClass:NSDictionary.class] ? ((NSDictionary *)entry)[k] : LTObj(entry, k);
        if (LTIsShopKey(v)) return YES;
    }
    return NO;
}

static NSArray *LTWithoutShop(NSArray *entries, NSString *where) {
    if (!LTOn(LTKeyShop) || ![entries isKindOfClass:NSArray.class]) return entries;
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:entries.count];
    for (id e in entries) if (!LTIsShopEntry(e)) [kept addObject:e];
    if (kept.count == entries.count) return entries;
    LTLog(@"Shop: %lu of %lu left out of %@", (unsigned long)(entries.count - kept.count), (unsigned long)entries.count, where);
    return kept;
}

// The home feed's top tabs (Following, For You, Shop, LIVE...) and the bottom tabs, as configured.
%group ShopTopTabs
%hook TTKFeedTopTabControlConfig
- (NSArray *)topTabList { return LTWithoutShop(%orig, @"top tabs"); }
%end
%end

%group ShopEntrances
%hook TTKFeedTopTabEntranceConfig
- (NSArray *)candidates { return LTWithoutShop(%orig, @"top bar entrances"); }
%end
%end

%group ShopTabEntrance
%hook TTKTabEntranceResult
- (NSArray *)topTabs { return LTWithoutShop(%orig, @"entrance top tabs"); }
- (NSArray *)bottomTabs { return LTWithoutShop(%orig, @"entrance bottom tabs"); }
%end
%end

%group ShopFCP
%hook TTKTabFCPConfigCheckResult
- (NSArray *)tabbarItems { return LTWithoutShop(%orig, @"launch tab bar"); }
- (NSArray *)toptabItems { return LTWithoutShop(%orig, @"launch top tabs"); }
%end
%end

// The bottom bar's own buttons, should a Shop tab get past the configs: its label, its screen's class
// (TTKECRefactorMixMallViewController and kin) or the name TikTok's tab manager logs it under.
BOOL LTIsShopTabButton(UIView *button, id tabBarController) {
    if (LTIsShopKey(button.accessibilityLabel) || LTIsShopKey(button.accessibilityIdentifier)) return YES;
    NSString *screen = NSStringFromClass([LTObj(button, @"viewController") class]);
    for (NSString *s in @[@"Mall", @"ECommerce", @"Shop"])
        if ([screen rangeOfString:s].location != NSNotFound) return YES;
    id manager = LTObj(tabBarController, @"dataSource") ?: LTObj(tabBarController, @"customDelegate");
    SEL name = NSSelectorFromString(@"trackTabNameForCommonTabFrameworkWithButtonType:");
    if (LTReturns(manager, name) == '@')
        return LTIsShopKey(((id (*)(id, SEL, long long))objc_msgSend)(manager, name, LTInt(button, @"type")));
    return NO;
}

%group ShopButton
%hook TTKTabBarController
- (NSArray *)buttonsForTabBar {
    NSArray *buttons = %orig;
    if (!LTOn(LTKeyShop) || ![buttons isKindOfClass:NSArray.class]) return buttons;
    NSMutableArray *kept = [NSMutableArray array];
    for (UIView *b in buttons) if (![b isKindOfClass:UIView.class] || !LTIsShopTabButton(b, self)) [kept addObject:b];
    if (kept.count != buttons.count) LTLog(@"Shop: tab bar button left out");
    return kept;
}
%end
%end

// MARK: - Setup

%ctor {
    NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
    for (NSString *k in LTKeys()) defaults[k] = @YES;
    [NSUserDefaults.standardUserDefaults registerDefaults:defaults];
    LTRefreshFlags();
    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *n) { LTRefreshFlags(); }];

    if (objc_getClass("AWEAwemeModel")) %init;
    if (objc_getClass("AWESplashManager")) %init(Splash);
    if (objc_getClass("BDASplashManager")) %init(BDASplash);
    if (objc_getClass("TTKFeedTopTabControlConfig")) %init(ShopTopTabs);
    if (objc_getClass("TTKFeedTopTabEntranceConfig")) %init(ShopEntrances);
    if (objc_getClass("TTKTabEntranceResult")) %init(ShopTabEntrance);
    if (objc_getClass("TTKTabFCPConfigCheckResult")) %init(ShopFCP);
    if (objc_getClass("TTKTabBarController")) %init(ShopButton);
    if (objc_getClass("AWEPlayInteractionAnchorElement")) %init(InfoCards);
}

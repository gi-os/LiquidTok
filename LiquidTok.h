#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// LiquidTok's switches, in the standard defaults. All on unless turned off in the Duo sidebar's menu.
#define LTKeyAds        @"liquidtok_hide_ads"        // ads, TopView and splash ads
#define LTKeySponsored  @"liquidtok_hide_sponsored"  // paid partnerships, Spark/Promote boosts
#define LTKeyProducts   @"liquidtok_hide_products"   // posts selling something (TikTok Shop product links)
#define LTKeyAI         @"liquidtok_hide_ai"         // posts labelled AI-generated
#define LTKeyShop       @"liquidtok_hide_shop"       // the Shop tab, top tab and entrances
#define LTKeyTracking   @"liquidtok_block_tracking"  // analytics SDKs, TikTok's event log, IDFA

BOOL LTOn(NSString *key);                                       // Tweak.x, cached
void LTLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);     // Debug.x: shown in the layout copy
NSString *LTFilterSummary(void);                                // Tweak.x: what's been hidden so far
BOOL LTIsShopTabButton(UIView *button, id tabBarController);    // Tweak.x

// Messages to TikTok's objects through the runtime, so a selector a new version drops, or one that turns
// out to return something else, is a no-op instead of a crash: each checks the method's return type.
static inline char LTReturns(id target, SEL sel) {
    if (!target) return 0;
    Method m = class_getInstanceMethod(object_getClass(target), sel);
    if (!m) return 0;
    const char *t = method_getTypeEncoding(m);
    while (t && (*t == 'r' || *t == 'n' || *t == 'N' || *t == 'o' || *t == 'O' || *t == 'R' || *t == 'V')) t++;
    return t ? *t : 0;
}

static inline id LTObj(id target, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    return LTReturns(target, sel) == '@' ? ((id (*)(id, SEL))objc_msgSend)(target, sel) : nil;
}

static inline BOOL LTBool(id target, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    char r = LTReturns(target, sel);
    return (r == 'B' || r == 'c' || r == 'C') ? ((BOOL (*)(id, SEL))objc_msgSend)(target, sel) : NO;
}

static inline long long LTInt(id target, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    switch (LTReturns(target, sel)) {
        case 'q': case 'Q': return ((long long (*)(id, SEL))objc_msgSend)(target, sel);
        case 'i': case 'I': case 'l': case 'L': return ((int (*)(id, SEL))objc_msgSend)(target, sel);
        default: return 0;
    }
}

static inline NSUInteger LTCount(id collection) {
    return [collection isKindOfClass:NSArray.class] || [collection isKindOfClass:NSDictionary.class] ||
           [collection isKindOfClass:NSSet.class] ? [collection count] : 0;
}

// The keys TikTok names its Shop surfaces by (bottom tab, home top tab, entrances): shop, mall,
// mall_tab, homepage_mall, ecommerce, ecom.
static inline BOOL LTIsShopKey(NSString *s) {
    if (![s isKindOfClass:NSString.class] || !s.length) return NO;
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"(^|[_\\-. ])(shop|mall|ecom|ecommerce|e-commerce)([_\\-. ]|$)"
                                                       options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)] != nil;
}

#import "LiquidTok.h"

// The Duo layout, kept minimal. TikTok's binary is linked at 27.1 (scripts/patch_duo.sh), so the system
// gives it the full-edge inner-display layout per Apple's Duo guidance — no runtime window resizing (that
// hack interfered with the feed swipe across fold transitions) and no custom sidebar (TikTok's own bottom
// bar is cleaner throughout). This file now only keeps interactive top items inside the safe area and
// shortens the bottom bar a little.

// MARK: - Keep the feed's top corner items clear of the Duo camera

// The feed's top corner items (the search button, etc.) must stay inside the safe area so they don't
// slide under the Duo's inner camera. TikTok otherwise lets a corner item ignore the safe area; make it
// respect it (Apple's Duo guidance: interactive controls belong inside the safe area).
%group SearchSafeArea
%hook AWEFeedContainerViewController
- (BOOL)p_shouldIgnoreSafeAreaForEdgeItem:(id)item atPosition:(long long)position { return NO; }
%end
%end

// MARK: - Hide the Duo's status pill in the feed

// On the Duo, the status bar is a Liquid Glass pill running down the trailing edge, over the feed and its
// action column. Giovanni wants it gone; the only way an app can remove it is to hide the status bar
// (Apple's Duo guidance: hiding the status bar removes the pill and its region). Only on the Duo (its
// displays are wider than any iPhone held upright) and only in the feed, so a normal phone and other
// screens keep their status bar. Costs the clock/Wi-Fi in the feed.
static BOOL LTIsDuo(UIViewController *vc) {
    UIScreen *screen = vc.viewIfLoaded.window.windowScene.screen ?: UIScreen.mainScreen;
    CGSize s = screen.bounds.size;
    return MIN(s.width, s.height) >= 440;   // folded Duo is ~466pt across; no upright iPhone is that wide
}

%group StatusBar
%hook AWEFeedContainerViewController
- (BOOL)prefersStatusBarHidden { return LTIsDuo(self) ? YES : %orig; }
- (UIViewController *)childViewControllerForStatusBarHidden { return LTIsDuo(self) ? nil : %orig; }
%end
%hook AWEFeedRootViewController
- (BOOL)prefersStatusBarHidden { return LTIsDuo(self) ? YES : %orig; }
- (UIViewController *)childViewControllerForStatusBarHidden { return LTIsDuo(self) ? nil : %orig; }
%end
%end

// MARK: - Keep the right action column clear of the Duo status/camera pill

// The right-side like/comment/share/save column hugs the screen edge, so on the Duo it overlaps the
// system status pill (time/Wi-Fi/camera) that runs down the trailing edge. Widen its right margin by the
// window's right safe-area inset (0 on a normal phone, the pill's width on the Duo) so it sits just left
// of the pill — interactive controls inside the safe area, per Apple's Duo guidance.
static CGFloat LTRightSafeInset(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows)
            if (w.isKeyWindow) return w.safeAreaInsets.right;
    }
    return 0;
}

%group ActionColumn
%hook AWEPlayInteractionRightElement
- (double)rightMarginWidth { return %orig + LTRightSafeInset(); }
- (double)rightMarginWidthMusic { return %orig + LTRightSafeInset(); }
%end
%end

// MARK: - A slightly shorter bottom tab bar

// The manager is the single authority contentViewDesireFrame reads, so one hook moves both the bar and
// the content above it.
%group TabHeight
%hook TTKTabBarManager
- (double)heightForTabBar:(id)tabBar { return MAX(44.0, %orig - 16.0); }
%end
%end

%ctor {
    if (objc_getClass("AWEFeedContainerViewController")) %init(SearchSafeArea);
    if (objc_getClass("AWEFeedContainerViewController") || objc_getClass("AWEFeedRootViewController")) %init(StatusBar);
    if (objc_getClass("AWEPlayInteractionRightElement")) %init(ActionColumn);
    if (objc_getClass("TTKTabBarManager")) %init(TabHeight);
}

#import "LiquidTok.h"

// The Duo layout, kept minimal and stable. TikTok's binary is linked at 27.1 (scripts/patch_duo.sh), so
// the system gives it the full-edge inner-display layout per Apple's Duo guidance — no runtime window
// resizing and no custom sidebar (TikTok's own bottom bar is cleaner throughout). This file only keeps
// the feed's search/corner items inside the safe area (clear of the camera) and shortens the bottom bar.
//
// NOT done, and why: shifting TikTok's right action column (AWEPlayInteractionRightElement rightMarginWidth)
// to clear the status pill split the icons from their counts; and hiding the status bar on the feed VCs
// didn't remove the Duo status pill. Both need the real view frames (Debug.x 4-finger dump) to get right,
// so they're left out rather than shipped broken.

@interface AWEFeedContainerViewController : UIViewController @end
@interface AWEFeedRootViewController : UIViewController @end

// MARK: - Hide the Duo's status/camera pill in the feed

// On the Duo the status bar is a Liquid Glass strip down the trailing edge, over the feed. Hiding the
// status bar removes it (Apple's Duo guidance). Only on the Duo and only in the feed VCs, and this time
// forcing a status-bar update so the change actually applies (the earlier try set the value but never
// refreshed). If the pill survives this, it's a system-reserved element (like the Dynamic Island) an app
// can't remove.
static BOOL LTIsDuo(UIViewController *vc) {
    UIScreen *screen = vc.viewIfLoaded.window.windowScene.screen ?: UIScreen.mainScreen;
    CGSize s = screen.bounds.size;
    return MIN(s.width, s.height) >= 440;   // folded Duo is ~466pt across; no upright iPhone is that wide
}

%group StatusBar
%hook AWEFeedRootViewController
- (BOOL)prefersStatusBarHidden { return LTIsDuo(self) ? YES : %orig; }
- (UIViewController *)childViewControllerForStatusBarHidden { return LTIsDuo(self) ? nil : %orig; }
- (void)viewDidAppear:(BOOL)animated { %orig; if (LTIsDuo(self)) [self setNeedsStatusBarAppearanceUpdate]; }
%end
%hook AWEFeedContainerViewController
- (BOOL)prefersStatusBarHidden { return LTIsDuo(self) ? YES : %orig; }
- (UIViewController *)childViewControllerForStatusBarHidden { return LTIsDuo(self) ? nil : %orig; }
- (void)viewDidAppear:(BOOL)animated { %orig; if (LTIsDuo(self)) [self setNeedsStatusBarAppearanceUpdate]; }
%end
%end

// MARK: - Keep the feed's top corner items clear of the Duo camera

// The feed's top corner items (the search button, etc.) must stay inside the safe area so they don't
// slide under the Duo's inner camera. TikTok otherwise lets a corner item ignore the safe area; make it
// respect it (Apple's Duo guidance: interactive controls belong inside the safe area).
%group SearchSafeArea
%hook AWEFeedContainerViewController
- (BOOL)p_shouldIgnoreSafeAreaForEdgeItem:(id)item atPosition:(long long)position { return NO; }
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
    if (objc_getClass("TTKTabBarManager")) %init(TabHeight);
}

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
    if (objc_getClass("TTKTabBarManager")) %init(TabHeight);
}

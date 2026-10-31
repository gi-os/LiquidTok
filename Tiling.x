#import "LiquidTok.h"

// The Duo layout. TikTok's binary is linked at 27.1 (scripts/patch_duo.sh), so the system gives it the
// full-edge inner-display layout per Apple's Duo guidance; no runtime window resizing and no custom
// sidebar. This file keeps TikTok's plain phone layout in every pose (no Liquid Glass tab bar, no iPad
// split shell when unfolded), turns on the Duo fixes TikTok already ships behind server flags, keeps the
// feed's search/corner items inside the safe area and shortens the bottom bar.
//
// NOT done, and why: shifting TikTok's right action column (AWEPlayInteractionRightElement rightMarginWidth)
// to clear the status pill split the icons from their counts; and hiding the status bar on the feed VCs
// didn't remove the Duo status pill. Both need the real view frames (Debug.x 4-finger dump) to get right,
// so they're left out rather than shipped broken.

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

// MARK: - TikTok's plain tab bar, not its Liquid Glass one

// TikTok 47.5 draws its own Liquid Glass tab bar when TTKTabBarLiquidGlassConfig allows it. On the Duo
// that hinges on a fold-screen server flag (ttk_tabbar_fold_screen_liquid_glass_enabled) that only counts
// once TikTok's online settings have loaded, which is why the glass came and went between launches.
// Giovanni wants TikTok's plain bar, so the gate, the bar's own check and the button layout all say no.
%group NoGlassConfig
%hook TTKTabBarLiquidGlassConfig
+ (BOOL)isLiquidGlassTabBarAllowed { return NO; }
+ (BOOL)liquidGlassABEnabled { return NO; }
+ (BOOL)foldScreenLiquidGlassEnabled { return NO; }
+ (BOOL)nonFullScreenLiquidGlassEnabled { return NO; }
%end
%end

%group NoGlassDependency
%hook TTKBizUIComponentDependencyImpl
- (BOOL)isLiquidGlassTabBarAllowed { return NO; }
%end
%end

%group NoGlassBar
%hook TTKTabBar
- (BOOL)isLiquidGlassTabBarChromeEnabled { return NO; }
- (BOOL)supportsLiquidGlassFullBarBackground { return NO; }
%end
%end

%group NoGlassButtons
%hook TTKTabBarButtonDefaultContentView
- (BOOL)usesLiquidGlassButtonLayout { return NO; }
%end
%end

%group NoGlassSnapshot
%hook TTKTransitionTabBarSnapshotHelper
+ (BOOL)usesLiquidGlassChrome { return NO; }
%end
%end

// MARK: - The phone layout on the unfolded Duo, not TikTok's split shell

// TikTok ships its iPad "split shell" switched on for the iPhone Duo (ttk_split_framework_enable defaults
// on for iPhone19,4) and installs it once the window is >= 816pt wide, i.e. unfolded landscape. It swaps
// the window's root for a split host with a side panel (the "<" handle), stops TTKTabBarController sizing
// its own content, and the four tab buttons end up squeezed top-right over the status pill. Every reader
// funnels into one cached class method (dispatch_once, so hooked before TikTok first asks); answering NO
// is what every other iPhone already computes, so the bottom bar and feed stay the phone ones.
%group NoSplitShell
%hook TTKTabBarManager
+ (BOOL)isSplitShellFrameworkEnabled { return NO; }
%end
%end

%group NoSplitGate
%hook TTKSplitFrameworkGate
+ (BOOL)isEnabled { return NO; }
%end
%end

// MARK: - TikTok's own iPhone Duo fixes

// TikTok 47.5 already carries fixes for the iPhone Duo, each behind a server test flag (TTKABTest) that a
// sideloaded install isn't enrolled in. Turn ByteDance's own fixes on instead of re-deriving them: the
// profile page, the home feed's bottom offset and insets, the Explore tab bar height, comments, stories
// and the camera. Features (Duo remix, avatar duos) stay as the server says.
%group DuoFixes
%hook TTKABTest
+ (BOOL)profileDuoIssueFix { return YES; }
+ (BOOL)feedDuoHomeBottomOffsetEnable { return YES; }
+ (BOOL)feedDuoTableInsetContentFix { return YES; }
+ (BOOL)feedDuoCleanModeExitOnDisappearEnable { return YES; }
+ (BOOL)exploreDuoTabBarHeightFix { return YES; }
+ (BOOL)storyFriendsSkylightDuoLayerOrderFix { return YES; }
+ (BOOL)commentDuoGestureRestoreEnabled { return YES; }
+ (BOOL)commentDuoLivePreviewDismissEnabled { return YES; }
+ (BOOL)commentDuoDragTrackingFixEnabled { return YES; }
+ (BOOL)commentDuoPhotoTransitionFixEnabled { return YES; }
+ (BOOL)commentDuoAudioSidePanelFixEnabled { return YES; }
+ (BOOL)studioIphoneDuoRecordToolbarFix { return YES; }
+ (BOOL)studioIphoneDuoCameraOrientationFix { return YES; }
+ (BOOL)studioIphoneDuoRecordButtonLayoutFix { return YES; }
+ (BOOL)studioIphoneDuoRecordToolbarSafeAreaFix { return YES; }
+ (BOOL)studioIphoneDuoRecordLayoutFix { return YES; }
%end
%end

%ctor {
    if (objc_getClass("AWEFeedContainerViewController")) %init(SearchSafeArea);
    if (objc_getClass("TTKTabBarManager")) %init(TabHeight);
    if (objc_getClass("TTKTabBarLiquidGlassConfig")) %init(NoGlassConfig);
    if (objc_getClass("TTKBizUIComponentDependencyImpl")) %init(NoGlassDependency);
    if (objc_getClass("TTKTabBar")) %init(NoGlassBar);
    if (objc_getClass("TTKTabBarButtonDefaultContentView")) %init(NoGlassButtons);
    if (objc_getClass("TTKTransitionTabBarSnapshotHelper")) %init(NoGlassSnapshot);
    if (objc_getClass("TTKTabBarManager")) %init(NoSplitShell);
    if (objc_getClass("TTKSplitFrameworkGate")) %init(NoSplitGate);
    if (objc_getClass("TTKABTest")) %init(DuoFixes);
}

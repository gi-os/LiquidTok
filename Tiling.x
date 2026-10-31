#import "LiquidTok.h"
#import <mach-o/dyld.h>

// The Duo layout. TikTok's binary is linked at 27.1 (scripts/patch_duo.sh), so the system gives it the
// full-edge inner-display layout per Apple's Duo guidance; no runtime window resizing and no custom
// sidebar. TikTok's own bottom tab bar (no Liquid Glass) runs along the bottom in every pose; unfolded
// landscape also gets TikTok's tablet layout (its split shell: Profile/Inbox in a side panel beside the
// feed), while unfolded portrait and folded stay phone layout. This file also turns on the Duo fixes TikTok
// ships behind server flags, keeps the feed's search/corner items inside the safe area and shortens the bar.
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

// TikTok only gives the top bar's corner items a horizontal safe-area inset on some layouts
// (+topNavigationEdgeItemSafeAreaInsetInView:atLeft: returns 0 otherwise), so on the Duo's poses with the
// status-bar strip the search button sat at x=411 of 466, under the status pill. When TikTok says 0 but
// the view really has a side inset, use it: the corner moves out of the strip and the tab row narrows to
// fit. Plain iPhones have no side inset in portrait, so nothing changes there.
%group CornerSafeArea
%hook TTKFeedTopTabUIConfig
+ (double)topNavigationEdgeItemSafeAreaInsetInView:(UIView *)view atLeft:(BOOL)atLeft {
    double inset = %orig;
    if (inset > 0 || ![view isKindOfClass:UIView.class]) return inset;
    UIEdgeInsets safe = view.safeAreaInsets;
    return atLeft ? safe.left : safe.right;
}
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
+ (BOOL)isLiquidGlassTabBarAllowed { return NO; }   // its ObjC callers; LTPinGlassGateOff covers the Swift ones
%end
%end

// The gate is Swift: its ObjC method and its 12 direct Swift callers (tab bar setup, colours, layout, button
// layout, background alpha) all branch through one function pointer in MusicallyCore's writable __DATA
// (trampoline 0x1aeced34 loads slot 0x331702f8; arm64, no pointer authentication). Point it at a C "no", but
// only if it still holds 47.5.0's target, so any other TikTok build is left alone.
static BOOL LTNoLiquidGlassTabBar(void) { return NO; }

static void LTPinGlassGateOff(void) {
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name || !strstr(name, "/MusicallyCore.framework/MusicallyCore")) continue;
        uintptr_t base = (uintptr_t)_dyld_get_image_header(i);   // __TEXT's vmaddr is 0, so the header is the slide
        uintptr_t *slot = (uintptr_t *)(base + 0x331702f8);
        if (*slot == base + 0x1aececec) {
            *slot = (uintptr_t)LTNoLiquidGlassTabBar;
            LTLog(@"Duo: TikTok's Liquid Glass tab bar gate pinned to NO");
        } else {
            LTLog(@"Duo: the Liquid Glass gate slot isn't 47.5.0's; left alone");
        }
        return;
    }
}

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

// MARK: - TikTok's tablet layout (its split shell) on the unfolded Duo

// TikTok ships its iPad "split shell" switched on for the iPhone Duo (ttk_split_framework_enable defaults on
// for iPhone19,4). With it on, TikTok makes a split host the window's root in every pose (a navigation
// controller > TUXSidePanelController > TTKTabBarController as the main column), and once the window is at
// least 816pt wide (unfolded landscape; unfolded portrait is 669pt, so it keeps the phone layout, as an iPad
// mini does upright) it opens Profile, Inbox and the like in a side panel beside the feed. The real tab bar
// stays at the bottom of the main column (DuoBottomTabBar keeps it a bottom bar). Both answers are cached
// (dispatch_once) and hooked before TikTok first asks, so a server flag can't flip the shell between launches.
%group SplitShell
%hook TTKTabBarManager
+ (BOOL)isSplitShellFrameworkEnabled { return YES; }
%end
%end

%group SplitGate
%hook TTKSplitFrameworkGate
+ (BOOL)isEnabled { return YES; }
%end
%end

// MARK: - TikTok's bottom tab bar on the unfolded Duo

// TikTok keeps its real TTKTabBar in its own view and hands UIKit a stand-in (TTKFakeTabBar, a proxy whose
// frame/alpha/hidden go straight to the real bar). On the unfolded screen (regular width) UIKit lays tab
// bars out in its wide-screen container, top-right or as a sidebar, and that frame reaches the real bar
// through the proxy. TikTok fixes the same iPad behaviour by giving its tab bar controller a compact width
// class (pad_updateTraitOverrides), but only on iPads. Do it here on the phone idiom: the tab bar controller
// reads compact, so UIKit lays out the phone bottom bar, and every tab gets the window's real width class
// back, so the screens inside don't change. Written only when it differs, so it's cheap and follows
// fold/unfold. A tab the split shell later docks into its side panel leaves this controller, so its width
// override is removed again and it inherits as usual.
@interface TTKTabBarController : UITabBarController
@end

static NSHashTable<UIViewController *> *gLTSizedTabs;   // the tabs DuoBottomTabBar gave the window's width class

%group DuoBottomTabBar
%hook TTKTabBarController
- (void)viewWillLayoutSubviews {
    if (@available(iOS 17.0, *)) {
        UITraitCollection *scene = self.view.window.windowScene.traitCollection;
        if (scene && scene.userInterfaceIdiom == UIUserInterfaceIdiomPhone) {
            if (self.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassCompact) {
                self.traitOverrides.horizontalSizeClass = UIUserInterfaceSizeClassCompact;
                LTLog(@"Duo: tab bar controller set to compact width (window h%ld)", (long)scene.horizontalSizeClass);
            }
            if (!gLTSizedTabs) gLTSizedTabs = [NSHashTable weakObjectsHashTable];
            for (UIViewController *vc in gLTSizedTabs.allObjects) {
                if (vc.parentViewController == self) continue;
                [vc.traitOverrides removeTrait:UITraitHorizontalSizeClass.class];
                [gLTSizedTabs removeObject:vc];
                LTLog(@"Duo: %@ left the tab bar controller; its width class is inherited again", NSStringFromClass(vc.class));
            }
            UIUserInterfaceSizeClass real = scene.horizontalSizeClass;
            for (UIViewController *child in self.childViewControllers) {
                if (child.traitCollection.horizontalSizeClass != real) child.traitOverrides.horizontalSizeClass = real;
                [gLTSizedTabs addObject:child];
            }
        }
    }
    %orig;
}
%end
%end

// MARK: - No glass from UIKit's copy of the bar

// TikTok keeps its real TTKTabBar as a direct subview of the tab bar controller's view and gives UIKit a
// stand-in, TTKFakeTabBar, that forwards alpha/hidden/frame/bounds/addSubview: to the real bar, so it's
// never touched here (hiding it hides TikTok's bar). Two kinds of UIKit chrome get drawn for it on the Duo:
//  - around/beside it: iOS 27.1 lays the tab bar out in the status strip, an empty Liquid Glass capsule
//    (_UITabContainerView's floating host, _UITabBarExpansionPlatterContainer);
//  - inside TikTok's real bar: UIKit's glass item platter (UIKit._UITabBarItemPlatterView, its selection
//    lens) arrives through the stand-in's forwarded addSubview:. Zero-width when folded, but full width on
//    the unfolded portrait screen, where it's the glass pill behind the four buttons.
// Hide only UIKit's own views, and never one that holds TikTok's real bar or a tab's content.
static Class gLTStandInTabBarClass;

static BOOL LTHoldsTikTokViews(UIView *container, UIView *real, UIViewController *tabs) {
    if ([real isDescendantOfView:container]) return YES;
    for (UIViewController *c in tabs.childViewControllers)
        if (c.viewIfLoaded && [c.viewIfLoaded isDescendantOfView:container]) return YES;
    return NO;
}

static void LTHideChrome(UIView *v, NSString *where) {
    if (v.alpha == 0 && !v.userInteractionEnabled) return;
    v.alpha = 0;
    v.userInteractionEnabled = NO;
    LTLog(@"Duo: hid UIKit's %@ %@ %@ the tab bar", NSStringFromClass(v.class), NSStringFromCGRect(v.frame), where);
}

%group HideStandInChrome
%hook TTKTabBarController
- (void)viewDidLayoutSubviews {
    %orig;
    UITabBar *standIn = self.tabBar;
    if (!gLTStandInTabBarClass || ![standIn isKindOfClass:gLTStandInTabBarClass]) return;   // TikTok-owns mode only
    UIView *view = self.view, *real = LTObj(self, @"visualTabBar");                          // TikTok's own TTKTabBar
    if (![real isKindOfClass:UIView.class] || real == standIn || real.superview != view) return;
    if (!standIn.layer.hidden) {   // TikTok hides the stand-in's own layer at init; the layer isn't proxied
        standIn.layer.hidden = YES;
        LTLog(@"Duo: UIKit had shown the stand-in tab bar's layer; hid it again");
    }
    for (UIView *a = standIn.superview; a && a != view; a = a.superview) {
        if ([view isDescendantOfView:a]) break;                                               // never above this controller
        if ([NSStringFromClass(a.class) hasPrefix:@"_UI"] && !LTHoldsTikTokViews(a, real, self)) LTHideChrome(a, @"around");
    }
    for (UIView *v in view.subviews) {
        NSString *name = NSStringFromClass(v.class);
        if ([name hasPrefix:@"_UI"] && [name rangeOfString:@"Tab"].location != NSNotFound && !LTHoldsTikTokViews(v, real, self))
            LTHideChrome(v, @"beside");
    }
    for (UIView *v in real.subviews)
        if ([NSStringFromClass(v.class) rangeOfString:@"_UITabBar"].location != NSNotFound) LTHideChrome(v, @"inside");
}
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
    if (objc_getClass("TTKFeedTopTabUIConfig")) %init(CornerSafeArea);
    if (objc_getClass("TTKTabBarManager")) %init(TabHeight);
    if (objc_getClass("TTKTabBarLiquidGlassConfig")) { %init(NoGlassConfig); LTPinGlassGateOff(); }
    if (objc_getClass("TTKBizUIComponentDependencyImpl")) %init(NoGlassDependency);
    if (objc_getClass("TTKTabBar")) %init(NoGlassBar);
    if (objc_getClass("TTKTabBarButtonDefaultContentView")) %init(NoGlassButtons);
    if (objc_getClass("TTKTransitionTabBarSnapshotHelper")) %init(NoGlassSnapshot);
    if (objc_getClass("TTKTabBarManager")) %init(SplitShell);
    if (objc_getClass("TTKSplitFrameworkGate")) %init(SplitGate);
    if (objc_getClass("TTKTabBarController")) %init(DuoBottomTabBar);
    gLTStandInTabBarClass = objc_getClass("TTKFakeTabBar");
    if (gLTStandInTabBarClass && objc_getClass("TTKTabBarController")) %init(HideStandInChrome);
    if (objc_getClass("TTKABTest")) %init(DuoFixes);
}

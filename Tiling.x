#import "LiquidTok.h"

// The Duo layout, kept simple: with TikTok's binary linked at 27.1 (scripts/patch_duo.sh) the system
// gives it the full-edge inner-display layout, so its own bottom tab bar works on every pose. No custom
// glass sidebar — Giovanni found the normal bottom bar cleaner throughout. This file now just: (1) a
// safety net that fills the window on any pose the system still letterboxes, and (2) a slightly shorter
// bottom bar.

// MARK: - Full screen on the Duo (safety net)

// TikTok's own windows (the logged-in TTKAccountWindow, the login AWELoginWindow); popups are left alone.
static BOOL LTIsMainTikTokWindow(UIWindow *w) {
    Class login = objc_getClass("AWELoginWindow");
    Class account = objc_getClass("TTKAccountWindow");
    return (account && [w isKindOfClass:account]) || (login && [w isKindOfClass:login]);
}

static void LTFillScreen(UIWindow *w) {
    UIWindowScene *scene = w.windowScene;
    if (!scene) return;
    CGRect full = scene.screen.bounds;
    CGRect f = w.frame;
    // Letterboxed: full height, at the leading edge, but narrower than the screen by about a status-bar
    // strip (40–160pt). With the 27.1 patch this rarely fires; it's a fallback.
    CGFloat gap = full.size.width - f.size.width;
    if (gap > 40 && gap < 160 && fabs(full.size.height - f.size.height) < 3 &&
        f.origin.x < 1 && !CGRectEqualToRect(f, full)) {
        LTLog(@"Duo full-screen: %@ %@ -> %@", NSStringFromClass(w.class), NSStringFromCGRect(f), NSStringFromCGRect(full));
        w.frame = full;
    }
}

%group FullScreen
%hook UIWindow
- (void)layoutSubviews {
    %orig;
    if (LTIsMainTikTokWindow(self)) LTFillScreen(self);
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

%ctor {
    if (objc_getClass("AWELoginWindow") || objc_getClass("TTKAccountWindow")) %init(FullScreen);
    if (objc_getClass("TTKTabBarManager")) %init(TabHeight);
}

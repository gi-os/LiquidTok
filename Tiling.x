#import "LiquidTok.h"
#import <QuartzCore/QuartzCore.h>

// The iPhone Duo's wide poses: TikTok's bottom tab bar becomes a floating glass rail down the trailing
// strip the status bar runs in, so the video keeps the whole screen and the tabs sit under the thumb on
// the right. Mirrors LiquidBird's Twitter sidebar, on TikTok's own bar (TTKTabBarController's buttons,
// TTKTabBar the visual bar faded out meanwhile). Shop is already gone from the buttons (Tweak.x). Narrow
// poses (folded, or any plain iPhone) stay stock.

@interface TTKTabBarController : UIViewController
- (NSArray *)buttons;
- (long long)selectedIndex;
- (void)setSelectedIndex:(long long)index;
- (UIView *)buttonForIndex:(long long)index;
- (UIView *)visualTabBar;
@end

@interface TTKTabBarButton : UIControl
- (long long)index;
- (long long)type;
@end

@interface TTKTabBar : UIView
@end

static const CGFloat LTSidebarWindow = 600;     // wider than any iPhone upright: the Duo's unfolded pose
static const CGFloat LTGlassWidth = 56;
static const CGFloat LTRow = 52;

static const void *kLTSidebar = &kLTSidebar;
static const void *kLTWantedAlpha = &kLTWantedAlpha;

static BOOL LTSidebarWanted(UIWindow *w) {
    // Only the Duo's wide (unfolded) pose, where there's room beside the video for a rail. The folded
    // pose stays stock — TikTok's bottom tab bar is fine on a tall, narrow screen.
    return w && w.bounds.size.width >= LTSidebarWindow;
}

static UIVisualEffectView *LTGlassView(void) {
    UIVisualEffect *effect;
    if (@available(iOS 26, *)) {
        UIGlassEffect *g = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        g.interactive = YES;
        effect = g;
    } else {
        effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    }
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:effect];
    v.layer.cornerCurve = kCACornerCurveContinuous;
    return v;
}

// A snapshot of one of TikTok's own tab buttons, so the rail shows exactly its icon (Home, Friends, the
// red +, Inbox, Profile), selected or not, without us owning any of its art.
static UIImage *LTButtonSnapshot(UIView *button) {
    if (button.bounds.size.width < 1 || button.bounds.size.height < 1) return nil;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.opaque = NO;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithBounds:button.bounds format:fmt];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [button drawViewHierarchyInRect:button.bounds afterScreenUpdates:NO];
    }];
}

// MARK: - The rail

@interface LTSidebar : UIView
@property (nonatomic) BOOL onRight;   // which edge the Duo's status strip is on
@property (nonatomic, copy) void (^activate)(NSInteger);
- (void)setButtonImages:(NSArray<UIImage *> *)images selected:(NSInteger)selected;
@end

@implementation LTSidebar {
    UIVisualEffectView *_rail;
    NSMutableArray<UIButton *> *_buttons;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        _rail = LTGlassView();
        [self addSubview:_rail];
        _buttons = [NSMutableArray array];
    }
    return self;
}

// Only the glass takes touches; the strip around it stays TikTok's (its video scrubber, say).
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return !_rail.hidden && CGRectContainsPoint(_rail.frame, point);
}

- (void)tapped:(UIButton *)b { if (self.activate) self.activate(b.tag); }

- (void)setButtonImages:(NSArray<UIImage *> *)images selected:(NSInteger)selected {
    while (_buttons.count > images.count) { [_buttons.lastObject removeFromSuperview]; [_buttons removeLastObject]; }
    while (_buttons.count < images.count) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.layer.cornerCurve = kCACornerCurveContinuous;
        b.imageView.contentMode = UIViewContentModeScaleAspectFit;
        [b addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
        [_rail.contentView addSubview:b];
        [_buttons addObject:b];
    }
    for (NSUInteger i = 0; i < images.count; i++) {
        UIButton *b = _buttons[i];
        b.tag = (NSInteger)i;
        [b setImage:[images[i] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forState:UIControlStateNormal];
        // The selected tab sits on a lighter lozenge, as in the system's glass tab bar.
        b.backgroundColor = (NSInteger)i == selected ? [UIColor colorWithWhite:1 alpha:0.16] : UIColor.clearColor;
    }
    [self setNeedsLayout];
}

// On the edge where the Duo runs its status strip (set by whoever places the bar), tucked to the TOP of
// that edge so it sits above TikTok's like/comment/share column (which runs down the centre to the
// bottom) and below the top tab row. A compact pill, only the glass takes touches.
- (void)layoutSubviews {
    [super layoutSubviews];
    NSUInteger n = _buttons.count;
    CGFloat pad = 4, inner = LTGlassWidth - 2 * pad, row = 48;
    CGFloat rail = n * row + 2 * pad;
    CGFloat x = _onRight ? self.bounds.size.width - LTGlassWidth - 16 - MAX(self.safeAreaInsets.right - 16, 0)
                         : 16 + MAX(self.safeAreaInsets.left - 16, 0);
    CGFloat y = MAX(self.safeAreaInsets.top, 20) + 72;   // below the status row and the top tabs
    _rail.hidden = n == 0;
    _rail.frame = CGRectMake(x, y, LTGlassWidth, rail);
    _rail.layer.cornerRadius = LTGlassWidth / 2;
    for (NSUInteger i = 0; i < n; i++) {
        UIButton *b = _buttons[i];
        b.frame = CGRectMake(pad, pad + i * row, inner, row);
        b.layer.cornerRadius = inner / 2;
    }
}
@end

// MARK: - Placing it

static void LTUpdateSidebar(TTKTabBarController *controller) {
    UIView *host = controller.viewIfLoaded;
    UIWindow *w = host.window;
    LTSidebar *bar = objc_getAssociatedObject(controller, kLTSidebar);
    NSArray *buttons = [controller respondsToSelector:@selector(buttons)] ? [controller buttons] : nil;
    if (!host || !LTSidebarWanted(w) || ![buttons isKindOfClass:NSArray.class] || buttons.count == 0) {
        [bar removeFromSuperview];
        return;
    }
    if (!bar) {
        bar = [[LTSidebar alloc] initWithFrame:CGRectZero];
        __weak TTKTabBarController *weak = controller;
        bar.activate = ^(NSInteger i) {
            TTKTabBarController *c = weak;
            NSArray *now = [c buttons];
            if (i >= (NSInteger)now.count) return;
            UIView *button = now[i];
            // As a tap does: the button's own touch-up action (scroll-to-top and double-tap handled
            // there), or the controller's selection if it isn't wired that way.
            if ([button isKindOfClass:UIControl.class] &&
                ([(UIControl *)button allControlEvents] & UIControlEventTouchUpInside)) {
                [(UIControl *)button sendActionsForControlEvents:UIControlEventTouchUpInside];
            } else if ([c respondsToSelector:@selector(setSelectedIndex:)]) {
                long long index = [button respondsToSelector:@selector(index)] ? [(TTKTabBarButton *)button index] : i;
                [c setSelectedIndex:index];
            }
        };
        objc_setAssociatedObject(controller, kLTSidebar, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (bar.superview != host) [host addSubview:bar];
    [host bringSubviewToFront:bar];
    // Follow the Duo: it runs the status bar down one side as a strip (a large left/right safe-area
    // inset). Put the rail on that edge; if the status bar is on top instead (no side strip), use the
    // trailing edge, where the Duo keeps its chrome. The rail sits at the top of the edge, clear of
    // TikTok's own action column lower down.
    UIEdgeInsets safe = host.safeAreaInsets;
    bar.onRight = !(safe.left >= 40 && safe.left > safe.right);
    bar.frame = host.bounds;
    LTLog(@"sidebar: host %@ safe %@ -> %@", NSStringFromCGRect(host.bounds),
          NSStringFromUIEdgeInsets(safe), bar.onRight ? @"right edge" : @"left edge");

    NSInteger selected = -1;
    long long selectedIndex = [controller respondsToSelector:@selector(selectedIndex)] ? [controller selectedIndex] : -1;
    NSMutableArray<UIImage *> *images = [NSMutableArray array];
    UIImage *blank = nil;
    for (NSUInteger i = 0; i < buttons.count; i++) {
        UIView *button = buttons[i];
        if (![button isKindOfClass:UIView.class]) continue;
        long long index = [button respondsToSelector:@selector(index)] ? [(TTKTabBarButton *)button index] : (long long)i;
        if (index == selectedIndex) selected = (NSInteger)images.count;
        UIImage *snap = LTButtonSnapshot(button);
        if (!snap) {
            if (!blank)
                blank = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1, 1)]
                         imageWithActions:^(UIGraphicsImageRendererContext *ctx) {}];
            snap = blank;
        }
        [images addObject:snap];
    }
    [bar setButtonImages:images selected:selected];
}

// X's own bottom bar fades out while the rail stands in for it; the alpha TikTok asks for is kept.
static CGFloat LTWantedAlpha(UIView *v) {
    NSNumber *n = objc_getAssociatedObject(v, kLTWantedAlpha);
    return n ? n.doubleValue : 1;
}

static CGFloat LTBarAlpha(UIView *v, CGFloat wanted) {
    objc_setAssociatedObject(v, kLTWantedAlpha, @(wanted), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return LTSidebarWanted(v.window) ? 0 : wanted;
}

// MARK: - Full screen on the Duo

// Unlike Twitter, TikTok sizes its main windows to the screen minus the side status-bar strip (e.g. a
// 386pt window on the Duo's 466pt display), leaving the strip black and — since the window then reports
// no right safe-area inset — keeping the sidebar from ever triggering. Its own fold/split-shell layout
// (TikTokPadImpl, splitShellFrameworkEnabled) is gated behind server flags that are off. So its two main
// windows (the logged-in TTKAccountWindow and the login AWELoginWindow; popups and the small live window
// are left alone) are grown to the full screen, which makes the strip a right safe-area inset like X's.
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
    // strip (40–160pt). A genuinely full (or folded-narrow) window has no gap and is left alone.
    CGFloat gap = full.size.width - f.size.width;
    if (gap > 40 && gap < 160 && fabs(full.size.height - f.size.height) < 3 &&
        f.origin.x < 1 && !CGRectEqualToRect(f, full)) {
        LTLog(@"Duo full-screen: %@ %@ -> %@ (safe before %@)", NSStringFromClass(w.class),
              NSStringFromCGRect(f), NSStringFromCGRect(full), NSStringFromUIEdgeInsets(w.safeAreaInsets));
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

%group Tiling
%hook TTKTabBarController
- (void)viewDidLayoutSubviews {
    %orig;
    @try { LTUpdateSidebar(self); } @catch (__unused NSException *e) {}
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try { LTUpdateSidebar(self); } @catch (__unused NSException *e) {}
}
%end

// The visual bar faded out (and taking no touches) while the rail shows; its alpha kept for when the
// window narrows again.
%hook TTKTabBar
- (void)didMoveToWindow {
    %orig;
    [self setAlpha:LTWantedAlpha(self)];
}
- (void)layoutSubviews {
    %orig;
    [self setAlpha:LTWantedAlpha(self)];
}
- (void)setAlpha:(CGFloat)alpha {
    %orig(LTBarAlpha(self, alpha));
}
%end
%end

%ctor {
    if (objc_getClass("AWELoginWindow") || objc_getClass("TTKAccountWindow")) %init(FullScreen);
    if (objc_getClass("TTKTabBarController") && objc_getClass("TTKTabBar")) %init(Tiling);
}

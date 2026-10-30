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

static const CGFloat LTSidebarWindow = 600;     // wider than any iPhone upright: the Duo's poses
static const CGFloat LTGlassWidth = 56;
static const CGFloat LTRow = 52;
static const CGFloat LTStripDefault = 66;

static const void *kLTSidebar = &kLTSidebar;
static const void *kLTSideStrip = &kLTSideStrip;
static const void *kLTWantedAlpha = &kLTWantedAlpha;

// The strip down the trailing edge the Duo's status bar runs in (a right-only safe area), remembered per
// window size: hiding the status bar takes its inset away, so the last seen value stands in meanwhile.
static CGFloat LTSideStrip(UIWindow *w) {
    if (!w) return 0;
    UIEdgeInsets safe = w.safeAreaInsets;
    NSValue *size = [NSValue valueWithCGSize:w.bounds.size];
    NSArray *seen = objc_getAssociatedObject(w, kLTSideStrip);
    if (safe.right >= 40 && safe.left < 20) {
        if (![seen.lastObject isEqual:size] || fabs([seen.firstObject doubleValue] - safe.right) >= 0.5)
            objc_setAssociatedObject(w, kLTSideStrip, @[@(safe.right), size], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return safe.right;
    }
    return [seen.lastObject isEqual:size] ? [seen.firstObject doubleValue] : 0;
}

static BOOL LTSidebarWanted(UIWindow *w) {
    if (!w) return NO;
    return w.bounds.size.width >= LTSidebarWindow || LTSideStrip(w) > 0;
}

static CGFloat LTStripWidth(UIView *host) {
    CGFloat r = LTSideStrip(host.window);
    return r > 0 ? r : LTStripDefault;
}

// Under the status bar: its inset, or (on the Duo, where it runs down the side and iOS reports a 2pt top
// line) the measured point its clock and Wi-Fi end.
static CGFloat LTStatusBottom(UIView *host) {
    return host.safeAreaInsets.top < 1 ? 150 : host.safeAreaInsets.top + 12;
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
@property (nonatomic) CGFloat top;
@property (nonatomic) CGFloat centreOffset;
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

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat mid = round(self.bounds.size.width / 2 + self.centreOffset);
    CGFloat bottom = self.bounds.size.height - MAX(self.safeAreaInsets.bottom, 16);
    CGFloat room = bottom - self.top;
    NSUInteger n = _buttons.count;
    CGFloat pad = 4, inner = LTGlassWidth - 2 * pad;
    CGFloat row = n ? MAX(40, MIN(LTRow, floor((room - 2 * pad) / n))) : LTRow;
    CGFloat rail = n * row + 2 * pad;
    CGFloat y = bottom - rail;
    _rail.hidden = n == 0;
    _rail.frame = CGRectMake(mid - LTGlassWidth / 2, y, LTGlassWidth, rail);
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
    CGFloat strip = LTStripWidth(host);
    bar.frame = CGRectMake(host.bounds.size.width - strip, 0, strip, host.bounds.size.height);
    bar.top = LTStatusBottom(host);
    bar.centreOffset = host.safeAreaInsets.top < 1 ? -5 : 0;

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

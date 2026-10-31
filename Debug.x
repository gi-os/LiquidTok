#import "LiquidTok.h"
#if __has_include("DumpURL.h")
#import "DumpURL.h"   // written by scripts/build.sh only for a diagnostic build (LT_DUMP_URL); never committed
#endif

// Working on LiquidTok without FLEX: press and hold anywhere with FOUR fingers and the window's view and
// view-controller hierarchies are copied to the pasteboard, for Giovanni to paste to Claude. Classes,
// frames, hidden/alpha, accessibility identifiers and control labels only; cells are listed by class
// without their contents, so no post text or DMs are copied. The copy also carries what LiquidTok has
// hidden so far (Tweak.x) and its recent layout changes (Tiling.x).

static NSMutableArray<NSArray *> *LTLogLines(void) {
    static NSMutableArray *lines;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lines = [NSMutableArray array]; });
    return lines;
}

void LTLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSMutableArray *lines = LTLogLines();
    [lines addObject:@[@(CFAbsoluteTimeGetCurrent()), line]];
    if (lines.count > 120) [lines removeObjectAtIndex:0];
}

static NSString *LTPad(NSInteger depth) {
    return [@"" stringByPaddingToLength:(NSUInteger)depth * 2 withString:@" " startingAtIndex:0];
}

static void LTDumpView(UIView *v, NSInteger depth, NSMutableString *out, NSInteger *lines) {
    if (*lines >= 1500) return;
    (*lines)++;
    [out appendFormat:@"%@%@ %@", LTPad(depth), NSStringFromClass(v.class), NSStringFromCGRect(v.frame)];
    if (v.hidden) [out appendString:@" hidden"];
    if (v.alpha < 0.99) [out appendFormat:@" a=%.2f", v.alpha];
    if (v.accessibilityIdentifier.length) [out appendFormat:@" id=%@", v.accessibilityIdentifier];
    if ([v isKindOfClass:UIScrollView.class]) {
        UIScrollView *sv = (UIScrollView *)v;
        [out appendFormat:@" offset=%@ inset=%@", NSStringFromCGPoint(sv.contentOffset),
                          NSStringFromUIEdgeInsets(sv.adjustedContentInset)];
    }
    if ([v.nextResponder isKindOfClass:UIViewController.class])
        [out appendFormat:@" safe=%@", NSStringFromUIEdgeInsets(v.safeAreaInsets)];
    BOOL cell = [v isKindOfClass:UITableViewCell.class] || [v isKindOfClass:UICollectionViewCell.class];
    if (!cell && ([v isKindOfClass:UIControl.class] || v.isAccessibilityElement) && v.accessibilityLabel.length)
        [out appendFormat:@" label=%@", [v.accessibilityLabel substringToIndex:MIN(v.accessibilityLabel.length, (NSUInteger)40)]];
    [out appendString:@"\n"];
    if (depth >= 45 || cell) return;
    for (UIView *s in v.subviews) LTDumpView(s, depth + 1, out, lines);
}

static void LTDumpViewController(UIViewController *vc, NSInteger depth, NSMutableString *out) {
    UIView *v = vc.viewIfLoaded;
    [out appendFormat:@"%@%@ view=%@ %@ additionalSafe=%@\n", LTPad(depth), NSStringFromClass(vc.class),
                      v ? NSStringFromClass(v.class) : @"-", v ? NSStringFromCGRect(v.frame) : @"",
                      NSStringFromUIEdgeInsets(vc.additionalSafeAreaInsets)];
    for (UIViewController *c in vc.childViewControllers) LTDumpViewController(c, depth + 1, out);
    UIViewController *p = vc.presentedViewController;
    if (p && p.presentingViewController == vc) {
        [out appendFormat:@"%@presents (style %ld):\n", LTPad(depth + 1), (long)p.modalPresentationStyle];
        LTDumpViewController(p, depth + 2, out);
    }
}

// The views that decide the Duo layout, with frames in window coordinates (the main dump's frames are
// relative to each superview, and it can run out of lines before reaching the tab bar).
static void LTFindLayoutViews(UIView *v, UIWindow *w, NSMutableString *out, NSInteger *n) {
    if (*n >= 300) return;
    NSString *name = NSStringFromClass(v.class);
    for (NSString *s in @[@"TabBar", @"TabCorner", @"SidePanel", @"SplitShell", @"Glass", @"InteractionRight", @"RightElement"]) {
        if ([name rangeOfString:s].location == NSNotFound) continue;
        (*n)++;
        [out appendFormat:@"%@ %@%@%@ in %@\n", name, NSStringFromCGRect([v convertRect:v.bounds toView:w]),
                          v.hidden ? @" hidden" : @"", v.alpha < 0.99 ? [NSString stringWithFormat:@" a=%.2f", v.alpha] : @"",
                          NSStringFromClass(v.superview.class)];
        break;
    }
    for (UIView *s in v.subviews) LTFindLayoutViews(s, w, out, n);
}

static NSString *LTDumpText(UIWindow *w) {
    UIWindowScene *scene = w.windowScene;
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"LiquidTok layout dump, iOS %@, idiom %ld, scale %.0f, build %@\n", UIDevice.currentDevice.systemVersion,
                      (long)UIDevice.currentDevice.userInterfaceIdiom, w.traitCollection.displayScale,
                      NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]];
    [out appendFormat:@"screen %@ orientation %ld designCompat %@\n", NSStringFromCGRect(scene.screen.bounds),
                      (long)scene.interfaceOrientation, NSBundle.mainBundle.infoDictionary[@"UIDesignRequiresCompatibility"]];
    [out appendFormat:@"window %@ safeArea %@ sizeClass h%ld v%ld\n", NSStringFromCGRect(w.bounds),
                      NSStringFromUIEdgeInsets(w.safeAreaInsets), (long)w.traitCollection.horizontalSizeClass,
                      (long)w.traitCollection.verticalSizeClass];
    [out appendFormat:@"statusBar %@%@\n", NSStringFromCGRect(scene.statusBarManager.statusBarFrame),
                      scene.statusBarManager.isStatusBarHidden ? @" hidden" : @""];
    [out appendFormat:@"filters: %@\n\n", LTFilterSummary()];
    [out appendString:@"== LiquidTok's log (seconds before this copy)\n"];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    for (NSArray *entry in LTLogLines())
        [out appendFormat:@"%7.2f  %@\n", now - [entry.firstObject doubleValue], entry.lastObject];
    [out appendString:@"\n== layout views (window coordinates)\n"];
    NSInteger found = 0;
    LTFindLayoutViews(w, w, out, &found);
    [out appendString:@"\n== view controllers\n"];
    if (w.rootViewController) LTDumpViewController(w.rootViewController, 0, out);
    [out appendString:@"\n== views\n"];
    NSInteger lines = 0;
    LTDumpView(w, 0, out, &lines);
    return out;
}

@interface LTDumper : NSObject
+ (instancetype)shared;
- (void)pressed:(UILongPressGestureRecognizer *)g;
@end

@implementation LTDumper
+ (instancetype)shared {
    static LTDumper *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [LTDumper new]; });
    return d;
}

- (void)pressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIWindow *w = (UIWindow *)g.view;
    NSString *out = LTDumpText(w);
    UIPasteboard.generalPasteboard.string = out;

    UIViewController *top = w.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Layout copied"
                                                               message:@"Paste it to Claude."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [top presentViewController:a animated:YES completion:nil];
}
@end

#ifdef LT_DUMP_URL
// Diagnostic builds only: send the same dump to Giovanni's Mac mini (scripts/dump_receiver.sh) whenever the
// window's shape or the screen on top changes (launch, fold/unfold, rotation, another tab, a profile), so
// the Duo layout can be fixed from real frames without anyone pasting anything. At most one every 8s and
// 60 per launch.
static NSString *LTShape(UIWindow *w) {
    NSMutableString *shape = [NSMutableString stringWithFormat:@"%@ h%ld v%ld", NSStringFromCGRect(w.bounds),
                              (long)w.traitCollection.horizontalSizeClass, (long)w.traitCollection.verticalSizeClass];
    UIViewController *vc = w.rootViewController;
    for (int depth = 0; vc && depth < 12; depth++) {
        [shape appendFormat:@">%@", NSStringFromClass(vc.class)];
        UIViewController *next = vc.presentedViewController;
        if (!next) next = LTObj(vc, @"selectedViewController");
        if (!next && [vc isKindOfClass:UINavigationController.class]) next = ((UINavigationController *)vc).topViewController;
        vc = [next isKindOfClass:UIViewController.class] ? next : nil;
    }
    return shape;
}

static void LTSendDump(UIWindow *w, NSString *reason) {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@LT_DUMP_URL]];
    req.HTTPMethod = @"POST";
    [req setValue:reason forHTTPHeaderField:@"X-LT-Reason"];
    [req setValue:@"text/plain; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [LTDumpText(w) dataUsingEncoding:NSUTF8StringEncoding];
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    });
    [[session dataTaskWithRequest:req] resume];
}

static void LTStartAutoDump(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        static NSString *last;
        static int sent;
        dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), (uint64_t)(8 * NSEC_PER_SEC), (uint64_t)NSEC_PER_SEC);
        dispatch_source_set_event_handler(t, ^{
            if (sent >= 60 || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            UIWindow *w = nil;
            for (UIScene *sc in UIApplication.sharedApplication.connectedScenes)
                if ([sc isKindOfClass:UIWindowScene.class])
                    for (UIWindow *win in ((UIWindowScene *)sc).windows) if (win.isKeyWindow) w = win;
            if (!w) return;
            NSString *shape = LTShape(w);
            if ([shape isEqualToString:last]) return;
            NSString *reason = last ? @"change" : @"launch";
            last = shape;
            sent++;
            LTSendDump(w, reason);
        });
        dispatch_resume(t);
        objc_setAssociatedObject(UIApplication.sharedApplication, &once, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}
#endif

static const void *kLTDumpGesture = &kLTDumpGesture;

%hook UIWindow
- (void)becomeKeyWindow {
    %orig;
#ifdef LT_DUMP_URL
    LTStartAutoDump();
#endif
    if (objc_getAssociatedObject(self, kLTDumpGesture)) return;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:[LTDumper shared]
                                                                                    action:@selector(pressed:)];
    g.numberOfTouchesRequired = 4;   // not 3: the Duo (iPad-class) reserves 3-finger gestures for system copy/paste
    g.minimumPressDuration = 1.0;
    g.cancelsTouchesInView = NO;
    [self addGestureRecognizer:g];
    objc_setAssociatedObject(self, kLTDumpGesture, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

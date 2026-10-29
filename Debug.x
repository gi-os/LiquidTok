#import "LiquidTok.h"

// Working on LiquidTok without FLEX: press and hold anywhere with three fingers and the window's view and
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
    UIWindowScene *scene = w.windowScene;
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"LiquidTok layout dump, iOS %@, idiom %ld, scale %.0f\n", UIDevice.currentDevice.systemVersion,
                      (long)UIDevice.currentDevice.userInterfaceIdiom, w.traitCollection.displayScale];
    [out appendFormat:@"window %@ safeArea %@ sizeClass h%ld v%ld\n", NSStringFromCGRect(w.bounds),
                      NSStringFromUIEdgeInsets(w.safeAreaInsets), (long)w.traitCollection.horizontalSizeClass,
                      (long)w.traitCollection.verticalSizeClass];
    [out appendFormat:@"statusBar %@%@\n", NSStringFromCGRect(scene.statusBarManager.statusBarFrame),
                      scene.statusBarManager.isStatusBarHidden ? @" hidden" : @""];
    [out appendFormat:@"filters: %@\n\n", LTFilterSummary()];
    [out appendString:@"== LiquidTok's layout changes (seconds before this copy)\n"];
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    for (NSArray *entry in LTLogLines())
        [out appendFormat:@"%7.2f  %@\n", now - [entry.firstObject doubleValue], entry.lastObject];
    [out appendString:@"\n== view controllers\n"];
    if (w.rootViewController) LTDumpViewController(w.rootViewController, 0, out);
    [out appendString:@"\n== views\n"];
    NSInteger lines = 0;
    LTDumpView(w, 0, out, &lines);
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

static const void *kLTDumpGesture = &kLTDumpGesture;

%hook UIWindow
- (void)becomeKeyWindow {
    %orig;
    if (objc_getAssociatedObject(self, kLTDumpGesture)) return;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:[LTDumper shared]
                                                                                    action:@selector(pressed:)];
    g.numberOfTouchesRequired = 3;
    g.minimumPressDuration = 1.0;
    g.cancelsTouchesInView = NO;
    [self addGestureRecognizer:g];
    objc_setAssociatedObject(self, kLTDumpGesture, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

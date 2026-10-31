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

static const void *kLTDumpGesture = &kLTDumpGesture;

static void LTAttachDumpGesture(UIWindow *w) {
    if (!w || objc_getAssociatedObject(w, kLTDumpGesture)) return;
    UILongPressGestureRecognizer *g = [[UILongPressGestureRecognizer alloc] initWithTarget:[LTDumper shared]
                                                                                    action:@selector(pressed:)];
    g.numberOfTouchesRequired = 4;   // not 3: the Duo reserves 3-finger gestures for system copy/paste
    g.minimumPressDuration = 1.0;
    g.cancelsTouchesInView = NO;
    [w addGestureRecognizer:g];
    objc_setAssociatedObject(w, kLTDumpGesture, g, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Every window of every connected scene, and the key one (or the first foreground one's first window).
static UIWindow *LTEachWindow(void (^body)(UIWindow *)) {
    UIWindow *key = nil, *first = nil;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *win in ((UIWindowScene *)sc).windows) {
            if (body) body(win);
            if (win.isKeyWindow) key = win;
            if (!first && sc.activationState == UISceneActivationStateForegroundActive) first = win;
        }
    }
    return key ?: first;
}

#ifdef LT_DUMP_URL
#import <Network/Network.h>

// Diagnostic builds only: send the dump to Giovanni's Mac mini (scripts/dump_receiver.sh) whenever the
// window's shape or the screen on top changes (launch, fold/unfold, rotation, another tab, a profile), so
// the Duo layout can be fixed from real frames without anyone pasting anything. At most one every 8s and
// 60 per launch. Sent over Network.framework, not NSURLSession (TikTok's network stack hooks the URL
// loading system, and the first diagnostic build's reports never arrived), and started from the tweak's
// constructor and app activation rather than -becomeKeyWindow, which TikTok's window may not reach.
static void LTPost(NSString *reason, NSData *body) {
    static dispatch_queue_t queue;
    static NSURL *url;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("liquidtok.dump", DISPATCH_QUEUE_SERIAL);
        url = [NSURL URLWithString:@LT_DUMP_URL];
    });
    if (!url.host.length || !body) return;
    NSMutableData *request = [[[NSString stringWithFormat:@"POST %@ HTTP/1.1\r\nHost: %@\r\nContent-Type: text/plain; charset=utf-8\r\n"
                                                          @"X-LT-Reason: %@\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
                                url.path, url.host, reason, (unsigned long)body.length]
                               dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [request appendData:body];
    nw_parameters_t params = nw_parameters_create_secure_tcp(NW_PARAMETERS_DEFAULT_CONFIGURATION,
                                                             NW_PARAMETERS_DEFAULT_CONFIGURATION);
    __block nw_connection_t connection = nw_connection_create(nw_endpoint_create_host(url.host.UTF8String, "443"), params);
    nw_connection_set_queue(connection, queue);
    // The handler holds the connection until it's cancelled, then lets go.
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        if (state == nw_connection_state_ready) {
            dispatch_data_t data = dispatch_data_create(request.bytes, request.length, queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            nw_connection_send(connection, data, NW_CONNECTION_FINAL_MESSAGE_CONTEXT, true, ^(nw_error_t sendError) {
                nw_connection_receive(connection, 1, 4096, ^(dispatch_data_t content, nw_content_context_t context,
                                                             bool complete, nw_error_t receiveError) {
                    nw_connection_cancel(connection);
                });
            });
        } else if (state == nw_connection_state_failed) {
            nw_connection_cancel(connection);
        } else if (state == nw_connection_state_cancelled) {
            connection = nil;
        }
    });
    nw_connection_start(connection);
}

static NSString *LTShape(UIWindow *w) {
    NSMutableString *shape = [NSMutableString stringWithFormat:@"%@ h%ld v%ld", NSStringFromCGRect(w.bounds),
                              (long)w.traitCollection.horizontalSizeClass, (long)w.traitCollection.verticalSizeClass];
    UIViewController *vc = w.rootViewController;
    for (int depth = 0; vc && depth < 12; depth++) {
        [shape appendFormat:@">%@", NSStringFromClass(vc.class)];
        UIViewController *next = vc.presentedViewController;
        id side = next ? nil : LTObj(vc, @"secondaryViewController");   // TikTok's split shell: its side panel
        if ([side isKindOfClass:UIViewController.class])
            [shape appendFormat:@"[side %@ state %lld]", NSStringFromClass([side class]), LTInt(vc, @"state")];
        if (!next) next = LTObj(vc, @"selectedViewController");
        if (!next && [vc isKindOfClass:UINavigationController.class]) next = ((UINavigationController *)vc).topViewController;
        if (!next) next = LTObj(vc, @"primaryViewController");          // ...and its main column, the tab bar controller
        vc = [next isKindOfClass:UIViewController.class] ? next : nil;
    }
    return shape;
}

static void LTStartAutoDump(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSDictionary *info = NSBundle.mainBundle.infoDictionary;
        LTPost(@"hello", [[NSString stringWithFormat:@"hello: LiquidTok diagnostic build %@, iOS %@, designCompat %@\n",
                           info[@"CFBundleVersion"], UIDevice.currentDevice.systemVersion,
                           info[@"UIDesignRequiresCompatibility"]] dataUsingEncoding:NSUTF8StringEncoding]);
        static NSString *last;
        static int sent;
        dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
                                  (uint64_t)(8 * NSEC_PER_SEC), (uint64_t)NSEC_PER_SEC);
        dispatch_source_set_event_handler(t, ^{
            if (sent >= 60 || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
            UIWindow *w = LTEachWindow(^(UIWindow *win) { LTAttachDumpGesture(win); });
            if (!w) return;
            NSString *shape = LTShape(w);
            if ([shape isEqualToString:last]) return;
            NSString *reason = last ? @"change" : @"launch";
            last = shape;
            sent++;
            LTPost(reason, [LTDumpText(w) dataUsingEncoding:NSUTF8StringEncoding]);
        });
        dispatch_resume(t);
        objc_setAssociatedObject(UIApplication.sharedApplication, &once, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}
#endif

// TikTok's API errors, into the log the dump carries: every response is parsed through Mantle, so a
// non-zero status_code (and its status_msg), or a response model that fails to parse, shows up here with
// the response class. How "Something went wrong" on profiles and saving gets a real reason.
@interface MTLJSONAdapter : NSObject
@end

%group APIErrors
%hook MTLJSONAdapter
+ (id)modelOfClass:(Class)modelClass fromJSONDictionary:(NSDictionary *)json error:(NSError **)error {
    id model = %orig;
    if ([json isKindOfClass:NSDictionary.class]) {
        id code = json[@"status_code"];
        if ([code respondsToSelector:@selector(integerValue)] && [code integerValue] != 0) {
            id msg = json[@"status_msg"] ?: json[@"message"];
            LTLog(@"API %@: status_code %@ %@", NSStringFromClass(modelClass), code,
                  [msg isKindOfClass:NSString.class] ? [msg substringToIndex:MIN([msg length], (NSUInteger)120)] : @"");
        } else if (!model && [NSStringFromClass(modelClass) rangeOfString:@"Response"].location != NSNotFound) {
            LTLog(@"API %@: didn't parse (%@)", NSStringFromClass(modelClass),
                  error && *error ? (*error).localizedDescription : @"no error");
        }
    }
    return model;
}
%end
%end

%hook UIWindow
- (void)becomeKeyWindow {
    %orig;
    LTAttachDumpGesture(self);
}
%end

%ctor {
    %init;
    if (objc_getClass("MTLJSONAdapter")) %init(APIErrors);
    // Also attach from app activation: TikTok's window may never reach -becomeKeyWindow.
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        LTEachWindow(^(UIWindow *win) { LTAttachDumpGesture(win); });
#ifdef LT_DUMP_URL
        LTStartAutoDump();
#endif
    }];
#ifdef LT_DUMP_URL
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ LTStartAutoDump(); });
#endif
}

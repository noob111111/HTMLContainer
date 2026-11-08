// HTML Opener — a full-screen, JavaScript-capable local HTML opener for iOS (WKWebView).
// Single source file; see docs/ARCHITECTURE.md for a map of the sections.
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <SafariServices/SafariServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/message.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <limits.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <poll.h>
#include <string.h>
#include <time.h>

#define APP_NAME @"HTML Opener"
#define APP_SCHEME @"htmlopener"

#pragma mark - Storage + breadcrumbs (so a failed launch can explain itself)
static NSString *StorageRoot(void) {
    static NSString *root; static dispatch_once_t o;
    dispatch_once(&o, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSMutableArray *cands = [NSMutableArray array];
        NSString *as = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
        if (as) [cands addObject:[as stringByAppendingPathComponent:@"HTMLViewer"]];
        [cands addObject:@"/var/mobile/Library/HTMLViewer"];
        [cands addObject:[NSTemporaryDirectory() stringByAppendingPathComponent:@"HTMLViewer"]];
        for (NSString *c in cands) {
            [fm createDirectoryAtPath:c withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *t = [c stringByAppendingPathComponent:@".w"];
            if ([@"x" writeToFile:t atomically:NO encoding:NSUTF8StringEncoding error:nil]) { [fm removeItemAtPath:t error:nil]; root = c; return; }
        }
        root = NSTemporaryDirectory();
    });
    return root;
}
static int gFd = -1;
static char gPrevBuf[4096];
static void CrumbC(const char *s) { if (gFd < 0) return; write(gFd, s, strlen(s)); write(gFd, "\n", 1); fsync(gFd); }
static void Crumb(NSString *s) { CrumbC(s.UTF8String); }
static void SigHandler(int sig) {
    char b[40]; int n = snprintf(b, sizeof b, "SIGNAL %d (crash)\n", sig);
    if (gFd >= 0) { write(gFd, b, n); fsync(gFd); }
    signal(sig, SIG_DFL); raise(sig);
}
__attribute__((constructor)) static void BootCrumbs(void) {
    @autoreleasepool {
        NSString *path = [StorageRoot() stringByAppendingPathComponent:@"breadcrumbs.txt"];
        int rf = open(path.fileSystemRepresentation, O_RDONLY);
        if (rf >= 0) { ssize_t n = read(rf, gPrevBuf, sizeof(gPrevBuf) - 1); close(rf); if (n > 0) gPrevBuf[n] = 0; }
        gFd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        CrumbC("1 process started");
        int sigs[] = {SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGTRAP, SIGFPE};
        for (unsigned i = 0; i < sizeof sigs / sizeof *sigs; i++) signal(sigs[i], SigHandler);
    }
}
static void UncaughtHandler(NSException *e) { Crumb([NSString stringWithFormat:@"EXCEPTION %@: %@", e.name, e.reason]); }

#pragma mark - Helpers
static void After(double s, void (^b)(void)) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(s * NSEC_PER_SEC)), dispatch_get_main_queue(), b); }
static NSUserDefaults *UD(void) { return NSUserDefaults.standardUserDefaults; }
static NSString *DocsRoot(void) {     // internal folder for copied HTMLs (visible in the Files app when the app has a Documents container)
    NSString *d = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: [StorageRoot() stringByAppendingPathComponent:@"Documents"];
    NSString *r = [d stringByAppendingPathComponent:@"HTML Files"];
    [NSFileManager.defaultManager createDirectoryAtPath:r withIntermediateDirectories:YES attributes:nil error:nil];
    return r;
}
static NSString *SessionsDir(void) {
    NSString *d = [StorageRoot() stringByAppendingPathComponent:@"Sessions"];
    [NSFileManager.defaultManager createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
static NSString *StatePath(NSString *ident) { return [SessionsDir() stringByAppendingPathComponent:[ident stringByAppendingString:@".state"]]; }
// Snapshot files: <id>.state is the current save, <id>.state.new exists only while a newer one has just been written.
static NSString *NewStatePath(NSString *ident) { return [StatePath(ident) stringByAppendingString:@".new"]; }
static void DeleteState(NSString *ident) { NSFileManager *fm = NSFileManager.defaultManager; [fm removeItemAtPath:StatePath(ident) error:nil]; [fm removeItemAtPath:NewStatePath(ident) error:nil]; }
static NSData *LoadState(NSString *ident) {         // newest complete snapshot; both files are removed afterwards (it lives in memory now)
    NSFileManager *fm = NSFileManager.defaultManager;
    NSData *d = [NSData dataWithContentsOfFile:NewStatePath(ident)] ?: [NSData dataWithContentsOfFile:StatePath(ident)];
    DeleteState(ident); return d;
}
static BOOL SaveState(NSString *ident, NSData *d) {
    NSFileManager *fm = NSFileManager.defaultManager; NSString *cur = StatePath(ident), *nw = NewStatePath(ident);
    if (!d.length) return NO;
    // 1. write the new copy completely (atomic write = temp file + rename, so a half-written file never has the real name)
    if (![d writeToFile:nw atomically:YES]) return NO;
    NSData *check = [NSData dataWithContentsOfFile:nw options:NSDataReadingMappedIfSafe error:nil];
    if (check.length != d.length) { [fm removeItemAtPath:nw error:nil]; return NO; }     // copy failed: keep the old save untouched
    // 2. only now remove the old save, then give the new one its name
    [fm removeItemAtPath:cur error:nil];
    if (![fm moveItemAtPath:nw toPath:cur error:nil]) return YES;        // still fine: LoadState also reads the .new file
    return YES;
}
static NSString *RealPath(NSString *p) { char rp[PATH_MAX]; return realpath(p.fileSystemRepresentation, rp) ? [NSString stringWithUTF8String:rp] : p; }

#pragma mark - Library (NSUserDefaults)
static NSMutableArray<NSMutableDictionary *> *Lib(void);
static void SaveLib(void) { [UD() setObject:Lib() forKey:@"library"]; }
static NSMutableArray<NSMutableDictionary *> *Lib(void) {
    static NSMutableArray *a;
    if (!a) {
        a = [NSMutableArray array]; BOOL dirty = NO;
        for (NSDictionary *d in [UD() arrayForKey:@"library"]) {
            NSMutableDictionary *m = [d mutableCopy];
            if (![m[@"id"] length]) { m[@"id"] = NSUUID.UUID.UUIDString; dirty = YES; }
            [a addObject:m];
        }
        if (dirty) [UD() setObject:a forKey:@"library"];
    }
    return a;
}
static NSMutableDictionary *ItemByPath(NSString *path) { for (NSMutableDictionary *d in Lib()) if ([d[@"path"] isEqualToString:path]) return d; return nil; }
static NSMutableDictionary *ItemById(NSString *ident) { if (!ident.length) return nil; for (NSMutableDictionary *d in Lib()) if ([d[@"id"] isEqualToString:ident]) return d; return nil; }
static NSMutableDictionary *NewItem(NSString *path, BOOL copied) {
    NSMutableDictionary *d = [@{@"id": NSUUID.UUID.UUIDString, @"path": path, @"copied": @(copied), @"last": @([NSDate date].timeIntervalSince1970)} mutableCopy];
    [Lib() addObject:d]; SaveLib(); return d;
}
static BOOL IB(NSDictionary *it, NSString *k, BOOL def) { id v = it[k]; return v ? [v boolValue] : def; }
static BOOL AppB(NSString *k, BOOL def) { id v = [UD() objectForKey:k]; return v ? [v boolValue] : def; }
static NSString *ItemName(NSDictionary *it) {
    NSString *n = it[@"name"]; if (n.length) return n;
    NSString *p = it[@"path"], *b = [p.lastPathComponent stringByDeletingPathExtension];
    if ([b.lowercaseString isEqualToString:@"index"]) b = p.stringByDeletingLastPathComponent.lastPathComponent;
    return b;
}

#pragma mark - Icons
static UIImage *Tile(CGFloat size, UIColor *bg, NSString *emoji, NSString *sym) {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(size, size)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [bg setFill]; [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size) cornerRadius:size * 0.22] fill];
        if (emoji.length) {
            NSDictionary *a = @{NSFontAttributeName: [UIFont systemFontOfSize:size * 0.58]}; CGSize ts = [emoji sizeWithAttributes:a];
            [emoji drawAtPoint:CGPointMake((size - ts.width) / 2, (size - ts.height) / 2) withAttributes:a];
        } else if (sym.length) {
            UIImage *s = [UIImage systemImageNamed:sym withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size * 0.5 weight:UIImageSymbolWeightSemibold]];
            s = [s imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
            if (s) { CGSize z = s.size; [s drawInRect:CGRectMake((size - z.width) / 2, (size - z.height) / 2, z.width, z.height)]; }
        }
    }];
}
static UIImage *ItemIcon(NSDictionary *it, CGFloat size) {
    NSString *ic = it[@"icon"]; BOOL copied = IB(it, @"copied", NO);
    if ([ic hasPrefix:@"e:"]) return Tile(size, [UIColor colorWithWhite:0.22 alpha:1], [ic substringFromIndex:2], nil);
    if ([ic hasPrefix:@"s:"]) return Tile(size, [UIColor colorWithRed:0.3 green:0.3 blue:0.75 alpha:1], nil, [ic substringFromIndex:2]);
    return Tile(size, copied ? [UIColor colorWithRed:0.14 green:0.6 blue:0.3 alpha:1] : [UIColor colorWithRed:0.9 green:0.5 blue:0.1 alpha:1], nil, copied ? @"square.and.arrow.down.fill" : @"mappin.circle.fill");
}
static UIImageView *BadgeView(NSString *sym, UIColor *c) {
    UIImage *i = [UIImage systemImageNamed:sym withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]];
    UIImageView *v = [[UIImageView alloc] initWithImage:[i imageWithTintColor:c renderingMode:UIImageRenderingModeAlwaysOriginal]]; v.contentMode = UIViewContentModeScaleAspectFit; return v;
}
static NSArray<NSString *> *IconPresets(void) { return @[@"gamecontroller.fill", @"star.fill", @"heart.fill", @"flame.fill", @"bolt.fill", @"book.fill", @"film.fill", @"music.note", @"globe", @"hammer.fill", @"leaf.fill", @"moon.fill", @"sun.max.fill", @"cart.fill", @"puzzlepiece.fill", @"wand.and.stars"]; }

#pragma mark - Web view configuration + data stores
static NSUUID *UUIDFor(NSString *s) {
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding]; unsigned char h[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(d.bytes, (CC_LONG)d.length, h);
    return [[NSUUID alloc] initWithUUIDBytes:h];
}
static WKWebsiteDataStore *DataStoreFor(NSDictionary *it) {
    SEL sel = NSSelectorFromString(@"dataStoreForIdentifier:");
    if (it && IB(it, @"sep", NO) && [WKWebsiteDataStore respondsToSelector:sel]) {
        id r = ((id (*)(id, SEL, id))objc_msgSend)(WKWebsiteDataStore.class, sel, UUIDFor(it[@"id"]));
        if (r) return r;
    }
    return WKWebsiteDataStore.defaultDataStore;
}
static BOOL SeparateSupported(void) { return [WKWebsiteDataStore respondsToSelector:NSSelectorFromString(@"dataStoreForIdentifier:")]; }
static void WipeStore(WKWebsiteDataStore *ds, void (^done)(void)) {
    [ds removeDataOfTypes:WKWebsiteDataStore.allWebsiteDataTypes modifiedSince:[NSDate dateWithTimeIntervalSince1970:0] completionHandler:^{ if (done) dispatch_async(dispatch_get_main_queue(), done); }];
}
#pragma mark - hvfile:// scheme: serves files from their ORIGINAL location through the app (which can read them) when WebKit's own file access is denied
@interface HVHandler : NSObject <WKURLSchemeHandler> @end
@implementation HVHandler
- (void)webView:(WKWebView *)w startURLSchemeTask:(id<WKURLSchemeTask>)t {
    NSURL *u = t.request.URL; NSString *p = u.path.stringByRemovingPercentEncoding ?: u.path;
    NSData *d = [NSData dataWithContentsOfFile:p options:NSDataReadingMappedIfSafe error:nil];
    NSString *mime = @"application/octet-stream";
    UTType *ty = [UTType typeWithFilenameExtension:p.pathExtension]; if (ty.preferredMIMEType) mime = ty.preferredMIMEType;
    NSString *ext = p.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"js"] || [ext isEqualToString:@"mjs"]) mime = @"text/javascript";
    if ([ext isEqualToString:@"wasm"]) mime = @"application/wasm";
    if (!d) { NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:u statusCode:404 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Access-Control-Allow-Origin":@"*"}];
        [t didReceiveResponse:r]; [t didFinish]; return; }
    NSInteger status = 200; NSData *body = d; NSMutableDictionary *h = [@{@"Content-Type":mime, @"Access-Control-Allow-Origin":@"*", @"Accept-Ranges":@"bytes"} mutableCopy];
    NSString *rg = [t.request valueForHTTPHeaderField:@"Range"];
    if ([rg hasPrefix:@"bytes="]) {
        NSArray *pr = [[rg substringFromIndex:6] componentsSeparatedByString:@"-"];
        long long a = [pr[0] longLongValue], b = ([pr count] > 1 && [pr[1] length]) ? [pr[1] longLongValue] : (long long)d.length - 1;
        if (b >= (long long)d.length) b = d.length - 1;
        if (a <= b) { body = [d subdataWithRange:NSMakeRange((NSUInteger)a, (NSUInteger)(b - a + 1))]; status = 206; h[@"Content-Range"] = [NSString stringWithFormat:@"bytes %lld-%lld/%lu", a, b, (unsigned long)d.length]; }
    }
    h[@"Content-Length"] = [NSString stringWithFormat:@"%lu", (unsigned long)body.length];
    [t didReceiveResponse:[[NSHTTPURLResponse alloc] initWithURL:u statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:h]];
    [t didReceiveData:body]; [t didFinish];
}
- (void)webView:(WKWebView *)w stopURLSchemeTask:(id<WKURLSchemeTask>)t {}
@end
static NSURL *HVURL(NSString *path) { NSURLComponents *c = [NSURLComponents new]; c.scheme = @"hvfile"; c.host = @"local"; c.path = path; return c.URL; }
static WKWebViewConfiguration *MakeConfig(NSDictionary *it, WKWebsiteDataStore *store) {
    WKWebViewConfiguration *cfg = [WKWebViewConfiguration new];
    cfg.websiteDataStore = store ?: DataStoreFor(it);
    cfg.allowsInlineMediaPlayback = YES;
    cfg.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    cfg.defaultWebpagePreferences.allowsContentJavaScript = YES;
    cfg.defaultWebpagePreferences.preferredContentMode = IB(it, @"desktop", YES) ? WKContentModeDesktop : WKContentModeMobile;
    cfg.preferences.javaScriptCanOpenWindowsAutomatically = YES;
    @try { [cfg.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"]; [cfg setValue:@YES forKey:@"allowUniversalAccessFromFileURLs"]; } @catch (__unused NSException *e) {}
    @try { [cfg.preferences setValue:@YES forKey:@"developerExtrasEnabled"]; } @catch (__unused NSException *e) {}
    @try { [cfg.preferences setValue:@YES forKey:@"fullScreenEnabled"]; } @catch (__unused NSException *e) {}
    @try { [cfg.preferences setValue:@YES forKey:@"elementFullscreenEnabled"]; } @catch (__unused NSException *e) {}
    [cfg setURLSchemeHandler:[HVHandler new] forURLScheme:@"hvfile"];
    WKUserContentController *u = cfg.userContentController;
    [u addUserScript:[[WKUserScript alloc] initWithSource:@"window.__hvErr=0;window.addEventListener('error',function(e){var t=e.target;if(t&&t!==window&&(t.src||t.href))window.__hvErr++;},true);" injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    NSString *css = it[@"css"], *js = it[@"js"];
    if (css.length) { NSData *j = [NSJSONSerialization dataWithJSONObject:@[css] options:0 error:nil]; NSString *arr = [[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding];
        [u addUserScript:[[WKUserScript alloc] initWithSource:[NSString stringWithFormat:@"(function(){var s=document.createElement('style');s.textContent=%@[0];(document.head||document.documentElement).appendChild(s);})();", arr] injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]]; }
    if (js.length) [u addUserScript:[[WKUserScript alloc] initWithSource:[NSString stringWithFormat:@"try{\n%@\n}catch(e){console.error('Custom JS error',e);}", js] injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES]];
    return cfg;
}

#pragma mark - Reading / writing a data store's localStorage through a hidden web view (used to share/move saves)
static UIWindow *gWin;
@interface StoreHelper : NSObject <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *web;
@property (nonatomic, copy) void (^ready)(WKWebView *);
@end
@implementation StoreHelper
- (void)fire:(WKWebView *)w { void (^r)(WKWebView *) = self.ready; self.ready = nil; if (r) r(w); }
- (void)webView:(WKWebView *)w didFinishNavigation:(WKNavigation *)n { [self fire:w]; }
- (void)webView:(WKWebView *)w didFailNavigation:(WKNavigation *)n withError:(NSError *)e { [self fire:nil]; }
- (void)webView:(WKWebView *)w didFailProvisionalNavigation:(WKNavigation *)n withError:(NSError *)e { [self fire:nil]; }
@end
static NSMutableArray *gHelpers;
static void WithStore(WKWebsiteDataStore *ds, void (^block)(WKWebView *w, void (^finish)(void))) {
    if (!gHelpers) gHelpers = [NSMutableArray array];
    NSString *p = [StorageRoot() stringByAppendingPathComponent:@"blank.html"];
    [@"<!doctype html><html><body></body></html>" writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil];
    StoreHelper *h = [StoreHelper new]; [gHelpers addObject:h];
    WKWebView *w = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 4, 4) configuration:MakeConfig(nil, ds)];
    h.web = w; w.navigationDelegate = h; w.alpha = 0.01; w.userInteractionEnabled = NO;
    [gWin addSubview:w];
    void (^finish)(void) = ^{ [w removeFromSuperview]; [gHelpers removeObject:h]; };
    h.ready = ^(WKWebView *ww) { block(ww, finish); };
    [w loadFileURL:[NSURL fileURLWithPath:p] allowingReadAccessToURL:[NSURL fileURLWithPath:p.stringByDeletingLastPathComponent]];
}
static void ReadLS(WKWebsiteDataStore *ds, void (^done)(NSDictionary *d)) {
    WithStore(ds, ^(WKWebView *w, void (^finish)(void)) {
        if (!w) { finish(); done(nil); return; }
        [w callAsyncJavaScript:@"var o={};for(var i=0;i<localStorage.length;i++){var k=localStorage.key(i);o[k]=localStorage.getItem(k);}return JSON.stringify(o);" arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id r, NSError *e) {
            finish();
            id obj = [r isKindOfClass:NSString.class] ? [NSJSONSerialization JSONObjectWithData:[(NSString *)r dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
            done([obj isKindOfClass:NSDictionary.class] ? obj : nil);
        }];
    });
}
static void WriteLS(WKWebsiteDataStore *ds, NSDictionary *data, BOOL replace, void (^done)(BOOL ok)) {
    WithStore(ds, ^(WKWebView *w, void (^finish)(void)) {
        if (!w) { finish(); done(NO); return; }
        [w callAsyncJavaScript:@"if(replace){localStorage.clear();} for(var k in data){localStorage.setItem(k,data[k]);} return 1;" arguments:@{@"data": data ?: @{}, @"replace": @(replace)} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(id r, NSError *e) { finish(); done(e == nil); }];
    });
}

#pragma mark - Home-screen shortcut (web clip profile served to Safari from localhost)
static void ServeProfile(NSData *data, void (^ready)(NSURL *)) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    int yes = 1; setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
    struct sockaddr_in a; memset(&a, 0, sizeof a);
    a.sin_family = AF_INET; a.sin_len = sizeof a; a.sin_addr.s_addr = htonl(INADDR_LOOPBACK); a.sin_port = 0;
    if (fd < 0 || bind(fd, (struct sockaddr *)&a, sizeof a) != 0 || listen(fd, 4) != 0) { if (fd >= 0) close(fd); ready(nil); return; }
    socklen_t len = sizeof a; getsockname(fd, (struct sockaddr *)&a, &len);
    int port = ntohs(a.sin_port);
    UIBackgroundTaskIdentifier bgt = [UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:nil];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        time_t end = time(NULL) + 180; int served = 0;
        while (time(NULL) < end && served < 6) {
            struct pollfd p = {fd, POLLIN, 0};
            if (poll(&p, 1, 1000) <= 0) continue;
            int c = accept(fd, NULL, NULL); if (c < 0) continue;
            char buf[2048]; read(c, buf, sizeof buf);
            NSString *h = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: application/x-apple-aspen-config\r\nContent-Disposition: attachment; filename=\"shortcut.mobileconfig\"\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n", (unsigned long)data.length];
            write(c, h.UTF8String, h.length);
            const uint8_t *b = data.bytes; size_t off = 0;
            while (off < data.length) { ssize_t n = write(c, b + off, data.length - off); if (n <= 0) break; off += n; }
            close(c); served++;
        }
        close(fd);
        dispatch_async(dispatch_get_main_queue(), ^{ if (bgt != UIBackgroundTaskInvalid) [UIApplication.sharedApplication endBackgroundTask:bgt]; });
    });
    ready([NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%d/shortcut.mobileconfig", port]]);
}

#pragma mark - Generic dark settings table
@interface SettingsVC : UITableViewController
@property (nonatomic, strong) NSArray<NSDictionary *> *sections;   // @{h, f, rows:[ @{t, k:sw|txt|ch|btn, get, set, opts, destructive, act} ]}
@end
@implementation SettingsVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = UIColor.blackColor; self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return [self.sections[s][@"rows"] count]; }
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s { return self.sections[s][@"h"]; }
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s { return self.sections[s][@"f"]; }
- (NSDictionary *)rowAt:(NSIndexPath *)ip { return self.sections[ip.section][@"rows"][ip.row]; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *r = [self rowAt:ip]; NSString *k = r[@"k"];
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    c.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1]; c.textLabel.textColor = UIColor.whiteColor; c.textLabel.text = r[@"t"];
    c.detailTextLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1]; c.selectionStyle = UITableViewCellSelectionStyleDefault;
    if ([k isEqualToString:@"sw"]) {
        UISwitch *sw = [UISwitch new]; sw.on = [((id (^)(void))r[@"get"])() boolValue]; sw.tag = ip.section * 1000 + ip.row;
        [sw addTarget:self action:@selector(swChanged:) forControlEvents:UIControlEventValueChanged]; c.accessoryView = sw; c.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([k isEqualToString:@"txt"]) {
        NSString *v = ((id (^)(void))r[@"get"])(); c.detailTextLabel.text = v.length ? (v.length > 24 ? [[v substringToIndex:24] stringByAppendingString:@"…"] : v) : @"—";
    } else if ([k isEqualToString:@"ch"]) {
        NSInteger i = [((id (^)(void))r[@"get"])() integerValue]; NSArray *o = r[@"opts"]; c.detailTextLabel.text = (i >= 0 && i < (NSInteger)o.count) ? o[i] : @"";
    } else if ([k isEqualToString:@"btn"]) {
        c.textLabel.textColor = [r[@"destructive"] boolValue] ? UIColor.systemRedColor : UIColor.systemBlueColor;
        if (r[@"get"]) c.detailTextLabel.text = ((id (^)(void))r[@"get"])();
    }
    return c;
}
- (void)swChanged:(UISwitch *)sw {
    NSDictionary *r = self.sections[sw.tag / 1000][@"rows"][sw.tag % 1000]; ((void (^)(id))r[@"set"])(@(sw.on));
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    NSDictionary *r = [self rowAt:ip]; NSString *k = r[@"k"];
    if ([k isEqualToString:@"btn"]) { ((void (^)(void))r[@"act"])(); [t reloadData]; return; }
    if ([k isEqualToString:@"txt"]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:r[@"t"] message:r[@"m"] preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = ((id (^)(void))r[@"get"])(); f.autocorrectionType = UITextAutocorrectionTypeNo; f.autocapitalizationType = UITextAutocapitalizationTypeNone; f.clearButtonMode = UITextFieldViewModeAlways; }];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(id x) { ((void (^)(id))r[@"set"])(a.textFields.firstObject.text ?: @""); [t reloadData]; }]];
        [self presentViewController:a animated:YES completion:nil];
    } else if ([k isEqualToString:@"ch"]) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:r[@"t"] message:nil preferredStyle:UIAlertControllerStyleAlert];
        NSArray *o = r[@"opts"];
        for (NSUInteger i = 0; i < o.count; i++) [a addAction:[UIAlertAction actionWithTitle:o[i] style:UIAlertActionStyleDefault handler:^(id x) { ((void (^)(id))r[@"set"])(@(i)); [t reloadData]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    }
}
@end

#pragma mark - Session = one open HTML (kept alive like a background tab)
@interface Session : NSObject
@property (nonatomic, copy) NSString *ident, *path;
@property (nonatomic, strong) WKWebView *web;
@property (nonatomic, strong) NSData *pendingState;
@property (nonatomic, strong) NSURL *scoped;
@property (nonatomic, copy) NSString *lastError;
@property (nonatomic) BOOL fellBack;
@end
@implementation Session
@end

static NSMutableSet *gScopes;   // folders picked with the document picker stay accessible
#pragma mark - Host (the only screen)
@interface HostVC : UIViewController <WKNavigationDelegate, WKUIDelegate, UIDocumentPickerDelegate, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSMutableDictionary<NSString *, Session *> *live;
@property (nonatomic, strong) NSMutableArray<NSString *> *order;
@property (nonatomic, strong) Session *current;
@property (nonatomic, strong) UIView *startView;
@property (nonatomic, strong) UITableView *table;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, copy) NSString *selectedId;
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
@property (nonatomic) NSInteger pickMode;
- (void)openIncomingURL:(NSURL *)url;
- (void)resumeLast;
- (void)showList;
- (void)restartCurrent;
- (void)saveAll;
- (void)purgeSnapshotsOfLiveSessions;
@end

@implementation HostVC
- (BOOL)prefersStatusBarHidden { return self.current != nil; }
- (BOOL)prefersHomeIndicatorAutoHidden { return self.current != nil; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (!self.current) return UIInterfaceOrientationMaskAll;
    NSInteger o = [ItemById(self.current.ident)[@"orient"] integerValue];
    return o == 1 ? UIInterfaceOrientationMaskPortrait : o == 2 ? UIInterfaceOrientationMaskLandscape : UIInterfaceOrientationMaskAll;
}
- (UIStatusBarStyle)preferredStatusBarStyle { return UIStatusBarStyleLightContent; }
- (UIViewController *)topVC { UIViewController *top = self; while (top.presentedViewController) top = top.presentedViewController; return top; }

- (void)viewDidLoad {
    [super viewDidLoad];
    Crumb(@"3 HostVC viewDidLoad");
    self.live = [NSMutableDictionary dictionary]; self.order = [NSMutableArray array];
    self.view.backgroundColor = UIColor.blackColor;
    [self buildStartView];
    UITapGestureRecognizer *tg = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(threeFingerTap:)]; tg.numberOfTouchesRequired = 3; tg.cancelsTouchesInView = NO; tg.delegate = self; [self.view addGestureRecognizer:tg];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(memoryWarning) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; Crumb(@"READY"); }

#pragma mark list screen
- (void)buildStartView {
    UIView *v = [UIView new]; v.backgroundColor = UIColor.blackColor; v.frame = self.view.bounds;
    v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UILabel *t = [UILabel new]; t.text = APP_NAME; t.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold]; t.textColor = UIColor.whiteColor;
    UILabel *hint = [UILabel new]; hint.text = @"Tap to highlight · tap again to unhighlight · 3-finger tap inside a page returns here"; hint.font = [UIFont systemFontOfSize:12]; hint.textColor = [UIColor colorWithWhite:0.5 alpha:1]; hint.numberOfLines = 0;
    UITableView *tv = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tv.backgroundColor = UIColor.blackColor; tv.separatorColor = [UIColor colorWithWhite:0.18 alpha:1]; tv.dataSource = self; tv.delegate = self; tv.rowHeight = 66;
    UILabel *e = [UILabel new];
    e.text = @"No HTML files yet.\nTap + to add one,\nor Run to open the Files app.";
    e.numberOfLines = 0; e.textAlignment = NSTextAlignmentCenter; e.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    tv.backgroundView = e; self.emptyLabel = e; self.table = tv;
    UIButton *run = [UIButton buttonWithType:UIButtonTypeSystem], *set = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *c1 = [UIButtonConfiguration filledButtonConfiguration]; c1.title = @"Run"; c1.baseBackgroundColor = UIColor.systemBlueColor; c1.baseForegroundColor = UIColor.whiteColor; c1.buttonSize = UIButtonConfigurationSizeLarge; run.configuration = c1;
    UIButtonConfiguration *c2 = [UIButtonConfiguration filledButtonConfiguration]; c2.title = @"Settings"; c2.baseBackgroundColor = [UIColor colorWithWhite:0.2 alpha:1]; c2.baseForegroundColor = UIColor.whiteColor; c2.buttonSize = UIButtonConfigurationSizeLarge; set.configuration = c2;
    [run addTarget:self action:@selector(runTapped) forControlEvents:UIControlEventTouchUpInside];
    [set addTarget:self action:@selector(settingsTapped) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *bar = [[UIStackView alloc] initWithArrangedSubviews:@[run, set]]; bar.axis = UILayoutConstraintAxisHorizontal; bar.spacing = 12; bar.distribution = UIStackViewDistributionFillEqually;
    NSMutableArray *views = [@[t, hint, tv, bar] mutableCopy];
    UIButton *plus = nil;
    plus = [UIButton buttonWithType:UIButtonTypeSystem];
    [plus setImage:[UIImage systemImageNamed:@"plus.circle.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:32]] forState:UIControlStateNormal];
    [plus addTarget:self action:@selector(plusTapped) forControlEvents:UIControlEventTouchUpInside]; [views addObject:plus];
    for (UIView *x in views) { x.translatesAutoresizingMaskIntoConstraints = NO; [v addSubview:x]; }
    [self.view addSubview:v]; self.startView = v;
    UILayoutGuide *g = v.safeAreaLayoutGuide;
    NSMutableArray *cs = [@[
        [t.topAnchor constraintEqualToAnchor:g.topAnchor constant:14], [t.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20],
        [hint.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:4], [hint.leadingAnchor constraintEqualToAnchor:t.leadingAnchor], [hint.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],
        [tv.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:10], [tv.leadingAnchor constraintEqualToAnchor:v.leadingAnchor], [tv.trailingAnchor constraintEqualToAnchor:v.trailingAnchor], [tv.bottomAnchor constraintEqualToAnchor:bar.topAnchor constant:-10],
        [bar.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:20], [bar.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20], [bar.bottomAnchor constraintEqualToAnchor:g.bottomAnchor constant:-12]] mutableCopy];
    if (plus) { [cs addObject:[plus.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20]]; [cs addObject:[plus.centerYAnchor constraintEqualToAnchor:t.centerYAnchor]]; }
    [NSLayoutConstraint activateConstraints:cs];
    if (gPrevBuf[0] && !strstr(gPrevBuf, "READY")) {
        e.text = [@"The previous launch did not finish. Last steps:\n\n" stringByAppendingString:[NSString stringWithUTF8String:gPrevBuf]]; e.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    }
}
- (void)reloadList {
    self.rows = [Lib() sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) { return [y[@"last"] compare:x[@"last"]]; }];
    self.emptyLabel.hidden = self.rows.count > 0; [self.table reloadData];
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return self.rows.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    NSDictionary *it = self.rows[ip.row]; NSString *p = it[@"path"]; BOOL copied = IB(it, @"copied", NO);
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    BOOL sel = [it[@"id"] isEqualToString:self.selectedId], gone = ![NSFileManager.defaultManager fileExistsAtPath:p], open = self.live[it[@"id"]] != nil;
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.backgroundColor = sel ? [UIColor colorWithRed:0.05 green:0.32 blue:0.7 alpha:1] : [UIColor colorWithWhite:0.09 alpha:1];
    c.imageView.image = ItemIcon(it, 40);
    c.textLabel.text = ItemName(it); c.textLabel.textColor = UIColor.whiteColor; c.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    NSString *loc = gone ? @"File missing" : copied ? @"Copied into the app" : [@"Running from " stringByAppendingString:p.stringByDeletingLastPathComponent];
    c.detailTextLabel.text = open ? [@"● open · " stringByAppendingString:loc] : loc;
    c.detailTextLabel.textColor = gone ? UIColor.systemRedColor : [UIColor colorWithWhite:sel ? 0.85 : 0.5 alpha:1];
    NSMutableArray *bs = [NSMutableArray array];
    if ([it[@"icon"] length]) [bs addObject:copied ? BadgeView(@"square.and.arrow.down.fill", UIColor.systemGreenColor) : BadgeView(@"mappin.circle.fill", UIColor.systemOrangeColor)];
    if (IB(it, @"sep", NO)) [bs addObject:BadgeView(@"lock.fill", UIColor.systemYellowColor)];
    if (bs.count) {
        UIStackView *st = [[UIStackView alloc] initWithArrangedSubviews:bs]; st.spacing = 6; st.alignment = UIStackViewAlignmentCenter;
        st.frame = CGRectMake(0, 0, bs.count * 22, 20); c.accessoryView = st;
    }
    return c;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    NSString *i = self.rows[ip.row][@"id"];
    self.selectedId = [i isEqualToString:self.selectedId] ? nil : i;      // tap = highlight, tap again = unhighlight
    [t reloadData];
}
- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip { return YES; }
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)st forRowAtIndexPath:(NSIndexPath *)ip {
    if (st != UITableViewCellEditingStyleDelete) return;
    [self removeItem:(NSMutableDictionary *)self.rows[ip.row]];
}
- (NSMutableDictionary *)selectedItem { return ItemById(self.selectedId); }
- (void)showList {
    [self loadViewIfNeeded];
    if (self.current) { [self.current.web removeFromSuperview]; self.current = nil; }
    UIApplication.sharedApplication.idleTimerDisabled = NO;
    [self reloadList]; self.startView.hidden = NO; [self.view bringSubviewToFront:self.startView];
    [self setNeedsStatusBarAppearanceUpdate]; [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    if ([self respondsToSelector:@selector(setNeedsUpdateOfSupportedInterfaceOrientations)]) [self setNeedsUpdateOfSupportedInterfaceOrientations];
}
- (void)resumeLast {
    NSString *i = [UD() stringForKey:@"lastId"];
    self.selectedId = (AppB(@"autoHL", YES) && ItemById(i)) ? i : nil;
    [self showList];
}
- (void)runTapped {
    NSMutableDictionary *it = [self selectedItem];
    if (it) { [self runItem:it]; return; }
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"shareddocuments://"] options:@{} completionHandler:nil];     // the Files app itself
}
- (void)settingsTapped { NSMutableDictionary *it = [self selectedItem]; if (it) [self presentItemSettings:it]; else [self presentAppSettings]; }

#pragma mark small UI helpers
- (void)present:(UIViewController *)vc { [[self topVC] presentViewController:vc animated:YES completion:nil]; }
- (void)say:(NSString *)title message:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self present:a];
}
- (void)confirm:(NSString *)title message:(NSString *)msg action:(NSString *)act then:(void (^)(void))blk {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:act style:UIAlertActionStyleDestructive handler:^(id x) { blk(); }]]; [self present:a];
}
- (void)toast:(NSString *)m {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:m preferredStyle:UIAlertControllerStyleAlert]; [self present:a];
    After(1.3, ^{ [a dismissViewControllerAnimated:YES completion:nil]; });
}
- (void)presentSettings:(SettingsVC *)vc title:(NSString *)title {
    vc.title = title;
    UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:vc]; n.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UINavigationBarAppearance *ap = [UINavigationBarAppearance new]; [ap configureWithOpaqueBackground]; ap.backgroundColor = UIColor.blackColor; ap.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    n.navigationBar.standardAppearance = ap; n.navigationBar.scrollEdgeAppearance = ap;
    [self present:n];
}

#pragma mark opening files
- (void)openIncomingURL:(NSURL *)url {
    Crumb([@"incoming: " stringByAppendingString:url.absoluteString ?: @"?"]);
    if (url.isFileURL) { After(0.3, ^{ [self openExternalFile:url]; }); return; }
    NSString *sc = url.scheme.lowercaseString;
    if ([sc isEqualToString:APP_SCHEME]) {
        NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        for (NSURLQueryItem *q in c.queryItems) {
            if ([q.name isEqualToString:@"path"] && q.value.length) { After(0.3, ^{ [self openExternalFile:[NSURL fileURLWithPath:q.value]]; }); return; }
            if ([q.name isEqualToString:@"id"] && q.value.length) { NSMutableDictionary *it = ItemById(q.value); if (it) { self.selectedId = q.value; After(0.2, ^{ [self runItem:it]; }); } return; }
        }
    }
}
- (void)runItem:(NSMutableDictionary *)it {
    if (![NSFileManager.defaultManager fileExistsAtPath:it[@"path"]]) { [self handleMissing:it]; return; }
    [self openItem:it scoped:nil];
}
- (void)openExternalFile:(NSURL *)url {
    [self loadViewIfNeeded];
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSString *path = RealPath(url.path); BOOL isDir = NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:path isDirectory:&isDir] || isDir) { if (scoped) [url stopAccessingSecurityScopedResource]; [self say:@"File not found" message:path]; return; }
    NSMutableDictionary *it = ItemByPath(path);
    if (!it && [path hasPrefix:[RealPath(DocsRoot()) stringByAppendingString:@"/"]]) it = NewItem(path, YES);      // already inside the app's own folder
    if (it) { [self openItem:it scoped:scoped ? url : nil]; return; }
    [self askHowToOpen:path scoped:scoped ? url : nil];
}
- (void)askHowToOpen:(NSString *)path scoped:(NSURL *)scoped {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Open “%@”", path.lastPathComponent]
        message:@"Where should it run from?\n\nRun where it is: nothing is copied. If you later move or delete the file, you'll be asked what to do with its saves.\n\nCopy: puts a copy in this app's own folder (visible in the Files app), so you can delete the original." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Run where it is" style:UIAlertActionStyleDefault handler:^(id x) { NSMutableDictionary *it = NewItem(path, NO); [self openItem:it scoped:scoped]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy the whole folder, then run" style:UIAlertActionStyleDefault handler:^(id x) { [self copyAndOpen:path whole:YES scoped:scoped]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Copy only this file, then run" style:UIAlertActionStyleDefault handler:^(id x) { [self copyAndOpen:path whole:NO scoped:scoped]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(id x) { if (scoped) [scoped stopAccessingSecurityScopedResource]; }]];
    [self present:a];
}
- (void)copyAndOpen:(NSString *)src whole:(BOOL)whole scoped:(NSURL *)scoped {
    UIAlertController *wait = [UIAlertController alertControllerWithTitle:@"Copying…" message:@"Please wait" preferredStyle:UIAlertControllerStyleAlert];
    [self present:wait];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = [NSFileManager new]; NSString *dir = src.stringByDeletingLastPathComponent;
        NSString *base = whole ? dir.lastPathComponent : [src.lastPathComponent stringByDeletingPathExtension];
        if (!base.length || [base isEqualToString:@"/"]) base = @"HTML";
        NSString *root = DocsRoot(), *dest = [root stringByAppendingPathComponent:base]; int n = 2;
        while ([fm fileExistsAtPath:dest]) dest = [root stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %d", base, n++]];
        NSError *err = nil; BOOL ok = NO, tooBig = NO; NSString *np = [dest stringByAppendingPathComponent:src.lastPathComponent];
        if (whole) {
            unsigned long long total = 0;
            for (NSString *f in [fm enumeratorAtPath:dir]) { total += [[fm attributesOfItemAtPath:[dir stringByAppendingPathComponent:f] error:nil] fileSize]; if (total > (2ull << 30)) { tooBig = YES; break; } }
            if (!tooBig) ok = [fm copyItemAtPath:dir toPath:dest error:&err];
        } else {
            [fm createDirectoryAtPath:dest withIntermediateDirectories:YES attributes:nil error:nil];
            ok = [fm copyItemAtPath:src toPath:np error:&err];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [wait dismissViewControllerAnimated:NO completion:^{
                if (tooBig) {
                    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"That folder is very large" message:@"It is over 2 GB. Copy only the HTML file instead? (Its images and scripts would not come along.)" preferredStyle:UIAlertControllerStyleAlert];
                    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(id x) { if (scoped) [scoped stopAccessingSecurityScopedResource]; }]];
                    [a addAction:[UIAlertAction actionWithTitle:@"Copy only the file" style:UIAlertActionStyleDefault handler:^(id x) { [self copyAndOpen:src whole:NO scoped:scoped]; }]]; [self present:a]; return;
                }
                if (scoped) [scoped stopAccessingSecurityScopedResource];
                if (!ok) { [self say:@"Couldn't copy" message:err.localizedDescription ?: src]; return; }
                NSMutableDictionary *it = NewItem(np, YES); it[@"origin"] = src; SaveLib();
                [self openItem:it scoped:nil];
            }];
        });
    });
}
- (void)openItem:(NSMutableDictionary *)it scoped:(NSURL *)scoped {
    [self loadViewIfNeeded];
    NSString *ident = it[@"id"], *path = it[@"path"];
    if (![NSFileManager.defaultManager isReadableFileAtPath:path]) { if (scoped) [scoped stopAccessingSecurityScopedResource]; [self say:@"Can't read this file" message:[path stringByAppendingString:@"\n\nThe app has no permission to read it."]]; return; }
    it[@"last"] = @([NSDate date].timeIntervalSince1970); SaveLib(); [UD() setObject:ident forKey:@"lastId"];
    Session *s = self.live[ident];
    if (s && ![s.path isEqualToString:path]) { [self dropSession:ident deleteState:NO]; s = nil; }
    if (s) { if (scoped) [scoped stopAccessingSecurityScopedResource]; }
    else s = [self makeSession:it scoped:scoped];
    [self show:s];
}
- (Session *)makeSession:(NSMutableDictionary *)it scoped:(NSURL *)scoped {
    NSString *path = it[@"path"], *ident = it[@"id"];
    Crumb([@"new session " stringByAppendingString:path.lastPathComponent]);
    Session *s = [Session new]; s.ident = ident; s.path = path; s.scoped = scoped;
    NSData *d = IB(it, @"resume", YES) ? LoadState(ident) : nil;
    if (!IB(it, @"resume", YES)) DeleteState(ident);
    if (d.length) s.pendingState = d;
    WKWebView *w = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:MakeConfig(it, nil)];
    w.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    w.navigationDelegate = self; w.UIDelegate = self;
    w.allowsBackForwardNavigationGestures = YES;
    w.opaque = YES; w.backgroundColor = UIColor.blackColor; w.scrollView.backgroundColor = UIColor.blackColor;
    w.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    if ([w respondsToSelector:NSSelectorFromString(@"setUnderPageBackgroundColor:")]) [w setValue:UIColor.blackColor forKey:@"underPageBackgroundColor"];
    if ([w respondsToSelector:NSSelectorFromString(@"setInspectable:")]) [w setValue:@YES forKey:@"inspectable"];
    double z = [it[@"zoom"] doubleValue]; w.pageZoom = z > 0 ? z : 1.0;
    if ([it[@"ua"] length]) w.customUserAgent = it[@"ua"];
    s.web = w;
    self.live[ident] = s; [self.order removeObject:ident]; [self.order addObject:ident];
    [w loadFileURL:[NSURL fileURLWithPath:path] allowingReadAccessToURL:[NSURL fileURLWithPath:path.stringByDeletingLastPathComponent isDirectory:YES]];
    After(4.0, ^{ [self diag:s]; });
    return s;
}
- (void)show:(Session *)s {
    if (self.current != s) { [self.current.web removeFromSuperview]; self.current = s; }
    if (!s.web.superview) { s.web.frame = self.view.bounds; [self.view addSubview:s.web]; }
    self.startView.hidden = YES;
    UIApplication.sharedApplication.idleTimerDisabled = IB(ItemById(s.ident), @"awake", NO);
    [self setNeedsStatusBarAppearanceUpdate]; [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    if ([self respondsToSelector:@selector(setNeedsUpdateOfSupportedInterfaceOrientations)]) [self setNeedsUpdateOfSupportedInterfaceOrientations];
    [self.order removeObject:s.ident]; [self.order addObject:s.ident];
    [self trim];
}
- (Session *)sessionForWeb:(WKWebView *)w { for (Session *s in self.live.allValues) if (s.web == w) return s; return nil; }
- (void)dropSession:(NSString *)ident deleteState:(BOOL)del {
    Session *s = self.live[ident];
    if (s) { if (s == self.current) { [s.web removeFromSuperview]; self.current = nil; } s.web.navigationDelegate = nil; s.web.UIDelegate = nil; if (s.scoped) [s.scoped stopAccessingSecurityScopedResource]; [self.live removeObjectForKey:ident]; [self.order removeObject:ident]; }
    if (del) DeleteState(ident);
}

#pragma mark page health check + info
- (void)probe:(Session *)s completion:(void (^)(NSDictionary *info, NSString *err))cb {
    NSString *js = @"JSON.stringify({text:document.body?document.body.innerText.length:-1,nodes:document.body?document.body.querySelectorAll('*').length:-1,scripts:document.scripts.length,resErr:window.__hvErr||0,proto:location.protocol,dark:matchMedia('(prefers-color-scheme: dark)').matches,fg:document.body?getComputedStyle(document.body).color:'',bg:document.body?getComputedStyle(document.body).backgroundColor:'',htmlbg:getComputedStyle(document.documentElement).backgroundColor,title:document.title,w:innerWidth,h:innerHeight})";
    [s.web evaluateJavaScript:js completionHandler:^(id r, NSError *e) {
        NSDictionary *j = [r isKindOfClass:NSString.class] ? [NSJSONSerialization JSONObjectWithData:[r dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
        cb(j, e.localizedDescription);
    }];
}
- (void)diag:(Session *)s {   // black-screen guard: if the page is empty (or its files couldn't load), serve it through hvfile:// from the original place
    if (!s || self.live[s.ident] != s || s.pendingState || s.fellBack) return;
    [self probe:s completion:^(NSDictionary *j, NSString *err) {
        BOOL empty = !j || [j[@"text"] longValue] <= 0, resProblem = j && [j[@"resErr"] longValue] > 0;
        Crumb([NSString stringWithFormat:@"diag text=%@ resErr=%@", j[@"text"], j[@"resErr"]]);
        if ((empty || resProblem) && !s.fellBack) { s.fellBack = YES; Crumb(@"-> hvfile"); [s.web loadRequest:[NSURLRequest requestWithURL:HVURL(s.path)]]; }
    }];
}
- (void)showPageInfo {
    Session *s = self.current; if (!s) return;
    [self probe:s completion:^(NSDictionary *j, NSString *err) {
        NSMutableString *m = [NSMutableString string];
        NSMutableDictionary *it = ItemById(s.ident);
        [m appendFormat:@"%@\n%@\n", ItemName(it), s.path];
        [m appendFormat:@"\nlocation: %@   data: %@   engine: %@", IB(it, @"copied", NO) ? @"copied" : @"in place", IB(it, @"sep", NO) ? @"separate" : @"shared", s.fellBack ? @"hvfile://" : @"file://"];
        if (j) for (NSString *k in @[@"title", @"text", @"nodes", @"scripts", @"resErr", @"proto", @"dark", @"fg", @"bg", @"htmlbg", @"w", @"h"]) [m appendFormat:@"\n%@: %@", k, j[k]];
        else [m appendFormat:@"\nprobe failed: %@", err ?: @"?"];
        if (s.lastError) [m appendFormat:@"\nlast error: %@", s.lastError];
        [self say:@"Page info" message:m];
    }];
}
- (void)threeFingerTap:(UITapGestureRecognizer *)g {
    if (!self.current || g.state != UIGestureRecognizerStateEnded) return;
    NSMutableDictionary *it = ItemById(self.current.ident);
    UIAlertController *a = [UIAlertController alertControllerWithTitle:ItemName(it) message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Back to list" style:UIAlertActionStyleDefault handler:^(id x) { [self saveSession:self.current]; [self showList]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Page info" style:UIAlertActionStyleDefault handler:^(id x) { [self showPageInfo]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Restart this page" style:UIAlertActionStyleDestructive handler:^(id x) { [self restartCurrent]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self present:a];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }

#pragma mark RAM -> storage
- (void)saveSession:(Session *)s {
    if (!IB(ItemById(s.ident), @"resume", YES)) return;
    if (s.pendingState) { SaveState(s.ident, s.pendingState); return; }     // page still loading: keep the save we were about to restore
    id st = s.web.interactionState;
    if ([st isKindOfClass:NSData.class] && s.web.URL) SaveState(s.ident, (NSData *)st);
}
- (void)evict:(Session *)s {
    [self saveSession:s];
    [self dropSession:s.ident deleteState:NO];
    Crumb([@"evicted to storage: " stringByAppendingString:s.path.lastPathComponent]);
}
- (void)trim {                                                    // keep a few pages in RAM; older ones go to storage
    NSInteger mx = [UD() integerForKey:@"maxLive"]; if (mx < 1) mx = 3;
    while ((NSInteger)self.live.count > mx) {
        Session *victim = nil;
        for (NSString *k in self.order) if (self.live[k] != self.current) { victim = self.live[k]; break; }
        if (!victim) return;
        [self evict:victim];
    }
}
- (void)memoryWarning { for (NSString *k in [self.order copy]) { Session *s = self.live[k]; if (s && s != self.current) [self evict:s]; } }
- (void)saveAll { for (Session *s in self.live.allValues) [self saveSession:s]; }
- (void)purgeSnapshotsOfLiveSessions {}   // snapshots now stay (one per HTML, replaced on every save) so a crash never loses the last autosave
- (void)restartCurrent {
    Session *s = self.current; if (!s) return;
    NSMutableDictionary *it = ItemById(s.ident); NSURL *scoped = s.scoped; s.scoped = nil;
    [self dropSession:s.ident deleteState:YES];
    if (it) { Session *n = [self makeSession:it scoped:scoped]; [self show:n]; }
}

#pragma mark WKNavigationDelegate / WKUIDelegate
- (void)webView:(WKWebView *)w decidePolicyForNavigationAction:(WKNavigationAction *)a decisionHandler:(void (^)(WKNavigationActionPolicy))h {
    NSString *scheme = a.request.URL.scheme.lowercaseString;
    NSArray *internal = @[@"http", @"https", @"file", @"about", @"data", @"blob", @"javascript", @"ws", @"wss", @"hvfile"];
    if (scheme.length && ![internal containsObject:scheme]) { [UIApplication.sharedApplication openURL:a.request.URL options:@{} completionHandler:nil]; h(WKNavigationActionPolicyCancel); return; }
    h(WKNavigationActionPolicyAllow);
}
- (WKWebView *)webView:(WKWebView *)w createWebViewWithConfiguration:(WKWebViewConfiguration *)c forNavigationAction:(WKNavigationAction *)a windowFeatures:(WKWindowFeatures *)f {
    if (a.request.URL && ![a.request.URL.absoluteString isEqualToString:@"about:blank"]) [w loadRequest:a.request];
    return nil;
}
- (void)webView:(WKWebView *)w didFinishNavigation:(WKNavigation *)n {
    Session *s = [self sessionForWeb:w];
    if (s.pendingState) { NSData *d = s.pendingState; s.pendingState = nil; w.interactionState = d; Crumb(@"restored saved position"); After(4, ^{ [self diag:s]; }); }
}
- (void)webView:(WKWebView *)w didFailProvisionalNavigation:(WKNavigation *)n withError:(NSError *)e {
    if (e.code == NSURLErrorCancelled) return;
    Session *s = [self sessionForWeb:w]; s.lastError = e.localizedDescription;
    Crumb([@"load failed: " stringByAppendingString:e.localizedDescription ?: @"?"]);
    if (s && !s.fellBack && [w.URL.scheme isEqualToString:@"file"] == NO) {}
    if (s && !s.fellBack) { s.fellBack = YES; [w loadRequest:[NSURLRequest requestWithURL:HVURL(s.path)]]; return; }
    if (w == self.current.web) [self say:@"Couldn't load the page" message:[NSString stringWithFormat:@"%@\n\n%@", e.localizedDescription, self.current.path]];
}
- (void)webViewWebContentProcessDidTerminate:(WKWebView *)w {
    Session *s = [self sessionForWeb:w]; if (!s) return;
    if (w.URL) [w reload]; else [w loadFileURL:[NSURL fileURLWithPath:s.path] allowingReadAccessToURL:[NSURL fileURLWithPath:s.path.stringByDeletingLastPathComponent isDirectory:YES]];
}
- (void)webView:(WKWebView *)w runJavaScriptAlertPanelWithMessage:(NSString *)m initiatedByFrame:(WKFrameInfo *)f completionHandler:(void (^)(void))h {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:m preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(id x){ h(); }]]; [self present:a];
}
- (void)webView:(WKWebView *)w runJavaScriptConfirmPanelWithMessage:(NSString *)m initiatedByFrame:(WKFrameInfo *)f completionHandler:(void (^)(BOOL))h {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:m preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(id x){ h(NO); }]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(id x){ h(YES); }]]; [self present:a];
}
- (void)webView:(WKWebView *)w runJavaScriptTextInputPanelWithPrompt:(NSString *)p defaultText:(NSString *)d initiatedByFrame:(WKFrameInfo *)f completionHandler:(void (^)(NSString *))h {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:p preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *t){ t.text = d; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(id x){ h(nil); }]];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(id x){ h(a.textFields.firstObject.text); }]]; [self present:a];
}
- (void)webView:(WKWebView *)w requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)o initiatedByFrame:(WKFrameInfo *)f type:(WKMediaCaptureType)t decisionHandler:(void (^)(WKPermissionDecision))h { h(WKPermissionDecisionGrant); }

#pragma mark file missing: what to do with the data
- (void)handleMissing:(NSMutableDictionary *)it {
    BOOL sep = IB(it, @"sep", NO); NSString *name = ItemName(it);
    NSString *msg = sep
      ? [NSString stringWithFormat:@"“%@” was moved or deleted. Its data (saves etc.) is still stored in the app and is kept separate from your other HTMLs.\n\nWhat do you want to do with that data?", name]
      : [NSString stringWithFormat:@"“%@” was moved or deleted. Its data (saves etc.) is shared with your other HTMLs.\n\nUpdating it? Choose Cancel, then open the new version from Files: it will use the same shared data.", name];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"File not found" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:sep ? @"Delete the data" : @"Delete the shared data (affects all sharing HTMLs)" style:UIAlertActionStyleDestructive handler:^(id x) { [self missingDelete:it]; }]];
    if (sep) {
        [a addAction:[UIAlertAction actionWithTitle:@"Share the data (move it into the shared data)" style:UIAlertActionStyleDefault handler:^(id x) { [self missingShare:it]; }]];
        [a addAction:[UIAlertAction actionWithTitle:@"Replace another HTML's data with this one's" style:UIAlertActionStyleDefault handler:^(id x) { [self missingReplace:it]; }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self present:a];
}
- (void)missingDelete:(NSMutableDictionary *)it {
    [self dropSession:it[@"id"] deleteState:YES];
    WipeStore(DataStoreFor(it), ^{ [self toast:@"Data deleted"]; After(1.6, ^{ [self askRemoveListing:it]; }); });
}
- (void)missingShare:(NSMutableDictionary *)it {
    WKWebsiteDataStore *priv = DataStoreFor(it);
    [self toast:@"Moving data…"];
    ReadLS(priv, ^(NSDictionary *d) {
        if (!d) { After(1.6, ^{ [self say:@"Couldn't read the data" message:@"Nothing was changed."]; }); return; }
        WriteLS(WKWebsiteDataStore.defaultDataStore, d, NO, ^(BOOL ok) {
            if (!ok) { After(1.6, ^{ [self say:@"Couldn't write the data" message:@"Nothing was changed."]; }); return; }
            [self dropSession:it[@"id"] deleteState:YES];
            it[@"sep"] = @NO; SaveLib(); WipeStore(priv, nil); [self reloadList];
            After(1.6, ^{ [self askRemoveListing:it]; });
        });
    });
}
- (void)missingReplace:(NSMutableDictionary *)it {
    NSMutableArray *others = [NSMutableArray array];
    for (NSMutableDictionary *o in Lib()) if (o != it) [others addObject:o];
    if (!others.count) { [self say:@"No other HTML" message:@"There is no other HTML in the list to replace."]; return; }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Replace whose data?" message:@"The chosen HTML's saved data is erased and replaced with this one's." preferredStyle:UIAlertControllerStyleAlert];
    for (NSMutableDictionary *o in others) [a addAction:[UIAlertAction actionWithTitle:ItemName(o) style:UIAlertActionStyleDefault handler:^(id x) {
        WKWebsiteDataStore *src = DataStoreFor(it), *dst = DataStoreFor(o);
        [self toast:@"Replacing data…"];
        ReadLS(src, ^(NSDictionary *d) {
            if (!d) { After(1.6, ^{ [self say:@"Couldn't read the data" message:@"Nothing was changed."]; }); return; }
            [self dropSession:o[@"id"] deleteState:YES];
            WipeStore(dst, ^{ WriteLS(dst, d, YES, ^(BOOL ok) { After(1.6, ^{ if (!ok) [self say:@"Couldn't write the data" message:@"The other HTML's data may now be empty."]; else [self askRemoveListing:it]; }); }); });
        });
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]; [self present:a];
}
- (void)askRemoveListing:(NSMutableDictionary *)it {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Remove “%@” from the list?", ItemName(it)] message:@"The file is already gone, so the entry can't open anything anymore." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Remove from list" style:UIAlertActionStyleDestructive handler:^(id x) { [self finishRemove:it deleteFiles:NO]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Keep it" style:UIAlertActionStyleCancel handler:nil]]; [self present:a];
}
- (void)removeItem:(NSMutableDictionary *)it {
    BOOL copied = IB(it, @"copied", NO) && [NSFileManager.defaultManager fileExistsAtPath:it[@"path"]];
    if (!copied) { [self finishRemove:it deleteFiles:NO]; return; }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Remove “%@”?", ItemName(it)] message:@"This HTML is a copy stored inside the app. Delete the copy too, or only remove it from the list?" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Remove and delete the copy" style:UIAlertActionStyleDestructive handler:^(id x) { [self finishRemove:it deleteFiles:YES]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Remove from list only" style:UIAlertActionStyleDefault handler:^(id x) { [self finishRemove:it deleteFiles:NO]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(id x) { [self reloadList]; }]]; [self present:a];
}
- (void)finishRemove:(NSMutableDictionary *)it deleteFiles:(BOOL)del {
    [self dropSession:it[@"id"] deleteState:YES];
    if (del) {
        NSString *root = RealPath(DocsRoot()), *top = RealPath(it[@"path"]);
        if ([top hasPrefix:[root stringByAppendingString:@"/"]]) {
            while (![top.stringByDeletingLastPathComponent isEqualToString:root] && top.length > root.length + 1) top = top.stringByDeletingLastPathComponent;
            BOOL shared = NO; for (NSDictionary *o in Lib()) if (o != it && [RealPath(o[@"path"]) hasPrefix:[top stringByAppendingString:@"/"]]) shared = YES;
            if (!shared) [NSFileManager.defaultManager removeItemAtPath:top error:nil];
        }
    }
    [Lib() removeObject:it]; SaveLib();
    if ([self.selectedId isEqualToString:it[@"id"]]) self.selectedId = nil;
    [self reloadList];
}

#pragma mark icon + home-screen shortcut
- (NSString *)iconLabel:(NSDictionary *)it {
    NSString *ic = it[@"icon"];
    if ([ic hasPrefix:@"e:"]) return [ic substringFromIndex:2];
    if ([ic hasPrefix:@"s:"]) { NSUInteger i = [IconPresets() indexOfObject:[ic substringFromIndex:2]]; NSArray *n = [self iconNames]; return i != NSNotFound ? n[i] : @"Symbol"; }
    return IB(it, @"copied", NO) ? @"Default (copied)" : @"Default (in place)";
}
- (NSArray *)iconNames { return @[@"Game controller", @"Star", @"Heart", @"Flame", @"Bolt", @"Book", @"Film", @"Music", @"Globe", @"Hammer", @"Leaf", @"Moon", @"Sun", @"Cart", @"Puzzle", @"Magic wand"]; }
- (void)pickIconFor:(NSMutableDictionary *)it {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Icon" message:@"Pick an icon for this HTML. If you change it, a small badge on the right still shows whether it's copied or running in place." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Default (green = copied, orange = in place)" style:UIAlertActionStyleDefault handler:^(id x) { [it removeObjectForKey:@"icon"]; SaveLib(); [self reloadList]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Emoji…" style:UIAlertActionStyleDefault handler:^(id x) {
        UIAlertController *e = [UIAlertController alertControllerWithTitle:@"Emoji icon" message:@"Type one emoji" preferredStyle:UIAlertControllerStyleAlert];
        [e addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"🎮"; }];
        [e addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [e addAction:[UIAlertAction actionWithTitle:@"Set" style:UIAlertActionStyleDefault handler:^(id y) {
            NSString *t = [e.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (t.length) { NSRange r = [t rangeOfComposedCharacterSequenceAtIndex:0]; it[@"icon"] = [@"e:" stringByAppendingString:[t substringWithRange:r]]; SaveLib(); [self reloadList]; }
        }]]; [self present:e];
    }]];
    NSArray *names = [self iconNames], *syms = IconPresets();
    for (NSUInteger i = 0; i < syms.count; i++) [a addAction:[UIAlertAction actionWithTitle:names[i] style:UIAlertActionStyleDefault handler:^(id x) { it[@"icon"] = [@"s:" stringByAppendingString:syms[i]]; SaveLib(); [self reloadList]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]; [self present:a];
}
- (void)addShortcutFor:(NSMutableDictionary *)it {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Add to Home Screen" message:@"iOS needs a small profile for this. Safari will open here in the app and ask to download it:\n\n1. Tap Allow\n2. Open Settings → “Profile Downloaded”\n3. Tap Install\n\nThe new icon runs this HTML immediately." preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDefault handler:^(id x) {
        NSString *bid = NSBundle.mainBundle.bundleIdentifier ?: @"app", *ident = it[@"id"], *name = ItemName(it);
        NSData *png = UIImagePNGRepresentation(ItemIcon(it, 180));
        NSDictionary *clip = @{@"PayloadType": @"com.apple.webClip.managed", @"PayloadVersion": @1, @"PayloadIdentifier": [NSString stringWithFormat:@"%@.clip.%@", bid, ident],
            @"PayloadUUID": NSUUID.UUID.UUIDString, @"PayloadDisplayName": name, @"Label": name,
            @"URL": [NSString stringWithFormat:@"%@://open?id=%@", APP_SCHEME, ident], @"Icon": png ?: [NSData data],
            @"IsRemovable": @YES, @"FullScreen": @YES, @"IgnoreManifestScope": @YES, @"Precomposed": @YES};     // full-screen clips hand custom-scheme URLs straight to the app (no browser, no "open in app?" question)
        NSDictionary *prof = @{@"PayloadType": @"Configuration", @"PayloadVersion": @1, @"PayloadIdentifier": [NSString stringWithFormat:@"%@.shortcut.%@", bid, ident],
            @"PayloadUUID": NSUUID.UUID.UUIDString, @"PayloadDisplayName": [name stringByAppendingString:@" shortcut"], @"PayloadOrganization": APP_NAME,
            @"PayloadDescription": [NSString stringWithFormat:@"Adds a Home Screen shortcut that runs this HTML in %@.", APP_NAME], @"PayloadRemovalDisallowed": @NO, @"PayloadContent": @[clip]};
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:prof format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
        ServeProfile(data, ^(NSURL *url) {
            if (!url) { [self say:@"Couldn't start" message:@"The app couldn't open a local server for the profile."]; return; }
            // Safari itself, shown inside this app (SFSafariViewController is Safari's engine, so profile downloads work, and it ignores the default-browser setting)
            SFSafariViewController *sf = [[SFSafariViewController alloc] initWithURL:url];
            sf.modalPresentationStyle = UIModalPresentationPageSheet;
            [self present:sf];
        });
    }]];
    [self present:a];
}

#pragma mark settings screens
- (void)presentAppSettings {
    __weak HostVC *me = self;
    NSArray *mx = @[@"1", @"2", @"3", @"4", @"5"];
    SettingsVC *vc = [[SettingsVC alloc] initWithStyle:UITableViewStyleInsetGrouped];
    vc.sections = @[
      @{@"h": @"Launch", @"rows": @[
         @{@"t": @"Highlight last played on launch", @"k": @"sw", @"get": ^id{ return @(AppB(@"autoHL", YES)); }, @"set": ^(id v){ [UD() setObject:v forKey:@"autoHL"]; }}]},
      @{@"h": @"Memory", @"f": @"Pages stay in memory like background tabs. When memory is low, or the app is closed, they are saved to storage and restored where you left off. The stored copy is deleted as soon as it is back in memory.", @"rows": @[
         @{@"t": @"Pages kept in memory", @"k": @"ch", @"opts": mx, @"get": ^id{ NSInteger m = [UD() integerForKey:@"maxLive"]; return @((m < 1 ? 3 : m) - 1); }, @"set": ^(id v){ [UD() setInteger:[v integerValue] + 1 forKey:@"maxLive"]; }}]},
      @{@"h": @"Storage", @"f": @"Copies live in the app's “HTML Files” folder.", @"rows": @[
         @{@"t": @"Where are copied files?", @"k": @"btn", @"act": ^{ [me say:@"Internal folder" message:DocsRoot()]; }},
         @{@"t": @"Clear all saved positions", @"k": @"btn", @"act": ^{ [me confirm:@"Clear all saved positions?" message:@"Every HTML will start fresh next time. Website data (saves) is NOT touched." action:@"Clear" then:^{
              for (NSDictionary *d in Lib()) [me dropSession:d[@"id"] deleteState:YES]; [me reloadList]; [me toast:@"Cleared"]; }]; }},
         @{@"t": @"Delete ALL website data", @"k": @"btn", @"destructive": @YES, @"act": ^{ [me confirm:@"Delete all website data?" message:@"Deletes the saves (localStorage, IndexedDB, cookies…) of every HTML, shared and separate." action:@"Delete" then:^{
              WipeStore(WKWebsiteDataStore.defaultDataStore, nil);
              for (NSDictionary *d in Lib()) if (IB(d, @"sep", NO)) WipeStore(DataStoreFor(d), nil);
              [me toast:@"Deleted"]; }]; }}]}];
    [self presentSettings:vc title:@"Settings"];
}
- (void)presentItemSettings:(NSMutableDictionary *)it {
    __weak HostVC *me = self;
    NSArray *zoomNames = @[@"50%", @"75%", @"90%", @"100%", @"110%", @"125%", @"150%", @"200%"]; static const double zoomVals[] = {.5, .75, .9, 1, 1.1, 1.25, 1.5, 2};
    SettingsVC *vc = [[SettingsVC alloc] initWithStyle:UITableViewStyleInsetGrouped];
    NSDictionary *(^sw)(NSString *, NSString *, BOOL) = ^NSDictionary *(NSString *t, NSString *k, BOOL d) { return @{@"t": t, @"k": @"sw", @"get": ^id{ return @(IB(it, k, d)); }, @"set": ^(id v){ it[k] = v; SaveLib(); [me reloadList]; }}; };
    NSDictionary *(^tx)(NSString *, NSString *, NSString *) = ^NSDictionary *(NSString *t, NSString *k, NSString *m) { return @{@"t": t, @"m": m ?: @"", @"k": @"txt", @"get": ^id{ return it[k] ?: @""; }, @"set": ^(id v){ it[k] = v; SaveLib(); [me reloadList]; }}; };
    NSString *where = IB(it, @"copied", NO) ? [@"Copied into the app\n" stringByAppendingString:it[@"path"]] : [@"Running where it is\n" stringByAppendingString:it[@"path"]];
    vc.sections = @[
      @{@"h": @"This HTML", @"f": where, @"rows": @[ tx(@"Name", @"name", @"Leave empty to use the file name"),
         @{@"t": @"Icon", @"k": @"btn", @"get": ^id{ return [me iconLabel:it]; }, @"act": ^{ [me pickIconFor:it]; }}]},
      @{@"h": @"Data", @"f": SeparateSupported() ? @"Off: every HTML shares one storage, so a newer version sees your old save. On: this HTML gets its own private storage (a lock shows in the list). Switching starts using the other storage; existing saves stay where they were." : @"Separate data needs iOS 17 or newer.", @"rows": @[ sw(@"Keep this one's data separate", @"sep", NO)]},
      @{@"h": @"Page", @"f": @"Changes apply the next time the page starts (use “Restart this page” below).", @"rows": @[
         sw(@"Desktop site", @"desktop", YES),
         @{@"t": @"Page zoom", @"k": @"ch", @"opts": zoomNames, @"get": ^id{ double z = [it[@"zoom"] doubleValue] ?: 1; NSInteger b = 3; double bd = 9; for (int i = 0; i < 8; i++) if (fabs(zoomVals[i] - z) < bd) { bd = fabs(zoomVals[i] - z); b = i; } return @(b); }, @"set": ^(id v){ it[@"zoom"] = @(zoomVals[[v integerValue]]); SaveLib(); }},
         @{@"t": @"Orientation", @"k": @"ch", @"opts": @[@"Auto", @"Portrait", @"Landscape"], @"get": ^id{ return @([it[@"orient"] integerValue]); }, @"set": ^(id v){ it[@"orient"] = v; SaveLib(); }},
         sw(@"Keep screen awake", @"awake", NO),
         tx(@"Custom user agent", @"ua", @"Empty = default"),
         tx(@"Custom CSS", @"css", @"Injected into every page as a style element"),
         tx(@"Custom JavaScript", @"js", @"Runs after every page loads")]},
      @{@"h": @"Memory", @"rows": @[ sw(@"Resume where I left off", @"resume", YES)]},
      @{@"h": @"Home Screen", @"rows": @[ @{@"t": @"Add to Home Screen", @"k": @"btn", @"act": ^{ [me addShortcutFor:it]; }}]},
      @{@"h": @"Reset", @"rows": @[
         @{@"t": @"Restart this page (forget position)", @"k": @"btn", @"act": ^{ [me dropSession:it[@"id"] deleteState:YES]; [me reloadList]; [me toast:@"It will start fresh next time"]; }},
         @{@"t": @"Delete this HTML's data", @"k": @"btn", @"destructive": @YES, @"act": ^{
              BOOL sep = IB(it, @"sep", NO);
              [me confirm:@"Delete data?" message:sep ? @"Deletes this HTML's private saves." : @"This HTML shares storage with the others: the saves of ALL HTMLs that share it will be deleted." action:@"Delete" then:^{
                  [me dropSession:it[@"id"] deleteState:YES]; WipeStore(DataStoreFor(it), ^{ [me toast:@"Data deleted"]; }); }]; }},
         @{@"t": @"Remove from list", @"k": @"btn", @"destructive": @YES, @"act": ^{ [me dismissViewControllerAnimated:YES completion:^{ [me removeItem:it]; }]; }}]}];
    [self presentSettings:vc title:@"HTML Settings"];
}

#pragma mark + button (sideloaded app): add a file or folder with the Files picker
- (void)plusTapped {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Add" message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"HTML file…" style:UIAlertActionStyleDefault handler:^(id x) { [self pick:0]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Folder (then choose an HTML in it)…" style:UIAlertActionStyleDefault handler:^(id x) { [self pick:1]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]]; [self present:a];
}
- (void)pick:(NSInteger)mode {
    self.pickMode = mode;
    UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:(mode == 0 ? @[UTTypeHTML, UTTypeItem] : @[UTTypeFolder]) asCopy:NO];
    p.delegate = self; p.allowsMultipleSelection = NO; [self present:p];
}
- (void)documentPicker:(UIDocumentPickerViewController *)c didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject; if (!u) return;
    if (self.pickMode == 0) { After(0.7, ^{ [self openExternalFile:u]; }); return; }
    if (!gScopes) gScopes = [NSMutableSet set];
    if ([u startAccessingSecurityScopedResource]) [gScopes addObject:u];
    NSString *dir = RealPath(u.path);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *found = [NSMutableArray array]; NSFileManager *fm = [NSFileManager new];
        for (NSString *rel in [fm enumeratorAtPath:dir]) {
            NSString *e = rel.pathExtension.lowercaseString;
            if ([e isEqualToString:@"html"] || [e isEqualToString:@"htm"] || [e isEqualToString:@"xhtml"]) { [found addObject:rel]; if (found.count >= 400) break; }
        }
        [found sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) { NSInteger da = [a componentsSeparatedByString:@"/"].count, db = [b componentsSeparatedByString:@"/"].count; return da != db ? (da < db ? NSOrderedAscending : NSOrderedDescending) : [a compare:b]; }];
        dispatch_async(dispatch_get_main_queue(), ^{
            After(0.7, ^{
                if (!found.count) { [self say:@"No HTML files" message:@"That folder doesn't contain any .html files."]; return; }
                if (found.count == 1) { [self openExternalFile:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:found[0]]]]; return; }
                NSMutableArray *rows = [NSMutableArray array]; __block SettingsVC *vc = [[SettingsVC alloc] initWithStyle:UITableViewStyleInsetGrouped];
                for (NSString *rel in found) [rows addObject:@{@"t": rel, @"k": @"btn", @"act": ^{ [vc dismissViewControllerAnimated:YES completion:^{ [self openExternalFile:[NSURL fileURLWithPath:[dir stringByAppendingPathComponent:rel]]]; }]; }}];
                vc.sections = @[@{@"h": @"Which HTML should open?", @"f": found.count >= 400 ? @"Showing the first 400." : nil, @"rows": rows}];
                [self presentSettings:vc title:dir.lastPathComponent];
            });
        });
    });
}
@end

#pragma mark - App lifecycle
static HostVC *gHost;
static NSURL *gPendingURL;
static UIApplicationShortcutItem *gPendingShortcut;
static BOOL gHaveWindow;
static NSTimer *gAutoSave;

static void HandleShortcut(UIApplicationShortcutItem *i) {
    if ([i.type isEqualToString:@"restart"]) [gHost restartCurrent];
    else if ([i.type isEqualToString:@"open"]) [gHost showList];
}
static void InstallApp(UIWindow *w) {
    w.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; w.backgroundColor = UIColor.blackColor; gWin = w;
    HostVC *h = [HostVC new]; gHost = h;
    w.rootViewController = h; [w makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{
        [h loadViewIfNeeded];
        [h resumeLast];
        if (gPendingURL) { NSURL *u = gPendingURL; gPendingURL = nil; [h openIncomingURL:u]; }
        if (gPendingShortcut) { UIApplicationShortcutItem *i = gPendingShortcut; gPendingShortcut = nil; After(0.4, ^{ HandleShortcut(i); }); }
    });
}

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation SceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)s options:(UISceneConnectionOptions *)opts {
    Crumb(@"2 scene willConnect");
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    gHaveWindow = YES;
    NSURL *u = opts.URLContexts.anyObject.URL; if (u) gPendingURL = u;
    if (opts.shortcutItem) gPendingShortcut = opts.shortcutItem;
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    InstallApp(self.window);
}
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)ctx {
    NSURL *u = ctx.anyObject.URL; if (!u) return;
    if (gHost) [gHost openIncomingURL:u]; else gPendingURL = u;
}
- (void)windowScene:(UIWindowScene *)ws performActionForShortcutItem:(UIApplicationShortcutItem *)item completionHandler:(void (^)(BOOL))done {
    if (gHost) HandleShortcut(item); else gPendingShortcut = item;
    done(YES);
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *fallbackWindow;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    Crumb(@"1b didFinishLaunching");
    NSSetUncaughtExceptionHandler(&UncaughtHandler);
    return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)s options:(UISceneConnectionOptions *)o {
    UISceneConfiguration *c = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:s.role];
    c.delegateClass = SceneDelegate.class; return c;
}
- (void)applicationDidBecomeActive:(UIApplication *)app {
    Crumb(@"1c didBecomeActive");
    if (!gAutoSave) gAutoSave = [NSTimer scheduledTimerWithTimeInterval:300 repeats:YES block:^(NSTimer *t) { [gHost saveAll]; }];   // autosave every 5 minutes while the app is open
    [gHost purgeSnapshotsOfLiveSessions];
    if (gHaveWindow || self.fallbackWindow) return;
    Crumb(@"2b no scene, using fallback window");
    self.fallbackWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    InstallApp(self.fallbackWindow);
}
- (void)applicationDidEnterBackground:(UIApplication *)app {
    __block UIBackgroundTaskIdentifier t = [app beginBackgroundTaskWithExpirationHandler:^{ [app endBackgroundTask:t]; t = UIBackgroundTaskInvalid; }];
    [gHost saveAll];
    if (t != UIBackgroundTaskInvalid) [app endBackgroundTask:t];
}
- (void)applicationWillTerminate:(UIApplication *)app { [gHost saveAll]; }
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary *)o {
    if (gHost) [gHost openIncomingURL:url]; else gPendingURL = url;
    return YES;
}
@end

int main(int argc, char *argv[]) {
    CrumbC("1a main()");
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class])); }
}

#import "TBAccountController.h"
#import "TBAccount.h"
#import "TBShell.h"
#import "TBStyle.h"
#import "TBSegments.h"
#include "qrcodegen.h"
#include "tb_http.h"

static UIImage *qrImage(NSString *text, CGFloat side) {
    uint8_t qr[qrcodegen_BUFFER_LEN_MAX], tmp[qrcodegen_BUFFER_LEN_MAX];
    if (!qrcodegen_encodeText(text.UTF8String, tmp, qr, qrcodegen_Ecc_MEDIUM, qrcodegen_VERSION_MIN, qrcodegen_VERSION_MAX,
                              qrcodegen_Mask_AUTO, true)) return nil;
    int n = qrcodegen_getSize(qr), quiet = 4;
    CGFloat m = floor(side / (n + 2 * quiet));
    CGFloat s = m * (n + 2 * quiet);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(s, s), YES, 1);
    CGContextRef c = UIGraphicsGetCurrentContext();
    [[UIColor whiteColor] setFill];
    CGContextFillRect(c, CGRectMake(0, 0, s, s));
    [[UIColor blackColor] setFill];
    for (int y = 0; y < n; y++)
        for (int x = 0; x < n; x++)
            if (qrcodegen_getModule(qr, x, y)) CGContextFillRect(c, CGRectMake((x + quiet) * m, (y + quiet) * m, m, m));
    UIImage *i = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return i;
}

static UILabel *label(CGFloat size, BOOL bold, UIColor *color) {
    UILabel *l = [UILabel new];
    l.font = bold ? TBFontBold(size) : TBFont(size);
    l.textColor = color;
    l.backgroundColor = [TBStyle cardFill];
    l.numberOfLines = 0;
    return l;
}

static UIButton *lightButton(NSString *title, id target, SEL action) {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setBackgroundImage:[TBStyle lightButtonImage:NO] forState:UIControlStateNormal];
    [b setBackgroundImage:[TBStyle lightButtonImage:YES] forState:UIControlStateHighlighted];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[TBStyle buttonText] forState:UIControlStateNormal];
    b.titleLabel.font = TBFont(16);
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

@implementation TBAccountController {
    UIScrollView *_scroll;
    UIImageView *_card, *_qr, *_aboutCard, *_themeCard;
    TBSegments *_theme;
    UILabel *_heading, *_body, *_address, *_code, *_status, *_about, *_themeLabel;
    UIButton *_action;
    UIActivityIndicatorView *_spin;
    NSString *_url, *_error;
    BOOL _waiting;
}

- (id)init {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    self.title = @"Account";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:TBAccountChanged object:nil];
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (NSString *)shownCode { return _waiting ? _code.text : nil; }

- (void)loadView {
    _scroll = [UIScrollView new];
    _scroll.backgroundColor = [TBStyle contentBackground];
    _scroll.alwaysBounceVertical = YES;
    _card = [[UIImageView alloc] initWithImage:[TBStyle cardImage]];
    _card.userInteractionEnabled = YES;
    _heading = label(22, NO, [TBStyle text]);
    _body = label(16, NO, [TBStyle secondary]);
    _address = label(30, YES, [TBStyle text]);
    _code = label(56, YES, TBHex(0xCD1A18));
    _code.textAlignment = NSTextAlignmentCenter;
    _status = label(15, NO, [TBStyle secondary]);
    _qr = [UIImageView new];
    _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spin.hidesWhenStopped = YES;
    _action = lightButton(@"", self, @selector(actionTapped));
    for (UIView *v in @[_heading, _body, _address, _code, _status, _qr, _spin, _action]) [_card addSubview:v];
    /* DUC-SET-THEME: Light / Dark */
    _themeCard = [[UIImageView alloc] initWithImage:[TBStyle cardImage]];
    _themeCard.userInteractionEnabled = YES;
    _themeLabel = label(18, YES, [TBStyle text]);
    _themeLabel.text = @"Theme";
    _theme = [TBSegments new];
    _theme.titles = @[@"Light", @"Dark"];
    _theme.selected = [TBStyle dark] ? 1 : 0;
    _theme.changed = ^(NSInteger i) { [TBStyle setDark:i == 1]; };
    [_themeCard addSubview:_themeLabel];
    [_themeCard addSubview:_theme];
    [_scroll addSubview:_themeCard];
    _aboutCard = [[UIImageView alloc] initWithImage:[TBStyle cardImage]];
    _about = label(14, NO, [TBStyle secondary]);
    [_aboutCard addSubview:_about];
    [_scroll addSubview:_card];
    [_scroll addSubview:_aboutCard];
    self.view = _scroll;
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refresh]; }

- (void)refresh {
    if (!self.isViewLoaded) return;
    BOOL in = [TBAccount signedIn];
    _address.hidden = _code.hidden = _qr.hidden = !_waiting;
    if (_waiting) {
        _heading.text = @"Sign in with a code";
        _body.text = @"On your phone or computer, open this address and type the code. You do not type a password on the iPad.";
        _address.text = @"google.com/device";
        _status.text = self.notice.length ? [self.notice stringByAppendingString:@" This page changes by itself when you are signed in."]
                                          : @"Waiting for you to enter the code. This page changes by itself when you are signed in.";
        [_action setTitle:@"Cancel" forState:UIControlStateNormal];
        [_spin startAnimating];
        _qr.image = qrImage(_url ?: @"https://www.google.com/device", 200);
    } else if (in) {
        _heading.text = @"Signed in";
        _body.text = @"Home, Subscriptions, History, Watch Later, Liked Videos and Playlists show your YouTube account.";
        _status.text = _error;
        [_action setTitle:@"Sign out" forState:UIControlStateNormal];
        [_spin stopAnimating];
    } else {
        _heading.text = @"Sign in to YouTube";
        _body.text = @"PadTube shows a short code. You enter it on your phone or computer at google.com/device. No web page opens on the iPad.";
        _status.text = _error;
        [_action setTitle:@"Get a sign-in code" forState:UIControlStateNormal];
        [_spin stopAnimating];
    }
    tb_http_stats st;
    tb_http_get_stats(&st);
    _about.text = [NSString stringWithFormat:@"PadTube %@ for iPad. Not affiliated with Google or YouTube.\nNetwork: %ld requests, %ld TLS handshakes, %.1f MB.\nLicences: OpenSSL, yyjson, QR Code generator (in the app bundle, Licenses folder).",
                   [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"], st.requests, st.handshakes, st.bytes_in / 1048576.0];
    [self.view setNeedsLayout];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, cw = MIN(748, w - 20), cx = floor((w - cw) / 2), pad = 24, tw = cw - 2 * pad;
    CGFloat y = pad;
    _heading.frame = CGRectMake(pad, y, tw, 28); y += 40;
    CGSize bs = [_body.text sizeWithFont:_body.font constrainedToSize:CGSizeMake(tw, 200)];
    _body.frame = CGRectMake(pad, y, tw, bs.height); y += bs.height + 20;
    if (_waiting) {
        CGFloat qs = 200, textw = tw - qs - 24;
        _qr.frame = CGRectMake(cw - pad - qs, y, qs, qs);
        _address.frame = CGRectMake(pad, y + 10, textw, 40);
        _code.frame = CGRectMake(pad, y + 70, textw, 70);
        y += qs + 20;
    }
    CGSize ss = [_status.text ?: @"" sizeWithFont:_status.font constrainedToSize:CGSizeMake(tw - 30, 200)];
    _spin.frame = CGRectMake(pad, y, 20, 20);
    _status.frame = CGRectMake(_waiting ? pad + 30 : pad, y, tw - (_waiting ? 30 : 0), ss.height); y += MAX(ss.height, _waiting ? 20 : 0) + (ss.height ? 20 : 0);
    _action.frame = CGRectMake(pad, y, 220, 38); y += 38 + pad;
    _card.frame = CGRectMake(cx, 12, cw, y);
    CGSize as = [_about.text sizeWithFont:_about.font constrainedToSize:CGSizeMake(tw, 400)];
    _about.frame = CGRectMake(pad, 16, tw, as.height);
    _themeCard.frame = CGRectMake(cx, CGRectGetMaxY(_card.frame) + 18, cw, 64);
    _themeLabel.frame = CGRectMake(pad, 18, 120, 28);
    _theme.frame = CGRectMake(cw - pad - 220, 17, 220, 30);
    _aboutCard.frame = CGRectMake(cx, CGRectGetMaxY(_themeCard.frame) + 18, cw, as.height + 34);
    _scroll.contentSize = CGSizeMake(w, CGRectGetMaxY(_aboutCard.frame) + 20);
}

- (void)actionTapped {
    if (_waiting) { [TBAccount cancelSignIn]; return; }
    if ([TBAccount signedIn]) { [TBAccount signOut]; _error = @"Signed out."; [self refresh]; return; }
    [self startSignIn];
}

- (void)startSignIn {
    _error = @"Asking Google for a code...";
    [self refresh];
    [TBAccount beginSignIn:^(NSString *code, NSString *url) {
        self->_waiting = YES;
        self->_code.text = code;
        self->_url = url;
        self->_error = self.notice;
        [self refresh];
    } done:^(BOOL ok, NSString *err) {
        self->_waiting = NO;
        self->_error = ok ? nil : [NSString stringWithFormat:@"Not signed in: %@", err];
        [self refresh];
        [[TBShell shared] refreshAccount];
    }];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end

#import "TBJS.h"
#include <dlfcn.h>

typedef const void *JRef;
static struct {
    JRef (*ctxCreate)(JRef);
    void (*ctxRelease)(JRef);
    JRef (*global)(JRef);
    JRef (*strCreate)(const char *);
    void (*strRelease)(JRef);
    JRef (*eval)(JRef, JRef, JRef, JRef, int, JRef *);
    JRef (*makeString)(JRef, JRef);
    void (*setProp)(JRef, JRef, JRef, JRef, unsigned, JRef *);
    JRef (*toString)(JRef, JRef, JRef *);
    size_t (*strMax)(JRef);
    size_t (*strGet)(JRef, char *, size_t);
} J;

static BOOL load(void) {
    static int state;   /* 0 unknown, 1 ok, -1 failed */
    if (state) return state > 0;
    void *h = dlopen("/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore", RTLD_LAZY);
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/JavaScriptCore.framework/JavaScriptCore", RTLD_LAZY);
    if (h) {
        J.ctxCreate = dlsym(h, "JSGlobalContextCreate");
        J.ctxRelease = dlsym(h, "JSGlobalContextRelease");
        J.global = dlsym(h, "JSContextGetGlobalObject");
        J.strCreate = dlsym(h, "JSStringCreateWithUTF8CString");
        J.strRelease = dlsym(h, "JSStringRelease");
        J.eval = dlsym(h, "JSEvaluateScript");
        J.makeString = dlsym(h, "JSValueMakeString");
        J.setProp = dlsym(h, "JSObjectSetProperty");
        J.toString = dlsym(h, "JSValueToStringCopy");
        J.strMax = dlsym(h, "JSStringGetMaximumUTF8CStringSize");
        J.strGet = dlsym(h, "JSStringGetUTF8CString");
    }
    state = J.ctxCreate && J.ctxRelease && J.global && J.strCreate && J.strRelease && J.eval && J.makeString && J.setProp &&
            J.toString && J.strMax && J.strGet ? 1 : -1;
    return state > 0;
}

static NSString *str(JRef ctx, JRef v) {
    JRef s = J.toString(ctx, v, NULL);
    if (!s) return nil;
    size_t n = J.strMax(s);
    char *b = malloc(n);
    J.strGet(s, b, n);
    NSString *r = [NSString stringWithUTF8String:b];
    free(b);
    J.strRelease(s);
    return r;
}

@implementation TBJS {
    JRef _ctx;
}

+ (BOOL)available { return load(); }

- (id)init {
    if (!load() || !(self = [super init])) return nil;
    _ctx = J.ctxCreate(NULL);
    return _ctx ? self : nil;
}

- (void)dealloc { if (_ctx) J.ctxRelease(_ctx); }

- (void)setString:(NSString *)value forName:(NSString *)name {
    JRef s = J.strCreate(value.UTF8String), n = J.strCreate(name.UTF8String);
    J.setProp(_ctx, J.global(_ctx), n, J.makeString(_ctx, s), 0, NULL);
    J.strRelease(s);
    J.strRelease(n);
}

- (NSString *)eval:(NSString *)src name:(NSString *)name error:(NSString **)error {
    JRef s = J.strCreate(src.UTF8String), u = J.strCreate(name.UTF8String), exc = NULL;
    JRef v = J.eval(_ctx, s, NULL, u, 1, &exc);
    J.strRelease(s);
    J.strRelease(u);
    if (exc) {
        if (error) *error = str(_ctx, exc) ?: @"exception";
        return nil;
    }
    return v ? str(_ctx, v) : @"";
}
@end

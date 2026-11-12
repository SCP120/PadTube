#import "TBLog.h"
#include "tb_http.h"

void TBLog(NSString *fmt, ...) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ q = dispatch_queue_create("padtube.log", DISPATCH_QUEUE_SERIAL); });
    va_list ap;
    va_start(ap, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    dispatch_async(q, ^{ tb_log("%s", line.UTF8String); });
}

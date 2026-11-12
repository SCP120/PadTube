/* iOS 6 has no clock_gettime (iOS 10+). QuickJS-NG uses it for timers and Date.now precision.
 * This shim gives CLOCK_REALTIME from gettimeofday and CLOCK_MONOTONIC from mach_absolute_time. */
#ifndef TB_IOS6_COMPAT_H
#define TB_IOS6_COMPAT_H
#include <mach/mach_time.h>
#include <sys/time.h>
#include <time.h>
#ifndef CLOCK_REALTIME
typedef int clockid_t;
#define CLOCK_REALTIME 0
#define CLOCK_MONOTONIC 6
static inline int clock_gettime(clockid_t id, struct timespec *ts) {
    if (id == CLOCK_REALTIME) {
        struct timeval tv;
        gettimeofday(&tv, NULL);
        ts->tv_sec = tv.tv_sec;
        ts->tv_nsec = tv.tv_usec * 1000;
        return 0;
    }
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    uint64_t ns = mach_absolute_time() * tb.numer / tb.denom;
    ts->tv_sec = (time_t)(ns / 1000000000ULL);
    ts->tv_nsec = (long)(ns % 1000000000ULL);
    return 0;
}
#endif
#endif

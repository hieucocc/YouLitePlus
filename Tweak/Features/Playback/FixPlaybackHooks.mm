#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>
#import <stdlib.h>
#import <string.h>

static NSString * const YTKACEFixPlaybackKey = @"YTKACE.Preference.Playback.Recovery";
static NSString * const kNeedsRefetch = @"YTKACEPlaybackNeedsRefetch";
static NSString * const kScrubBegan  = @"YTKACEPlaybackScrubBegan";

static BOOL FixOn(void) {
    return YTKACEFeatureEnabled(YTKACEFixPlaybackKey);
}

static __weak id gCurrentController = nil;
static BOOL gIsRefetching = NO;
static NSTimeInterval gLastRefetchAt = 0.0;

static NSTimeInterval FPNow(void) { return CFAbsoluteTimeGetCurrent(); }

static NSTimeInterval gSessionStart = 0.0;
static NSTimeInterval gLoadedAt     = 0.0;
static NSTimeInterval gLastFailAt   = 0.0;

static void FPLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void FPLog(NSString *format, ...) {
    (void)format;
}

static long gcState8, gcErrOverlay, gcExpiry, gcPlayability, gcHeartbeat, gcStall;

static void FPFlushCounters(BOOL force) {
    static NSTimeInterval last = 0.0;
    NSTimeInterval now = FPNow();
    if (!force && now - last < 5.0) return;
    last = now;
    long a = gcState8, b = gcErrOverlay, c = gcExpiry,
         d = gcPlayability, e = gcHeartbeat, f = gcStall;
    if ((a | b | c | d | e | f) == 0) return;
    gcState8 = gcErrOverlay = gcExpiry = gcPlayability = gcHeartbeat = gcStall = 0;
    FPLog(@"counters state8=%ld errOverlay=%ld expiryQ=%ld playabilityQ=%ld heartbeat=%ld stall=%ld",
          a, b, c, d, e, f);
}

static BOOL InRecoveryWindow(void) {
    if (gIsRefetching) return YES;
    NSTimeInterval now = FPNow();
    if (gLoadedAt   > 0.0 && now - gLoadedAt   <  6.0) return YES;
    if (gLastFailAt > 0.0 && now - gLastFailAt < 15.0) return YES;
    return NO;
}

static void NoteFailure(NSString *why) {
    gLastFailAt = FPNow();
    FPLog(@"failure noted: %@", why);
}

static long gRefetchStreak = 0;
static NSTimeInterval gBackoffUntil = 0.0;
static const NSTimeInterval kItemFailureWindow = 10.0;
static NSTimeInterval gItemFailureTimes[8] = {0};
static NSUInteger gItemFailureCount = 0;
static long gTotalItemFails = 0;
static long gRawMediaState = -1;
static BOOL gReloadPending = NO;
static NSUInteger gPlaybackGeneration = 0;
static double gLastPlaybackPosition = NAN;
static NSTimeInterval gLastPlaybackObservationAt = 0.0;
static NSUInteger gPlaybackProgressSerial = 0;

static BOOL PlaybackAdvancedSince(double position,
                                  NSUInteger serial,
                                  NSTimeInterval observedAt,
                                  double minimumAdvance) {
    if (gPlaybackProgressSerial == serial ||
        gLastPlaybackObservationAt <= observedAt ||
        !isfinite(position) || !isfinite(gLastPlaybackPosition)) {
        return NO;
    }
    double delta = gLastPlaybackPosition - position;
    return delta >= minimumAdvance || fabs(delta) >= 2.0;
}

static void ClearRecentItemFailures(void) {
    memset(gItemFailureTimes, 0, sizeof(gItemFailureTimes));
    gItemFailureCount = 0;
}

static NSUInteger RecordRecentItemFailure(NSTimeInterval failedAt) {
    NSTimeInterval kept[8] = {0};
    NSUInteger keptCount = 0;
    for (NSUInteger i = 0; i < gItemFailureCount; i++) {
        NSTimeInterval timestamp = gItemFailureTimes[i];
        if (timestamp > 0.0 && failedAt - timestamp <= kItemFailureWindow) {
            kept[keptCount++] = timestamp;
        }
    }
    if (keptCount == 8) {
        memmove(kept, kept + 1, 7 * sizeof(NSTimeInterval));
        keptCount = 7;
    }
    kept[keptCount++] = failedAt;
    memcpy(gItemFailureTimes, kept, sizeof(gItemFailureTimes));
    gItemFailureCount = keptCount;
    return keptCount;
}

static void RequestRefetch(NSString *reason) {
    NSTimeInterval now = FPNow();
    if (gIsRefetching) {
        FPLog(@"refetch request ignored (already refetching) reason=%@", reason);
        return;
    }
    if (now < gBackoffUntil) {
        FPLog(@"refetch suppressed by backoff (%.0fs left) reason=%@",
              gBackoffUntil - now, reason);
        return;
    }
    if (gLastRefetchAt > 0.0 && now - gLastRefetchAt < 15.0) {
        gRefetchStreak++;
    } else {
        gRefetchStreak = 1;
    }
    if (gRefetchStreak > 3) {
        gBackoffUntil = now + 90.0;
        gRefetchStreak = 0;
        FPLog(@"refetch NOT helping (4 within 15s each) -- backing off 90s, reason=%@", reason);
        return;
    }
    NSTimeInterval since = now - gLastRefetchAt;
    if (gLastRefetchAt > 0.0 && since < 8.0) {
        FPLog(@"refetch request throttled (%.1fs since last, need 8s) reason=%@", since, reason);
        return;
    }
    if (gLastRefetchAt > 0.0 && since < 20.0) {
        gLastRefetchAt = now - 20.0;
    }
    FPLog(@"refetch requested reason=%@ (%.1fs since last)", reason, since);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kNeedsRefetch object:nil];
    });
}

static IMP OrigIosguardEnable, OrigHasIosguardEnable;
static IMP OrigHeartbeatNonFatal, OrigHasHeartbeatNonFatal;
static IMP OrigReqIosguardAfter, OrigHasReqIosguardAfter;
static IMP OrigRequiresAtt, OrigHasRequiresAtt;
static IMP OrigStopHeartbeat, OrigHasStopHeartbeat;
static IMP OrigAuthMismatch, OrigHasAuthMismatch;
static IMP OrigHasPlayabilityStatus, OrigPlayabilityStatus;
static IMP OrigHaltIfNeeded, OrigTransitionIfNeeded, OrigHandleHBResp;
static IMP OrigHaltPlaybackWithError;
static IMP OrigSkipOnPlayabilityError, OrigHasSkipOnPlayabilityError;

static IMP OrigCannotPlay, OrigCannotPlayErr, OrigCannotPlayStatus;

static IMP OrigShowErrLong, OrigShowErrMsg, OrigUpdateErrState;

static IMP OrigWatchReset, OrigWatchResetStart;
static IMP OrigOverlayReset, OrigOverlayShowLoading;
static IMP OrigStallReset, OrigStallStartBuf, OrigStallInit;
static IMP OrigInlineReset;
static IMP OrigMainOverlayReset;

static IMP OrigMLEvInit1, OrigMLEvInit2, OrigMLEvInit3;
static IMP OrigMLPlayerItemSetState;
static IMP OrigHAMPlayerSetState;
static IMP OrigAVPlayerSetState, OrigAVPlayerFail, OrigAVPlayerSyncFail, OrigAVPlayerErrOccur;
static IMP OrigAVAssetPlayerSetState;
static IMP OrigHAMQPSetState, OrigHAMQPFail, OrigHAMQPPlayerItemFail, OrigHAMQPTrackFail;
static IMP OrigPostponeFmt;

static IMP OrigSVStateChanged, OrigSVFail;
static IMP OrigLPCRawMedia, OrigLPCLoadTrans, OrigLPCInitPlayback;

static IMP OrigIsWebMEnabled;
static IMP OrigABRInit, OrigABRPostpone, OrigABRStallLikely;

static IMP OrigSkipVideoErr, OrigSkipVideo, OrigHandlePlaybackErr;

static IMP OrigIsPlayable, OrigIsPlayableNowOrAfter, OrigStatus, OrigStatusString;
static IMP OrigErrorCode, OrigHasErrorCode, OrigHasErrorScreen, OrigErrorScreen;

static IMP OrigIsExpiredByMaxAge, OrigStreamsCloseExpiring;
static IMP OrigTimeUntilExpiry, OrigIsReuse;
static IMP OrigMLTimeToExpiry, OrigYTIExpiresIn;

static IMP OrigCacheKeyRelax, OrigStreamingWatchEnabled, OrigPlayerRespCacheToken;


static BOOL CallBool(IMP fn, id r, SEL s) {
    return fn && ((BOOL (*)(id, SEL))fn)(r, s);
}
static id CallObj(IMP fn, id r, SEL s) {
    return fn ? ((id (*)(id, SEL))fn)(r, s) : nil;
}
static long CallLong(IMP fn, id r, SEL s) {
    return fn ? ((long (*)(id, SEL))fn)(r, s) : 0;
}
static double CallDouble(IMP fn, id r, SEL s) {
    return fn ? ((double (*)(id, SEL))fn)(r, s) : 0.0;
}

static void InstallBool(NSString *cls, NSString *sel, IMP repl, IMP *orig) {
    if (!YTKACEInstallInstanceHook(cls, sel, repl, orig)) {
        YTKACEAddInstanceMethod(cls, sel, repl, "B@:");
    }
}
static void InstallObj(NSString *cls, NSString *sel, IMP repl, IMP *orig) {
    if (!YTKACEInstallInstanceHook(cls, sel, repl, orig)) {
        YTKACEAddInstanceMethod(cls, sel, repl, "@@:");
    }
}
static void InstallLong(NSString *cls, NSString *sel, IMP repl, IMP *orig) {
    if (!YTKACEInstallInstanceHook(cls, sel, repl, orig)) {
        YTKACEAddInstanceMethod(cls, sel, repl, "q@:");
    }
}
static void InstallDouble(NSString *cls, NSString *sel, IMP repl, IMP *orig) {
    if (!YTKACEInstallInstanceHook(cls, sel, repl, orig)) {
        YTKACEAddInstanceMethod(cls, sel, repl, "d@:");
    }
}

static BOOL H_IosguardEnable(id r, SEL s)    { return FixOn() ? NO  : CallBool(OrigIosguardEnable, r, s); }
static BOOL H_HasIosguardEnable(id r, SEL s) { return FixOn() ? NO  : CallBool(OrigHasIosguardEnable, r, s); }
static BOOL H_HeartbeatNonFatal(id r, SEL s) { return FixOn() ? YES : CallBool(OrigHeartbeatNonFatal, r, s); }
static BOOL H_HasHeartbeatNonFatal(id r, SEL s) { return FixOn() ? YES : CallBool(OrigHasHeartbeatNonFatal, r, s); }
static BOOL H_ReqIosguardAfter(id r, SEL s)  { return FixOn() ? NO  : CallBool(OrigReqIosguardAfter, r, s); }
static BOOL H_HasReqIosguardAfter(id r, SEL s) { return FixOn() ? NO : CallBool(OrigHasReqIosguardAfter, r, s); }
static BOOL H_RequiresAtt(id r, SEL s)       { return FixOn() ? NO  : CallBool(OrigRequiresAtt, r, s); }
static BOOL H_HasRequiresAtt(id r, SEL s)    { return FixOn() ? NO  : CallBool(OrigHasRequiresAtt, r, s); }
static BOOL H_StopHeartbeat(id r, SEL s)     { return FixOn() ? NO  : CallBool(OrigStopHeartbeat, r, s); }
static BOOL H_HasStopHeartbeat(id r, SEL s)  { return FixOn() ? NO  : CallBool(OrigHasStopHeartbeat, r, s); }
static BOOL H_AuthMismatch(id r, SEL s)      { return FixOn() ? NO  : CallBool(OrigAuthMismatch, r, s); }
static BOOL H_HasAuthMismatch(id r, SEL s)   { return FixOn() ? NO  : CallBool(OrigHasAuthMismatch, r, s); }
static BOOL H_HasPlayabilityStatus(id r, SEL s) { return FixOn() ? NO : CallBool(OrigHasPlayabilityStatus, r, s); }
static id   H_PlayabilityStatus(id r, SEL s) {
    if (FixOn()) { gcPlayability++; FPFlushCounters(NO); return nil; }
    return CallObj(OrigPlayabilityStatus, r, s);
}

static void H_HaltIfNeeded(id r, SEL s) {
    if (FixOn()) { gcHeartbeat++; FPFlushCounters(NO); return; }
    if (OrigHaltIfNeeded) ((void (*)(id, SEL))OrigHaltIfNeeded)(r, s);
}
static void H_TransitionIfNeeded(id r, SEL s) {
    if (FixOn()) return;
    if (OrigTransitionIfNeeded) ((void (*)(id, SEL))OrigTransitionIfNeeded)(r, s);
}
static void H_HandleHBResp(id r, SEL s, id resp, id req) {
    if (FixOn()) return;
    if (OrigHandleHBResp) ((void (*)(id, SEL, id, id))OrigHandleHBResp)(r, s, resp, req);
}
static void H_HaltPlaybackWithError(id r, SEL s, id err, id ctl) {
    if (FixOn()) { gcHeartbeat++; NoteFailure(@"haltPlaybackWithError"); return; }
    if (OrigHaltPlaybackWithError) ((void (*)(id, SEL, id, id))OrigHaltPlaybackWithError)(r, s, err, ctl);
}

static BOOL H_SkipOnPlayabilityError(id r, SEL s) { return FixOn() ? YES : CallBool(OrigSkipOnPlayabilityError, r, s); }
static BOOL H_HasSkipOnPlayabilityError(id r, SEL s) { return FixOn() ? YES : CallBool(OrigHasSkipOnPlayabilityError, r, s); }

static void H_CannotPlay(id r, SEL s) {
    if (FixOn()) return;
    if (OrigCannotPlay) ((void (*)(id, SEL))OrigCannotPlay)(r, s);
}
static void H_CannotPlayErr(id r, SEL s, id err) {
    if (FixOn()) return;
    if (OrigCannotPlayErr) ((void (*)(id, SEL, id))OrigCannotPlayErr)(r, s, err);
}
static void H_CannotPlayStatus(id r, SEL s, id st) {
    if (FixOn()) return;
    if (OrigCannotPlayStatus) ((void (*)(id, SEL, id))OrigCannotPlayStatus)(r, s, st);
}

static void H_ShowErrLong(id r, SEL s, id reason, id sub, id learn, BOOL a, BOOL b, BOOL c) {
    if (FixOn()) { gcErrOverlay++; NoteFailure(@"errorOverlay"); return; }
    if (OrigShowErrLong) ((void (*)(id, SEL, id, id, id, BOOL, BOOL, BOOL))OrigShowErrLong)(r, s, reason, sub, learn, a, b, c);
}
static void H_ShowErrMsg(id r, SEL s, id msg, BOOL a, BOOL b, BOOL c) {
    if (FixOn()) { gcErrOverlay++; NoteFailure(@"errorOverlayMessage"); return; }
    if (OrigShowErrMsg) ((void (*)(id, SEL, id, BOOL, BOOL, BOOL))OrigShowErrMsg)(r, s, msg, a, b, c);
}
static void H_UpdateErrState(id r, SEL s, BOOL a, BOOL b, BOOL c) {
    if (FixOn()) return;
    if (OrigUpdateErrState) ((void (*)(id, SEL, BOOL, BOOL, BOOL))OrigUpdateErrState)(r, s, a, b, c);
}

static void H_WatchReset(id r, SEL s, id vc, long st) {
    if (FixOn() && st == 7) return;
    if (OrigWatchReset) ((void (*)(id, SEL, id, long))OrigWatchReset)(r, s, vc, st);
}
static void H_WatchResetStart(id r, SEL s, BOOL a, id b, id c, id d, BOOL e) {
    if (FixOn()) return;
    if (OrigWatchResetStart) ((void (*)(id, SEL, BOOL, id, id, id, BOOL))OrigWatchResetStart)(r, s, a, b, c, d, e);
}
static void H_OverlayReset(id r, SEL s, id vc, long st) {
    if (FixOn() && st == 7) return;
    if (OrigOverlayReset) ((void (*)(id, SEL, id, long))OrigOverlayReset)(r, s, vc, st);
}
static void H_OverlayShowLoading(id r, SEL s, BOOL flag) {
    if (FixOn() && gIsRefetching) return;
    if (OrigOverlayShowLoading) ((void (*)(id, SEL, BOOL))OrigOverlayShowLoading)(r, s, flag);
}
static void H_StallReset(id r, SEL s, id vc, long st) {
    if (FixOn() && st == 7) return;
    if (OrigStallReset) ((void (*)(id, SEL, id, long))OrigStallReset)(r, s, vc, st);
}
static void H_StallStartBuf(id r, SEL s, double thresh, long reason) {
    if (FixOn()) { gcStall++; FPFlushCounters(NO); return; }
    if (OrigStallStartBuf) ((void (*)(id, SEL, double, long))OrigStallStartBuf)(r, s, thresh, reason);
}
static id H_StallInit(id r, SEL s, id player, double join, double buf) {
    if (FixOn()) { join = 15.0; buf = 15.0; }
    if (OrigStallInit) return ((id (*)(id, SEL, id, double, double))OrigStallInit)(r, s, player, join, buf);
    return r;
}
static void H_InlineReset(id r, SEL s, id vc, long st) {
    if (OrigInlineReset) ((void (*)(id, SEL, id, long))OrigInlineReset)(r, s, vc, st);
}
static void H_MainOverlayReset(id r, SEL s, id vc, long st) {
    if (FixOn() && st == 7) return;
    if (OrigMainOverlayReset) ((void (*)(id, SEL, id, long))OrigMainOverlayReset)(r, s, vc, st);
}

static id H_MLEvInit1(id r, SEL s, long st, long prev, double t) {
    if (FixOn() && st == 8) st = 3;
    if (OrigMLEvInit1) return ((id (*)(id, SEL, long, long, double))OrigMLEvInit1)(r, s, st, prev, t);
    return r;
}
static id H_MLEvInit2(id r, SEL s, long st, long prev, double t, id ann, long stop) {
    if (FixOn() && st == 8) st = 3;
    if (OrigMLEvInit2) return ((id (*)(id, SEL, long, long, double, id, long))OrigMLEvInit2)(r, s, st, prev, t, ann, stop);
    return r;
}
static id H_MLEvInit3(id r, SEL s, long st, long prev, double t, id ann, long stop, BOOL seek) {
    if (FixOn() && st == 8) st = 3;
    if (OrigMLEvInit3) return ((id (*)(id, SEL, long, long, double, id, long, BOOL))OrigMLEvInit3)(r, s, st, prev, t, ann, stop, seek);
    return r;
}

static void H_MLPlayerItemSetState(id r, SEL s, long st) {
    if (FixOn() && st == 8) { gcState8++; FPFlushCounters(NO); return; }
    if (OrigMLPlayerItemSetState) ((void (*)(id, SEL, long))OrigMLPlayerItemSetState)(r, s, st);
}
static void H_HAMPlayerSetState(id r, SEL s, long st) {
    if (FixOn() && st == 8) return;
    if (OrigHAMPlayerSetState) ((void (*)(id, SEL, long))OrigHAMPlayerSetState)(r, s, st);
}
static void H_AVPlayerSetState(id r, SEL s, long st) {
    if (FixOn() && st == 8) return;
    if (OrigAVPlayerSetState) ((void (*)(id, SEL, long))OrigAVPlayerSetState)(r, s, st);
}
static void H_AVPlayerFail(id r, SEL s, id err) {
    if (FixOn()) { NoteFailure(@"MLAVPlayer.failWithError"); return; }
    if (OrigAVPlayerFail) ((void (*)(id, SEL, id))OrigAVPlayerFail)(r, s, err);
}
static void H_AVPlayerSyncFail(id r, SEL s, id err, id fid, BOOL retry) {
    if (FixOn()) return;
    if (OrigAVPlayerSyncFail) ((void (*)(id, SEL, id, id, BOOL))OrigAVPlayerSyncFail)(r, s, err, fid, retry);
}
static void H_AVPlayerErrOccur(id r, SEL s, id err) {
    if (FixOn()) return;
    if (OrigAVPlayerErrOccur) ((void (*)(id, SEL, id))OrigAVPlayerErrOccur)(r, s, err);
}
static void H_AVAssetPlayerSetState(id r, SEL s, long st) {
    if (FixOn() && st == 8) return;
    if (OrigAVAssetPlayerSetState) ((void (*)(id, SEL, long))OrigAVAssetPlayerSetState)(r, s, st);
}
static void H_HAMQPSetState(id r, SEL s, long st) {
    if (FixOn() && st == 8) return;
    if (OrigHAMQPSetState) ((void (*)(id, SEL, long))OrigHAMQPSetState)(r, s, st);
}
static void H_HAMQPFail(id r, SEL s, id err) {
    if (FixOn()) return;
    if (OrigHAMQPFail) ((void (*)(id, SEL, id))OrigHAMQPFail)(r, s, err);
}

static void H_HAMQPPlayerItemFail(id r, SEL s, id item, NSError *err) {
    if (FixOn()) {
        NSInteger code = 0;
        @try { code = err.code; } @catch (__unused id e) {}
        FPLog(@"MLHAMQueuePlayer playerItem:didFailWithError: code=%ld", (long)code);
        if (code == 0x77 || code == 0x193) {
            NSString *reason = [NSString stringWithFormat:@"itemFail(%ld)", (long)code];
            NoteFailure(reason);
            NSTimeInterval failedAt = FPNow();
            NSUInteger recentFailures = RecordRecentItemFailure(failedAt);
            gTotalItemFails++;
            if (recentFailures >= 3) {
                if (gReloadPending) return;
                gReloadPending = YES;
                long failsAtBurst = gTotalItemFails;
                NSUInteger generation = gPlaybackGeneration;
                double positionAtBurst = gLastPlaybackPosition;
                NSTimeInterval observationAtBurst = gLastPlaybackObservationAt;
                NSUInteger progressSerialAtBurst = gPlaybackProgressSerial;
                FPLog(@"itemFail(%ld) recovery threshold (%lu in %.0fs) -- probing 3s",
                      (long)code, (unsigned long)recentFailures, kItemFailureWindow);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                             (int64_t)(3.0 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (generation != gPlaybackGeneration) return;
                    gReloadPending = NO;
                    long since = gTotalItemFails - failsAtBurst;
                    BOOL playing = (gRawMediaState == 3);
                    BOOL advanced = PlaybackAdvancedSince(positionAtBurst,
                                                          progressSerialAtBurst,
                                                          observationAtBurst,
                                                          0.75);
                    if (playing && advanced) {
                        FPLog(@"background item failures ignored: playback advanced "
                              @"%.2fs during probe (state=3)",
                              gLastPlaybackPosition - positionAtBurst);
                        ClearRecentItemFailures();
                        return;
                    }
                    if (since == 0 && playing) {
                        FPLog(@"recovered on its own (no new failures, state=3) "
                              @"-- reload skipped");
                        ClearRecentItemFailures();
                        return;
                    }
                    FPLog(@"still broken after 3s (%ld new failures, state=%ld) "
                          @"-- reloading", since, gRawMediaState);
                    ClearRecentItemFailures();
                    RequestRefetch([reason stringByAppendingString:@"-burst"]);
                });
            } else {
                FPLog(@"itemFail(%ld) swallowed (%lu in %.0fs window)",
                      (long)code, (unsigned long)recentFailures, kItemFailureWindow);
            }
            return;
        }
    }
    if (OrigHAMQPPlayerItemFail) ((void (*)(id, SEL, id, id))OrigHAMQPPlayerItemFail)(r, s, item, err);
}

static void H_HAMQPTrackFail(id r, SEL s, id track, id err) {
    if (FixOn()) return;
    if (OrigHAMQPTrackFail) ((void (*)(id, SEL, id, id))OrigHAMQPTrackFail)(r, s, track, err);
}

static BOOL H_PostponeFmt(id r, SEL s) { return FixOn() ? NO : CallBool(OrigPostponeFmt, r, s); }

static void H_SVStateChanged(id r, SEL s, long from, long to, BOOL init, long seek, long stop) {
    if (FixOn() && stop == 8) return;
    if (OrigSVStateChanged) ((void (*)(id, SEL, long, long, BOOL, long, long))OrigSVStateChanged)(r, s, from, to, init, seek, stop);
}
static void H_SVFail(id r, SEL s, id err) {
    if (FixOn()) return;
    if (OrigSVFail) ((void (*)(id, SEL, id))OrigSVFail)(r, s, err);
}

static void H_LPCRawMedia(id self, SEL sel, id sv, long from, long to, BOOL mp) {
    if (OrigLPCRawMedia) ((void (*)(id, SEL, id, long, long, BOOL))OrigLPCRawMedia)(self, sel, sv, from, to, mp);
    if (!FixOn()) return;
    gRawMediaState = to;
    FPLog(@"rawMediaState %ld -> %ld", from, to);
    if (to == 6) {
        FPLog(@"  stalled; scheduling 8s re-check");
        __weak id weakSelf = self;
        long failuresAtStall = gTotalItemFails;
        NSUInteger generation = gPlaybackGeneration;
        double positionAtStall = gLastPlaybackPosition;
        NSTimeInterval observationAtStall = gLastPlaybackObservationAt;
        NSUInteger progressSerialAtStall = gPlaybackProgressSerial;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation != gPlaybackGeneration) return;
            id strong = weakSelf;
            if (!strong) return;
            id seq = [strong valueForKey:@"videoSequencer"];
            id active = [seq valueForKey:@"activeVideoController"];
            if (!active) active = [seq valueForKey:@"contentVideoController"];
            if (!active) return;
            long rms = 0;
            SEL rmsSel = NSSelectorFromString(@"rawMediaState");
            if ([active respondsToSelector:rmsSel]) {
                rms = ((long (*)(id, SEL))objc_msgSend)(active, rmsSel);
            }
            long newFailures = gTotalItemFails - failuresAtStall;
            BOOL advanced = PlaybackAdvancedSince(positionAtStall,
                                                  progressSerialAtStall,
                                                  observationAtStall,
                                                  1.0);
            FPLog(@"stall re-check after 8s: rawMediaState=%ld newItemFails=%ld",
                  rms, newFailures);
            if (advanced) {
                FPLog(@"stall recovery skipped: playback advanced %.2fs",
                      gLastPlaybackPosition - positionAtStall);
                ClearRecentItemFailures();
                gReloadPending = NO;
            } else if (rms == 6 || newFailures >= 3) {
                NSString *reason = rms == 6 ? @"stalled8s" : @"stalled8s-itemFailures";
                NoteFailure(reason);
                ClearRecentItemFailures();
                gReloadPending = NO;
                RequestRefetch(reason);
            }
        });
    }
}

static void H_ACERegisterNotifications(id self, SEL _cmd);
static void H_ACEStartProactiveTimer(id self, SEL _cmd);

static void FinishLPCLoad(id self) {
    if (!FixOn()) return;
    gLastRefetchAt = 0.0;
    gIsRefetching = NO;
    gLastFailAt = 0.0;
    gRefetchStreak = 0;
    gBackoffUntil = 0.0;
    ClearRecentItemFailures();
    gTotalItemFails = 0;
    gReloadPending = NO;
    gPlaybackGeneration++;
    gLastPlaybackPosition = NAN;
    gLastPlaybackObservationAt = 0.0;
    gPlaybackProgressSerial = 0;
    gLoadedAt = FPNow();
    if (gSessionStart <= 0.0) gSessionStart = gLoadedAt;
    gCurrentController = self;
    H_ACERegisterNotifications(self, NULL);
    FPFlushCounters(YES);
    FPLog(@"---- loadWithPlayerTransition: new playback session ----");
}

static void H_LPCLoadTransObject(id self, SEL sel, id trans, id cfg, id initialTime) {
    if (OrigLPCLoadTrans) {
        ((void (*)(id, SEL, id, id, id))OrigLPCLoadTrans)(self, sel, trans, cfg, initialTime);
    }
    FinishLPCLoad(self);
}

static void H_LPCLoadTransDouble(id self, SEL sel, id trans, id cfg, double initialTime) {
    if (OrigLPCLoadTrans) {
        ((void (*)(id, SEL, id, id, double))OrigLPCLoadTrans)(self, sel, trans, cfg, initialTime);
    }
    FinishLPCLoad(self);
}

static void H_LPCLoadTransInteger(id self, SEL sel, id trans, id cfg, NSInteger initialTime) {
    if (OrigLPCLoadTrans) {
        ((void (*)(id, SEL, id, id, NSInteger))OrigLPCLoadTrans)(self, sel, trans, cfg, initialTime);
    }
    FinishLPCLoad(self);
}

static void InstallLPCLoadTransitionHook(void) {
    Class cls = NSClassFromString(@"YTLocalPlaybackController");
    SEL sel = NSSelectorFromString(@"loadWithPlayerTransition:playbackConfig:initialTime:");
    Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!method || method_getNumberOfArguments(method) != 5) return;

    char *argumentType = method_copyArgumentType(method, 4);
    if (!argumentType) return;
    const char *type = argumentType;
    while (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' ||
           *type == 'O' || *type == 'R' || *type == 'V') {
        type++;
    }

    IMP replacement = NULL;
    if (*type == '@' || *type == '#') {
        replacement = (IMP)H_LPCLoadTransObject;
    } else if (*type == 'd') {
        replacement = (IMP)H_LPCLoadTransDouble;
    } else if (*type == 'q' || *type == 'Q' || *type == 'l' || *type == 'L' ||
               *type == 'i' || *type == 'I' || *type == 's' || *type == 'S' ||
               *type == 'c' || *type == 'C' || *type == 'B') {
        replacement = (IMP)H_LPCLoadTransInteger;
    }
    if (replacement) {
        YTKACEInstallInstanceHook(@"YTLocalPlaybackController",
                                  @"loadWithPlayerTransition:playbackConfig:initialTime:",
                                  replacement,
                                  &OrigLPCLoadTrans);
    }
    free(argumentType);
}

static void H_LPCInitPlayback(id self, SEL sel) {
    if (OrigLPCInitPlayback) ((void (*)(id, SEL))OrigLPCInitPlayback)(self, sel);
    if (!FixOn()) return;
    if (gSessionStart <= 0.0) gSessionStart = FPNow();
    gLoadedAt = FPNow();
    gCurrentController = self;
    H_ACERegisterNotifications(self, NULL);
    FPLog(@"initializePlayback");
}

static void H_ACERegisterNotifications(id self, SEL _cmd) {
    (void)_cmd;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:kNeedsRefetch object:nil];
    [nc removeObserver:self name:kScrubBegan  object:nil];
    [nc removeObserver:self name:@"YTKACEPlaybackTimeDidChange" object:nil];
    [nc addObserver:self selector:NSSelectorFromString(@"ace_handleRefetch:")
               name:kNeedsRefetch object:nil];
    [nc addObserver:self selector:NSSelectorFromString(@"ace_handleScrubBegan:")
               name:kScrubBegan  object:nil];
    [nc addObserver:self selector:NSSelectorFromString(@"ace_handlePlaybackTime:")
               name:@"YTKACEPlaybackTimeDidChange" object:nil];
}

static void H_ACEHandlePlaybackTime(id self, SEL _cmd, NSNotification *note) {
    (void)self;
    (void)_cmd;
    double position = [note.userInfo[@"time"] doubleValue];
    if (!isfinite(position) || position < 0.0) return;
    gLastPlaybackPosition = position;
    gLastPlaybackObservationAt = FPNow();
    gPlaybackProgressSerial++;
}

static void H_ACEStartProactiveTimer(id self, SEL _cmd) {
    (void)self;
    (void)_cmd;
}

static UIView *YTKACESearchPlayerSurface(UIView *view, NSUInteger depth) {
    if (view == nil || depth > 12) return nil;
    NSString *name = NSStringFromClass(view.class);
    BOOL candidate = [name containsString:@"PlayerRenderingView"] ||
        [name isEqualToString:@"YTPlayerView"] ||
        [name containsString:@"MLVideoView"] ||
        [name containsString:@"YTPlayerOverlayView"];
    if (candidate && CGRectGetWidth(view.bounds) > 40.0 &&
        CGRectGetHeight(view.bounds) > 40.0) {
        return view;
    }
    for (UIView *subview in view.subviews) {
        UIView *found = YTKACESearchPlayerSurface(subview, depth + 1);
        if (found != nil) return found;
    }
    return nil;
}

static UIView *YTKACEFindPlayerSurface(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isHidden || window.alpha < 0.05) continue;
            UIView *found = YTKACESearchPlayerSurface(window, 0);
            if (found != nil) return found;
        }
    }
    return nil;
}

static void H_ACEHandleRefetch(id self, SEL _cmd, NSNotification *note) {
    (void)_cmd; (void)note;
    if (self != gCurrentController) { FPLog(@"refetch skipped: not current controller"); return; }
    if (gIsRefetching) { FPLog(@"refetch skipped: already in flight"); return; }
    NSTimeInterval now = FPNow();
    if (gLastRefetchAt > 0.0 && now - gLastRefetchAt < 20.0) {
        FPLog(@"refetch skipped: rate limited (%.1fs of 20s)", now - gLastRefetchAt);
        return;
    }

    id seq = [self valueForKey:@"videoSequencer"];
    id active = [seq valueForKey:@"activeVideoController"];
    if (!active) active = [seq valueForKey:@"contentVideoController"];
    if (!active) { FPLog(@"refetch aborted: no active video controller"); return; }

    gIsRefetching = YES;
    gLastRefetchAt = now;
    FPLog(@"REFETCH START -- player reload begins (expect A/V hitch here)");

    __weak id weakSelf = self;
    __weak id weakActive = active;

    dispatch_async(dispatch_get_main_queue(), ^{
        id strong = weakSelf;
        id activeStrong = weakActive;
        if (!strong || !activeStrong) { gIsRefetching = NO; return; }

        UIView *source = nil;
        SEL prvSel = NSSelectorFromString(@"playerRenderingView");
        if ([activeStrong respondsToSelector:prvSel]) {
            source = ((id (*)(id, SEL))objc_msgSend)(activeStrong, prvSel);
        }
        if (source == nil || source.superview == nil) {
            source = YTKACEFindPlayerSurface();
        }
        UIView *snapshot = nil;
        if (source != nil && source.superview != nil &&
            CGRectGetWidth(source.bounds) > 40.0 &&
            CGRectGetHeight(source.bounds) > 40.0) {
            snapshot = [source snapshotViewAfterScreenUpdates:NO];
            if (snapshot != nil) {
                snapshot.frame = source.frame;
                [source.superview addSubview:snapshot];
                [source.superview bringSubviewToFront:snapshot];
            }
        }
        FPLog(@"reload mask: source=%@ snapshot=%d",
              source == nil ? @"none" : NSStringFromClass(source.class),
              snapshot != nil);

        Class RCtx = NSClassFromString(@"MLPlayerReloadContext");
        id ctx = nil;
        if (RCtx) {
            ctx = [RCtx alloc];
            SEL initSel = NSSelectorFromString(@"initWithStartPlayback:refreshStreamingData:");
            if ([ctx respondsToSelector:initSel]) {
                ctx = ((id (*)(id, SEL, BOOL, BOOL))objc_msgSend)(ctx, initSel, YES, YES);
            }
        }

        SEL reqReloadSel = NSSelectorFromString(@"singleVideoController:requiresReloadWithContext:");
        SEL reloadPlayerSel = NSSelectorFromString(@"reloadPlayerWithContext:");
        SEL fetchSel = NSSelectorFromString(@"fetchPlayerDataAndResolveVideo");
        if ([strong respondsToSelector:reqReloadSel]) {
            FPLog(@"reload path: singleVideoController:requiresReloadWithContext: (snapshot=%d)", snapshot != nil);
            ((void (*)(id, SEL, id, id))objc_msgSend)(strong, reqReloadSel, activeStrong, ctx);
        } else if ([activeStrong respondsToSelector:reloadPlayerSel]) {
            FPLog(@"reload path: reloadPlayerWithContext: (snapshot=%d)", snapshot != nil);
            ((void (*)(id, SEL, id))objc_msgSend)(activeStrong, reloadPlayerSel, ctx);
        } else if ([strong respondsToSelector:fetchSel]) {
            FPLog(@"reload path: fetchPlayerDataAndResolveVideo (snapshot=%d)", snapshot != nil);
            ((void (*)(id, SEL))objc_msgSend)(strong, fetchSel);
        } else {
            FPLog(@"reload path: NONE AVAILABLE");
        }

        if (snapshot) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.2 animations:^{
                    snapshot.alpha = 0.0;
                } completion:^(BOOL finished) {
                    (void)finished;
                    [snapshot removeFromSuperview];
                }];
            });
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            gIsRefetching = NO;
            id s = weakSelf;
            if (s) {
                SEL playSel = NSSelectorFromString(@"play");
                if ([s respondsToSelector:playSel]) {
                    ((void (*)(id, SEL))objc_msgSend)(s, playSel);
                }
            }
        });
    });
}

static void H_ACEHandleScrubBegan(id self, SEL _cmd, NSNotification *note) {
    (void)_cmd; (void)note;
    if (self != gCurrentController) return;
    FPLog(@"scrub began -> pause");
    SEL pauseSel = NSSelectorFromString(@"pauseWithStoppageReason:");
    if ([self respondsToSelector:pauseSel]) {
        ((void (*)(id, SEL, long))objc_msgSend)(self, pauseSel, 0);
    }
}

static BOOL H_IsWebMEnabled(id r, SEL s) { return FixOn() ? NO : CallBool(OrigIsWebMEnabled, r, s); }

static id H_ABRInit(id r, SEL s,
                    id ctx, id cfg, id cache, id ns, id ra, id rp,
                    id pd, id dd, BOOL postpone, id itag) {
    if (FixOn()) postpone = NO;
    if (OrigABRInit) {
        return ((id (*)(id, SEL, id, id, id, id, id, id, id, id, BOOL, id))OrigABRInit)(
            r, s, ctx, cfg, cache, ns, ra, rp, pd, dd, postpone, itag);
    }
    return r;
}
static BOOL H_ABRPostpone(id r, SEL s) { return FixOn() ? NO : CallBool(OrigABRPostpone, r, s); }
static BOOL H_ABRStallLikely(id r, SEL s) {
    if (OrigABRStallLikely) ((void (*)(id, SEL))OrigABRStallLikely)(r, s);
    return FixOn() ? NO : NO;
}

static void H_SkipVideoErr(id r, SEL s, id err) {
    if (FixOn()) return;
    if (OrigSkipVideoErr) ((void (*)(id, SEL, id))OrigSkipVideoErr)(r, s, err);
}
static void H_SkipVideo(id r, SEL s) {
    if (FixOn()) return;
    if (OrigSkipVideo) ((void (*)(id, SEL))OrigSkipVideo)(r, s);
}
static void H_HandlePlaybackErr(id r, SEL s, id err) {
    if (FixOn()) return;
    if (OrigHandlePlaybackErr) ((void (*)(id, SEL, id))OrigHandlePlaybackErr)(r, s, err);
}

static BOOL H_IsPlayable(id r, SEL s)              { return FixOn() ? YES : CallBool(OrigIsPlayable, r, s); }
static BOOL H_IsPlayableNowOrAfter(id r, SEL s)    { return FixOn() ? YES : CallBool(OrigIsPlayableNowOrAfter, r, s); }
static long H_Status(id r, SEL s)                  { return FixOn() ? 1   : CallLong(OrigStatus, r, s); }
static id   H_StatusString(id r, SEL s)            { return FixOn() ? @"OK" : CallObj(OrigStatusString, r, s); }
static long H_ErrorCode(id r, SEL s)               { return FixOn() ? 0   : CallLong(OrigErrorCode, r, s); }
static BOOL H_HasErrorCode(id r, SEL s)            { return FixOn() ? NO  : CallBool(OrigHasErrorCode, r, s); }
static BOOL H_HasErrorScreen(id r, SEL s)          { return FixOn() ? NO  : CallBool(OrigHasErrorScreen, r, s); }
static id   H_ErrorScreen(id r, SEL s)             { return FixOn() ? nil : CallObj(OrigErrorScreen, r, s); }

static BOOL ForceStale(void) {
    gcExpiry++;
    FPFlushCounters(NO);
    return FixOn() && InRecoveryWindow();
}

static BOOL H_IsExpiredByMaxAge(id r, SEL s)    { return ForceStale() ? YES : CallBool(OrigIsExpiredByMaxAge, r, s); }
static BOOL H_StreamsCloseExpiring(id r, SEL s) { return ForceStale() ? YES : CallBool(OrigStreamsCloseExpiring, r, s); }
static long H_TimeUntilExpiry(id r, SEL s)      { return ForceStale() ? 0   : CallLong(OrigTimeUntilExpiry, r, s); }
static BOOL H_IsReuse(id r, SEL s)              { return ForceStale() ? NO  : CallBool(OrigIsReuse, r, s); }

static double H_MLTimeToExpiry(id r, SEL s) {
    double v = CallDouble(OrigMLTimeToExpiry, r, s);
    if (FixOn() && v < 3600.0) v = 3600.0;
    return v;
}
static long H_YTIExpiresIn(id r, SEL s) {
    long v = CallLong(OrigYTIExpiresIn, r, s);
    if (FixOn() && v < 0xe10) v = 0xe10;
    return v;
}

static BOOL H_CacheKeyRelax(id r, SEL s)           { return FixOn() ? YES : CallBool(OrigCacheKeyRelax, r, s); }
static BOOL H_StreamingWatchEnabled(id r, SEL s)   { return FixOn() ? YES : CallBool(OrigStreamingWatchEnabled, r, s); }
static id   H_PlayerRespCacheToken(id r, SEL s)    { return FixOn() ? nil : CallObj(OrigPlayerRespCacheToken, r, s); }

void YTKACEInstallFixPlaybackHooks(void) {
    if (!FixOn()) return;

    InstallBool(@"YTIIosPlayerAttestationConfig", @"iosguardEnable",     (IMP)H_IosguardEnable,    &OrigIosguardEnable);
    InstallBool(@"YTIIosPlayerAttestationConfig", @"hasIosguardEnable",  (IMP)H_HasIosguardEnable, &OrigHasIosguardEnable);

    InstallBool(@"YTIIosPlayerConfig", @"heartbeatPolicyErrorIsNonFatal",         (IMP)H_HeartbeatNonFatal,    &OrigHeartbeatNonFatal);
    InstallBool(@"YTIIosPlayerConfig", @"hasHeartbeatPolicyErrorIsNonFatal",      (IMP)H_HasHeartbeatNonFatal, &OrigHasHeartbeatNonFatal);
    InstallBool(@"YTIIosPlayerConfig", @"requestIosguardDataAfterPlaybackStarts", (IMP)H_ReqIosguardAfter,     &OrigReqIosguardAfter);
    InstallBool(@"YTIIosPlayerConfig", @"hasRequestIosguardDataAfterPlaybackStarts",(IMP)H_HasReqIosguardAfter,&OrigHasReqIosguardAfter);

    InstallBool(@"YTIHeartbeatAttestationConfig", @"requiresAttestation",    (IMP)H_RequiresAtt,    &OrigRequiresAtt);
    InstallBool(@"YTIHeartbeatAttestationConfig", @"hasRequiresAttestation", (IMP)H_HasRequiresAtt, &OrigHasRequiresAtt);

    InstallBool(@"YTIHeartbeatResponse", @"stopHeartbeat",          (IMP)H_StopHeartbeat,    &OrigStopHeartbeat);
    InstallBool(@"YTIHeartbeatResponse", @"hasStopHeartbeat",       (IMP)H_HasStopHeartbeat, &OrigHasStopHeartbeat);
    InstallBool(@"YTIHeartbeatResponse", @"authenticationMismatch", (IMP)H_AuthMismatch,     &OrigAuthMismatch);
    InstallBool(@"YTIHeartbeatResponse", @"hasAuthenticationMismatch",(IMP)H_HasAuthMismatch,&OrigHasAuthMismatch);
    InstallBool(@"YTIHeartbeatResponse", @"hasPlayabilityStatus",   (IMP)H_HasPlayabilityStatus, &OrigHasPlayabilityStatus);
    InstallObj (@"YTIHeartbeatResponse", @"playabilityStatus",      (IMP)H_PlayabilityStatus,    &OrigPlayabilityStatus);

    YTKACEInstallInstanceHook(@"YTSingleVideoHeartbeatController", @"haltIfNeeded",              (IMP)H_HaltIfNeeded,       &OrigHaltIfNeeded);
    YTKACEInstallInstanceHook(@"YTSingleVideoHeartbeatController", @"transitionIfNeeded",        (IMP)H_TransitionIfNeeded, &OrigTransitionIfNeeded);
    YTKACEInstallInstanceHook(@"YTSingleVideoHeartbeatController", @"handleResponse:forRequest:",(IMP)H_HandleHBResp,       &OrigHandleHBResp);
    YTKACEInstallInstanceHook(@"YTPlaybackHeartbeatController",
                              @"haltPlaybackWithError:forHeartbeatController:",
                              (IMP)H_HaltPlaybackWithError, &OrigHaltPlaybackWithError);

    InstallBool(@"YTIPlayabilityErrorSkipConfig", @"skipOnPlayabilityError",    (IMP)H_SkipOnPlayabilityError,    &OrigSkipOnPlayabilityError);
    InstallBool(@"YTIPlayabilityErrorSkipConfig", @"hasSkipOnPlayabilityError", (IMP)H_HasSkipOnPlayabilityError, &OrigHasSkipOnPlayabilityError);

    YTKACEInstallInstanceHook(@"MDXPlaybackController", @"playerCannotPlayThisVideo",                       (IMP)H_CannotPlay,       &OrigCannotPlay);
    YTKACEInstallInstanceHook(@"MDXPlaybackController", @"playerCannotPlayThisVideoWithError:",             (IMP)H_CannotPlayErr,    &OrigCannotPlayErr);
    YTKACEInstallInstanceHook(@"MDXPlaybackController", @"playerCannotPlayThisVideoWithPlayabilityStatus:", (IMP)H_CannotPlayStatus, &OrigCannotPlayStatus);

    YTKACEInstallInstanceHook(@"YTErrorPlayerOverlayView",
        @"showErrorWithReason:subreason:learnMore:allowTapToRetry:showTapToRetryMessage:showErrorBackground:",
        (IMP)H_ShowErrLong, &OrigShowErrLong);
    YTKACEInstallInstanceHook(@"YTErrorPlayerOverlayView",
        @"showErrorWithMessage:allowTapToRetry:showTapToRetryMessage:showErrorBackground:",
        (IMP)H_ShowErrMsg, &OrigShowErrMsg);
    YTKACEInstallInstanceHook(@"YTErrorPlayerOverlayView",
        @"updateStateForNewErrorWithAllowTapToRetry:showTapToRetryMessage:showErrorBackground:",
        (IMP)H_UpdateErrState, &OrigUpdateErrState);

    YTKACEInstallInstanceHook(@"YTWatchPlaybackController", @"playerViewController:willResetToState:", (IMP)H_WatchReset, &OrigWatchReset);
    YTKACEInstallInstanceHook(@"YTWatchPlaybackController",
        @"resetPlayerViewControllerStartPlayback:latencyLogger:playerThumbnailView:slimVideoTitle:disableReportingWatchTimeAsFinal:",
        (IMP)H_WatchResetStart, &OrigWatchResetStart);
    YTKACEInstallInstanceHook(@"YTPlayerOverlayManager", @"playerViewController:willResetToState:", (IMP)H_OverlayReset, &OrigOverlayReset);
    YTKACEInstallInstanceHook(@"YTPlayerOverlayManager", @"resetContentOverlayAndShowLoading:",     (IMP)H_OverlayShowLoading, &OrigOverlayShowLoading);
    YTKACEInstallInstanceHook(@"YTPlayerStallController", @"playerViewController:willResetToState:", (IMP)H_StallReset,   &OrigStallReset);
    YTKACEInstallInstanceHook(@"YTPlayerStallController", @"startBufferingTimerWithThreshold:stallReason:", (IMP)H_StallStartBuf, &OrigStallStartBuf);
    YTKACEInstallInstanceHook(@"YTPlayerStallController", @"initWithPlayer:joinStallThreshold:bufferingStallThreshold:", (IMP)H_StallInit, &OrigStallInit);
    YTKACEInstallInstanceHook(@"YTInlinePlayerViewController", @"playerViewController:willResetToState:", (IMP)H_InlineReset, &OrigInlineReset);
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayViewController", @"playerViewController:willResetToState:", (IMP)H_MainOverlayReset, &OrigMainOverlayReset);

    YTKACEInstallInstanceHook(@"MLPlayerStateChangeEvent", @"initWithState:previousState:absoluteTime:", (IMP)H_MLEvInit1, &OrigMLEvInit1);
    YTKACEInstallInstanceHook(@"MLPlayerStateChangeEvent",
        @"initWithState:previousState:absoluteTime:seekAnnotations:stoppageReason:", (IMP)H_MLEvInit2, &OrigMLEvInit2);
    YTKACEInstallInstanceHook(@"MLPlayerStateChangeEvent",
        @"initWithState:previousState:absoluteTime:seekAnnotations:stoppageReason:playerInitiatedSeek:", (IMP)H_MLEvInit3, &OrigMLEvInit3);

    YTKACEInstallInstanceHook(@"MLPlayerItem",       @"setState:", (IMP)H_MLPlayerItemSetState, &OrigMLPlayerItemSetState);
    YTKACEInstallInstanceHook(@"MLHAMPlayer",        @"setState:", (IMP)H_HAMPlayerSetState,    &OrigHAMPlayerSetState);
    YTKACEInstallInstanceHook(@"MLAVPlayer",         @"setState:", (IMP)H_AVPlayerSetState,     &OrigAVPlayerSetState);
    YTKACEInstallInstanceHook(@"MLAVPlayer",         @"failWithError:", (IMP)H_AVPlayerFail,    &OrigAVPlayerFail);
    YTKACEInstallInstanceHook(@"MLAVPlayer",         @"syncFailWithError:failureID:forceAttemptRetry:", (IMP)H_AVPlayerSyncFail, &OrigAVPlayerSyncFail);
    YTKACEInstallInstanceHook(@"MLAVPlayer",         @"playerViewErrorDidOccur:", (IMP)H_AVPlayerErrOccur, &OrigAVPlayerErrOccur);
    YTKACEInstallInstanceHook(@"MLAVAssetPlayer",    @"setState:", (IMP)H_AVAssetPlayerSetState,&OrigAVAssetPlayerSetState);
    YTKACEInstallInstanceHook(@"MLHAMQueuePlayer",   @"setState:", (IMP)H_HAMQPSetState,        &OrigHAMQPSetState);
    YTKACEInstallInstanceHook(@"MLHAMQueuePlayer",   @"failWithError:", (IMP)H_HAMQPFail,       &OrigHAMQPFail);
    YTKACEInstallInstanceHook(@"MLHAMQueuePlayer",   @"playerItem:didFailWithError:", (IMP)H_HAMQPPlayerItemFail, &OrigHAMQPPlayerItemFail);
    YTKACEInstallInstanceHook(@"MLHAMQueuePlayer",   @"trackRenderer:didFailWithError:", (IMP)H_HAMQPTrackFail,   &OrigHAMQPTrackFail);
    InstallBool(@"MLHAMQueuePlayer", @"_postponePreferredFormatFiltering", (IMP)H_PostponeFmt, &OrigPostponeFmt);

    YTKACEInstallInstanceHook(@"YTSingleVideoController",
        @"stateDidChangeFromState:toState:playerInitiated:lastSeekSource:stoppageReason:", (IMP)H_SVStateChanged, &OrigSVStateChanged);
    YTKACEInstallInstanceHook(@"YTSingleVideoController", @"failWithError:", (IMP)H_SVFail, &OrigSVFail);

    YTKACEInstallInstanceHook(@"YTLocalPlaybackController",
        @"singleVideo:rawMediaStateDidChangeFromState:toState:mediaPlayerInitiatedSeek:",
        (IMP)H_LPCRawMedia, &OrigLPCRawMedia);
    InstallLPCLoadTransitionHook();
    YTKACEInstallInstanceHook(@"YTLocalPlaybackController", @"initializePlayback",
        (IMP)H_LPCInitPlayback, &OrigLPCInitPlayback);

    YTKACEAddInstanceMethod(@"YTLocalPlaybackController", @"ace_registerNotifications", (IMP)H_ACERegisterNotifications, "v@:");
    YTKACEAddInstanceMethod(@"YTLocalPlaybackController", @"ace_startProactiveTimer",   (IMP)H_ACEStartProactiveTimer,   "v@:");
    YTKACEAddInstanceMethod(@"YTLocalPlaybackController", @"ace_handleRefetch:",        (IMP)H_ACEHandleRefetch,         "v@:@");
    YTKACEAddInstanceMethod(@"YTLocalPlaybackController", @"ace_handleScrubBegan:",     (IMP)H_ACEHandleScrubBegan,      "v@:@");
    YTKACEAddInstanceMethod(@"YTLocalPlaybackController", @"ace_handlePlaybackTime:",  (IMP)H_ACEHandlePlaybackTime,   "v@:@");

    InstallBool(@"YTUserDefaults", @"isWebMEnabled", (IMP)H_IsWebMEnabled, &OrigIsWebMEnabled);
    YTKACEInstallInstanceHook(@"HAMDefaultABRPolicy",
        @"initWithContext:config:cache:networkStatsProvider:readaheadPolicy:loadRetryPolicy:policyDelegate:defaultDelegate:postponePreferredFormatFiltering:itagAllowList:",
        (IMP)H_ABRInit, &OrigABRInit);
    InstallBool(@"HAMDefaultABRPolicy", @"postponePreferredFormatFiltering", (IMP)H_ABRPostpone,    &OrigABRPostpone);
    InstallBool(@"HAMDefaultABRPolicy", @"stallLikely",                      (IMP)H_ABRStallLikely, &OrigABRStallLikely);

    YTKACEInstallInstanceHook(@"YTPlaybackErrorController", @"skipVideoWithError:",   (IMP)H_SkipVideoErr,       &OrigSkipVideoErr);
    YTKACEInstallInstanceHook(@"YTPlaybackErrorController", @"skipVideo",             (IMP)H_SkipVideo,          &OrigSkipVideo);
    YTKACEInstallInstanceHook(@"YTPlaybackErrorController", @"handlePlaybackError:",  (IMP)H_HandlePlaybackErr,  &OrigHandlePlaybackErr);

    InstallBool(@"YTIPlayabilityStatus", @"isPlayable",                    (IMP)H_IsPlayable,              &OrigIsPlayable);
    InstallBool(@"YTIPlayabilityStatus", @"isPlayableNowOrAfterUserAction",(IMP)H_IsPlayableNowOrAfter,    &OrigIsPlayableNowOrAfter);
    InstallLong(@"YTIPlayabilityStatus", @"status",                        (IMP)H_Status,                  &OrigStatus);
    InstallObj (@"YTIPlayabilityStatus", @"statusString",                  (IMP)H_StatusString,            &OrigStatusString);
    InstallLong(@"YTIPlayabilityStatus", @"errorCode",                     (IMP)H_ErrorCode,               &OrigErrorCode);
    InstallBool(@"YTIPlayabilityStatus", @"hasErrorCode",                  (IMP)H_HasErrorCode,            &OrigHasErrorCode);
    InstallBool(@"YTIPlayabilityStatus", @"hasErrorScreen",                (IMP)H_HasErrorScreen,          &OrigHasErrorScreen);
    InstallObj (@"YTIPlayabilityStatus", @"errorScreen",                   (IMP)H_ErrorScreen,             &OrigErrorScreen);

    InstallBool(@"YTPlayerResponse", @"isExpiredByMaxAgeSeconds",              (IMP)H_IsExpiredByMaxAge,     &OrigIsExpiredByMaxAge);
    InstallBool(@"YTPlayerResponse", @"areStreamsCloseToExpiringIfPlaybackStartsNow", (IMP)H_StreamsCloseExpiring, &OrigStreamsCloseExpiring);
    InstallLong(@"YTPlayerResponse", @"timeUntilStreamingDataExpirySeconds",   (IMP)H_TimeUntilExpiry,       &OrigTimeUntilExpiry);
    InstallBool(@"YTPlayerResponse", @"isReuse",                               (IMP)H_IsReuse,               &OrigIsReuse);
    InstallDouble(@"MLStreamingData", @"timeToExpiry",       (IMP)H_MLTimeToExpiry, &OrigMLTimeToExpiry);
    InstallLong  (@"YTIStreamingData", @"expiresInSeconds",  (IMP)H_YTIExpiresIn,   &OrigYTIExpiresIn);

    InstallBool(@"YTPlaybackRequest", @"enablePlayerResponseCacheKeyRelaxation", (IMP)H_CacheKeyRelax,          &OrigCacheKeyRelax);
    InstallBool(@"YTPlaybackRequest", @"streamingWatchEnabled",                  (IMP)H_StreamingWatchEnabled,  &OrigStreamingWatchEnabled);
    InstallObj (@"YTPlaybackRequest", @"playerResponseCacheToken",               (IMP)H_PlayerRespCacheToken,   &OrigPlayerRespCacheToken);

    gSessionStart = FPNow();
    FPLog(@"installed: hooks=%lu", (unsigned long)YTKACEInstalledHookCount());

}

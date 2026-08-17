#import "../../YTKACE.h"
#import "../../Runtime/Localization.h"
#import "../../Runtime/Preferences.h"
#import "../../UI/Assets.h"
#import "../../UI/Notice.h"
#import "../../UI/OverlayButtonHost.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <math.h>
#import <objc/message.h>

@interface YTKACEPiPCoordinator : NSObject <AVPictureInPictureControllerDelegate>
+ (instancetype)sharedCoordinator;
@property(nonatomic, weak) UIView *overlay;
@property(nonatomic, strong) AVPictureInPictureController *controller;
- (void)togglePiP;
@end

@implementation YTKACEPiPCoordinator

+ (instancetype)sharedCoordinator {
    static YTKACEPiPCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [YTKACEPiPCoordinator new];
    });
    return coordinator;
}

- (AVPlayerLayer *)playerLayerInLayer:(CALayer *)layer {
    if ([layer isKindOfClass:AVPlayerLayer.class]) {
        return (AVPlayerLayer *)layer;
    }
    for (CALayer *child in layer.sublayers) {
        AVPlayerLayer *result = [self playerLayerInLayer:child];
        if (result != nil) {
            return result;
        }
    }
    return nil;
}

- (AVPlayerLayer *)activePlayerLayer {
    UIView *root = self.overlay;
    while (root.superview != nil) {
        root = root.superview;
    }
    return [self playerLayerInLayer:root.layer];
}

- (void)showError:(NSString *)message {
    YTKACEShowNotice([NSString stringWithFormat:@"Picture in Picture\n%@", message]);
}

- (void)togglePiP {
    if (!YTKACEFeatureEnabled(YTKACEPiPKey)) {
        return;
    }
    if (self.controller.isPictureInPictureActive) {
        [self.controller stopPictureInPicture];
        return;
    }
    if (![AVPictureInPictureController isPictureInPictureSupported]) {
        [self showError:@"PiP is not supported on this device."];
        return;
    }
    AVPlayerLayer *activeLayer = [self activePlayerLayer];
    if (activeLayer != nil) {
        self.controller = [[AVPictureInPictureController alloc]
            initWithPlayerLayer:activeLayer];
        self.controller.delegate = self;
        [self.controller startPictureInPicture];
        return;
    }
    [self showError:@"No active video layer found."];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    (void)change;
    (void)context;
    if (object != self.playerItem || ![keyPath isEqualToString:@"status"]) {
        return;
    }
    if (self.playerItem.status == AVPlayerItemStatusReadyToPlay) {
        if (!self.polling) {
            self.polling = YES;
            [self startPiPWithAttempts:10];
        }
    } else if (self.playerItem.status == AVPlayerItemStatusFailed) {
        NSString *reason = self.playerItem.error.localizedDescription ?: @"Playback failed.";
        [self showError:reason];
        [self clearPlayer];
        [self resumeYouTubePlayer];
    }
}

- (void)startPiPWithAttempts:(NSInteger)attempts {
    if (self.controller.isPictureInPicturePossible) {
        self.polling = NO;
        [self hideLoading];
        self.player.volume = 1.0;
        [self.player play];
        [self.controller startPictureInPicture];
        return;
    }
    if (attempts <= 0) {
        self.polling = NO;
        [self showError:@"PiP is not available for this video."];
        [self clearPlayer];
        [self resumeYouTubePlayer];
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self startPiPWithAttempts:attempts - 1];
    });
}

- (void)pictureInPictureControllerDidStartPictureInPicture:
    (AVPictureInPictureController *)pictureInPictureController {
    (void)pictureInPictureController;
    [self hideLoading];
}

- (void)pictureInPictureController:
    (AVPictureInPictureController *)pictureInPictureController
    failedToStartPictureInPictureWithError:(NSError *)error {
    (void)pictureInPictureController;
    [self showError:error.localizedDescription ?: @"PiP failed to start."];
    [self clearPlayer];
    [self resumeYouTubePlayer];
}

- (void)pictureInPictureControllerDidStopPictureInPicture:
    (AVPictureInPictureController *)pictureInPictureController {
    (void)pictureInPictureController;
    [self hideLoading];
    [self clearPlayer];
    [self resumeYouTubePlayer];
}

@end

void YTKACEInstallPiPHooks(void) {
    YTKACERegisterOverlayConfigurator(@"pip", ^(UIView *overlay, UIStackView *stack) {
        YTKACEPiPCoordinator.sharedCoordinator.overlay = overlay;
        UIButton *button = YTKACEOverlayButton(
            stack,
            @"YTKACE PiP",
            @"pip",
            YTKACEPiPCoordinator.sharedCoordinator,
            @selector(togglePiP)
        );
        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration configurationWithPointSize:21.0
                                                            weight:UIImageSymbolWeightMedium];
        [button setImage:[[YTKACEAssetImage(@"picture_in_picture_24pt_3x_Normal", @"pip")
            imageByApplyingSymbolConfiguration:configuration]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                  forState:UIControlStateNormal];
        button.hidden = !YTKACEFeatureEnabled(YTKACEPiPKey);
    });
}

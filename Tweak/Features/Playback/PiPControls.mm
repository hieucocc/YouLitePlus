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

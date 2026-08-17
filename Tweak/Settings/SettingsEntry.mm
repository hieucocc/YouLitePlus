#import "../YTKACE.h"
#import "../Runtime/Hooking.h"
#import "../Features/Interface/NavigationVisibility.h"
#import "../UI/Assets.h"
#import "YTKACERootOptionsController.h"

#import <objc/runtime.h>

static IMP OriginalPivotViewDidAppear;
static IMP OriginalRightButtonsLayoutSubviews;
static const void *YTKACESettingsButtonAssociation = &YTKACESettingsButtonAssociation;

static UIViewController *YTKACETopViewController(UIViewController *controller) {
    if (controller.presentedViewController != nil) {
        return YTKACETopViewController(controller.presentedViewController);
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        return YTKACETopViewController(((UINavigationController *)controller).visibleViewController);
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        return YTKACETopViewController(((UITabBarController *)controller).selectedViewController);
    }
    return controller;
}

@interface YTKACESettingsPresenter : NSObject
+ (instancetype)sharedPresenter;
- (void)openSettings;
@end

@implementation YTKACESettingsPresenter

+ (instancetype)sharedPresenter {
    static YTKACESettingsPresenter *presenter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        presenter = [YTKACESettingsPresenter new];
    });
    return presenter;
}

- (void)openSettings {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (window == nil &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                window = candidate;
            }
            if (candidate.isKeyWindow) {
                window = candidate;
                break;
            }
        }
        if (window != nil) {
            break;
        }
    }
    UIViewController *presenter = YTKACETopViewController(window.rootViewController);
    if ([presenter.presentedViewController isKindOfClass:UINavigationController.class] &&
        [((UINavigationController *)presenter.presentedViewController).viewControllers.firstObject
            isKindOfClass:YTKACERootOptionsController.class]) {
        return;
    }
    [presenter presentViewController:YTKACEMakeSettingsNavigationController()
                            animated:YES
                          completion:nil];
}

@end

static UIBarButtonItem *YTKACESettingsBarButton(void) {
    UIImage *image = [YTKACEGearImage()
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    return [[UIBarButtonItem alloc] initWithImage:image
                                           style:UIBarButtonItemStylePlain
                                          target:YTKACESettingsPresenter.sharedPresenter
                                          action:@selector(openSettings)];
}

static void YTKACEPivotViewDidAppear(id receiver, SEL selector, BOOL animated) {
    if (OriginalPivotViewDidAppear != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalPivotViewDidAppear)(receiver, selector, animated);
    }

    if (![receiver isKindOfClass:UIViewController.class]) {
        return;
    }
    UIViewController *controller = receiver;
    if (objc_getAssociatedObject(controller, YTKACESettingsButtonAssociation) != nil) {
        return;
    }

    NSMutableArray<UIBarButtonItem *> *items =
        [controller.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
    [items insertObject:YTKACESettingsBarButton() atIndex:0];
    controller.navigationItem.rightBarButtonItems = items;
    objc_setAssociatedObject(controller,
                             YTKACESettingsButtonAssociation,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void YTKACERightButtonsLayoutSubviews(UIView *receiver, SEL selector) {
    if (OriginalRightButtonsLayoutSubviews != NULL) {
        ((void (*)(id, SEL))OriginalRightButtonsLayoutSubviews)(receiver, selector);
    }
    if (objc_getAssociatedObject(receiver, YTKACESettingsButtonAssociation) != nil) {
        YTKACEApplyRightNavigationVisibility(receiver);
        return;
    }

    UIStackView *stack = nil;
    for (UIView *subview in receiver.subviews) {
        if ([subview isKindOfClass:UIStackView.class]) {
            stack = (UIStackView *)subview;
            break;
        }
    }
    if (stack == nil) {
        return;
    }

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[YTKACEGearImage()
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
             forState:UIControlStateNormal];
    button.accessibilityLabel = @"YouLite+ Settings";
    [button addTarget:YTKACESettingsPresenter.sharedPresenter
               action:@selector(openSettings)
     forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintEqualToConstant:32.0].active = YES;
    [button.heightAnchor constraintEqualToConstant:32.0].active = YES;
    [stack insertArrangedSubview:button atIndex:0];

    objc_setAssociatedObject(receiver,
                             YTKACESettingsButtonAssociation,
                             button,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    YTKACEApplyRightNavigationVisibility(receiver);
}

void YTKACEInstallSettingsEntryHooks(void) {
    YTKACEInstallInstanceHook(@"YTPivotBarViewController",
                              @"viewDidAppear:",
                              (IMP)YTKACEPivotViewDidAppear,
                              &OriginalPivotViewDidAppear);
    YTKACEInstallInstanceHook(@"YTRightNavigationButtons",
                              @"layoutSubviews",
                              (IMP)YTKACERightButtonsLayoutSubviews,
                              &OriginalRightButtonsLayoutSubviews);
}

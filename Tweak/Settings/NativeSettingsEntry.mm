#import "YTKACESettingsPages.h"
#import "YTKACESettingsSearch.h"
#import "../Runtime/Localization.h"
#import "YTKACERootOptionsController.h"
#import "../Runtime/Hooking.h"
#import "../UI/Assets.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const NSUInteger YTKACENativeSettingsCategory = 789;
static const NSUInteger YTKACENativeSettingsGroup = 0x796b6163;
static NSString *const YTKACEInertIdentifier = @"YTKACEInertItem";
static const NSInteger YTKACESearchFieldTag = 0x5954534B;
static const void *YTKACEDeveloperHoldKey = &YTKACEDeveloperHoldKey;
static const void *YTKACESettingIconImageKey = &YTKACESettingIconImageKey;
static IMP OriginalSettingsCategoryOrder;
static IMP OriginalUpdateSettingsSection;
static IMP OriginalOrderedSettingsGroups;
static IMP OriginalSettingsGroupTitle;
static IMP OriginalOrderedGroupCategories;
static IMP OriginalSettingsCellLayout;

typedef UIViewController * _Nonnull (^YTKACENativeBuilder)(void);

static NSArray<NSDictionary *> *YTKACENativeLayout(void) {
    return @[
        @{@"kind": @"header", @"title": @"FEATURES"},
        @{@"kind": @"row", @"title": @"Block YouTube Ads"},
        @{@"kind": @"row", @"title": @"Background Playback & PiP"},
        @{@"kind": @"row", @"title": @"SponsorBlock & DeArrow"},
        @{@"kind": @"row", @"title": @"Premium Logo"},
        @{@"kind": @"header", @"title": @"ABOUT"},
        @{@"kind": @"row", @"title": @"hieucocc", @"developer": @YES},
        @{@"kind": @"footer"}
    ];
}

static NSArray *YTKACESettingsCategoryOrder(id receiver, SEL selector) {
    NSArray *order = OriginalSettingsCategoryOrder == NULL ? @[] :
        ((id (*)(id, SEL))OriginalSettingsCategoryOrder)(receiver, selector);
    if ([order containsObject:@(YTKACENativeSettingsCategory)]) return order;
    NSMutableArray *updated = [order mutableCopy] ?: [NSMutableArray array];
    NSUInteger index = [updated indexOfObject:@1];
    [updated insertObject:@(YTKACENativeSettingsCategory)
                  atIndex:index == NSNotFound ? updated.count : index + 1];
    return updated;
}

static NSArray *YTKACEOrderedSettingsGroups(id receiver, SEL selector) {
    NSArray *groups = OriginalOrderedSettingsGroups == NULL ? @[] :
        ((id (*)(id, SEL))OriginalOrderedSettingsGroups)(receiver, selector);
    Class groupClass = NSClassFromString(@"YTSettingsGroupData");
    SEL initializer = NSSelectorFromString(@"initWithGroupType:");
    if (groupClass == Nil || ![groupClass instancesRespondToSelector:initializer]) return groups;
    id group = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
        [groupClass alloc], initializer, YTKACENativeSettingsGroup);
    if (group == nil) return groups;
    NSMutableArray *updated = [groups mutableCopy] ?: [NSMutableArray array];
    [updated insertObject:group atIndex:0];
    return updated;
}

static NSString *YTKACESettingsGroupTitle(id receiver, SEL selector, NSUInteger type) {
    if (type == YTKACENativeSettingsGroup) return @"YouLite+";
    return OriginalSettingsGroupTitle == NULL ? nil :
        ((id (*)(id, SEL, NSUInteger))OriginalSettingsGroupTitle)(receiver, selector, type);
}

static NSArray *YTKACEOrderedGroupCategories(id receiver, SEL selector, NSUInteger type) {
    if (type == YTKACENativeSettingsGroup) return @[@(YTKACENativeSettingsCategory)];
    return OriginalOrderedGroupCategories == NULL ? @[] :
        ((id (*)(id, SEL, NSUInteger))OriginalOrderedGroupCategories)(receiver, selector, type);
}

static NSString *YTKACENativeSettingsSubtitle(NSString *title) {
    static NSDictionary<NSString *, NSString *> *subtitles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        subtitles = @{
            @"Block YouTube Ads": @"Remove all native video and banner ads",
            @"Background Playback & PiP": @"Play audio in background and enable PiP",
            @"SponsorBlock & DeArrow": @"Automatically skip sponsored segments",
            @"Premium Logo": @"Display YouTube Premium logo",
            @"hieucocc": @"Forked from YTKACE by itzzace"
        };
    });
    NSString *value = subtitles[title];
    return value != nil ? YTKACELocalized(value) : nil;
}

static UIImage *YTKACESettingIconStoredImage(id receiver) {
    return objc_getAssociatedObject(receiver, YTKACESettingIconImageKey);
}

static UIImage *YTKACETintedIcon(UIImage *image, UIColor *color) {
    if (image == nil) return nil;
    UIColor *fill = color ?: UIColor.labelColor;
    UIGraphicsImageRendererFormat *format =
        UIGraphicsImageRendererFormat.preferredFormat;
    format.opaque = NO;
    format.scale = image.scale;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:image.size format:format];
    UIImage *tinted = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        (void)ctx;
        CGRect bounds = CGRectMake(0.0, 0.0, image.size.width, image.size.height);
        [image drawInRect:bounds];
        [fill set];
        UIRectFillUsingBlendMode(bounds, kCGBlendModeSourceIn);
    }];
    return [tinted imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

static id YTKACEIconImageForStyle(id receiver, SEL selector, long long style) {
    (void)selector;
    (void)style;
    return YTKACETintedIcon(YTKACESettingIconStoredImage(receiver), nil);
}

static id YTKACEIconImageForColor(id receiver, SEL selector, UIColor *color) {
    (void)selector;
    return YTKACETintedIcon(YTKACESettingIconStoredImage(receiver), color);
}

static id YTKACEIconImageForSelected(id receiver, SEL selector, BOOL selected) {
    (void)selector;
    (void)selected;
    return YTKACETintedIcon(YTKACESettingIconStoredImage(receiver), nil);
}

static id YTKACEIconImagePlain(id receiver, SEL selector) {
    (void)selector;
    return YTKACETintedIcon(YTKACESettingIconStoredImage(receiver), nil);
}

static Class YTKACESettingIconClass(void) {
    static Class iconClass;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class superclass = NSClassFromString(@"YTIIcon");
        if (superclass == Nil) return;
        iconClass = objc_allocateClassPair(superclass, "YTKACESettingIcon", 0);
        if (iconClass == Nil) return;
        class_addMethod(iconClass, NSSelectorFromString(@"iconImageWithPageStyle:"),
                        (IMP)YTKACEIconImageForStyle, "@24@0:8q16");
        class_addMethod(iconClass, NSSelectorFromString(@"delhiIconImageWithPageStyle:"),
                        (IMP)YTKACEIconImageForStyle, "@24@0:8q16");
        class_addMethod(iconClass, NSSelectorFromString(@"iconImageWithColor:"),
                        (IMP)YTKACEIconImageForColor, "@24@0:8@16");
        class_addMethod(iconClass, NSSelectorFromString(@"newIconImageWithColor:"),
                        (IMP)YTKACEIconImageForColor, "@24@0:8@16");
        class_addMethod(iconClass, NSSelectorFromString(@"iconImageWithSelected:"),
                        (IMP)YTKACEIconImageForSelected, "@20@0:8B16");
        class_addMethod(iconClass, NSSelectorFromString(@"delhiIconImageWithSelected:"),
                        (IMP)YTKACEIconImageForSelected, "@20@0:8B16");
        class_addMethod(iconClass, NSSelectorFromString(@"iconImageForContextMenu"),
                        (IMP)YTKACEIconImagePlain, "@16@0:8");
        objc_registerClassPair(iconClass);
    });
    return iconClass;
}

static UIImage *YTKACENativeSettingsIconImage(NSString *title) {
    if ([title isEqualToString:@"SponsorBlock"]) {
        return YTKACEAssetImage(@"sponsorblock_shield_template", @"play.shield");
    }
    if ([title isEqualToString:@"Shorts"]) return YTKACEShortsImage(NO);
    if ([title isEqualToString:@"Downloads & Library"]) {
        return YTKACEDownloadTabImage(NO);
    }
    static NSDictionary<NSString *, NSString *> *symbols;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        symbols = @{
            @"Player": @"play.rectangle",
            @"Overlay": @"rectangle.on.rectangle",
            @"Playback": @"playpause",
            @"Navigation": @"rectangle.topthird.inset.filled",
            @"Tabs": @"rectangle.bottomthird.inset.filled",
            @"Gestures": @"hand.draw",
            @"Wi-Fi Quality": @"wifi",
            @"Cellular Quality": @"antenna.radiowaves.left.and.right",
            @"Other": @"ellipsis.circle",
            @"hieucocc": @"person.crop.circle"
        };
    });
    NSString *symbol = symbols[title];
    return symbol.length != 0 ? [UIImage systemImageNamed:symbol] : nil;
}

static UIImage *YTKACESquaredIcon(UIImage *image) {
    if (image == nil) return nil;
    CGFloat side = MAX(image.size.width, image.size.height);
    if (side <= 0.0) return image;
    UIGraphicsImageRendererFormat *format =
        UIGraphicsImageRendererFormat.preferredFormat;
    format.opaque = NO;
    format.scale = image.scale;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)
                                               format:format];
    UIImage *padded = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        (void)ctx;
        [image drawInRect:CGRectMake((side - image.size.width) / 2.0,
                                     (side - image.size.height) / 2.0,
                                     image.size.width, image.size.height)];
    }];
    return [padded imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static void YTKACEApplyNativeSettingsIcon(id item, NSString *title) {
    SEL setSettingIcon = NSSelectorFromString(@"setSettingIcon:");
    if (item == nil || ![item respondsToSelector:setSettingIcon]) return;
    Class iconClass = YTKACESettingIconClass();
    UIImage *image = YTKACESquaredIcon(YTKACENativeSettingsIconImage(title));
    if (iconClass == Nil || image == nil) return;
    id icon = [iconClass new];
    objc_setAssociatedObject(icon, YTKACESettingIconImageKey, image,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ((void (*)(id, SEL, id))objc_msgSend)(item, setSettingIcon, icon);
}

static id YTKACENativePlainItem(NSString *title, NSString *description) {
    Class itemClass = NSClassFromString(@"YTSettingsSectionItem");
    if (itemClass == Nil) return nil;
    SEL described = NSSelectorFromString(
        @"itemWithTitle:titleDescription:accessibilityIdentifier:detailTextBlock:"
         "selectBlock:");
    if (description != nil && [itemClass respondsToSelector:described]) {
        return ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(
            itemClass, described, title, description,
            YTKACEInertIdentifier, nil, nil);
    }
    SEL plain = NSSelectorFromString(
        @"itemWithTitle:accessibilityIdentifier:detailTextBlock:selectBlock:");
    if (![itemClass respondsToSelector:plain]) return nil;
    return ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(
        itemClass, plain, title, YTKACEInertIdentifier, nil, nil);
}

static void YTKACEMakeItemInert(id item) {
    if (item == nil) return;
    for (NSString *name in @[@"setInkEnabled:", @"setEnabled:", @"setSettingEnabled:"]) {
        SEL selector = NSSelectorFromString(name);
        if ([item respondsToSelector:selector]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(item, selector, NO);
        }
    }
}

@interface YTKACEDeveloperHoldTarget : NSObject
@property(nonatomic, weak) UIView *cell;
@end

@implementation YTKACEDeveloperHoldTarget

- (void)handleHold:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    UIResponder *responder = self.cell;
    while (responder != nil && ![responder isKindOfClass:UIViewController.class]) {
        responder = responder.nextResponder;
    }
    UINavigationController *navigation =
        ((UIViewController *)responder).navigationController;
    if (navigation == nil) return;
    [navigation pushViewController:YTKACEMakeDownloadLogController() animated:YES];
}

@end

static void YTKACESettingsCellLayout(id receiver, SEL selector) {
    if (OriginalSettingsCellLayout != NULL) {
        ((void (*)(id, SEL))OriginalSettingsCellLayout)(receiver, selector);
    }
    if (![receiver isKindOfClass:UIView.class]) return;
    UIView *cell = receiver;
    NSString *identifier = cell.accessibilityIdentifier;
    UIView *host = cell;
    if ([cell respondsToSelector:@selector(contentView)]) {
        UIView *content = ((UIView *(*)(id, SEL))objc_msgSend)(
            cell, @selector(contentView));
        if (content != nil) host = content;
    }
    UISearchBar *field = (UISearchBar *)[host viewWithTag:YTKACESearchFieldTag];
    if ([identifier isEqualToString:@"YTKACESearchItem"]) {
        if (field == nil) {
            field = [UISearchBar new];
            field.tag = YTKACESearchFieldTag;
            field.placeholder = YTKACELocalized(@"Search");
            field.searchBarStyle = UISearchBarStyleMinimal;
            field.userInteractionEnabled = NO;
            [host addSubview:field];
        }
        field.frame = CGRectInset(host.bounds, -8.0, 0.0);
        [host bringSubviewToFront:field];
        cell.userInteractionEnabled = YES;
        return;
    }
    if (field != nil) [field removeFromSuperview];
    if ([identifier isEqualToString:@"YTKACEDeveloperItem"] &&
        objc_getAssociatedObject(cell, YTKACEDeveloperHoldKey) == nil) {
        YTKACEDeveloperHoldTarget *target = [YTKACEDeveloperHoldTarget new];
        target.cell = cell;
        UILongPressGestureRecognizer *hold =
            [[UILongPressGestureRecognizer alloc] initWithTarget:target
                                                          action:@selector(handleHold:)];
        hold.minimumPressDuration = 4.0;
        [cell addGestureRecognizer:hold];
        objc_setAssociatedObject(cell, YTKACEDeveloperHoldKey, target,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    cell.userInteractionEnabled = ![identifier isEqualToString:YTKACEInertIdentifier];
}

static id YTKACENativeSearchRow(id settingsController) {
    Class itemClass = NSClassFromString(@"YTSettingsSectionItem");
    SEL plain = NSSelectorFromString(
        @"itemWithTitle:accessibilityIdentifier:detailTextBlock:selectBlock:");
    if (itemClass == Nil || ![itemClass respondsToSelector:plain]) return nil;
    __weak id weakController = settingsController;
    BOOL (^select)(id, NSUInteger) = ^BOOL(__unused id cell, __unused NSUInteger index) {
        id controller = weakController;
        if (![controller isKindOfClass:UIViewController.class]) return NO;
        YTKACEPresentSettingsSearchOverlay(controller);
        return YES;
    };
    return ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(
        itemClass, plain, @" ", @"YTKACESearchItem", nil, [select copy]);
}

static id YTKACENativeSettingsItem(NSString *title,
                                   id settingsController,
                                   YTKACENativeBuilder builder) {
    Class itemClass = NSClassFromString(@"YTSettingsSectionItem");
    SEL selector = NSSelectorFromString(
        @"itemWithTitle:accessibilityIdentifier:detailTextBlock:selectBlock:");
    if (itemClass == Nil || ![itemClass respondsToSelector:selector]) return nil;
    NSString *(^detail)(void) = builder == nil
        ? (NSString *(^)(void))nil
        : ^NSString *{ return @"›"; };
    BOOL (^select)(id, NSUInteger) = builder == nil
        ? (BOOL (^)(id, NSUInteger))nil
        : ^BOOL(__unused id cell, __unused NSUInteger index) {
            UIViewController *controller = builder();
            if (controller == nil) return NO;
            SEL push = NSSelectorFromString(@"pushViewController:");
            if ([settingsController respondsToSelector:push]) {
                ((void (*)(id, SEL, id))objc_msgSend)(settingsController, push, controller);
                return YES;
            }
            UINavigationController *navigation =
                [settingsController isKindOfClass:UIViewController.class]
                    ? ((UIViewController *)settingsController).navigationController : nil;
            [navigation pushViewController:controller animated:YES];
            return navigation != nil;
        };
    SEL described = NSSelectorFromString(
        @"itemWithTitle:titleDescription:accessibilityIdentifier:detailTextBlock:"
         "selectBlock:");
    NSString *subtitle = YTKACENativeSettingsSubtitle(title);
    NSString *localizedTitle = YTKACELocalized(title);
    id item = nil;
    if (subtitle.length != 0 && [itemClass respondsToSelector:described]) {
        item = ((id (*)(id, SEL, id, id, id, id, id))objc_msgSend)(
            itemClass, described, localizedTitle, subtitle,
            @"YTKACENativeSettingsItem", detail, select);
    } else {
        item = ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(
            itemClass, selector, localizedTitle, @"YTKACENativeSettingsItem",
            detail, select);
    }
    YTKACEApplyNativeSettingsIcon(item, title);
    return item;
}

static void YTKACEUpdateNativeSettingsSection(id receiver, SEL selector,
                                              NSUInteger category, id entry) {
    if (category != YTKACENativeSettingsCategory) {
        if (OriginalUpdateSettingsSection != NULL) {
            ((void (*)(id, SEL, NSUInteger, id))OriginalUpdateSettingsSection)(
                receiver, selector, category, entry);
        }
        return;
    }

    id settingsController = nil;
    @try {
        settingsController = [receiver valueForKey:@"_settingsViewControllerDelegate"];
    } @catch (__unused NSException *exception) {
        return;
    }
    NSDictionary<NSString *, YTKACENativeBuilder> *builders = @{
        @"hieucocc": [^UIViewController *{
            NSURL *URL = [NSURL URLWithString:@"https://github.com/hieucocc/YouLitePlus"];
            [UIApplication.sharedApplication openURL:URL options:@{}
                                   completionHandler:nil];
            return nil;
        } copy]
    };

    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *definition in YTKACENativeLayout()) {
        NSString *kind = definition[@"kind"];
        NSString *title = definition[@"title"];
        id item = nil;
        if ([kind isEqualToString:@"search"]) {
            item = YTKACENativeSearchRow(settingsController);
        } else if ([kind isEqualToString:@"header"]) {
            item = YTKACENativePlainItem(nil, YTKACELocalized(title));
            YTKACEMakeItemInert(item);
        } else if ([kind isEqualToString:@"footer"]) {
            NSString *info = [YTKACEDeviceInformationText()
                stringByReplacingOccurrencesOfString:@"\n" withString:@"  •  "];
            item = YTKACENativePlainItem(nil, info);
            YTKACEMakeItemInert(item);
        } else {
            item = YTKACENativeSettingsItem(title, settingsController, builders[title]);
            if ([definition[@"developer"] boolValue] && item != nil) {
                SEL setIdentifier = NSSelectorFromString(@"setAccessibilityIdentifier:");
                if ([item respondsToSelector:setIdentifier]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(
                        item, setIdentifier, @"YTKACEDeveloperItem");
                }
            }
        }
        if (item != nil) [items addObject:item];
    }

    SEL modern = NSSelectorFromString(
        @"setSectionItems:forCategory:title:icon:titleDescription:headerHidden:");
    SEL legacy = NSSelectorFromString(
        @"setSectionItems:forCategory:title:titleDescription:headerHidden:");
    if ([settingsController respondsToSelector:modern]) {
        id icon = [NSClassFromString(@"YTIIcon") new];
        SEL setIconType = NSSelectorFromString(@"setIconType:");
        if ([icon respondsToSelector:setIconType]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(icon, setIconType, 44);
        }
        ((void (*)(id, SEL, id, NSUInteger, id, id, id, BOOL))objc_msgSend)(
            settingsController, modern, items, category, @"YouLite+", icon, nil, NO);
    } else if ([settingsController respondsToSelector:legacy]) {
        ((void (*)(id, SEL, id, NSUInteger, id, id, BOOL))objc_msgSend)(
            settingsController, legacy, items, category, @"YouLite+", nil, NO);
    }
}

void YTKACEInstallNativeSettingsHooks(void) {
    YTKACEInstallClassHook(@"YTAppSettingsPresentationData", @"settingsCategoryOrder",
                           (IMP)YTKACESettingsCategoryOrder,
                           &OriginalSettingsCategoryOrder);
    YTKACEInstallInstanceHook(@"YTSettingsSectionItemManager",
                              @"updateSectionForCategory:withEntry:",
                              (IMP)YTKACEUpdateNativeSettingsSection,
                              &OriginalUpdateSettingsSection);
    YTKACEInstallInstanceHook(@"YTSettingsCell", @"layoutSubviews",
                              (IMP)YTKACESettingsCellLayout,
                              &OriginalSettingsCellLayout);
    YTKACEInstallClassHook(@"YTAppSettingsGroupPresentationData", @"orderedGroups",
                           (IMP)YTKACEOrderedSettingsGroups,
                           &OriginalOrderedSettingsGroups);
    YTKACEInstallInstanceHook(@"YTSettingsGroupData", @"titleForSettingGroupType:",
                              (IMP)YTKACESettingsGroupTitle,
                              &OriginalSettingsGroupTitle);
    YTKACEInstallInstanceHook(@"YTSettingsGroupData", @"orderedCategoriesForGroupType:",
                              (IMP)YTKACEOrderedGroupCategories,
                              &OriginalOrderedGroupCategories);
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        for (NSUInteger attempt = 1; attempt <= 60; attempt++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                (int64_t)(attempt * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                YTKACEInstallNativeSettingsHooks();
            });
        }
    });
}

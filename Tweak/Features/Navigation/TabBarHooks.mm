#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../../UI/Assets.h"
#import "../Interface/NavigationVisibility.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static IMP OriginalSetPivotRenderer;
static IMP OriginalPivotItemLayout;
static IMP OriginalPivotItemSetSelected;
static IMP OriginalPivotItemTraitChanged;
static IMP OriginalPivotLabelSetHidden;
static IMP OriginalPivotLabelSetAlpha;
static IMP OriginalPivotButtonLayout;
static IMP OriginalPivotBarLayout;
static IMP OriginalPivotBarStyleColors;
static IMP OriginalPivotBarSetBackgroundStyle;
static IMP OriginalAppViewDidLoad;
static IMP OriginalBrowseViewDidLoad;
static IMP OriginalBrowseResponseViewDidLoad;
static IMP OriginalWrapperViewDidLoad;
static const void *YTKACEDownloadsAssociation = &YTKACEDownloadsAssociation;
static const void *YTKACETabAssociation = &YTKACETabAssociation;
static const void *YTKACETabSelectedAssociation = &YTKACETabSelectedAssociation;
static NSString * const YTKACEPivotIdentifier = @"FEYTKACE";
static NSInteger const YTKACEExtraIconTag = 0x59414349;
static NSInteger const YTKACEExtraLabelTag = 0x5941434A;
static BOOL YTKACEStartupApplied;
static BOOL YTKACENavigationRefreshScheduled;

static id YTKACEValue(id receiver, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return receiver != nil && [receiver respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(receiver, selector)
        : nil;
}

static void YTKACESetValue(id receiver, NSString *selectorName, id value) {
    SEL selector = NSSelectorFromString(selectorName);
    if (receiver != nil && [receiver respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(receiver, selector, value);
    }
}

static id YTKACENew(NSString *className) {
    Class cls = NSClassFromString(className);
    return cls == Nil ? nil : [[cls alloc] init];
}

static id YTKACEMakePivotItem(void) {
    Class rendererClass = NSClassFromString(@"YTIPivotBarRenderer");
    SEL factory = NSSelectorFromString(@"pivotSupportedRenderersWithBrowseId:title:iconType:");
    if (rendererClass != Nil && [rendererClass respondsToSelector:factory]) {
        id renderer = ((id (*)(id, SEL, id, id, NSInteger))objc_msgSend)(
            rendererClass,
            factory,
            YTKACEPivotIdentifier,
            @"YTKACE",
            77
        );
        id item = YTKACEValue(renderer, @"pivotBarItemRenderer");
        if (item != nil) {
            YTKACESetValue(item, @"setPivotIdentifier:", YTKACEPivotIdentifier);
        }
        if (renderer != nil) {
            return renderer;
        }
    }
    id browseEndpoint = YTKACENew(@"YTIBrowseEndpoint");
    id command = YTKACENew(@"YTICommand");
    id itemRenderer = YTKACENew(@"YTIPivotBarItemRenderer");
    id supportedRenderer = YTKACENew(@"YTIPivotBarSupportedRenderers");
    Class formattedClass = NSClassFromString(@"YTIFormattedString");
    SEL formattedSelector = NSSelectorFromString(@"formattedStringWithString:");
    if (browseEndpoint == nil || command == nil || itemRenderer == nil ||
        supportedRenderer == nil || formattedClass == Nil ||
        ![formattedClass respondsToSelector:formattedSelector]) {
        return nil;
    }

    YTKACESetValue(browseEndpoint, @"setBrowseId:", YTKACEPivotIdentifier);
    YTKACESetValue(command, @"setBrowseEndpoint:", browseEndpoint);
    YTKACESetValue(itemRenderer, @"setPivotIdentifier:", YTKACEPivotIdentifier);
    YTKACESetValue(itemRenderer, @"setNavigationEndpoint:", command);
    id title = ((id (*)(id, SEL, id))objc_msgSend)(
        formattedClass,
        formattedSelector,
        @"YTKACE"
    );
    YTKACESetValue(itemRenderer, @"setTitle:", title);

    id icon = YTKACEValue(itemRenderer, @"icon");
    SEL iconSelector = NSSelectorFromString(@"setIconType:");
    if ([icon respondsToSelector:iconSelector]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(icon, iconSelector, 77);
    }
    YTKACESetValue(
        supportedRenderer,
        @"setPivotBarItemRenderer:",
        itemRenderer
    );
    return supportedRenderer;
}

static id YTKACEMakeBrowsePivotItem(NSString *browseID,
                                    NSString *title,
                                    NSInteger iconType) {
    Class rendererClass = NSClassFromString(@"YTIPivotBarRenderer");
    SEL factory = NSSelectorFromString(@"pivotSupportedRenderersWithBrowseId:title:iconType:");
    if (rendererClass != Nil && [rendererClass respondsToSelector:factory]) {
        id renderer = ((id (*)(id, SEL, id, id, NSInteger))objc_msgSend)(
            rendererClass, factory, browseID, title, iconType
        );
        id item = YTKACEValue(renderer, @"pivotBarItemRenderer");
        if (item != nil) {
            YTKACESetValue(item, @"setPivotIdentifier:", browseID);
        }
        if (renderer != nil) {
            return renderer;
        }
    }
    id browseEndpoint = YTKACENew(@"YTIBrowseEndpoint");
    id command = YTKACENew(@"YTICommand");
    id itemRenderer = YTKACENew(@"YTIPivotBarItemRenderer");
    id supportedRenderer = YTKACENew(@"YTIPivotBarSupportedRenderers");
    Class formattedClass = NSClassFromString(@"YTIFormattedString");
    SEL formattedSelector = NSSelectorFromString(@"formattedStringWithString:");
    if (browseEndpoint == nil || command == nil || itemRenderer == nil ||
        supportedRenderer == nil || formattedClass == Nil ||
        ![formattedClass respondsToSelector:formattedSelector]) {
        return nil;
    }
    YTKACESetValue(browseEndpoint, @"setBrowseId:", browseID);
    YTKACESetValue(command, @"setBrowseEndpoint:", browseEndpoint);
    YTKACESetValue(itemRenderer, @"setPivotIdentifier:", browseID);
    YTKACESetValue(itemRenderer, @"setNavigationEndpoint:", command);
    id icon = YTKACEValue(itemRenderer, @"icon");
    SEL setIconType = NSSelectorFromString(@"setIconType:");
    if ([icon respondsToSelector:setIconType]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(icon, setIconType, iconType);
    }
    id formatted = ((id (*)(id, SEL, id))objc_msgSend)(
        formattedClass, formattedSelector, title
    );
    YTKACESetValue(itemRenderer, @"setTitle:", formatted);
    YTKACESetValue(supportedRenderer, @"setPivotBarItemRenderer:", itemRenderer);
    return supportedRenderer;
}

static NSInteger YTKACEInteger(id receiver, NSString *selectorName) {
    SEL selector = NSSelectorFromString(selectorName);
    return receiver != nil && [receiver respondsToSelector:selector]
        ? ((NSInteger (*)(id, SEL))objc_msgSend)(receiver, selector)
        : 0;
}

static NSString *YTKACEBrowseIdentifier(UIViewController *controller) {
    id endpoint = YTKACEValue(controller, @"navigationEndpoint");
    if (endpoint == nil) {
        endpoint = YTKACEValue(controller, @"navEndpoint");
    }
    if (endpoint == nil) {
        @try {
            endpoint = [controller valueForKey:@"_navEndpoint"];
        } @catch (__unused NSException *exception) {
        }
    }
    id browseEndpoint = YTKACEValue(endpoint, @"browseEndpoint");
    if (browseEndpoint == nil &&
        [endpoint respondsToSelector:NSSelectorFromString(@"browseId")]) {
        browseEndpoint = endpoint;
    }
    return YTKACEValue(browseEndpoint, @"browseId");
}

static void YTKACEAttachDownloads(UIViewController *controller) {
    if (!YTKACEMasterEnabled() ||
        ![YTKACEBrowseIdentifier(controller) isEqualToString:YTKACEPivotIdentifier] ||
        objc_getAssociatedObject(controller, YTKACEDownloadsAssociation) != nil) {
        return;
    }
    YTKACEDownloadsController *downloads = [YTKACEDownloadsController new];
    [controller addChildViewController:downloads];
    downloads.view.frame = controller.view.bounds;
    downloads.view.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    [controller.view addSubview:downloads.view];
    [downloads didMoveToParentViewController:controller];
    objc_setAssociatedObject(controller,
                             YTKACEDownloadsAssociation,
                             downloads,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void YTKACETryAttachDownloads(UIViewController *controller) {
    YTKACEAttachDownloads(controller);
    if (objc_getAssociatedObject(controller, YTKACEDownloadsAssociation) == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            YTKACEAttachDownloads(controller);
        });
    }
}

static void YTKACEAppViewDidLoad(UIViewController *receiver, SEL selector) {
    if (OriginalAppViewDidLoad != NULL) {
        ((void (*)(id, SEL))OriginalAppViewDidLoad)(receiver, selector);
    }
    YTKACETryAttachDownloads(receiver);
}

static void YTKACEBrowseViewDidLoad(UIViewController *receiver, SEL selector) {
    if (OriginalBrowseViewDidLoad != NULL) {
        ((void (*)(id, SEL))OriginalBrowseViewDidLoad)(receiver, selector);
    }
    YTKACETryAttachDownloads(receiver);
}

static void YTKACEBrowseResponseViewDidLoad(UIViewController *receiver,
                                            SEL selector) {
    if (OriginalBrowseResponseViewDidLoad != NULL) {
        ((void (*)(id, SEL))OriginalBrowseResponseViewDidLoad)(receiver, selector);
    }
    YTKACETryAttachDownloads(receiver);
}

static void YTKACEWrapperViewDidLoad(UIViewController *receiver, SEL selector) {
    if (OriginalWrapperViewDidLoad != NULL) {
        ((void (*)(id, SEL))OriginalWrapperViewDidLoad)(receiver, selector);
    }
    YTKACETryAttachDownloads(receiver);
}

static id YTKACETabValue(id receiver, NSArray<NSString *> *selectors) {
    for (NSString *name in selectors) {
        SEL selector = NSSelectorFromString(name);
        if ([receiver respondsToSelector:selector]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
            if (value != nil) {
                return value;
            }
        }
    }
    return nil;
}

static NSString *YTKACETabToken(id item) {
    for (NSString *selectorName in @[
        @"pivotIdentifier",
        @"tabIdentifier",
        @"browseId"
    ]) {
        id value = YTKACETabValue(item, @[selectorName]);
        if ([value isKindOfClass:NSString.class] && [value length] != 0) {
            return [value lowercaseString];
        }
    }
    NSArray<NSString *> *activeRenderers =
        YTKACEInteger(item, @"hasPivotBarItemRenderer") != 0
            ? @[@"pivotBarItemRenderer"]
            : (YTKACEInteger(item, @"hasPivotBarIconOnlyItemRenderer") != 0
                ? @[@"pivotBarIconOnlyItemRenderer"]
                : @[@"pivotBarItemRenderer", @"pivotBarIconOnlyItemRenderer"]);
    for (NSString *rendererName in activeRenderers) {
        id nested = YTKACETabValue(item, @[rendererName]);
        if (nested != nil && nested != item) {
            NSString *token = YTKACETabToken(nested);
            if (token.length != 0) {
                return token;
            }
        }
    }
    id renderer = YTKACETabValue(item, @[@"renderer"]);
    if (renderer != nil && renderer != item) {
        NSString *token = YTKACETabToken(renderer);
        if (token.length != 0) {
            return token;
        }
    }
    id endpoint = YTKACETabValue(item, @[@"navigationEndpoint", @"endpoint"]);
    id browseEndpoint = YTKACETabValue(endpoint, @[@"browseEndpoint"]);
    id browseID = YTKACETabValue(browseEndpoint ?: endpoint, @[@"browseId"]);
    if ([browseID isKindOfClass:NSString.class] && [browseID length] != 0) {
        return [browseID lowercaseString];
    }
    id identifier = YTKACETabValue(item, @[@"identifier"]);
    return [identifier isKindOfClass:NSString.class]
        ? [identifier lowercaseString]
        : @"";
}

static NSString *YTKACEHideKeyForToken(NSString *token) {
    if ([token containsString:@"uc-9-kytw8zkzndhqj6fgpwq"] ||
        [token containsString:@"music_home"]) {
        return @"YTKACE.Preference.Tabs.Hidden.Music";
    }
    if ([token containsString:@"uc4r8dwomoi7cawx8_ljqhig"] ||
        [token containsString:@"trending_live"]) {
        return @"YTKACE.Preference.Tabs.Hidden.Live";
    }
    if ([token containsString:@"ucopncn46ubxvtpkmrmu4abg"] ||
        [token containsString:@"gaming"]) {
        return @"YTKACE.Preference.Tabs.Hidden.Gaming";
    }
    if ([token containsString:@"ucyfdidrxb8qhf0nx7iooyw"] ||
        [token containsString:@"news"]) {
        return @"YTKACE.Preference.Tabs.Hidden.News";
    }
    if ([token containsString:@"ucegdi0xixxz-qjofpf4jskw"] ||
        [token containsString:@"sports"]) {
        return @"YTKACE.Preference.Tabs.Hidden.Sports";
    }
    if ([token containsString:@"uctfrv9o2ahqozjjynzrv-xg"] ||
        [token containsString:@"learning"]) {
        return @"YTKACE.Preference.Tabs.Hidden.Learning";
    }
    if ([token containsString:@"ucrpq4p1ql_hg8rkxikm1moq"] ||
        [token containsString:@"fashion"]) {
        return @"YTKACE.Preference.Tabs.Hidden.Fashion";
    }
    if ([token containsString:@"feplaylist_aggregation"] ||
        [token containsString:@"playlist_aggregation"]) {
        return @"YTKACE.Preference.Tabs.Hidden.Playlists";
    }
    if ([token containsString:@"fehistory"] ||
        [token isEqualToString:@"history"]) {
        return @"YTKACE.Preference.Tabs.Hidden.History";
    }
    if ([token containsString:@"fenotifications_inbox"] ||
        [token containsString:@"notifications_inbox"]) {
        return @"YTKACE.Preference.Tabs.Hidden.Notifs";
    }
    if ([token isEqualToString:@"vlwl"] ||
        [token containsString:@"watch_later"]) {
        return @"YTKACE.Preference.Tabs.Hidden.WatchLater";
    }
    if ([token containsString:@"short"]) {
        return @"YTKACE.Preference.Tabs.Hidden.Shorts";
    }
    if ([token containsString:@"subscription"]) {
        return @"YTKACE.Preference.Tabs.Hidden.Subscriptions";
    }
    if ([token containsString:@"library"] ||
        [token containsString:@"you_tab"] ||
        [token isEqualToString:@"you"]) {
        return @"YTKACE.Preference.Tabs.Hidden.Library";
    }
    if ([token containsString:@"create"] ||
        [token containsString:@"upload"] ||
        [token containsString:@"plus"]) {
        return @"YTKACE.Preference.Tabs.Hidden.Create";
    }
    if ([token containsString:@"home"] ||
        [token containsString:@"what_to_watch"]) {
        return @"YTKACE.Preference.Tabs.Hidden.Home";
    }
    return nil;
}

static NSString *YTKACECanonicalTabToken(NSString *token) {
    if ([token containsString:@"uc-9-kytw8zkzndhqj6fgpwq"] ||
        [token containsString:@"music_home"]) {
        return @"music";
    }
    if ([token containsString:@"uc4r8dwomoi7cawx8_ljqhig"] ||
        [token containsString:@"trending_live"]) {
        return @"live";
    }
    if ([token containsString:@"ucopncn46ubxvtpkmrmu4abg"] ||
        [token containsString:@"gaming"]) {
        return @"gaming";
    }
    if ([token containsString:@"ucyfdidrxb8qhf0nx7iooyw"] ||
        [token containsString:@"news"]) {
        return @"news";
    }
    if ([token containsString:@"ucegdi0xixxz-qjofpf4jskw"] ||
        [token containsString:@"sports"]) {
        return @"sports";
    }
    if ([token containsString:@"uctfrv9o2ahqozjjynzrv-xg"] ||
        [token containsString:@"learning"]) {
        return @"learning";
    }
    if ([token containsString:@"ucrpq4p1ql_hg8rkxikm1moq"] ||
        [token containsString:@"fashion"]) {
        return @"fashion";
    }
    if ([token containsString:@"feplaylist_aggregation"] ||
        [token containsString:@"playlist_aggregation"]) {
        return @"playlists";
    }
    if ([token containsString:@"fehistory"] ||
        [token isEqualToString:@"history"]) {
        return @"history";
    }
    if ([token containsString:@"fenotifications_inbox"] ||
        [token containsString:@"notifications_inbox"]) {
        return @"notifications";
    }
    if ([token isEqualToString:@"vlwl"] ||
        [token containsString:@"watch_later"]) {
        return @"watchlater";
    }
    if ([token containsString:@"short"] || [token containsString:@"reel"]) {
        return @"shorts";
    }
    if ([token containsString:@"subscription"]) {
        return @"subscriptions";
    }
    if ([token containsString:@"library"] ||
        [token containsString:@"you_tab"] ||
        [token isEqualToString:@"you"]) {
        return @"you";
    }
    if ([token containsString:@"create"] ||
        [token containsString:@"upload"] ||
        [token containsString:@"plus"]) {
        return @"create";
    }
    if ([token containsString:@"home"] ||
        [token containsString:@"what_to_watch"]) {
        return @"home";
    }
    return token;
}

static NSArray *YTKACETabItems(id renderer, NSString **setterName) {
    NSArray<NSString *> *getters = @[
        @"itemsArray",
        @"items",
        @"pivotBarItemsArray",
        @"pivotBarItems"
    ];
    NSArray<NSString *> *setters = @[
        @"setItemsArray:",
        @"setItems:",
        @"setPivotBarItemsArray:",
        @"setPivotBarItems:"
    ];
    for (NSUInteger index = 0; index < getters.count; index++) {
        id value = YTKACETabValue(renderer, @[getters[index]]);
        if ([value isKindOfClass:NSArray.class]) {
            if (setterName != NULL) {
                *setterName = setters[index];
            }
            return value;
        }
    }
    return nil;
}

static NSInteger YTKACETabOrderIndex(NSString *token, NSArray *order) {
    NSString *canonical = YTKACECanonicalTabToken(token);
    for (NSUInteger index = 0; index < order.count; index++) {
        id value = order[index];
        if ([value isKindOfClass:NSString.class] &&
            ([canonical isEqualToString:[value lowercaseString]] ||
             [token containsString:[value lowercaseString]])) {
            return (NSInteger)index;
        }
    }
    return NSIntegerMax;
}

static void YTKACEApplyTabName(id item, NSString *token) {
    NSDictionary *names =
        [NSUserDefaults.standardUserDefaults dictionaryForKey:@"YTKACE.Preference.Tabs.Names"];
    NSString *replacement = names[token] ?: names[YTKACECanonicalTabToken(token)];
    if (![replacement isKindOfClass:NSString.class] || replacement.length == 0) {
        return;
    }
    id target = YTKACETabValue(item, @[
        @"pivotBarItemRenderer",
        @"pivotBarIconOnlyItemRenderer"
    ]) ?: item;
    Class formattedClass = NSClassFromString(@"YTIFormattedString");
    SEL formattedSelector = NSSelectorFromString(@"formattedStringWithString:");
    id value = replacement;
    if (formattedClass != Nil && [formattedClass respondsToSelector:formattedSelector]) {
        value = ((id (*)(id, SEL, id))objc_msgSend)(
            formattedClass,
            formattedSelector,
            replacement
        );
    }
    SEL selector = NSSelectorFromString(@"setTitle:");
    if ([target respondsToSelector:selector]) {
        ((void (*)(id, SEL, id))objc_msgSend)(target, selector, value);
    }
}

static BOOL YTKACEIsDownloadTab(id item) {
    NSString *token = YTKACETabToken(item);
    if ([token containsString:@"ytkace"]) {
        return YES;
    }
    NSString *description = [[item description] lowercaseString];
    return [description containsString:@"feytkace"] ||
        [description containsString:@"ytkace"];
}

static void YTKACESetPivotRenderer(id receiver, SEL selector, id renderer) {
    if (renderer != nil) {
        NSString *setterName = nil;
        NSArray *items = YTKACETabItems(renderer, &setterName);
        if (items != nil) {
            NSMutableArray *filtered = [NSMutableArray array];
            BOOL hasDownloadTab = NO;
            for (id item in items) {
                id candidate = item;
                NSString *token = YTKACETabToken(candidate);
                if (YTKACEIsDownloadTab(candidate)) {
                    BOOL duplicate = hasDownloadTab;
                    hasDownloadTab = YES;
                    if (!duplicate && YTKACEMasterEnabled() &&
                        ![NSUserDefaults.standardUserDefaults boolForKey:@"YTKACE.Preference.Tabs.Hidden.YTKACETab"]) {
                        [filtered addObject:candidate];
                    }
                    continue;
                }
                NSString *hideKey = YTKACEHideKeyForToken(token);
                if (YTKACEMasterEnabled() && hideKey != nil &&
                    [NSUserDefaults.standardUserDefaults boolForKey:hideKey]) {
                    continue;
                }
                if (YTKACEMasterEnabled() &&
                    [YTKACECanonicalTabToken(token) isEqualToString:@"create"]) {
                    [filtered addObject:candidate];
                    continue;
                }
                if (YTKACEMasterEnabled()) {
                    YTKACEApplyTabName(candidate, token);
                }
                [filtered addObject:candidate];
            }

            NSArray<NSDictionary *> *extraTabs = @[
                @{@"token": @"music", @"id": @"UC-9-kyTW8ZkZNDHQJ6FgpwQ",
                  @"title": @"Music", @"key": @"YTKACE.Preference.Tabs.Hidden.Music", @"icon": @1001},
                @{@"token": @"live", @"id": @"UC4R8DWoMoI7CAwX8_LjQHig",
                  @"title": @"Live", @"key": @"YTKACE.Preference.Tabs.Hidden.Live", @"icon": @1002},
                @{@"token": @"gaming", @"id": @"UCOpNcN46UbXVtpKMrmU4Abg",
                  @"title": @"Gaming", @"key": @"YTKACE.Preference.Tabs.Hidden.Gaming", @"icon": @1003},
                @{@"token": @"news", @"id": @"UCYfdidRxbB8Qhf0Nx7ioOYw",
                  @"title": @"News", @"key": @"YTKACE.Preference.Tabs.Hidden.News", @"icon": @1004},
                @{@"token": @"sports", @"id": @"UCEgdi0XIXXZ-qJOFPf4JSKw",
                  @"title": @"Sports", @"key": @"YTKACE.Preference.Tabs.Hidden.Sports", @"icon": @1005},
                @{@"token": @"learning", @"id": @"UCtFRv9O2AHqOZjjynzrv-xg",
                  @"title": @"Learning", @"key": @"YTKACE.Preference.Tabs.Hidden.Learning", @"icon": @1006},
                @{@"token": @"fashion", @"id": @"UCrpQ4p1Ql_hG8rKXIKM1MOQ",
                  @"title": @"Fashion", @"key": @"YTKACE.Preference.Tabs.Hidden.Fashion", @"icon": @1007},
                @{@"token": @"playlists", @"id": @"FEplaylist_aggregation",
                  @"title": @"Playlists", @"key": @"YTKACE.Preference.Tabs.Hidden.Playlists", @"icon": @1008},
                @{@"token": @"history", @"id": @"FEhistory",
                  @"title": @"History", @"key": @"YTKACE.Preference.Tabs.Hidden.History", @"icon": @1009},
                @{@"token": @"notifications", @"id": @"FEnotifications_inbox",
                  @"title": @"Notifs", @"key": @"YTKACE.Preference.Tabs.Hidden.Notifs", @"icon": @1010},
                @{@"token": @"watchlater", @"id": @"VLWL",
                  @"title": @"WLater", @"key": @"YTKACE.Preference.Tabs.Hidden.WatchLater", @"icon": @1011}
            ];
            NSMutableSet<NSString *> *present = [NSMutableSet set];
            for (id item in filtered) {
                [present addObject:YTKACECanonicalTabToken(YTKACETabToken(item))];
            }
            NSDictionary *customNames =
                [NSUserDefaults.standardUserDefaults dictionaryForKey:@"YTKACE.Preference.Tabs.Names"];
            for (NSDictionary *entry in extraTabs) {
                NSString *token = entry[@"token"];
                if ([NSUserDefaults.standardUserDefaults boolForKey:entry[@"key"]] ||
                    [present containsObject:token]) {
                    continue;
                }
                NSString *title = customNames[token] ?: entry[@"title"];
                id item = YTKACEMakeBrowsePivotItem(entry[@"id"],
                                                     title,
                                                     [entry[@"icon"] integerValue]);
                if (item != nil) {
                    [filtered addObject:item];
                    [present addObject:token];
                }
            }

            if (YTKACEMasterEnabled() && !hasDownloadTab &&
                ![NSUserDefaults.standardUserDefaults boolForKey:@"YTKACE.Preference.Tabs.Hidden.YTKACETab"]) {
                id downloadItem = YTKACEMakePivotItem();
                if (downloadItem != nil) {
                    [filtered addObject:downloadItem];
                }
            }

            NSArray *order =
                [NSUserDefaults.standardUserDefaults arrayForKey:@"YTKACE.Preference.Tabs.Order"];
            if (YTKACEMasterEnabled() && order.count != 0) {
                [filtered sortUsingComparator:^NSComparisonResult(id left, id right) {
                    NSInteger leftIndex =
                        YTKACETabOrderIndex(YTKACETabToken(left), order);
                    NSInteger rightIndex =
                        YTKACETabOrderIndex(YTKACETabToken(right), order);
                    if (leftIndex == rightIndex) {
                        return NSOrderedSame;
                    }
                    return leftIndex < rightIndex
                        ? NSOrderedAscending
                        : NSOrderedDescending;
                }];
            }

            SEL setter = NSSelectorFromString(setterName);
            if ([items isKindOfClass:NSMutableArray.class]) {
                [(NSMutableArray *)items setArray:filtered];
            } else if ([renderer respondsToSelector:setter]) {
                ((void (*)(id, SEL, id))objc_msgSend)(renderer, setter, filtered);
            }
        }
    }

    if (OriginalSetPivotRenderer != NULL) {
        ((void (*)(id, SEL, id))OriginalSetPivotRenderer)(
            receiver, selector, renderer
        );
    }
}

static void YTKACESetLabelsHidden(UIView *view, BOOL hidden) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:UILabel.class]) {
            subview.hidden = hidden;
            subview.alpha = hidden ? 0.0 : 1.0;
        }
        YTKACESetLabelsHidden(subview, hidden);
    }
}

static BOOL YTKACEInsidePivotItem(UIView *view) {
    for (UIView *current = view.superview; current != nil; current = current.superview) {
        if ([NSStringFromClass(current.class) containsString:@"PivotBarItemView"]) {
            return YES;
        }
    }
    return NO;
}

static UIView *YTKACEPivotItemAncestor(UIView *view) {
    for (UIView *current = view.superview; current != nil; current = current.superview) {
        if ([NSStringFromClass(current.class) containsString:@"PivotBarItemView"]) {
            return current;
        }
    }
    return nil;
}

static void YTKACEPivotLabelSetHidden(UILabel *receiver,
                                      SEL selector,
                                      BOOL hidden) {
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Tabs.LabelsHidden") &&
        YTKACEInsidePivotItem(receiver)) {
        hidden = YES;
    }
    if (OriginalPivotLabelSetHidden != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalPivotLabelSetHidden)(
            receiver, selector, hidden
        );
    }
}

static void YTKACEPivotLabelSetAlpha(UILabel *receiver,
                                     SEL selector,
                                     CGFloat alpha) {
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Tabs.LabelsHidden") &&
        YTKACEInsidePivotItem(receiver)) {
        alpha = 0.0;
    }
    if (OriginalPivotLabelSetAlpha != NULL) {
        ((void (*)(id, SEL, CGFloat))OriginalPivotLabelSetAlpha)(
            receiver, selector, alpha
        );
    }
}

static UIImageView *YTKACEFindImageView(UIView *view);

static BOOL YTKACEContainsLabel(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) return YES;
    for (UIView *child in view.subviews) {
        if (YTKACEContainsLabel(child)) return YES;
    }
    return NO;
}

static void YTKACECollectIconCandidates(UIView *view,
                                        UIView *root,
                                        NSMutableArray<UIView *> *candidates) {
    if (view != root && ![view isKindOfClass:UILabel.class]) {
        NSString *name = NSStringFromClass(view.class).lowercaseString;
        CGFloat width = CGRectGetWidth(view.bounds);
        CGFloat height = CGRectGetHeight(view.bounds);
        BOOL iconClass = [view isKindOfClass:UIImageView.class] ||
            [name containsString:@"icon"] || [name containsString:@"image"];
        BOOL iconSize = width >= 12.0 && height >= 12.0 &&
            width <= 64.0 && height <= 64.0;
        if ((view.tag == 0x59414345 || view.tag == YTKACEExtraIconTag ||
             iconClass) && iconSize) {
            [candidates addObject:view];
        }
    }
    for (UIView *child in view.subviews) {
        YTKACECollectIconCandidates(child, root, candidates);
    }
}

static UIView *YTKACEIconContainer(UIView *candidate, UIView *root) {
    UIView *container = candidate;
    while (container.superview != nil && container.superview != root) {
        UIView *parent = container.superview;
        if (YTKACEContainsLabel(parent) ||
            CGRectGetWidth(parent.bounds) > 80.0 ||
            CGRectGetHeight(parent.bounds) > 80.0) {
            break;
        }
        container = parent;
    }
    return container;
}

static void YTKACECenterPivotIcon(UIView *view, BOOL centered) {
    if (!centered) return;
    NSMutableArray<UIView *> *candidates = [NSMutableArray array];
    YTKACECollectIconCandidates(view, view, candidates);
    UIView *candidate = nil;
    CGFloat bestScore = CGFLOAT_MAX;
    CGPoint rootCenter = CGPointMake(CGRectGetMidX(view.bounds),
                                     CGRectGetMidY(view.bounds));
    for (UIView *item in candidates) {
        CGPoint center = [item.superview convertPoint:item.center toView:view];
        CGFloat score = fabs(center.x - rootCenter.x) +
            fabs(CGRectGetWidth(item.bounds) - 24.0) * 0.25 +
            (item.hidden ? 100.0 : 0.0);
        if (item.tag == 0x59414345 || item.tag == YTKACEExtraIconTag) {
            score -= 1000.0;
        }
        if (score < bestScore) {
            bestScore = score;
            candidate = item;
        }
    }
    UIView *iconView = candidate == nil ? nil : YTKACEIconContainer(candidate, view);
    if (iconView == nil || iconView.superview == nil) return;
    CGPoint target = [view convertPoint:CGPointMake(CGRectGetMidX(view.bounds),
                                                     CGRectGetMidY(view.bounds))
                                toView:iconView.superview];
    iconView.center = target;
}

static UILabel *YTKACEFindNativeLabel(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) {
        return (view.tag == 0x59414347 || view.tag == YTKACEExtraLabelTag)
            ? nil : (UILabel *)view;
    }
    for (UIView *subview in view.subviews) {
        UILabel *label = YTKACEFindNativeLabel(subview);
        if (label != nil) {
            return label;
        }
    }
    return nil;
}

static UIColor *YTKACETabForegroundColor(UIView *view) {
    for (UIView *current = view.superview; current != nil; current = current.superview) {
        UIColor *color = [current.backgroundColor
            resolvedColorWithTraitCollection:view.traitCollection];
        CGFloat red = 0.0;
        CGFloat green = 0.0;
        CGFloat blue = 0.0;
        CGFloat alpha = 0.0;
        if ([color getRed:&red green:&green blue:&blue alpha:&alpha] &&
            alpha > 0.2) {
            CGFloat luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722;
            return luminance < 0.5 ? UIColor.whiteColor : UIColor.blackColor;
        }
    }
    return [UIColor.labelColor
        resolvedColorWithTraitCollection:view.traitCollection];
}

static UIImageView *YTKACEFindImageView(UIView *view) {
    if ([view isKindOfClass:UIImageView.class]) {
        return (view.tag == 0x59414345 || view.tag == YTKACEExtraIconTag)
            ? nil : (UIImageView *)view;
    }
    for (UIView *subview in view.subviews) {
        UIImageView *imageView = YTKACEFindImageView(subview);
        if (imageView != nil) {
            return imageView;
        }
    }
    return nil;
}

static BOOL YTKACEViewIsVisible(UIView *view) {
    if (view.window == nil) {
        return NO;
    }
    for (UIView *current = view; current != nil; current = current.superview) {
        if (current.hidden || current.alpha < 0.01) {
            return NO;
        }
    }
    return YES;
}

static UIView *YTKACEFindDownloadsRoot(UIView *view) {
    if ([view.accessibilityIdentifier isEqualToString:@"YTKACEDownloadsRoot"]) {
        return view;
    }
    for (UIView *subview in view.subviews) {
        UIView *result = YTKACEFindDownloadsRoot(subview);
        if (result != nil) {
            return result;
        }
    }
    return nil;
}

static BOOL YTKACEDownloadsAreVisible(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            UIView *root = YTKACEFindDownloadsRoot(window);
            if (root != nil && YTKACEViewIsVisible(root)) {
                return YES;
            }
        }
    }
    return NO;
}

static void YTKACERestorePivotItem(UIView *view,
                                   UILabel *nativeLabel,
                                   BOOL hideLabel) {
    [[view viewWithTag:0x59414347] removeFromSuperview];
    [[view viewWithTag:0x59414345] removeFromSuperview];
    objc_setAssociatedObject(view,
                             YTKACETabAssociation,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (nativeLabel != nil) {
        nativeLabel.hidden = hideLabel;
        nativeLabel.alpha = 1.0;
    }
    UIImageView *nativeImageView = YTKACEFindImageView(view);
    if (nativeImageView != nil) {
        nativeImageView.hidden = NO;
    }
}

static void YTKACEApplyDownloadIcon(UIView *view) {
    UILabel *nativeLabel = YTKACEFindNativeLabel(view);
    NSString *token = YTKACETabToken(view);
    NSString *text = nativeLabel.text ?: @"";
    BOOL exactIdentifier = [token isEqualToString:@"feytkace"];
    BOOL exactLabel = [text caseInsensitiveCompare:@"YTKACE"] == NSOrderedSame;
    BOOL associated = [objc_getAssociatedObject(
        view,
        YTKACETabAssociation
    ) boolValue];
    BOOL definiteOther = (token.length != 0 && !exactIdentifier) ||
        (text.length != 0 && !exactLabel);
    BOOL hideLabel = YTKACEFeatureEnabled(@"YTKACE.Preference.Tabs.LabelsHidden");
    if (definiteOther) {
        YTKACERestorePivotItem(view, nativeLabel, hideLabel);
        return;
    }
    BOOL recognized = exactIdentifier || exactLabel || associated;
    if (!recognized) {
        return;
    }
    objc_setAssociatedObject(view,
                             YTKACETabAssociation,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIImageView *nativeImageView = YTKACEFindImageView(view);
    UIColor *tabColor = YTKACETabForegroundColor(view);
    UILabel *label = (UILabel *)[view viewWithTag:0x59414347];
    if (nativeLabel != nil) {
        nativeLabel.text = @"";
        nativeLabel.hidden = YES;
        nativeLabel.alpha = 0.0;
    }
    if (label == nil) {
        label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.tag = 0x59414347;
        label.text = @"YTKACE";
        label.font = nativeLabel.font ?: [UIFont systemFontOfSize:10.0];
        label.textAlignment = NSTextAlignmentCenter;
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleTopMargin;
        [view addSubview:label];
    }
    label.textColor = tabColor;
    label.hidden = hideLabel;
    label.alpha = 1.0;
    BOOL selected = [objc_getAssociatedObject(
        view,
        YTKACETabSelectedAssociation
    ) boolValue];
    SEL selectedSelector = NSSelectorFromString(@"isSelected");
    if ([view respondsToSelector:selectedSelector]) {
        selected = selected ||
            ((BOOL (*)(id, SEL))objc_msgSend)(view, selectedSelector);
    }
    selected = selected ||
        ((view.accessibilityTraits & UIAccessibilityTraitSelected) != 0) ||
        YTKACEDownloadsAreVisible();
    UIImage *image = YTKACEDownloadTabImage(selected);
    UIImageView *imageView = (UIImageView *)[view viewWithTag:0x59414345];
    if (imageView == nil) {
        imageView = [[UIImageView alloc] initWithFrame:CGRectZero];
        imageView.tag = 0x59414345;
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        imageView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
            UIViewAutoresizingFlexibleRightMargin |
            UIViewAutoresizingFlexibleBottomMargin;
        [view addSubview:imageView];
    }
    if (nativeImageView != nil && nativeImageView != imageView) {
        nativeImageView.hidden = YES;
    }
    imageView.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    imageView.tintColor = tabColor;
    imageView.hidden = NO;
    CGFloat size = 24.0;
    imageView.frame = CGRectMake(
        (CGRectGetWidth(view.bounds) - size) * 0.5,
        hideLabel ? (CGRectGetHeight(view.bounds) - size) * 0.5 : 4.0,
        size,
        size
    );
    label.frame = CGRectMake(0.0,
                             MAX(0.0, CGRectGetHeight(view.bounds) - 16.0),
                             CGRectGetWidth(view.bounds),
                             14.0);
}

static NSDictionary *YTKACEExtraTabIcon(NSString *token) {
    static NSDictionary *icons;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        icons = @{
            @"music": @[@"yt_outline_music_24pt_3x_Normal",
                         @"music_24pt_3x_Normal",
                         @"music.note", @"music.note"],
            @"live": @[@"live_24pt_3x_Normal", @"ic_youtube_live_3x_Normal",
                        @"dot.radiowaves.left.and.right",
                        @"dot.radiowaves.left.and.right"],
            @"gaming": @[@"gaming_24pt_3x_Normal",
                          @"gaming_24pt_3x_Normal_fill",
                          @"gamecontroller", @"gamecontroller.fill"],
            @"news": @[@"news_24pt_3x_Normal", @"news_24pt_3x_Normal",
                        @"newspaper", @"newspaper.fill"],
            @"sports": @[@"G_sport", @"G_sport_fill",
                          @"trophy", @"trophy.fill"],
            @"learning": @[@"G_Learning", @"G_Learning_fill",
                            @"graduationcap", @"graduationcap.fill"],
            @"fashion": @[@"fashion_24pt_3x_Normal",
                           @"fashion_24pt_3x_Normal",
                           @"tshirt", @"tshirt.fill"],
            @"playlists": @[@"playlist", @"playlist_fill",
                             @"music.note.list", @"music.note.list"],
            @"history": @[@"history", @"history_fill",
                           @"clock.arrow.circlepath",
                           @"clock.arrow.circlepath"],
            @"notifications": @[@"ic_notifications_none_3x_Normal",
                                 @"ic_notifications_3x_Normal",
                                 @"bell", @"bell.fill"],
            @"watchlater": @[@"clock_24pt_3x_Normal",
                              @"yt_fill_clock_24pt_3x_Normal",
                              @"clock", @"clock.fill"]
        };
    });
    NSArray *values = icons[token];
    return values == nil ? nil : @{
        @"normalAsset": values[0],
        @"selectedAsset": values[1],
        @"normalSymbol": values[2],
        @"selectedSymbol": values[3]
    };
}

static BOOL YTKACEPivotItemSelected(UIView *view) {
    BOOL selected = [objc_getAssociatedObject(
        view,
        YTKACETabSelectedAssociation
    ) boolValue];
    SEL selector = NSSelectorFromString(@"isSelected");
    if ([view respondsToSelector:selector]) {
        selected = selected ||
            ((BOOL (*)(id, SEL))objc_msgSend)(view, selector);
    }
    return selected ||
        ((view.accessibilityTraits & UIAccessibilityTraitSelected) != 0);
}

static void YTKACEApplyExtraTabIcon(UIView *view) {
    NSString *token = YTKACECanonicalTabToken(YTKACETabToken(view));
    NSDictionary *config = YTKACEExtraTabIcon(token);
    if (config == nil) {
        UILabel *nativeLabel = YTKACEFindNativeLabel(view);
        NSString *hint = [[NSString stringWithFormat:@"%@ %@ %@ %@",
            nativeLabel.text ?: @"", view.accessibilityLabel ?: @"",
            view.accessibilityIdentifier ?: @"", view.description ?: @""] lowercaseString];
        NSDictionary *aliases = @{
            @"music": @[@"music"],
            @"live": @[@"live"],
            @"gaming": @[@"gaming"],
            @"news": @[@"news"],
            @"sports": @[@"sports"],
            @"learning": @[@"learning"],
            @"fashion": @[@"fashion"],
            @"playlists": @[@"playlists", @"playlist"],
            @"history": @[@"history"],
            @"notifications": @[@"notifs", @"notifications"],
            @"watchlater": @[@"wlater", @"watch later"]
        };
        for (NSString *candidate in aliases) {
            for (NSString *alias in aliases[candidate]) {
                if ([hint containsString:alias]) {
                    token = candidate;
                    config = YTKACEExtraTabIcon(token);
                    break;
                }
            }
            if (config != nil) break;
        }
    }
    if (config == nil) {
        [[view viewWithTag:YTKACEExtraIconTag] removeFromSuperview];
        [[view viewWithTag:YTKACEExtraLabelTag] removeFromSuperview];
        return;
    }
    UIImageView *nativeImage = YTKACEFindImageView(view);
    if (nativeImage != nil) {
        nativeImage.hidden = YES;
    }
    UIImageView *icon = (UIImageView *)[view viewWithTag:YTKACEExtraIconTag];
    if (icon == nil) {
        icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        icon.tag = YTKACEExtraIconTag;
        icon.contentMode = UIViewContentModeScaleAspectFit;
        icon.userInteractionEnabled = NO;
        [view addSubview:icon];
    }
    BOOL selected = YTKACEPivotItemSelected(view);
    NSString *asset = config[selected ? @"selectedAsset" : @"normalAsset"];
    NSString *symbol = config[selected ? @"selectedSymbol" : @"normalSymbol"];
    UIImage *image = YTKACEAssetImage(asset, symbol);
    if (image == nil) {
        image = [UIImage systemImageNamed:@"circle"];
    }
    icon.image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    icon.tintColor = YTKACETabForegroundColor(view);
    icon.hidden = NO;
    CGFloat size = 24.0;
    BOOL hideLabel = YTKACEFeatureEnabled(@"YTKACE.Preference.Tabs.LabelsHidden");
    icon.frame = CGRectMake(
        (CGRectGetWidth(view.bounds) - size) * 0.5,
        hideLabel ? (CGRectGetHeight(view.bounds) - size) * 0.5 : 4.0,
        size,
        size
    );
    UILabel *nativeLabel = YTKACEFindNativeLabel(view);
    UILabel *label = (UILabel *)[view viewWithTag:YTKACEExtraLabelTag];
    NSString *title = nativeLabel.text.length != 0
        ? nativeLabel.text : label.text;
    UIFont *font = nativeLabel.font ?: label.font;
    if (nativeLabel != nil) {
        nativeLabel.text = @"";
        nativeLabel.hidden = YES;
        nativeLabel.alpha = 0.0;
    }
    if (label == nil) {
        label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.tag = YTKACEExtraLabelTag;
        label.textAlignment = NSTextAlignmentCenter;
        label.userInteractionEnabled = NO;
        [view addSubview:label];
    }
    label.text = title;
    label.font = font ?: [UIFont systemFontOfSize:10.0];
    label.textColor = icon.tintColor;
    label.hidden = hideLabel;
    label.alpha = hideLabel ? 0.0 : 1.0;
    label.frame = CGRectMake(
        0.0,
        MAX(0.0, CGRectGetHeight(view.bounds) - 16.0),
        CGRectGetWidth(view.bounds),
        14.0
    );
}

static void YTKACEApplyPivotItemPresentation(UIView *view) {
    BOOL hideLabels = YTKACEFeatureEnabled(@"YTKACE.Preference.Tabs.LabelsHidden");
    YTKACESetLabelsHidden(view, hideLabels);
    YTKACEApplyDownloadIcon(view);
    YTKACEApplyExtraTabIcon(view);
    YTKACECenterPivotIcon(view, hideLabels);
}

static void YTKACEPivotButtonLayout(UIView *receiver, SEL selector) {
    if (OriginalPivotButtonLayout != NULL) {
        ((void (*)(id, SEL))OriginalPivotButtonLayout)(receiver, selector);
    }
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Tabs.LabelsHidden")) return;
    UIView *item = YTKACEPivotItemAncestor(receiver);
    if (item == nil || CGRectIsEmpty(item.bounds)) return;
    YTKACESetLabelsHidden(receiver, YES);
    UIImageView *icon = nil;
    for (UIView *child in receiver.subviews) {
        if (![child isKindOfClass:UIImageView.class] || child.hidden ||
            CGRectGetWidth(child.bounds) < 12.0 ||
            CGRectGetHeight(child.bounds) < 12.0) {
            continue;
        }
        icon = (UIImageView *)child;
        break;
    }
    if (icon == nil) return;
    CGPoint target = [item convertPoint:CGPointMake(CGRectGetMidX(item.bounds),
                                                    CGRectGetMidY(item.bounds))
                                  toView:receiver];
    icon.center = target;
}

static BOOL YTKACEContainsCreateText(NSString *value) {
    NSString *text = value.lowercaseString;
    return [text containsString:@"create"] ||
        [text containsString:@"upload"] ||
        [text containsString:@"add video"];
}

static void YTKACEHideCreateViews(UIView *view) {
    BOOL hideCreate = [NSUserDefaults.standardUserDefaults boolForKey:@"YTKACE.Preference.Tabs.Hidden.Create"];
    for (UIView *subview in view.subviews) {
        NSString *label = subview.accessibilityLabel;
        NSString *identifier = subview.accessibilityIdentifier;
        NSString *className = NSStringFromClass(subview.class);
        if (hideCreate &&
            (YTKACEContainsCreateText(label) ||
             YTKACEContainsCreateText(identifier) ||
             YTKACEContainsCreateText(className))) {
            subview.hidden = YES;
            subview.userInteractionEnabled = NO;
        }
        YTKACEHideCreateViews(subview);
    }
}

static const void *YTKACEPivotBarSolidAssociation = &YTKACEPivotBarSolidAssociation;

static void YTKACEApplyPivotBarBackground(UIView *receiver) {
    SEL blurSelector = NSSelectorFromString(@"blurView");
    UIView *blur = [receiver respondsToSelector:blurSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(receiver, blurSelector)
        : nil;
    BOOL applied = [objc_getAssociatedObject(
        receiver, YTKACEPivotBarSolidAssociation) boolValue];
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Tabs.FrostedHidden")) {
        if (!applied) return;
        blur.hidden = NO;
        receiver.backgroundColor = UIColor.clearColor;
        receiver.opaque = NO;
        objc_setAssociatedObject(receiver, YTKACEPivotBarSolidAssociation,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    UIUserInterfaceStyle style = receiver.traitCollection.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) {
        style = receiver.window.traitCollection.userInterfaceStyle;
    }
    UIColor *solid = style == UIUserInterfaceStyleDark
        ? UIColor.blackColor
        : UIColor.whiteColor;
    blur.hidden = YES;
    for (UIView *sibling in receiver.subviews) {
        if (sibling != blur && [sibling isKindOfClass:UIVisualEffectView.class]) {
            sibling.hidden = YES;
        }
    }
    receiver.backgroundColor = solid;
    receiver.opaque = YES;
    objc_setAssociatedObject(receiver, YTKACEPivotBarSolidAssociation,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void YTKACERefreshPivotBarsInView(UIView *view) {
    if ([NSStringFromClass(view.class) isEqualToString:@"YTPivotBarView"]) {
        YTKACEApplyPivotBarBackground(view);
        return;
    }
    for (UIView *subview in view.subviews) {
        YTKACERefreshPivotBarsInView(subview);
    }
}

void YTKACERefreshPivotBarBackground(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.hidden) YTKACERefreshPivotBarsInView(window);
        }
    }
}

static void YTKACEPivotBarStyleColors(UIView *receiver, SEL selector) {
    if (OriginalPivotBarStyleColors != NULL) {
        ((void (*)(id, SEL))OriginalPivotBarStyleColors)(receiver, selector);
    }
    YTKACEApplyPivotBarBackground(receiver);
}

static void YTKACEPivotBarSetBackgroundStyle(UIView *receiver, SEL selector,
                                             int style) {
    if (OriginalPivotBarSetBackgroundStyle != NULL) {
        ((void (*)(id, SEL, int))OriginalPivotBarSetBackgroundStyle)(
            receiver, selector, style);
    }
    YTKACEApplyPivotBarBackground(receiver);
}

static void YTKACEPivotBarLayout(UIView *receiver, SEL selector) {
    if (OriginalPivotBarLayout != NULL) {
        ((void (*)(id, SEL))OriginalPivotBarLayout)(receiver, selector);
    }
    YTKACEHideCreateViews(receiver);
    YTKACEApplyPivotBarBackground(receiver);
    NSInteger startup = [NSUserDefaults.standardUserDefaults
        integerForKey:@"YTKACE.Preference.Tabs.Startup"];
    SEL select = NSSelectorFromString(@"selectItemWithPivotIdentifier:");
    if (!YTKACEStartupApplied && startup > 0 && startup < 5 &&
        [receiver respondsToSelector:select]) {
        NSArray<NSString *> *identifiers = @[
            @"FEwhat_to_watch",
            @"FEexplore",
            @"FEsubscriptions",
            @"FEshorts",
            @"FElibrary"
        ];
        ((void (*)(id, SEL, id))objc_msgSend)(
            receiver,
            select,
            identifiers[(NSUInteger)startup]
        );
        YTKACEStartupApplied = YES;
    }
}

static void YTKACEPivotItemLayout(UIView *receiver, SEL selector) {
    if (OriginalPivotItemLayout != NULL) {
        ((void (*)(id, SEL))OriginalPivotItemLayout)(receiver, selector);
    }
    YTKACEApplyPivotItemPresentation(receiver);
}

static void YTKACEPivotItemSetSelected(UIView *receiver,
                                       SEL selector,
                                       BOOL selected) {
    if (OriginalPivotItemSetSelected != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalPivotItemSetSelected)(
            receiver, selector, selected
        );
    }
    objc_setAssociatedObject(receiver,
                             YTKACETabSelectedAssociation,
                             @(selected),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    YTKACEApplyPivotItemPresentation(receiver);
    dispatch_async(dispatch_get_main_queue(), ^{
        YTKACEApplyPivotItemPresentation(receiver);
    });
}

static void YTKACEPivotItemTraitChanged(UIView *receiver,
                                        SEL selector,
                                        UITraitCollection *previous) {
    if (OriginalPivotItemTraitChanged != NULL) {
        ((void (*)(id, SEL, id))OriginalPivotItemTraitChanged)(
            receiver, selector, previous
        );
    }
    YTKACEApplyPivotItemPresentation(receiver);
    dispatch_async(dispatch_get_main_queue(), ^{
        YTKACEApplyPivotItemPresentation(receiver);
    });
    if (YTKACEFeatureEnabled(YTKACEOLEDKey) &&
        !YTKACENavigationRefreshScheduled) {
        YTKACENavigationRefreshScheduled = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            YTKACENavigationRefreshScheduled = NO;
            YTKACERefreshNavigationAppearance();
        });
    }
}

void YTKACEInstallTabBarHooks(void) {
    YTKACEInstallInstanceHook(@"UILabel",
                              @"setHidden:",
                              (IMP)YTKACEPivotLabelSetHidden,
                              &OriginalPivotLabelSetHidden);
    YTKACEInstallInstanceHook(@"UILabel",
                              @"setAlpha:",
                              (IMP)YTKACEPivotLabelSetAlpha,
                              &OriginalPivotLabelSetAlpha);
    YTKACEInstallInstanceHook(@"YTQTMButton",
                              @"layoutSubviews",
                              (IMP)YTKACEPivotButtonLayout,
                              &OriginalPivotButtonLayout);
    YTKACEInstallInstanceHook(@"YTPivotBarView",
                              @"setRenderer:",
                              (IMP)YTKACESetPivotRenderer,
                              &OriginalSetPivotRenderer);
    YTKACEInstallInstanceHook(@"YTPivotBarItemView",
                              @"layoutSubviews",
                              (IMP)YTKACEPivotItemLayout,
                              &OriginalPivotItemLayout);
    YTKACEInstallInstanceHook(@"YTPivotBarItemView",
                              @"setSelected:",
                              (IMP)YTKACEPivotItemSetSelected,
                              &OriginalPivotItemSetSelected);
    YTKACEInstallInstanceHook(@"YTPivotBarItemView",
                              @"traitCollectionDidChange:",
                              (IMP)YTKACEPivotItemTraitChanged,
                              &OriginalPivotItemTraitChanged);
    YTKACEInstallInstanceHook(@"YTPivotBarView",
                              @"layoutSubviews",
                              (IMP)YTKACEPivotBarLayout,
                              &OriginalPivotBarLayout);
    YTKACEInstallInstanceHook(@"YTPivotBarView",
                              @"styleBackgroundColors",
                              (IMP)YTKACEPivotBarStyleColors,
                              &OriginalPivotBarStyleColors);
    YTKACEInstallInstanceHook(@"YTPivotBarView",
                              @"setBackgroundStyle:",
                              (IMP)YTKACEPivotBarSetBackgroundStyle,
                              &OriginalPivotBarSetBackgroundStyle);
    YTKACEInstallInstanceHook(@"YTAppViewController",
                              @"viewDidLoad",
                              (IMP)YTKACEAppViewDidLoad,
                              &OriginalAppViewDidLoad);
    YTKACEInstallInstanceHook(@"YTBrowseViewController",
                              @"viewDidLoad",
                              (IMP)YTKACEBrowseViewDidLoad,
                              &OriginalBrowseViewDidLoad);
    YTKACEInstallInstanceHook(@"YTBrowseResponseViewController",
                              @"viewDidLoad",
                              (IMP)YTKACEBrowseResponseViewDidLoad,
                              &OriginalBrowseResponseViewDidLoad);
    YTKACEInstallInstanceHook(@"YTWrapperFlatViewController",
                              @"viewDidLoad",
                              (IMP)YTKACEWrapperViewDidLoad,
                              &OriginalWrapperViewDidLoad);
}

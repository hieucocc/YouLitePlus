#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static IMP OriginalDisplayViewDidMove;
static IMP OriginalDisplayViewSetIdentifier;
static IMP OriginalAddSections;
static IMP OriginalSectionControllers;
static IMP OriginalEnableSubheaderBar;
static IMP OriginalChipBarUpdate;
static IMP OriginalChipCloudSetEntry;
static IMP OriginalSubsChipFilter;
static IMP OriginalChipCloudLayout;
static IMP OriginalFeedHeaderScrollMode;
static IMP OriginalSubsSetChipFilterView;
static IMP OriginalMaximumSubheaderHeight;
static IMP OriginalMaximumSubheaderHeightGetter;
static IMP OriginalSubheaderDefaultHeight;
static IMP OriginalSetHeaderHeights;
static IMP OriginalShouldHideSubheader;
static IMP OriginalPaidContentLayout;
static IMP OriginalPaidContentDidAppear;
static IMP OriginalPaidContentPlaybackStarted;
static IMP OriginalSetPaidContentPlayerData;
static IMP OriginalSetPaidContentRenderer;
static IMP OriginalHasPaidContentOverlay;
static IMP OriginalPaidContentOverlay;
static IMP OriginalOverlayPaidContentPlayerData;
static IMP OriginalInlinePaidContentPlayerData;
static IMP OriginalDidInsertPlayerOverlay;
static IMP OriginalScrollableActionButtonsArray;
static IMP OriginalScrollableActionBarButtonsArray;
static IMP OriginalScrollableButtonsArray;
static IMP OriginalScrollableActionsArray;
static IMP OriginalActionButtonsArray;
static IMP OriginalActionBarButtonsArray;
static IMP OriginalButtonsArray;
static IMP OriginalActionsArray;
static IMP OriginalActionViewDidMove;
static IMP OriginalActionsViewDidMove;
static IMP OriginalActionCellDidMove;
static IMP OriginalCreateActionViews;
static IMP OriginalActionCellControllerInit;
static IMP OriginalActionCellSize;
static IMP OriginalActionCellSizeWithInsets;
static IMP OriginalASCollectionViewLayout;
static const void *YTKACEContentHiddenAssociation = &YTKACEContentHiddenAssociation;
static const void *YTKACEActionCellPreferenceAssociation =
    &YTKACEActionCellPreferenceAssociation;
static const void *YTKACEActionLayoutRefreshAssociation =
    &YTKACEActionLayoutRefreshAssociation;
static const void *YTKACEActionGroupCompactAssociation =
    &YTKACEActionGroupCompactAssociation;
static BOOL YTKACEContentContains(NSString *token,
                                  NSArray<NSString *> *needles);
static id YTKACEContentValue(id object, NSString *key);
static BOOL YTKACESectionIsShortsShelf(id section);
static BOOL YTKACESectionIsProductsShelf(id section);
static BOOL YTKACESectionIsCommunityPosts(id section);
static BOOL YTKACESectionIsMix(id section);
static BOOL YTKACESectionIsPlayable(id section);
static NSArray<NSString *> *YTKACEProductsMarkers(void);
static BOOL YTKACEHideTopics(void);
static NSString *YTKACEActionViewText(UIView *view);
static BOOL YTKACEEnsureStructuralActionHook(void);
static BOOL YTKACEEnsureActionCellControllerHooks(void);
static BOOL YTKACEEnsureActionCollectionLayoutHook(void);

static BOOL YTKACEViewIsInsideWatchActionBar(UIView *view) {
    for (UIView *candidate = view; candidate != nil; candidate = candidate.superview) {
        NSString *identifier = [candidate.accessibilityIdentifier lowercaseString] ?: @"";
        NSString *className = NSStringFromClass(candidate.class) ?: @"";
        if ([identifier containsString:@"scrollable_action_bar"] ||
            [className containsString:@"SlimVideoScrollableDetailsActionsView"] ||
            [className containsString:@"SlimVideoScrollableActionBarCell"]) {
            return YES;
        }
        if ([candidate isKindOfClass:UICollectionView.class] &&
            CGRectGetHeight(candidate.bounds) <= 64.0 &&
            CGRectGetHeight(candidate.bounds) > 0.0) {
            return YES;
        }
    }
    return NO;
}

static NSString *YTKACEActionPreference(id item) {
    NSString *token = [[[NSString stringWithFormat:@"%@ %@",
        NSStringFromClass([item class]), [item description] ?: @""] lowercaseString]
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSArray<NSArray<NSString *> *> *rules = @[
        @[@"YTKACE.Preference.ActionBar.DislikeHidden", @"dislike"],
        @[@"YTKACE.Preference.ActionBar.ShareHidden", @"share"],
        @[@"YTKACE.Preference.ActionBar.DownloadHidden", @"offline", @"download"],
        @[@"YTKACE.Preference.ActionBar.SaveHidden", @"save", @"add_to"],
        @[@"YTKACE.Preference.ActionBar.ClipHidden", @"clip"],
        @[@"YTKACE.Preference.ActionBar.RemixHidden", @"remix"],
        @[@"YTKACE.Preference.ActionBar.ThanksHidden", @"thanks"],
        @[@"YTKACE.Preference.ActionBar.HypeHidden", @"hype"],
        @[@"YTKACE.Preference.ActionBar.ReportHidden", @"report"],
        @[@"YTKACE.Preference.ActionBar.AskHidden", @"ask", @"gemini"],
        @[@"YTKACE.Preference.ActionBar.LikeHidden", @"like"]
    ];
    for (NSArray<NSString *> *rule in rules) {
        for (NSUInteger index = 1; index < rule.count; index++) {
            if ([token containsString:rule[index]]) return rule.firstObject;
        }
    }
    return nil;
}

static BOOL YTKACEAnyActionPreferenceEnabled(void) {
    for (NSString *key in @[
        @"YTKACE.Preference.ActionBar.LikeHidden",
        @"YTKACE.Preference.ActionBar.DislikeHidden",
        @"YTKACE.Preference.ActionBar.ShareHidden",
        @"YTKACE.Preference.ActionBar.DownloadHidden",
        @"YTKACE.Preference.ActionBar.SaveHidden",
        @"YTKACE.Preference.ActionBar.ClipHidden",
        @"YTKACE.Preference.ActionBar.RemixHidden",
        @"YTKACE.Preference.ActionBar.ThanksHidden",
        @"YTKACE.Preference.ActionBar.HypeHidden",
        @"YTKACE.Preference.ActionBar.ReportHidden",
        @"YTKACE.Preference.ActionBar.AskHidden"
    ]) {
        if (YTKACEFeatureEnabled(key)) return YES;
    }
    return NO;
}

static NSString *YTKACEActionPreferenceForView(UIView *view) {
    if (view == nil || !YTKACEViewIsInsideWatchActionBar(view)) return nil;
    NSString *identifier = view.accessibilityIdentifier ?: @"";
    NSString *label = view.accessibilityLabel ?: @"";
    NSString *text = YTKACEActionViewText(view) ?: @"";
    NSString *token = [[[NSString stringWithFormat:@"%@ %@ %@ %@",
        NSStringFromClass(view.class), identifier, label, text] lowercaseString]
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSArray<NSArray<NSString *> *> *rules = @[
        @[@"YTKACE.Preference.ActionBar.DislikeHidden", @"id_video_dislike_button", @"dislike"],
        @[@"YTKACE.Preference.ActionBar.ShareHidden", @"id_video_share_button", @"share"],
        @[@"YTKACE.Preference.ActionBar.DownloadHidden", @"offline", @"download"],
        @[@"YTKACE.Preference.ActionBar.SaveHidden", @"save", @"add_to"],
        @[@"YTKACE.Preference.ActionBar.ClipHidden", @"clip"],
        @[@"YTKACE.Preference.ActionBar.RemixHidden", @"remix"],
        @[@"YTKACE.Preference.ActionBar.ThanksHidden", @"thanks"],
        @[@"YTKACE.Preference.ActionBar.HypeHidden", @"hype"],
        @[@"YTKACE.Preference.ActionBar.ReportHidden", @"report"],
        @[@"YTKACE.Preference.ActionBar.AskHidden", @"ask", @"gemini"],
        @[@"YTKACE.Preference.ActionBar.LikeHidden", @"id_video_like_button", @"like"]
    ];
    for (NSArray<NSString *> *rule in rules) {
        for (NSUInteger index = 1; index < rule.count; index++) {
            if ([token containsString:rule[index]]) return rule.firstObject;
        }
    }
    return nil;
}

static void YTKACECreateActionViews(id receiver, SEL selector,
                                    NSArray *renderers) {
    NSArray *filtered = renderers;
    if ([renderers isKindOfClass:NSArray.class] &&
        renderers.count != 0 && YTKACEAnyActionPreferenceEnabled()) {
        NSMutableArray *kept = [NSMutableArray arrayWithCapacity:renderers.count];
        for (id renderer in renderers) {
            NSString *preference = YTKACEActionPreference(renderer);
            if (preference.length != 0 && YTKACEFeatureEnabled(preference)) {
                continue;
            }
            [kept addObject:renderer];
        }
        if (kept.count != renderers.count) filtered = kept;
    }
    if (OriginalCreateActionViews != NULL) {
        ((void (*)(id, SEL, id))OriginalCreateActionViews)(
            receiver, selector, filtered);
    }
}

static BOOL YTKACEEnsureStructuralActionHook(void) {
    if (OriginalCreateActionViews != NULL) return YES;

    BOOL installed = YTKACEInstallInstanceHook(
        @"YTSlimVideoScrollableDetailsActionsView",
        @"createActionViewsFromSupportedRenderers:",
        (IMP)YTKACECreateActionViews,
        &OriginalCreateActionViews
    );
    if (installed && OriginalCreateActionViews != NULL) return YES;
    return NO;
}

static NSString *YTKACEActionPreferenceForController(id controller) {
    NSString *cached = objc_getAssociatedObject(
        controller, YTKACEActionCellPreferenceAssociation);
    if (cached.length != 0) return cached;

    for (Class cls = [controller class]; cls != Nil; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned int index = 0; index < count; index++) {
            const char *type = ivar_getTypeEncoding(ivars[index]);
            const char *name = ivar_getName(ivars[index]);
            if (type == NULL || type[0] != '@' || name == NULL) continue;
            NSString *ivarName = [[NSString stringWithUTF8String:name] lowercaseString];
            if (![ivarName containsString:@"entry"] &&
                ![ivarName containsString:@"render"] &&
                ![ivarName containsString:@"button"] &&
                ![ivarName containsString:@"cell"]) {
                continue;
            }
            id value = object_getIvar(controller, ivars[index]);
            if (value == nil) continue;
            NSString *preference = [value isKindOfClass:UIView.class]
                ? YTKACEActionPreferenceForView(value)
                : YTKACEActionPreference(value);
            if (preference.length == 0) continue;
            free(ivars);
            objc_setAssociatedObject(controller,
                                     YTKACEActionCellPreferenceAssociation,
                                     preference,
                                     OBJC_ASSOCIATION_COPY_NONATOMIC);
            return preference;
        }
        free(ivars);
    }
    return nil;
}

static id YTKACEActionCellControllerInit(id receiver, SEL selector,
                                          id entry, id parentResponder) {
    id result = OriginalActionCellControllerInit == NULL ? receiver :
        ((id (*)(id, SEL, id, id))OriginalActionCellControllerInit)(
            receiver, selector, entry, parentResponder);
    NSString *preference = YTKACEActionPreference(entry);
    if (result != nil && preference.length != 0) {
        objc_setAssociatedObject(result,
                                 YTKACEActionCellPreferenceAssociation,
                                 preference,
                                 OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    return result;
}

static CGSize YTKACEActionCellSize(id receiver, SEL selector, CGSize size) {
    CGSize result = OriginalActionCellSize == NULL ? size :
        ((CGSize (*)(id, SEL, CGSize))OriginalActionCellSize)(
            receiver, selector, size);
    NSString *preference = YTKACEActionPreferenceForController(receiver);
    if (preference.length != 0 && YTKACEFeatureEnabled(preference)) {
        result.width = 0.0;
    }
    return result;
}

static CGSize YTKACEActionCellSizeWithInsets(id receiver, SEL selector,
                                               CGSize size,
                                               UIEdgeInsets insets) {
    CGSize result = OriginalActionCellSizeWithInsets == NULL ? size :
        ((CGSize (*)(id, SEL, CGSize, UIEdgeInsets))
            OriginalActionCellSizeWithInsets)(receiver, selector, size, insets);
    NSString *preference = YTKACEActionPreferenceForController(receiver);
    if (preference.length != 0 && YTKACEFeatureEnabled(preference)) {
        result.width = 0.0;
    }
    return result;
}

static BOOL YTKACEEnsureActionCellControllerHooks(void) {
    if (OriginalActionCellSize != NULL ||
        OriginalActionCellSizeWithInsets != NULL) return YES;

    YTKACEInstallInstanceHook(
        @"YTSlimVideoScrollableActionBarCellController",
        @"initWithEntry:parentResponder:",
        (IMP)YTKACEActionCellControllerInit,
        &OriginalActionCellControllerInit);
    YTKACEInstallInstanceHook(
        @"YTSlimVideoScrollableActionBarCellController",
        @"cellSizeWithSize:",
        (IMP)YTKACEActionCellSize,
        &OriginalActionCellSize);
    YTKACEInstallInstanceHook(
        @"YTSlimVideoScrollableActionBarCellController",
        @"cellSizeWithSize:safeAreaInsets:",
        (IMP)YTKACEActionCellSizeWithInsets,
        &OriginalActionCellSizeWithInsets);
    return OriginalActionCellSize != NULL ||
        OriginalActionCellSizeWithInsets != NULL;
}

static NSSet<NSString *> *YTKACEActionPreferencesInCell(UIView *cell) {
    NSMutableSet<NSString *> *preferences = [NSMutableSet set];
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:cell];
    NSUInteger visited = 0;
    while (pending.count != 0 && visited < 120) {
        UIView *candidate = pending.firstObject;
        [pending removeObjectAtIndex:0];
        visited++;
        NSString *identifier = candidate.accessibilityIdentifier ?: @"";
        NSString *label = candidate.accessibilityLabel ?: @"";
        if (identifier.length != 0 || label.length != 0) {
            NSString *preference = YTKACEActionPreference(
                [NSString stringWithFormat:@"%@ %@", identifier, label]);
            if (preference.length != 0) [preferences addObject:preference];
        }
        [pending addObjectsFromArray:candidate.subviews];
    }
    return preferences;
}

static void YTKACEASCollectionViewLayout(UICollectionView *receiver,
                                          SEL selector) {
    if (OriginalASCollectionViewLayout != NULL) {
        ((void (*)(id, SEL))OriginalASCollectionViewLayout)(receiver, selector);
    }
    if (!YTKACEAnyActionPreferenceEnabled() || receiver.window == nil) return;
    CGFloat height = CGRectGetHeight(receiver.bounds);
    if (height < 36.0 || height > 68.0) return;

    NSArray<UICollectionViewCell *> *visible = [receiver.visibleCells
        sortedArrayUsingComparator:^NSComparisonResult(UICollectionViewCell *left,
                                                       UICollectionViewCell *right) {
            CGFloat leftX = CGRectGetMinX(left.frame);
            CGFloat rightX = CGRectGetMinX(right.frame);
            if (leftX < rightX) return NSOrderedAscending;
            if (leftX > rightX) return NSOrderedDescending;
            return NSOrderedSame;
        }];
    if (visible.count == 0) return;

    CGFloat removedWidth = 0.0;
    NSUInteger matchedCells = 0;
    for (UICollectionViewCell *cell in visible) {
        CGRect frame = cell.frame;
        frame.origin.x -= removedWidth;
        NSSet<NSString *> *preferences = YTKACEActionPreferencesInCell(cell);
        if (preferences.count != 0) {
            matchedCells++;
            NSUInteger hiddenCount = 0;
            for (NSString *preference in preferences) {
                if (YTKACEFeatureEnabled(preference)) hiddenCount++;
            }
            if (hiddenCount != 0) {
                CGFloat oldWidth = CGRectGetWidth(frame);
                CGFloat visibleFraction =
                    (CGFloat)(preferences.count - hiddenCount) /
                    (CGFloat)preferences.count;
                CGFloat newWidth = floor(oldWidth * visibleFraction);
                BOOL combinedReactions =
                    [preferences containsObject:
                        @"YTKACE.Preference.ActionBar.LikeHidden"] &&
                    [preferences containsObject:
                        @"YTKACE.Preference.ActionBar.DislikeHidden"];
                removedWidth += oldWidth - newWidth;
                frame.size.width = newWidth;
                cell.hidden = newWidth <= 0.5;
                cell.userInteractionEnabled = !cell.hidden;
                cell.clipsToBounds = combinedReactions && !cell.hidden;
                cell.contentView.clipsToBounds = cell.clipsToBounds;
                if (combinedReactions && !cell.hidden &&
                    YTKACEFeatureEnabled(
                        @"YTKACE.Preference.ActionBar.LikeHidden") &&
                    !YTKACEFeatureEnabled(
                        @"YTKACE.Preference.ActionBar.DislikeHidden")) {
                    cell.contentView.transform =
                        CGAffineTransformMakeTranslation(-newWidth, 0.0);
                } else {
                    cell.contentView.transform = CGAffineTransformIdentity;
                }
            } else {
                cell.hidden = NO;
                cell.userInteractionEnabled = YES;
                cell.clipsToBounds = NO;
                cell.contentView.clipsToBounds = NO;
                cell.contentView.transform = CGAffineTransformIdentity;
            }
        }
        cell.frame = frame;
    }
    if (matchedCells == 0 || removedWidth <= 0.0) return;

    CGSize contentSize = receiver.contentSize;
    contentSize.width = MAX(CGRectGetWidth(receiver.bounds),
                            contentSize.width - removedWidth);
    receiver.contentSize = contentSize;
}

static BOOL YTKACEEnsureActionCollectionLayoutHook(void) {
    if (OriginalASCollectionViewLayout != NULL) return YES;
    BOOL installed = YTKACEInstallInstanceHook(
        @"ASCollectionView", @"layoutSubviews",
        (IMP)YTKACEASCollectionViewLayout,
        &OriginalASCollectionViewLayout);
    if (installed && OriginalASCollectionViewLayout != NULL) return YES;
    return NO;
}

static void YTKACEScheduleStructuralActionHook(void) {
    NSArray<NSNumber *> *delays =
        @[@0.0, @0.5, @1.5, @3.0, @6.0, @9.0, @12.0, @18.0];
    for (NSNumber *delay in delays) {
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW,
                          (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
            dispatch_get_main_queue(),
            ^{
                YTKACEEnsureStructuralActionHook();
                YTKACEEnsureActionCellControllerHooks();
                YTKACEEnsureActionCollectionLayoutHook();
            }
        );
    }
}

static UICollectionView *YTKACEActionCollectionView(UIView *view) {
    for (UIView *candidate = view; candidate != nil; candidate = candidate.superview) {
        if ([candidate isKindOfClass:UICollectionView.class]) {
            return (UICollectionView *)candidate;
        }
    }
    return nil;
}

static void YTKACERefreshActionCollection(UIView *view) {
    if (!YTKACEEnsureActionCellControllerHooks()) return;
    UICollectionView *collectionView = YTKACEActionCollectionView(view);
    if (collectionView == nil || objc_getAssociatedObject(
            collectionView, YTKACEActionLayoutRefreshAssociation) != nil) {
        return;
    }
    objc_setAssociatedObject(collectionView,
                             YTKACEActionLayoutRefreshAssociation,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        [collectionView.collectionViewLayout invalidateLayout];
        [collectionView reloadData];
        [collectionView layoutIfNeeded];
    });
}

static UIView *YTKACEActionContainer(UIView *view) {
    UIView *candidate = view;
    UIView *best = view;
    for (NSUInteger index = 0; candidate.superview != nil && index < 7; index++) {
        UIView *parent = candidate.superview;
        if ([parent isKindOfClass:UIStackView.class]) return candidate;
        CGFloat width = CGRectGetWidth(parent.bounds);
        CGFloat height = CGRectGetHeight(parent.bounds);
        if (width > 0.0 && height > 0.0 && width <= 180.0 && height <= 130.0) {
            best = parent;
            candidate = parent;
            continue;
        }
        break;
    }
    return best;
}

static void YTKACECompactFixedActionGroup(UIView *target) {
    UIView *group = target.superview;
    if (group == nil || CGRectGetHeight(group.bounds) < 40.0 ||
        CGRectGetHeight(group.bounds) > 56.0 ||
        CGRectGetWidth(group.bounds) < 160.0 ||
        CGRectGetWidth(group.bounds) > 260.0) {
        return;
    }
    if (objc_getAssociatedObject(group,
            YTKACEActionGroupCompactAssociation) != nil) {
        return;
    }
    objc_setAssociatedObject(group,
                             YTKACEActionGroupCompactAssociation,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakGroup = group;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *strongGroup = weakGroup;
        if (strongGroup == nil) return;
        NSArray<UIView *> *slots = [strongGroup.subviews
            filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:
                ^BOOL(UIView *view, __unused NSDictionary *bindings) {
                    CGFloat width = CGRectGetWidth(view.frame);
                    CGFloat height = CGRectGetHeight(view.frame);
                    return width >= 32.0 && width <= 56.0 &&
                           height >= 40.0 && height <= 56.0;
                }]];
        slots = [slots sortedArrayUsingComparator:
            ^NSComparisonResult(UIView *left, UIView *right) {
                CGFloat leftX = CGRectGetMinX(left.frame);
                CGFloat rightX = CGRectGetMinX(right.frame);
                if (leftX < rightX) return NSOrderedAscending;
                if (leftX > rightX) return NSOrderedDescending;
                return NSOrderedSame;
            }];
        if (slots.count < 3) {
            objc_setAssociatedObject(strongGroup,
                                     YTKACEActionGroupCompactAssociation,
                                     nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        CGFloat cursor = CGRectGetMinX(slots.firstObject.frame);
        for (UIView *slot in slots) {
            if (slot.hidden || slot.alpha <= 0.01) continue;
            CGRect frame = slot.frame;
            frame.origin.x = cursor;
            slot.frame = frame;
            cursor += CGRectGetWidth(frame);
        }
        objc_setAssociatedObject(strongGroup,
                                 YTKACEActionGroupCompactAssociation,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

static NSArray *YTKACEFilterActionButtons(id receiver, SEL selector,
                                           IMP original) {
    NSArray *items = original == NULL ? nil :
        ((id (*)(id, SEL))original)(receiver, selector);
    if (![items isKindOfClass:NSArray.class] || items.count == 0) return items;
    if (!YTKACEAnyActionPreferenceEnabled()) return items;
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        NSString *preference = YTKACEActionPreference(item);
        if (preference.length != 0 && YTKACEFeatureEnabled(preference)) continue;
        [filtered addObject:item];
    }
    return filtered.count == items.count ? items : filtered;
}

static NSString *YTKACEActionViewText(UIView *view) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:view];
    NSUInteger visited = 0;
    while (pending.count != 0 && visited < 80) {
        UIView *candidate = pending.firstObject;
        [pending removeObjectAtIndex:0];
        visited++;
        NSString *identifier = candidate.accessibilityIdentifier;
        NSString *label = candidate.accessibilityLabel;
        NSString *text = [candidate isKindOfClass:UILabel.class]
            ? ((UILabel *)candidate).text : nil;
        if (identifier.length != 0) [parts addObject:[@"id=" stringByAppendingString:identifier]];
        if (label.length != 0) [parts addObject:[@"label=" stringByAppendingString:label]];
        if (text.length != 0) [parts addObject:[@"text=" stringByAppendingString:text]];
        [pending addObjectsFromArray:candidate.subviews];
    }
    return [parts componentsJoinedByString:@" | "];
}


static void YTKACEActionViewDidMove(UIView *receiver, SEL selector) {
    if (OriginalActionViewDidMove != NULL) {
        ((void (*)(id, SEL))OriginalActionViewDidMove)(receiver, selector);
    }
}

static void YTKACEActionsViewDidMove(UIView *receiver, SEL selector) {
    if (OriginalActionsViewDidMove != NULL) {
        ((void (*)(id, SEL))OriginalActionsViewDidMove)(receiver, selector);
    }
}

static void YTKACEActionCellDidMove(UIView *receiver, SEL selector) {
    if (OriginalActionCellDidMove != NULL) {
        ((void (*)(id, SEL))OriginalActionCellDidMove)(receiver, selector);
    }
}

#define YTKACE_ACTION_WRAPPER(name, storage) \
static NSArray *name(id receiver, SEL selector) { \
    return YTKACEFilterActionButtons(receiver, selector, storage); \
}

YTKACE_ACTION_WRAPPER(YTKACEScrollableActionButtonsArray, OriginalScrollableActionButtonsArray)
YTKACE_ACTION_WRAPPER(YTKACEScrollableActionBarButtonsArray, OriginalScrollableActionBarButtonsArray)
YTKACE_ACTION_WRAPPER(YTKACEScrollableButtonsArray, OriginalScrollableButtonsArray)
YTKACE_ACTION_WRAPPER(YTKACEScrollableActionsArray, OriginalScrollableActionsArray)
YTKACE_ACTION_WRAPPER(YTKACEActionButtonsArray, OriginalActionButtonsArray)
YTKACE_ACTION_WRAPPER(YTKACEActionBarButtonsArray, OriginalActionBarButtonsArray)
YTKACE_ACTION_WRAPPER(YTKACEButtonsArray, OriginalButtonsArray)
YTKACE_ACTION_WRAPPER(YTKACEActionsArray, OriginalActionsArray)

static id YTKACEContentValue(id object, NSString *key) {
    if (object == nil || key.length == 0) {
        return nil;
    }
    @try {
        SEL selector = NSSelectorFromString(key);
        if ([object respondsToSelector:selector]) {
            return ((id (*)(id, SEL))objc_msgSend)(object, selector);
        }
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL YTKACEItemIsShorts(id item) {
    NSString *description = [[[item description] lowercaseString]
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    return YTKACEContentContains(description, @[
        @"shorts_shelf_eml", @"shorts_shelf", @"reel_shelf",
        @"shorts_lockup_shelf", @"shortsshelfrenderer", @"reelshelfrenderer",
        @"shortslockupviewmodel", @"shorts_video_cell", @"reelitemrenderer",
        @"shortslockup"
    ]);
}

static BOOL YTKACESectionIsShortsShelf(id section) {
    if (section == nil) {
        return NO;
    }

    NSArray *entries = YTKACEContentValue(section, @"contentsArray");
    if ([entries isKindOfClass:NSArray.class] && entries.count != 0) {
        for (id entry in entries) {
            if (!YTKACEItemIsShorts(entry)) {
                return NO;
            }
        }
        return YES;
    }

    NSString *description = [[[section description] lowercaseString]
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    if (YTKACEContentContains(description, @[
        @"shorts_shelf_eml", @"shorts_shelf", @"reel_shelf",
        @"shorts_lockup_shelf", @"shortsshelfrenderer",
        @"reelshelfrenderer", @"shortslockupviewmodel"
    ])) {
        return YES;
    }
    NSString *className = NSStringFromClass([section class]).lowercaseString;
    if (![className containsString:@"shelfrenderer"] &&
        ![className containsString:@"richsectionrenderer"]) {
        return NO;
    }
    id content = YTKACEContentValue(section, @"content");
    id list = YTKACEContentValue(content, @"horizontalListRenderer") ?:
        YTKACEContentValue(content, @"richShelfRenderer") ?:
        content;
    NSArray *items = YTKACEContentValue(list, @"itemsArray") ?:
        YTKACEContentValue(list, @"contentsArray");
    for (id item in items) {
        NSString *itemDescription = [[item description] lowercaseString];
        if (YTKACEContentContains(itemDescription, @[
            @"shorts_video_cell", @"reelitemrenderer", @"shortslockup"
        ])) {
            return YES;
        }
    }
    return NO;
}

static NSArray<NSString *> *YTKACEProductsMarkers(void) {
    return @[
        @"merchandise_shelf", @"merchandise_item",
        @"product_shelf", @"products_shelf", @"shopping_shelf",
        @"promoted_sparkles_text_product_watch",
        @"product_in_video", @"products_in_video"
    ];
}

static BOOL YTKACESectionIsProductsShelf(id section) {
    if (section == nil) {
        return NO;
    }
    NSArray *markers = YTKACEProductsMarkers();

    NSArray *entries = YTKACEContentValue(section, @"contentsArray");
    if ([entries isKindOfClass:NSArray.class] && entries.count != 0) {
        for (id entry in entries) {
            NSString *entryDescription = [[[entry description] lowercaseString]
                stringByReplacingOccurrencesOfString:@"." withString:@"_"];
            if (YTKACEContentContains(entryDescription, markers)) {
                return YES;
            }
        }
        return NO;
    }

    NSString *description = [[[section description] lowercaseString]
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    if (YTKACEContentContains(description, markers)) {
        return YES;
    }
    NSString *className = NSStringFromClass([section class]).lowercaseString;
    if (![className containsString:@"shelfrenderer"] &&
        ![className containsString:@"richsectionrenderer"]) {
        return NO;
    }
    id content = YTKACEContentValue(section, @"content");
    id list = YTKACEContentValue(content, @"horizontalListRenderer") ?:
        YTKACEContentValue(content, @"richShelfRenderer") ?:
        YTKACEContentValue(content, @"shelfRenderer") ?:
        content;
    NSArray *items = YTKACEContentValue(list, @"itemsArray") ?:
        YTKACEContentValue(list, @"contentsArray");
    for (id item in items) {
        NSString *itemDescription = [[[item description] lowercaseString]
            stringByReplacingOccurrencesOfString:@"." withString:@"_"];
        if (YTKACEContentContains(itemDescription, markers)) {
            return YES;
        }
    }
    return NO;
}

static NSString *YTKACESectionToken(id section) {
    if (section == nil) return @"";
    NSMutableString *token = [NSMutableString stringWithFormat:@"%@ %@",
        NSStringFromClass([section class]), [section description] ?: @""];
    NSArray *entries = YTKACEContentValue(section, @"contentsArray");
    if ([entries isKindOfClass:NSArray.class]) {
        for (id entry in entries) {
            [token appendFormat:@" %@ %@", NSStringFromClass([entry class]),
                                                [entry description] ?: @""];
        }
    }
    id content = YTKACEContentValue(section, @"content");
    id list = YTKACEContentValue(content, @"horizontalListRenderer") ?:
        YTKACEContentValue(content, @"richShelfRenderer") ?:
        YTKACEContentValue(content, @"shelfRenderer") ?:
        content;
    NSArray *items = YTKACEContentValue(list, @"itemsArray") ?:
        YTKACEContentValue(list, @"contentsArray");
    if ([items isKindOfClass:NSArray.class]) {
        for (id item in items) {
            [token appendFormat:@" %@ %@", NSStringFromClass([item class]),
                                               [item description] ?: @""];
        }
    }
    return [[token lowercaseString]
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
}

static BOOL YTKACESectionIsCommunityPosts(id section) {
    return YTKACEContentContains(YTKACESectionToken(section), @[
        @"id_ui_backstage_original_post",
        @"communitypostsectionrenderer", @"community_post_section",
        @"postscontainerrenderer", @"communitypostrenderer",
        @"backstagepostrenderer", @"community_post"
    ]);
}

static BOOL YTKACESectionIsMix(id section) {
    return YTKACEContentContains(YTKACESectionToken(section), @[
        @"feed_nudge_view",
        @"automixpreviewvideorenderer", @"automixplaylistvideorenderer",
        @"mixradiorenderer", @"radioautomixplaylistid",
        @"radioplaylistmixplaylistid", @"radio_playlist_mix"
    ]);
}

static BOOL YTKACESectionIsPlayable(id section) {
    return YTKACEContentContains(YTKACESectionToken(section), @[
        @"playables_shelf", @"playablesshelfrenderer",
        @"playableitemrenderer", @"playable_game",
        @"compactboxgamerenderer"
    ]);
}

static NSArray *YTKACEFilteredFeedSections(NSArray *sections) {
    NSArray *adFiltered = YTKACEFilterAdSections(sections);
    BOOL hideShorts = YTKACEFeatureEnabled(@"YTKACE.Preference.Shorts.FeedHidden");
    BOOL hideProducts = YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.ProductsHidden");
    BOOL hideCommunity = YTKACEFeatureEnabled(
        @"YTKACE.Preference.Feed.CommunityPostsHidden");
    BOOL hideMixes = YTKACEFeatureEnabled(
        @"YTKACE.Preference.Feed.MixesHidden");
    BOOL hidePlayables = YTKACEFeatureEnabled(
        @"YTKACE.Preference.Feed.PlayablesHidden");
    if ((!hideShorts && !hideProducts && !hideCommunity &&
         !hideMixes && !hidePlayables) ||
        ![adFiltered isKindOfClass:NSArray.class]) {
        return adFiltered;
    }
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:adFiltered.count];
    for (id section in adFiltered) {
        if (hideShorts && YTKACESectionIsShortsShelf(section)) continue;
        if (hideProducts && YTKACESectionIsProductsShelf(section)) continue;
        if (hideCommunity && YTKACESectionIsCommunityPosts(section)) continue;
        if (hideMixes && YTKACESectionIsMix(section)) continue;
        if (hidePlayables && YTKACESectionIsPlayable(section)) continue;
        [filtered addObject:section];
    }
    return filtered;
}

static id YTKACESectionControllers(id receiver, SEL selector,
                                   NSArray *sections, id reloadMap) {
    if (OriginalSectionControllers == NULL) return nil;
    YTKACEEnsureStructuralActionHook();
    NSArray *filtered = YTKACEFilteredFeedSections(sections);
    return ((id (*)(id, SEL, id, id))OriginalSectionControllers)(
        receiver, selector, filtered, reloadMap);
}

static BOOL YTKACEContentContains(NSString *token,
                                  NSArray<NSString *> *needles) {
    for (NSString *needle in needles) {
        if ([token containsString:needle]) {
            return YES;
        }
    }
    return NO;
}

static BOOL YTKACEContentShouldHide(UIView *view, BOOL *hideSuperview) {
    NSString *identifier = [view.accessibilityIdentifier.lowercaseString
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSString *token = [NSString stringWithFormat:@"%@ %@ %@",
                       identifier ?: @"",
                       view.accessibilityLabel.lowercaseString ?: @"",
                       NSStringFromClass(view.class).lowercaseString];

    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.CommentsHidden")) {
        if ([identifier isEqualToString:@"id_comment_guidelines_text"]) {
            if (hideSuperview != NULL) {
                *hideSuperview = YES;
            }
            return YES;
        }
        if (YTKACEContentContains(token, @[
            @"id_ui_comments_composite_entry_point_teaser",
            @"id_ui_comments_entry_point_teaser",
            @"id_comment_channel_guidelines_bottom_sheet_container",
            @"id_comment_channel_guidelines_entry_banner_container"
        ])) {
            return YES;
        }
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.CommentPreviewsHidden") &&
        [identifier isEqualToString:@"id_ui_comments_entry_point_teaser"]) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.CommentGuidelinesHidden") &&
        YTKACEContentContains(token, @[
            @"id_comment_guidelines_text",
            @"id_comment_channel_guidelines_bottom_sheet_container",
            @"id_comment_channel_guidelines_entry_banner_container"
        ])) {
        if ([identifier isEqualToString:@"id_comment_guidelines_text"] &&
            hideSuperview != NULL) {
            *hideSuperview = YES;
        }
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Navigation.TopicsHidden") &&
        YTKACEContentContains(token, @[@"topic_chip", @"feed_filter", @"chip_cloud"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Privacy.SearchHistoryDisabled") &&
        YTKACEContentContains(token, @[@"search_history", @"history_suggestion"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden") &&
        YTKACEContentContains(token, @[@"paid_promotion", @"paidpromotion"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Ads.PremiumPromosHidden") &&
        YTKACEContentContains(token, @[@"premium_upsell", @"premium_promo"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.App.UpdatePromptHidden") &&
        YTKACEContentContains(token, @[@"update_dialog", @"upgrade_dialog"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.SuggestedVideosHidden") &&
        YTKACEContentContains(token, @[@"suggested_video", @"related_video"])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.RelatedVideosHidden") &&
        YTKACEContentContains(token, @[
            @"related_video", @"relatedvideo", @"more_videos", @"watch_next"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.ContinueWatchingDisabled") &&
        YTKACEContentContains(token, @[
            @"continue_watching", @"continuewatching", @"resume_watching"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Shorts.PauseCardHidden") &&
        YTKACEContentContains(token, @[
            @"shorts_pause", @"reel_pause", @"pause_card", @"pausecard",
            @"paused_state_carousel", @"reelpausedstatecarousel"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.ProductsHidden") &&
        YTKACEContentContains(token, @[
            @"shorts_product", @"product_sticker", @"shopping_carousel",
            @"shopping_destination", @"tagged_product", @"creator_product"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Shorts.StickerAdsHidden") &&
        YTKACEContentContains(token, @[
            @"brand_link_sticker", @"product_sticker", @"promoted_sticker",
            @"sponsored_sticker", @"shorts_ads_shopping"
        ])) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.ProductsHidden") &&
        YTKACEContentContains(token, YTKACEProductsMarkers())) {
        return YES;
    }
    if (YTKACEFeatureEnabled(
            @"YTKACE.Preference.Feed.CommunityPostsHidden") &&
        [identifier isEqualToString:@"id_ui_backstage_original_post"]) {
        return YES;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Feed.MixesHidden") &&
        [identifier isEqualToString:@"feed_nudge_view"]) {
        return YES;
    }
    return NO;
}

static void YTKACEApplyContentVisibility(UIView *view) {
    NSString *actionPreference = YTKACEAnyActionPreferenceEnabled()
        ? YTKACEActionPreferenceForView(view) : nil;
    if (actionPreference.length != 0) {
        YTKACEEnsureStructuralActionHook();
        UIView *target = YTKACEActionContainer(view);
        BOOL hidden = YTKACEFeatureEnabled(actionPreference);
        NSNumber *baseline = objc_getAssociatedObject(
            target,
            YTKACEContentHiddenAssociation
        );
        if (hidden) {
            if (baseline == nil) {
                objc_setAssociatedObject(target,
                                         YTKACEContentHiddenAssociation,
                                         @(target.hidden),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            target.hidden = YES;
            target.userInteractionEnabled = NO;
            YTKACERefreshActionCollection(view);
        } else if (baseline != nil) {
            target.hidden = baseline.boolValue;
            target.userInteractionEnabled = YES;
            objc_setAssociatedObject(target,
                                     YTKACEContentHiddenAssociation,
                                     nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        YTKACECompactFixedActionGroup(target);
        return;
    }

    BOOL hideSuperview = NO;
    BOOL hidden = YTKACEContentShouldHide(view, &hideSuperview);

    UIView *target = hideSuperview ? view.superview : view;
    if (target == nil) {
        return;
    }

    NSNumber *baseline = objc_getAssociatedObject(
        target,
        YTKACEContentHiddenAssociation
    );
    if (hidden) {
        if (baseline == nil) {
            objc_setAssociatedObject(target,
                                     YTKACEContentHiddenAssociation,
                                     @(target.hidden),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        target.hidden = YES;
        target.userInteractionEnabled = NO;
    } else if (baseline != nil) {
        target.hidden = baseline.boolValue;
        target.userInteractionEnabled = YES;
        objc_setAssociatedObject(target,
                                 YTKACEContentHiddenAssociation,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void YTKACEDisplayViewDidMove(UIView *receiver, SEL selector) {
    if (OriginalDisplayViewDidMove != NULL) {
        ((void (*)(id, SEL))OriginalDisplayViewDidMove)(receiver, selector);
    }
    YTKACEApplyContentVisibility(receiver);
    YTKACEHandleAdDisplayView(receiver);
}

static void YTKACEDisplayViewSetIdentifier(UIView *receiver,
                                           SEL selector,
                                           NSString *identifier) {
    if (OriginalDisplayViewSetIdentifier != NULL) {
        ((void (*)(id, SEL, id))OriginalDisplayViewSetIdentifier)(
            receiver,
            selector,
            identifier
        );
    }
    YTKACEApplyContentVisibility(receiver);
    YTKACEHandleAdDisplayView(receiver);
}

static BOOL YTKACEHideTopics(void) {
    return YTKACEFeatureEnabled(@"YTKACE.Preference.Navigation.TopicsHidden");
}

static void YTKACECollapseSubheader(id receiver) {
    SEL height = NSSelectorFromString(@"setMaximumSubheaderHeight:");
    if ([receiver respondsToSelector:height]) {
        ((void (*)(id, SEL, double))objc_msgSend)(receiver, height, 0.0);
    }
    for (NSString *name in @[@"hideSubheaderBar", @"disableSubheaderBar",
                             @"setSubheaderHeightToZero",
                             @"resetScrollViewInsetOffset"]) {
        SEL selector = NSSelectorFromString(name);
        if ([receiver respondsToSelector:selector]) {
            ((void (*)(id, SEL))objc_msgSend)(receiver, selector);
        }
    }
    SEL enabled = NSSelectorFromString(@"setSubheaderBarEnabled:");
    if ([receiver respondsToSelector:enabled]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(receiver, enabled, NO);
    }
}

static double YTKACEMaximumSubheaderHeightGetter(id receiver, SEL selector) {
    if (YTKACEHideTopics()) return 0.0;
    return OriginalMaximumSubheaderHeightGetter == NULL
        ? 0.0
        : ((double (*)(id, SEL))OriginalMaximumSubheaderHeightGetter)(
            receiver, selector);
}

static double YTKACESubheaderDefaultHeight(id receiver, SEL selector) {
    if (YTKACEHideTopics()) return 0.0;
    return OriginalSubheaderDefaultHeight == NULL
        ? 0.0
        : ((double (*)(id, SEL))OriginalSubheaderDefaultHeight)(
            receiver, selector);
}

static void YTKACEPaidContentLayout(UIView *receiver, SEL selector) {
    if (OriginalPaidContentLayout != NULL) {
        ((void (*)(id, SEL))OriginalPaidContentLayout)(receiver, selector);
    }
    BOOL hide = YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden");
    NSNumber *baseline = objc_getAssociatedObject(
        receiver, YTKACEContentHiddenAssociation);
    if (hide) {
        if (baseline == nil) {
            objc_setAssociatedObject(receiver,
                                     YTKACEContentHiddenAssociation,
                                     @(receiver.hidden),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        receiver.hidden = YES;
        receiver.userInteractionEnabled = NO;
    } else if (baseline != nil) {
        receiver.hidden = baseline.boolValue;
        receiver.userInteractionEnabled = YES;
        objc_setAssociatedObject(receiver,
                                 YTKACEContentHiddenAssociation,
                                 nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void YTKACEPaidContentDidAppear(UIViewController *receiver,
                                       SEL selector,
                                       BOOL animated) {
    if (OriginalPaidContentDidAppear != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalPaidContentDidAppear)(
            receiver, selector, animated);
    }
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden")) return;
    receiver.view.hidden = YES;
    receiver.view.userInteractionEnabled = NO;
    for (NSString *name in @[@"hidePaidContent",
                             @"removePaidContentViewController"]) {
        SEL action = NSSelectorFromString(name);
        if ([receiver respondsToSelector:action]) {
            ((void (*)(id, SEL))objc_msgSend)(receiver, action);
        }
    }
}

static void YTKACEPaidContentPlaybackStarted(id receiver, SEL selector) {
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden") &&
        OriginalPaidContentPlaybackStarted != NULL) {
        ((void (*)(id, SEL))OriginalPaidContentPlaybackStarted)(receiver, selector);
    }
}

static void YTKACESetPaidContentPlayerData(id receiver, SEL selector, id data) {
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden") &&
        OriginalSetPaidContentPlayerData != NULL) {
        ((void (*)(id, SEL, id))OriginalSetPaidContentPlayerData)(
            receiver, selector, data);
    }
}

static void YTKACESetPaidContentRenderer(id receiver, SEL selector, id renderer) {
    if (OriginalSetPaidContentRenderer != NULL) {
        ((void (*)(id, SEL, id))OriginalSetPaidContentRenderer)(
            receiver, selector,
            YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden") ? nil : renderer);
    }
}

static BOOL YTKACEHasPaidContentOverlay(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden")) return NO;
    return OriginalHasPaidContentOverlay != NULL &&
        ((BOOL (*)(id, SEL))OriginalHasPaidContentOverlay)(receiver, selector);
}

static id YTKACEPaidContentOverlay(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden")) return nil;
    return OriginalPaidContentOverlay == NULL ? nil :
        ((id (*)(id, SEL))OriginalPaidContentOverlay)(receiver, selector);
}

static void YTKACEOverlayPaidContentPlayerData(id receiver, SEL selector, id data) {
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden") &&
        OriginalOverlayPaidContentPlayerData != NULL) {
        ((void (*)(id, SEL, id))OriginalOverlayPaidContentPlayerData)(
            receiver, selector, data);
    }
}

static void YTKACEInlinePaidContentPlayerData(id receiver, SEL selector, id data) {
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden") &&
        OriginalInlinePaidContentPlayerData != NULL) {
        ((void (*)(id, SEL, id))OriginalInlinePaidContentPlayerData)(
            receiver, selector, data);
    }
}

static void YTKACEDidInsertPlayerOverlay(id receiver, SEL selector,
                                         id provider, id overlay) {
    NSString *identifier = YTKACEContentValue(overlay, @"overlayIdentifier");
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.PaidPromotionHidden") &&
        [identifier isEqualToString:@"player_overlay_paid_content"]) {
        return;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Overlay.ProductsHidden") &&
        [identifier isEqualToString:@"player_overlay_product_in_video"]) {
        return;
    }
    if (OriginalDidInsertPlayerOverlay != NULL) {
        ((void (*)(id, SEL, id, id))OriginalDidInsertPlayerOverlay)(
            receiver, selector, provider, overlay);
    }
}

static void YTKACEEnableSubheaderBar(__unsafe_unretained id receiver, SEL selector,
                                     __unsafe_unretained id view) {
    BOOL hide = YTKACEHideTopics();
    if (hide) {
        YTKACECollapseSubheader(receiver);
        return;
    }
    if (OriginalEnableSubheaderBar != NULL) {
        ((void (*)(id, SEL, id))OriginalEnableSubheaderBar)(receiver, selector, view);
    }
}

static void YTKACEChipBarUpdate(__unsafe_unretained id receiver, SEL selector,
                                __unsafe_unretained id collectionViewController,
                                __unsafe_unretained id host,
                                __unsafe_unretained id renderer,
                                __unsafe_unretained id browseIdentifier,
                                __unsafe_unretained id sectionList) {
    BOOL hide = YTKACEHideTopics();
    if (hide) return;
    if (OriginalChipBarUpdate != NULL) {
        ((void (*)(id, SEL, id, id, id, id, id))OriginalChipBarUpdate)(
            receiver, selector, collectionViewController, host, renderer,
            browseIdentifier, sectionList);
    }
}

static void YTKACEChipCloudSetEntry(__unsafe_unretained id receiver, SEL selector,
                                    __unsafe_unretained id entry) {
    if (OriginalChipCloudSetEntry != NULL) {
        ((void (*)(id, SEL, id))OriginalChipCloudSetEntry)(receiver, selector, entry);
    }
    BOOL hide = YTKACEHideTopics();
    if (!hide) return;
    if ([receiver isKindOfClass:UIView.class]) {
        UIView *cell = (UIView *)receiver;
        cell.hidden = YES;
        cell.userInteractionEnabled = NO;
    }
}

static void YTKACEChipCloudLayout(__unsafe_unretained id receiver, SEL selector) {
    if (OriginalChipCloudLayout != NULL) {
        ((void (*)(id, SEL))OriginalChipCloudLayout)(receiver, selector);
    }
    BOOL hide = YTKACEHideTopics();
    if (!hide) return;
    if (![receiver isKindOfClass:UIView.class]) return;
    UIView *cell = (UIView *)receiver;
    cell.hidden = YES;
    cell.userInteractionEnabled = NO;
    CGRect frame = cell.frame;
    if (frame.size.height != 0.0) {
        frame.size.height = 0.0;
        cell.frame = frame;
    }
    for (UIView *subview in cell.subviews) {
        subview.hidden = YES;
    }
}

static void YTKACEFeedHeaderScrollMode(__unsafe_unretained id receiver, SEL selector,
                                       NSInteger mode) {
    if (OriginalFeedHeaderScrollMode != NULL) {
        ((void (*)(id, SEL, NSInteger))OriginalFeedHeaderScrollMode)(
            receiver, selector, mode);
    }
}

static void YTKACESubsSetChipFilterView(__unsafe_unretained id receiver, SEL selector,
                                        __unsafe_unretained id view) {
    BOOL hide = YTKACEHideTopics();
    if (hide) return;
    if (OriginalSubsSetChipFilterView != NULL) {
        ((void (*)(id, SEL, id))OriginalSubsSetChipFilterView)(receiver, selector, view);
    }
}

static void YTKACESubsChipFilter(__unsafe_unretained id receiver, SEL selector,
                                 __unsafe_unretained id model) {
    BOOL hide = YTKACEHideTopics();
    if (hide) return;
    if (OriginalSubsChipFilter != NULL) {
        ((void (*)(id, SEL, id))OriginalSubsChipFilter)(receiver, selector, model);
    }
}

static void YTKACEMaximumSubheaderHeight(__unsafe_unretained id receiver,
                                        SEL selector, double height) {
    BOOL hide = YTKACEHideTopics();
    if (hide) height = 0.0;
    if (OriginalMaximumSubheaderHeight != NULL) {
        ((void (*)(id, SEL, double))OriginalMaximumSubheaderHeight)(
            receiver, selector, height);
    }
}

static void YTKACESetHeaderHeights(id receiver, SEL selector,
                                    double headerHeight,
                                    double subheaderHeight,
                                    double topOffset,
                                    BOOL animated) {
    if (YTKACEHideTopics()) {
        subheaderHeight = 0.0;
    }
    if (OriginalSetHeaderHeights != NULL) {
        ((void (*)(id, SEL, double, double, double, BOOL))OriginalSetHeaderHeights)(
            receiver, selector, headerHeight, subheaderHeight, topOffset, animated);
    }
}

static BOOL YTKACEShouldHideSubheader(id receiver, SEL selector) {
    if (YTKACEHideTopics()) return YES;
    return OriginalShouldHideSubheader != NULL &&
        ((BOOL (*)(id, SEL))OriginalShouldHideSubheader)(receiver, selector);
}

static void YTKACEAddSections(id receiver, SEL selector, NSArray *sections) {
    if (OriginalAddSections != NULL) {
        YTKACEEnsureStructuralActionHook();
        NSArray *filtered = YTKACEFilteredFeedSections(sections);
        ((void (*)(id, SEL, id))OriginalAddSections)(
            receiver, selector, filtered);
    }
}

void YTKACEInstallContentVisibilityHooks(void) {
    __unused NSArray<NSNumber *> *actionHooks = @[
        @(YTKACEInstallInstanceHook(@"YTISlimVideoScrollableActionBarRenderer",
                                    @"actionButtonsArray",
                                    (IMP)YTKACEScrollableActionButtonsArray,
                                    &OriginalScrollableActionButtonsArray)),
        @(YTKACEInstallInstanceHook(@"YTISlimVideoScrollableActionBarRenderer",
                                    @"actionBarButtonsArray",
                                    (IMP)YTKACEScrollableActionBarButtonsArray,
                                    &OriginalScrollableActionBarButtonsArray)),
        @(YTKACEInstallInstanceHook(@"YTISlimVideoScrollableActionBarRenderer",
                                    @"buttonsArray",
                                    (IMP)YTKACEScrollableButtonsArray,
                                    &OriginalScrollableButtonsArray)),
        @(YTKACEInstallInstanceHook(@"YTISlimVideoScrollableActionBarRenderer",
                                    @"actionsArray",
                                    (IMP)YTKACEScrollableActionsArray,
                                    &OriginalScrollableActionsArray)),
        @(YTKACEInstallInstanceHook(@"YTISlimVideoActionBarRenderer",
                                    @"actionButtonsArray",
                                    (IMP)YTKACEActionButtonsArray,
                                    &OriginalActionButtonsArray)),
        @(YTKACEInstallInstanceHook(@"YTISlimVideoActionBarRenderer",
                                    @"actionBarButtonsArray",
                                    (IMP)YTKACEActionBarButtonsArray,
                                    &OriginalActionBarButtonsArray)),
        @(YTKACEInstallInstanceHook(@"YTISlimVideoActionBarRenderer",
                                    @"buttonsArray",
                                    (IMP)YTKACEButtonsArray,
                                    &OriginalButtonsArray)),
        @(YTKACEInstallInstanceHook(@"YTISlimVideoActionBarRenderer",
                                    @"actionsArray",
                                    (IMP)YTKACEActionsArray,
                                    &OriginalActionsArray))
    ];
    YTKACEInstallInstanceHook(@"YTSlimVideoDetailsActionView",
                              @"didMoveToWindow",
                              (IMP)YTKACEActionViewDidMove,
                              &OriginalActionViewDidMove);
    YTKACEEnsureStructuralActionHook();
    YTKACEEnsureActionCellControllerHooks();
    YTKACEEnsureActionCollectionLayoutHook();
    YTKACEScheduleStructuralActionHook();
    YTKACEInstallInstanceHook(@"YTSlimVideoScrollableDetailsActionsView",
                              @"didMoveToWindow",
                              (IMP)YTKACEActionsViewDidMove,
                              &OriginalActionsViewDidMove);
    YTKACEInstallInstanceHook(@"YTSlimVideoScrollableActionBarCell",
                              @"didMoveToWindow",
                              (IMP)YTKACEActionCellDidMove,
                              &OriginalActionCellDidMove);
    YTKACEInstallInstanceHook(@"_ASDisplayView",
                              @"didMoveToWindow",
                              (IMP)YTKACEDisplayViewDidMove,
                              &OriginalDisplayViewDidMove);
    YTKACEInstallInstanceHook(@"_ASDisplayView",
                              @"setAccessibilityIdentifier:",
                              (IMP)YTKACEDisplayViewSetIdentifier,
                              &OriginalDisplayViewSetIdentifier);
    YTKACEInstallInstanceHook(@"YTInnerTubeCollectionViewController",
                              @"addSectionsFromArray:",
                              (IMP)YTKACEAddSections,
                              &OriginalAddSections);
    YTKACEInstallInstanceHook(@"YTInnerTubeCollectionViewController",
                              @"sectionControllersForSectionRenderers:reloadingSectionControllerByRenderer:",
                              (IMP)YTKACESectionControllers,
                              &OriginalSectionControllers);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"enableSubheaderBarWithView:",
                              (IMP)YTKACEEnableSubheaderBar,
                              &OriginalEnableSubheaderBar);
    YTKACEInstallInstanceHook(@"YTFeedFilterChipBarController",
                              @"updateWithCollectionViewController:feedFilterChipBarHost:feedFilterChipBarRenderer:browseIdentifier:sectionList:",
                              (IMP)YTKACEChipBarUpdate,
                              &OriginalChipBarUpdate);
    YTKACEInstallInstanceHook(@"YTChipCloudCell",
                              @"setEntry:",
                              (IMP)YTKACEChipCloudSetEntry,
                              &OriginalChipCloudSetEntry);
    YTKACEInstallInstanceHook(@"YTMySubsFilterHeaderViewController",
                              @"loadChipFilterFromModel:",
                              (IMP)YTKACESubsChipFilter,
                              &OriginalSubsChipFilter);
    YTKACEInstallInstanceHook(@"YTChipCloudCell",
                              @"layoutSubviews",
                              (IMP)YTKACEChipCloudLayout,
                              &OriginalChipCloudLayout);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"setFeedHeaderScrollMode:",
                              (IMP)YTKACEFeedHeaderScrollMode,
                              &OriginalFeedHeaderScrollMode);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"setMaximumSubheaderHeight:",
                              (IMP)YTKACEMaximumSubheaderHeight,
                              &OriginalMaximumSubheaderHeight);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"maximumSubheaderHeight",
                              (IMP)YTKACEMaximumSubheaderHeightGetter,
                              &OriginalMaximumSubheaderHeightGetter);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"subheaderDefaultHeight",
                              (IMP)YTKACESubheaderDefaultHeight,
                              &OriginalSubheaderDefaultHeight);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"setHeaderHeight:subheaderHeight:topOffset:animated:",
                              (IMP)YTKACESetHeaderHeights,
                              &OriginalSetHeaderHeights);
    YTKACEInstallInstanceHook(@"YTHeaderContentComboView",
                              @"shouldHideSubHeader",
                              (IMP)YTKACEShouldHideSubheader,
                              &OriginalShouldHideSubheader);
    YTKACEInstallInstanceHook(@"YTMySubsFilterHeaderView",
                              @"setChipFilterView:",
                              (IMP)YTKACESubsSetChipFilterView,
                              &OriginalSubsSetChipFilterView);
    YTKACEInstallInstanceHook(@"YTPaidContentOverlayView",
                              @"layoutSubviews",
                              (IMP)YTKACEPaidContentLayout,
                              &OriginalPaidContentLayout);
    YTKACEInstallInstanceHook(@"YTPaidContentViewController",
                              @"viewDidAppear:",
                              (IMP)YTKACEPaidContentDidAppear,
                              &OriginalPaidContentDidAppear);
    YTKACEInstallInstanceHook(@"YTPaidContentController",
                              @"playbackDidStart",
                              (IMP)YTKACEPaidContentPlaybackStarted,
                              &OriginalPaidContentPlaybackStarted);
    YTKACEInstallInstanceHook(@"YTPaidContentController",
                              @"setPaidContentWithPlayerData:",
                              (IMP)YTKACESetPaidContentPlayerData,
                              &OriginalSetPaidContentPlayerData);
    YTKACEInstallInstanceHook(@"YTPaidContentViewController",
                              @"setPaidContentRenderer:",
                              (IMP)YTKACESetPaidContentRenderer,
                              &OriginalSetPaidContentRenderer);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse",
                              @"hasPaidContentOverlay",
                              (IMP)YTKACEHasPaidContentOverlay,
                              &OriginalHasPaidContentOverlay);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse",
                              @"paidContentOverlay",
                              (IMP)YTKACEPaidContentOverlay,
                              &OriginalPaidContentOverlay);
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayViewController",
                              @"setPaidContentWithPlayerData:",
                              (IMP)YTKACEOverlayPaidContentPlayerData,
                              &OriginalOverlayPaidContentPlayerData);
    YTKACEInstallInstanceHook(@"YTInlineMutedPlaybackPlayerOverlayViewController",
                              @"setPaidContentWithPlayerData:",
                              (IMP)YTKACEInlinePaidContentPlayerData,
                              &OriginalInlinePaidContentPlayerData);
    YTKACEInstallInstanceHook(@"YTMainAppVideoPlayerOverlayViewController",
                              @"playerOverlayProvider:didInsertPlayerOverlay:",
                              (IMP)YTKACEDidInsertPlayerOverlay,
                              &OriginalDidInsertPlayerOverlay);
}

#import "YTKACESettingsPages.h"
#import "YTKACERootOptionsController.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/Localization.h"
#import "../UI/Assets.h"
#import "../UI/Notice.h"
#import "../Features/SponsorBlock/SponsorPreferences.h"
#import "../Features/SponsorBlock/DeArrow.h"

#import <objc/runtime.h>
#import <objc/message.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

typedef UIViewController * _Nonnull (^YTKACEControllerBuilder)(void);
typedef void (^YTKACEAction)(UIViewController *controller);

static const void *YTKACEItemAssociation = &YTKACEItemAssociation;
static const void *YTKACEValueLabelAssociation = &YTKACEValueLabelAssociation;

static NSArray<NSString *> *YTKACELocalizedList(NSArray<NSString *> *titles) {
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:titles.count];
    for (NSString *title in titles) {
        [out addObject:YTKACELocalized(title)];
    }
    return out;
}

static NSDictionary *YTKACEToggle(NSString *title,
                                   NSString *key,
                                   NSString *asset,
                                   NSString *symbol) {
    return @{
        @"type": @"toggle",
        @"title": YTKACELocalized(title),
        @"key": key,
        @"asset": asset ?: @"",
        @"symbol": symbol ?: @""
    };
}

static NSDictionary *YTKACEToggleDetail(NSString *title,
                                         NSString *subtitle,
                                         NSString *key) {
    return @{
        @"type": @"toggle",
        @"title": YTKACELocalized(title),
        @"subtitle": YTKACELocalized(subtitle ?: @""),
        @"key": key,
        @"asset": @"",
        @"symbol": @""
    };
}

static NSDictionary *YTKACEPicker(NSString *title,
                                   NSString *key,
                                   NSArray<NSString *> *titles,
                                   NSArray *values,
                                   NSUInteger defaultIndex,
                                   NSString *asset,
                                   NSString *symbol) {
    return @{
        @"type": @"picker",
        @"title": YTKACELocalized(title),
        @"key": key,
        @"titles": YTKACELocalizedList(titles),
        @"values": values,
        @"default": @(defaultIndex),
        @"asset": asset ?: @"",
        @"symbol": symbol ?: @""
    };
}

static NSDictionary *YTKACEStepper(NSString *title,
                                    NSString *key,
                                    double minimum,
                                    double maximum,
                                    double step,
                                    double fallback) {
    return @{
        @"type": @"stepper",
        @"title": YTKACELocalized(title),
        @"key": key,
        @"minimum": @(minimum),
        @"maximum": @(maximum),
        @"step": @(step),
        @"fallback": @(fallback)
    };
}

static NSDictionary *YTKACESegmentedStacked(NSString *title,
                                            NSString *key,
                                            NSArray<NSString *> *titles,
                                            NSArray *values,
                                            NSUInteger defaultIndex) {
    return @{
        @"type": @"segmented",
        @"stacked": @YES,
        @"title": YTKACELocalized(title),
        @"key": key,
        @"titles": YTKACELocalizedList(titles),
        @"values": values,
        @"default": @(defaultIndex)
    };
}

static NSDictionary *YTKACESlider(NSString *title,
                                   NSString *key,
                                   double minimum,
                                   double maximum,
                                   double step,
                                   double fallback) {
    return @{
        @"type": @"slider",
        @"title": YTKACELocalized(title),
        @"key": key,
        @"minimum": @(minimum),
        @"maximum": @(maximum),
        @"step": @(step),
        @"fallback": @(fallback)
    };
}

static const void *YTKACESliderAssociation = &YTKACESliderAssociation;

static NSDictionary *YTKACESpeedSlider(NSString *title,
                                       NSString *key,
                                       double minimum,
                                       double maximum,
                                       double step,
                                       double fallback) {
    NSMutableDictionary *item =
        [YTKACESlider(title, key, minimum, maximum, step, fallback) mutableCopy];
    item[@"unit"] = @"speed";
    item[@"stacked"] = @YES;
    return item;
}

static NSDictionary *YTKACEPercentSlider(NSString *title,
                                         NSString *key,
                                         double minimum,
                                         double maximum,
                                         double step,
                                         double fallback) {
    NSMutableDictionary *item =
        [YTKACESlider(title, key, minimum, maximum, step, fallback) mutableCopy];
    item[@"unit"] = @"percent";
    item[@"stacked"] = @YES;
    return item;
}

static UIButton *YTKACESliderStepButton(NSString *symbol,
                                        NSInteger tag,
                                        id target,
                                        SEL action,
                                        UISlider *slider) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = tag;
    button.tintColor = YTKACEAccentColor();
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:14.0
                                                        weight:UIImageSymbolWeightSemibold];
    [button setImage:[UIImage systemImageNamed:symbol withConfiguration:configuration]
            forState:UIControlStateNormal];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    objc_setAssociatedObject(button, YTKACESliderAssociation, slider,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

static NSString *YTKACESliderValueText(NSDictionary *item, double value) {
    if ([item[@"unit"] isEqualToString:@"percent"]) {
        return [NSString stringWithFormat:@"%.0f%%", value];
    }
    if (![item[@"unit"] isEqualToString:@"speed"]) {
        return [NSString stringWithFormat:YTKACELocalized(@"%@ seconds"),
                [NSString stringWithFormat:@"%.0f", value]];
    }
    if (fabs(value - round(value)) < 0.001) {
        return [NSString stringWithFormat:@"%.0fx", value];
    }
    if (fabs(value * 10.0 - round(value * 10.0)) < 0.001) {
        return [NSString stringWithFormat:@"%.1fx", value];
    }
    return [NSString stringWithFormat:@"%.2fx", value];
}

static NSDictionary *YTKACEColor(NSString *title,
                                 NSString *key,
                                 NSString *fallback) {
    return @{
        @"type": @"color",
        @"title": YTKACELocalized(title),
        @"key": key,
        @"fallback": fallback
    };
}

static NSString *YTKACEHexFromColor(UIColor *color) {
    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;
    if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) return @"#00D400";
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)lround(red * 255.0), (int)lround(green * 255.0),
            (int)lround(blue * 255.0)];
}

static UIColor *YTKACEColorFromHex(NSString *hex) {
    NSString *value = [[hex ?: @"" stringByReplacingOccurrencesOfString:@"#"
                                                                withString:@""] uppercaseString];
    if (value.length != 6) return UIColor.systemGreenColor;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:value] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static NSDictionary *YTKACEActionDetail(NSString *title,
                                         NSString *subtitle,
                                         YTKACEAction action) {
    return @{
        @"type": @"action",
        @"title": YTKACELocalized(title),
        @"subtitle": YTKACELocalized(subtitle ?: @""),
        @"asset": @"",
        @"symbol": @"",
        @"action": [action copy]
    };
}

static UIColor *YTKACESettingsBackground(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return YTKACEInterfaceBackgroundColor(traits);
    }];
}

static UIColor *YTKACESettingsCellBackground(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return YTKACEInterfaceBackgroundColor(traits);
    }];
}

BOOL YTKACEPreferenceNeedsRestart(NSString *key) {
    return [@[
        YTKACEOLEDKey,
        @"YTKACE.Preference.Navigation.PremiumLogo",
        @"YTKACE.Preference.Navigation.LogoHidden",
        @"YTKACE.Preference.App.iPadLayout",
        @"YTKACE.Preference.App.RTLDisabled",
        @"YTKACE.Preference.Playback.LegacyQualityMenu",
        @"YTKACE.Preference.Navigation.StatusBarHidden",
        @"YTKACE.Preference.Tabs.Startup",
        @"YTKACE.Preference.Playback.Recovery",
        @"YTKACE.Preference.Playback.CaptionsAlwaysOn",
        @"YTKACE.Preference.Navigation.NotificationsHidden"
    ] containsObject:key];
}

void YTKACEShowRestartNotice(UIViewController *controller) {
    UIView *host = controller.navigationController.view ?: controller.view;
    UIView *old = [host viewWithTag:0x594B524E];
    [old removeFromSuperview];
    UILabel *notice = [UILabel new];
    notice.tag = 0x594B524E;
    notice.text = YTKACELocalized(@"Restart YouTube to apply changes.");
    notice.textColor = UIColor.labelColor;
    notice.backgroundColor = [UIColor colorWithWhite:0.72 alpha:0.96];
    notice.font = [UIFont systemFontOfSize:13.0];
    notice.layer.cornerRadius = 8.0;
    notice.layer.masksToBounds = YES;
    notice.textAlignment = NSTextAlignmentLeft;
    notice.translatesAutoresizingMaskIntoConstraints = NO;
    [host addSubview:notice];
    UILayoutGuide *safe = host.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [notice.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8.0],
        [notice.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8.0],
        [notice.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8.0],
        [notice.heightAnchor constraintEqualToConstant:48.0]
    ]];
    notice.alpha = 0.0;
    [UIView animateWithDuration:0.2 animations:^{ notice.alpha = 1.0; }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.2 animations:^{ notice.alpha = 0.0; }
                         completion:^(__unused BOOL finished) { [notice removeFromSuperview]; }];
    });
}

static void YTKACEStorePickerValue(NSString *key, id value, NSUInteger index) {
    YTKACESetPreferenceObject(key, value);
    if ([key isEqualToString:@"YTKACE.Preference.Tabs.Startup"]) {
        NSArray *browseIDs = @[@"FEwhat_to_watch", @"FEexplore", @"FEsubscriptions",
                               @"FEshorts", @"FElibrary"];
        if (index < browseIDs.count) {
            YTKACESetPreferenceObject(@"kStartupPageID", browseIDs[index]);
        }
    }
}

static UIImage *YTKACEBlankChoiceIcon(void) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(24.0, 24.0), NO, 0.0);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

void YTKACEPresentSelectionMenu(UIViewController *presenter,
                                UIView *sourceView,
                                NSString *title,
                                NSArray<NSString *> *titles,
                                NSUInteger selectedIndex,
                                YTKACEChoiceHandler handler) {
    (void)title;
    if (titles.count == 0) {
        return;
    }
    selectedIndex = MIN(selectedIndex, titles.count - 1);
    Class sheetClass = NSClassFromString(@"YTDefaultSheetController");
    Class actionClass = NSClassFromString(@"YTActionSheetAction");
    SEL makeSheet = NSSelectorFromString(
        @"sheetControllerWithMessage:subMessage:delegate:parentResponder:");
    SEL makeAction = NSSelectorFromString(@"actionWithTitle:iconImage:style:handler:");
    if (sheetClass != Nil && actionClass != Nil &&
        [sheetClass respondsToSelector:makeSheet] &&
        [actionClass respondsToSelector:makeAction]) {
        id sheet = ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(
            sheetClass, makeSheet, nil, nil, nil, nil);
        UIImage *check = [[UIImage systemImageNamed:@"checkmark"]
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIImage *blank = YTKACEBlankChoiceIcon();
        [titles enumerateObjectsUsingBlock:^(NSString *choice, NSUInteger index, BOOL *stop) {
            (void)stop;
            dispatch_block_t selection = ^{
                if (handler != nil) {
                    handler(index);
                }
            };
            id action = ((id (*)(id, SEL, id, id, NSInteger, id))objc_msgSend)(
                actionClass, makeAction, choice,
                index == selectedIndex ? check : blank, 0, selection);
            SEL addAction = NSSelectorFromString(@"addAction:");
            if ([sheet respondsToSelector:addAction]) {
                ((void (*)(id, SEL, id))objc_msgSend)(sheet, addAction, action);
            }
        }];
        if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad &&
            sourceView != nil &&
            [sheet respondsToSelector:NSSelectorFromString(@"presentFromView:animated:completion:")]) {
            ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(
                sheet, NSSelectorFromString(@"presentFromView:animated:completion:"),
                sourceView, YES, nil);
        } else if ([sheet respondsToSelector:
                    NSSelectorFromString(@"presentFromViewController:animated:completion:")]) {
            ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(
                sheet, NSSelectorFromString(@"presentFromViewController:animated:completion:"),
                presenter, YES, nil);
        }
        return;
    }
    YTKACEShowNotice(YTKACELocalized(@"YouTube menu unavailable"));
}

void YTKACEPresentChoiceMenu(UIViewController *presenter,
                             UIView *sourceView,
                             NSString *title,
                             NSArray<NSString *> *titles,
                             NSArray *values,
                             NSString *key,
                             NSUInteger defaultIndex,
                             YTKACEChoiceHandler handler) {
    id selected = YTKACEPreferenceObject(key);
    NSUInteger selectedIndex = [values indexOfObject:selected];
    if (selectedIndex == NSNotFound) {
        selectedIndex = MIN(defaultIndex, values.count - 1);
    }
    YTKACEPresentSelectionMenu(presenter, sourceView, title, titles, selectedIndex,
        ^(NSUInteger index) {
            YTKACEStorePickerValue(key, values[index], index);
            if (([key isEqualToString:@"YTKACE.Preference.Gestures.BrightnessSide"] ||
                 [key isEqualToString:@"YTKACE.Preference.Gestures.VolumeSide"]) && index < 2) {
                NSString *otherKey = [key isEqualToString:@"YTKACE.Preference.Gestures.BrightnessSide"]
                    ? @"YTKACE.Preference.Gestures.VolumeSide" : @"YTKACE.Preference.Gestures.BrightnessSide";
                id otherValue = YTKACEPreferenceObject(otherKey);
                NSInteger otherSide = otherValue == nil
                    ? ([otherKey isEqualToString:@"YTKACE.Preference.Gestures.BrightnessSide"] ? 1 : 0)
                    : [otherValue integerValue];
                if (otherSide == [values[index] integerValue] || otherSide == 3) {
                    YTKACEStorePickerValue(otherKey, @([values[index] integerValue] == 0),
                                           [values[index] integerValue] == 0 ? 1 : 0);
                }
            }
            if ([key isEqualToString:@"YTKACE.Preference.Gestures.VolumeSide"] &&
                [values[index] integerValue] == 3) {
                YTKACEStorePickerValue(@"YTKACE.Preference.Gestures.BrightnessSide", @2, 2);
            }
            if (handler != nil) handler(index);
        });
}

NSString *YTKACEPickerSummary(NSString *key,
                              NSArray<NSString *> *titles,
                              NSArray *values,
                              NSUInteger defaultIndex) {
    id selected = YTKACEPreferenceObject(key);
    NSUInteger index = [values indexOfObject:selected];
    if (index == NSNotFound || index >= titles.count) {
        index = MIN(defaultIndex, titles.count - 1);
    }
    return titles.count == 0 ? @"" : titles[index];
}

@interface YTKACEPickerController : UITableViewController
- (instancetype)initWithTitle:(NSString *)title
                           key:(NSString *)key
                        titles:(NSArray<NSString *> *)titles
                        values:(NSArray *)values
                  defaultIndex:(NSUInteger)defaultIndex;
@end

@implementation YTKACEPickerController {
    NSString *_preferenceKey;
    NSArray<NSString *> *_titles;
    NSArray *_values;
    NSUInteger _defaultIndex;
}

- (instancetype)initWithTitle:(NSString *)title
                           key:(NSString *)key
                        titles:(NSArray<NSString *> *)titles
                        values:(NSArray *)values
                  defaultIndex:(NSUInteger)defaultIndex {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self != nil) {
        self.title = title;
        _preferenceKey = [key copy];
        _titles = [titles copy];
        _values = [values copy];
        _defaultIndex = defaultIndex;
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (YTKACEOwnsNavigationController(self.navigationController)) {
        [self.navigationController setNavigationBarHidden:NO animated:NO];
    }
    YTKACEApplyAppearance(self);
    self.tableView.backgroundColor = YTKACESettingsBackground();
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)_titles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"YTKACEPickerCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:identifier];
    }
    id selected = YTKACEPreferenceObject(_preferenceKey);
    NSUInteger selectedIndex = [_values indexOfObject:selected];
    if (selectedIndex == NSNotFound) {
        selectedIndex = MIN(_defaultIndex, _values.count - 1);
    }
    cell.textLabel.text = _titles[(NSUInteger)indexPath.row];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.backgroundColor = YTKACESettingsCellBackground();
    cell.accessoryType = (NSUInteger)indexPath.row == selectedIndex
        ? UITableViewCellAccessoryCheckmark
        : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    id value = _values[(NSUInteger)indexPath.row];
    YTKACEStorePickerValue(_preferenceKey, value, (NSUInteger)indexPath.row);
    [tableView reloadData];
}

@end

@interface YTKACEOptionsController : UITableViewController
    <UIDocumentPickerDelegate, UIColorPickerViewControllerDelegate>
- (instancetype)initWithTitle:(NSString *)title
                      sections:(NSArray<NSArray<NSDictionary *> *> *)sections
                sectionTitles:(NSArray<NSString *> *)sectionTitles;
@end

@implementation YTKACEOptionsController {
    NSArray<NSArray<NSDictionary *> *> *_sections;
    NSArray<NSString *> *_sectionTitles;
    NSInteger _pickerMode;
    NSString *_importCategory;
    NSString *_colorKey;
    NSIndexPath *_colorPath;
    UIView *_backupOverlay;
    UILabel *_backupOverlayLabel;
    NSURL *_pendingBackupURL;
    BOOL _backupRunning;
    BOOL _restoreRunning;
}

- (instancetype)initWithTitle:(NSString *)title
                      sections:(NSArray<NSArray<NSDictionary *> *> *)sections
                sectionTitles:(NSArray<NSString *> *)sectionTitles {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self != nil) {
        self.title = title;
        _sections = [sections copy];
        _sectionTitles = [sectionTitles copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.rowHeight = 50.0;
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 0.0;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (YTKACEOwnsNavigationController(self.navigationController)) {
        [self.navigationController setNavigationBarHidden:NO animated:NO];
    }
    YTKACEApplyAppearance(self);
    self.tableView.backgroundColor = YTKACESettingsBackground();
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return (NSInteger)_sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)_sections[(NSUInteger)section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if ((NSUInteger)section >= _sectionTitles.count) {
        return nil;
    }
    NSString *title = _sectionTitles[(NSUInteger)section];
    return title.length == 0 ? nil : title;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    NSString *title = (NSUInteger)section < _sectionTitles.count
        ? _sectionTitles[(NSUInteger)section]
        : @"";
    return title.length == 0 ? 18.0 : 38.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    NSDictionary *item = _sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    NSString *type = item[@"type"];
    if ([type isEqualToString:@"text"]) {
        return 92.0;
    }
    if ([type isEqualToString:@"slider"]) {
        return [item[@"stacked"] boolValue] ? 78.0 : 58.0;
    }
    if ([type isEqualToString:@"segmented"] && [item[@"stacked"] boolValue]) {
        return 74.0;
    }
    return [item[@"subtitle"] length] == 0 ? 40.0 : 56.0;
}

- (void)tableView:(UITableView *)tableView
willDisplayHeaderView:(UIView *)view
        forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    if ([view isKindOfClass:UITableViewHeaderFooterView.class]) {
        UITableViewHeaderFooterView *header = (UITableViewHeaderFooterView *)view;
        header.textLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
        header.textLabel.textColor = UIColor.secondaryLabelColor;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = _sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    NSString *type = item[@"type"];
    UITableViewCellStyle style = [type isEqualToString:@"picker"]
        ? UITableViewCellStyleValue1
        : ([item[@"subtitle"] length] == 0 ? UITableViewCellStyleDefault : UITableViewCellStyleSubtitle);
    NSString *identifier = [NSString stringWithFormat:@"YTKACEOption-%ld", (long)style];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:identifier];
    }

    [[cell.contentView viewWithTag:8801] removeFromSuperview];
    [[cell.contentView viewWithTag:8802] removeFromSuperview];
    [[cell.contentView viewWithTag:8803] removeFromSuperview];

    cell.textLabel.text = item[@"title"];
    cell.detailTextLabel.text = item[@"subtitle"];
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    cell.textLabel.numberOfLines = 1;
    cell.detailTextLabel.numberOfLines = 2;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.backgroundColor = YTKACESettingsCellBackground();
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.imageView.image = nil;

    if ([type isEqualToString:@"toggle"]) {
        UISwitch *toggle = [UISwitch new];
        toggle.transform = CGAffineTransformMakeScale(0.95, 0.95);
        toggle.onTintColor = YTKACEAccentColor();
        id stored = YTKACEPreferenceObject(item[@"key"]);
        toggle.on = [stored respondsToSelector:@selector(boolValue)] && [stored boolValue];
        objc_setAssociatedObject(toggle,
                                 YTKACEItemAssociation,
                                 item,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [toggle addTarget:self
                   action:@selector(toggleChanged:)
         forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"segmented"]) {
        UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:item[@"titles"]];
        id selected = YTKACEPreferenceObject(item[@"key"]);
        NSUInteger selectedIndex = [item[@"values"] indexOfObject:selected];
        control.selectedSegmentIndex = selectedIndex == NSNotFound
            ? [item[@"default"] unsignedIntegerValue]
            : selectedIndex;
        objc_setAssociatedObject(control,
                                 YTKACEItemAssociation,
                                 item,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [control addTarget:self
                    action:@selector(segmentChanged:)
          forControlEvents:UIControlEventValueChanged];
        if ([item[@"stacked"] boolValue]) {
            UILabel *caption = [UILabel new];
            caption.tag = 8802;
            caption.text = item[@"title"];
            caption.font = [UIFont systemFontOfSize:16.0];
            caption.textColor = UIColor.labelColor;
            caption.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:caption];
            control.tag = 8801;
            control.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.contentView addSubview:control];
            UILayoutGuide *guide = cell.contentView.layoutMarginsGuide;
            [NSLayoutConstraint activateConstraints:@[
                [caption.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
                [caption.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
                [caption.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor
                                                  constant:8.0],
                [control.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
                [control.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
                [control.topAnchor constraintEqualToAnchor:caption.bottomAnchor
                                                  constant:8.0],
                [control.heightAnchor constraintEqualToConstant:30.0]
            ]];
            cell.textLabel.text = nil;
            cell.accessoryView = nil;
        } else {
            CGFloat width = MAX(128.0, [item[@"titles"] count] * 68.0);
            control.frame = CGRectMake(0.0, 0.0, width, 30.0);
            cell.accessoryView = control;
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"stepper"]) {
        double stored = [YTKACEPreferenceObject(item[@"key"]) doubleValue];
        double value = stored > 0.0 ? stored : [item[@"fallback"] doubleValue];
        cell.textLabel.text = [NSString stringWithFormat:YTKACELocalized(@"Seconds: %@"), [NSString stringWithFormat:@"%.0f", value]];
        UIStepper *stepper = [UIStepper new];
        stepper.tintColor = YTKACEAccentColor();
        stepper.minimumValue = [item[@"minimum"] doubleValue];
        stepper.maximumValue = [item[@"maximum"] doubleValue];
        stepper.stepValue = [item[@"step"] doubleValue];
        stepper.value = value;
        objc_setAssociatedObject(stepper,
                                 YTKACEItemAssociation,
                                 item,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(stepper,
                                 YTKACEValueLabelAssociation,
                                 cell,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [stepper addTarget:self
                    action:@selector(stepperChanged:)
          forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = stepper;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"slider"] && [item[@"stacked"] boolValue]) {
        double stored = [YTKACEPreferenceObject(item[@"key"]) doubleValue];
        double value = stored > 0.0 ? stored : [item[@"fallback"] doubleValue];

        UIView *container = [UIView new];
        container.tag = 8803;
        container.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:container];

        UILabel *caption = [UILabel new];
        caption.text = item[@"title"];
        caption.font = [UIFont systemFontOfSize:16.0];
        caption.textColor = UIColor.labelColor;
        caption.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:caption];

        UILabel *valueLabel = [UILabel new];
        valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:15.0
                                                           weight:UIFontWeightSemibold];
        valueLabel.textColor = YTKACEAccentColor();
        valueLabel.textAlignment = NSTextAlignmentRight;
        valueLabel.text = YTKACESliderValueText(item, value);
        valueLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [container addSubview:valueLabel];

        UISlider *slider = [UISlider new];
        slider.minimumTrackTintColor = YTKACEAccentColor();
        slider.minimumValue = [item[@"minimum"] floatValue];
        slider.maximumValue = [item[@"maximum"] floatValue];
        slider.value = (float)value;
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        objc_setAssociatedObject(slider, YTKACEItemAssociation, item,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(slider, YTKACEValueLabelAssociation, valueLabel,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [slider addTarget:self
                   action:@selector(sliderChanged:)
         forControlEvents:UIControlEventValueChanged];
        [container addSubview:slider];

        UIButton *minus = YTKACESliderStepButton(@"minus", 1, self,
                                                 @selector(sliderStepped:), slider);
        UIButton *plus = YTKACESliderStepButton(@"plus", 2, self,
                                                @selector(sliderStepped:), slider);
        [container addSubview:minus];
        [container addSubview:plus];

        UILayoutGuide *guide = cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[
            [container.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [container.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
            [container.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor
                                                constant:8.0],
            [container.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor
                                                   constant:-8.0],

            [caption.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [caption.topAnchor constraintEqualToAnchor:container.topAnchor],
            [valueLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [valueLabel.firstBaselineAnchor constraintEqualToAnchor:caption.firstBaselineAnchor],
            [valueLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:caption.trailingAnchor
                                                                  constant:8.0],

            [minus.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [minus.centerYAnchor constraintEqualToAnchor:slider.centerYAnchor],
            [minus.widthAnchor constraintEqualToConstant:30.0],
            [minus.heightAnchor constraintEqualToConstant:30.0],

            [plus.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            [plus.centerYAnchor constraintEqualToAnchor:slider.centerYAnchor],
            [plus.widthAnchor constraintEqualToConstant:30.0],
            [plus.heightAnchor constraintEqualToConstant:30.0],

            [slider.leadingAnchor constraintEqualToAnchor:minus.trailingAnchor constant:10.0],
            [slider.trailingAnchor constraintEqualToAnchor:plus.leadingAnchor constant:-10.0],
            [slider.topAnchor constraintEqualToAnchor:caption.bottomAnchor constant:6.0],
            [slider.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
        ]];
        cell.textLabel.text = nil;
        cell.accessoryView = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"slider"]) {
        double stored = [YTKACEPreferenceObject(item[@"key"]) doubleValue];
        double value = stored > 0.0 ? stored : [item[@"fallback"] doubleValue];
        UIView *accessory = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 158.0, 46.0)];
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0.0, 0.0, 158.0, 30.0)];
        slider.minimumTrackTintColor = YTKACEAccentColor();
        slider.minimumValue = [item[@"minimum"] floatValue];
        slider.maximumValue = [item[@"maximum"] floatValue];
        slider.value = (float)value;
        UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 28.0, 158.0, 14.0)];
        valueLabel.font = [UIFont systemFontOfSize:10.0];
        valueLabel.textColor = UIColor.tertiaryLabelColor;
        valueLabel.textAlignment = NSTextAlignmentRight;
        valueLabel.text = YTKACESliderValueText(item, value);
        objc_setAssociatedObject(slider, YTKACEItemAssociation, item, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(slider, YTKACEValueLabelAssociation, valueLabel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [accessory addSubview:slider];
        [accessory addSubview:valueLabel];
        cell.accessoryView = accessory;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"picker"]) {
        cell.detailTextLabel.text = YTKACEPickerSummary(
            item[@"key"],
            item[@"titles"],
            item[@"values"],
            [item[@"default"] unsignedIntegerValue]
        );
        cell.detailTextLabel.textColor = YTKACEAccentColor();
        cell.accessoryType = UITableViewCellAccessoryNone;
    } else if ([type isEqualToString:@"color"]) {
        NSString *stored = YTKACEPreferenceObject(item[@"key"]);
        UIColor *color = YTKACEColorFromHex(
            [stored isKindOfClass:NSString.class] ? stored : item[@"fallback"]);
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 28.0, 28.0)];
        dot.backgroundColor = color;
        dot.layer.cornerRadius = 14.0;
        dot.layer.borderWidth = 2.0;
        dot.layer.borderColor = UIColor.secondaryLabelColor.CGColor;
        cell.accessoryView = dot;
    } else if ([type isEqualToString:@"text"]) {
        cell.textLabel.font = [UIFont systemFontOfSize:10.0];
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.textLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)segmentChanged:(UISegmentedControl *)sender {
    NSDictionary *item = objc_getAssociatedObject(sender, YTKACEItemAssociation);
    NSArray *values = item[@"values"];
    if ((NSUInteger)sender.selectedSegmentIndex < values.count) {
        YTKACESetPreferenceObject(item[@"key"], values[(NSUInteger)sender.selectedSegmentIndex]);
        if (YTKACEPreferenceNeedsRestart(item[@"key"])) {
            YTKACEShowRestartNotice(self);
        }
    }
}

- (void)toggleChanged:(UISwitch *)sender {
    NSDictionary *item = objc_getAssociatedObject(sender, YTKACEItemAssociation);
    NSString *key = item[@"key"];
    YTKACESetPreference(key, sender.isOn);
    if ([key isEqualToString:@"YTKACE.Preference.Playback.Recovery"] && sender.isOn) {
        NSString *message = YTKACELocalized(@"✅ Playback recovery hooks will install on next launch.\n\n"
            @"📍 What this does:\n• Forces iOS guard attestation off\n• Marks heartbeat policy errors non-fatal\n• Swallows halt / cannot-play / error-overlay paths\n• Forces skip-on-playability-error\n\n"
            @"📍 When to use it:\nEnable if videos error out mid-playback, show \"an error occurred,\" or get killed by heartbeat / attestation failures.\n\n"
            @"⚠️ Restart YouTube for the hooks to take effect. Leave off if playback already works — it bypasses server-side stop signals and can mask real issues.");
        if (!YTKACEShowYouTubeDialog(YTKACELocalized(@"Fix Playback & Account Recovery"), message)) {
            YTKACEShowNotice(YTKACELocalized(@"Playback recovery guidance unavailable"));
        }
    }
    if ([key isEqualToString:YTKACEOLEDKey]) {
        YTKACEApplyAppearance(self);
        self.tableView.backgroundColor = YTKACESettingsBackground();
        [self.tableView reloadData];
    }
    if (YTKACEPreferenceNeedsRestart(key)) {
        YTKACEShowRestartNotice(self);
    }
}

- (void)stepperChanged:(UIStepper *)sender {
    NSDictionary *item = objc_getAssociatedObject(sender, YTKACEItemAssociation);
    UITableViewCell *cell = objc_getAssociatedObject(sender, YTKACEValueLabelAssociation);
    YTKACESetPreferenceObject(item[@"key"], @(sender.value));
    cell.textLabel.text = [NSString stringWithFormat:YTKACELocalized(@"Seconds: %@"), [NSString stringWithFormat:@"%.0f", sender.value]];
}

- (void)sliderStepped:(UIButton *)sender {
    UISlider *slider = objc_getAssociatedObject(sender, YTKACESliderAssociation);
    NSDictionary *item = objc_getAssociatedObject(slider, YTKACEItemAssociation);
    if (slider == nil || item == nil) {
        return;
    }
    double step = MAX(0.01, [item[@"step"] doubleValue]);
    double value = slider.value + (sender.tag == 2 ? step : -step);
    slider.value = (float)MIN([item[@"maximum"] doubleValue],
                              MAX([item[@"minimum"] doubleValue], value));
    [self sliderChanged:slider];
}

- (void)sliderChanged:(UISlider *)sender {
    NSDictionary *item = objc_getAssociatedObject(sender, YTKACEItemAssociation);
    UILabel *label = objc_getAssociatedObject(sender, YTKACEValueLabelAssociation);
    double step = MAX(0.01, [item[@"step"] doubleValue]);
    double value = round(round(sender.value / step) * step * 100.0) / 100.0;
    YTKACESetPreferenceObject(item[@"key"], @(value));
    label.text = YTKACESliderValueText(item, value);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = _sections[(NSUInteger)indexPath.section][(NSUInteger)indexPath.row];
    NSString *type = item[@"type"];
    UIViewController *controller = nil;
    if ([type isEqualToString:@"controller"]) {
        YTKACEControllerBuilder builder = item[@"builder"];
        controller = builder();
    } else if ([type isEqualToString:@"picker"]) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        YTKACEPresentChoiceMenu(self, cell, item[@"title"], item[@"titles"],
            item[@"values"], item[@"key"],
            [item[@"default"] unsignedIntegerValue], ^(__unused NSUInteger index) {
                NSString *key = item[@"key"];
                if ([key isEqualToString:@"YTKACE.Preference.Gestures.BrightnessSide"] ||
                    [key isEqualToString:@"YTKACE.Preference.Gestures.VolumeSide"]) {
                    [self.tableView reloadData];
                } else {
                    [self.tableView reloadRowsAtIndexPaths:@[indexPath]
                                          withRowAnimation:UITableViewRowAnimationNone];
                }
                if (YTKACEPreferenceNeedsRestart(item[@"key"])) {
                    YTKACEShowRestartNotice(self);
                }
            });
    } else if ([type isEqualToString:@"action"]) {
        YTKACEAction action = item[@"action"];
        action(self);
    } else if ([type isEqualToString:@"color"]) {
        NSString *stored = YTKACEPreferenceObject(item[@"key"]);
        UIColorPickerViewController *picker = [UIColorPickerViewController new];
        picker.title = item[@"title"];
        picker.supportsAlpha = NO;
        picker.selectedColor = YTKACEColorFromHex(
            [stored isKindOfClass:NSString.class] ? stored : item[@"fallback"]);
        picker.delegate = self;
        _colorKey = [item[@"key"] copy];
        _colorPath = indexPath;
        [self presentViewController:picker animated:YES completion:nil];
    }
    if (controller != nil) {
        [self.navigationController pushViewController:controller animated:YES];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    if (_pickerMode == 3) {
        if (_pendingBackupURL != nil) {
            [NSFileManager.defaultManager removeItemAtURL:_pendingBackupURL error:nil];
        }
        _pendingBackupURL = nil;
        _pickerMode = 0;
        return;
    }
    if (urls.count == 0) return;
    NSMutableArray<NSURL *> *scoped = [NSMutableArray array];
    for (NSURL *URL in urls) {
        if ([URL startAccessingSecurityScopedResource]) [scoped addObject:URL];
    }
    if (_pickerMode == 1) {
        _restoreRunning = NO;
        [self setBackupProgressVisible:NO message:nil];
        _pickerMode = 0;
        return;
    }
    for (NSURL *URL in scoped) [URL stopAccessingSecurityScopedResource];
            NSString *message = error.localizedDescription ?: [NSString
                stringWithFormat:YTKACELocalized(@"%lu items added to %@."),
                (unsigned long)count, category];
            [self showResult:error == nil ? YTKACELocalized(@"Import Complete") : YTKACELocalized(@"Import Failed")
                      message:message];
        }];
}

- (void)colorPickerViewController:(UIColorPickerViewController *)viewController
                   didSelectColor:(UIColor *)color
                     continuously:(BOOL)continuously {
    (void)continuously;
    if (_colorKey.length == 0 || color == nil) return;
    YTKACESetPreferenceObject(_colorKey, YTKACEHexFromColor(color));
    if (_colorPath != nil) {
        [self.tableView reloadRowsAtIndexPaths:@[_colorPath]
                              withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    if (_colorKey.length != 0) {
        YTKACESetPreferenceObject(_colorKey, YTKACEHexFromColor(viewController.selectedColor));
        if (_colorPath != nil) {
            [self.tableView reloadRowsAtIndexPaths:@[_colorPath]
                                  withRowAnimation:UITableViewRowAnimationNone];
        }
    }
    _colorKey = nil;
    _colorPath = nil;
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    NSInteger mode = _pickerMode;
    _pickerMode = 0;
    if (mode == 3) {
        if (_pendingBackupURL != nil) {
            [NSFileManager.defaultManager removeItemAtURL:_pendingBackupURL error:nil];
        }
        _pendingBackupURL = nil;
        NSString *message = YTKACELocalized(@"The backup was not saved to the Files app.");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
                if (!YTKACEShowYouTubeDialog(YTKACELocalized(@"Backup Not Saved"), message)) {
                    YTKACEShowNotice(YTKACELocalized(@"Warning: Backup was not saved to Files app."));
                }
            });
    }
}

- (void)setBackupProgressVisible:(BOOL)visible message:(NSString *)message {
    if (!visible) {
        UIView *overlay = _backupOverlay;
        _backupOverlay = nil;
        _backupOverlayLabel = nil;
        [UIView animateWithDuration:0.18 animations:^{
            overlay.alpha = 0.0;
        } completion:^(__unused BOOL finished) {
            [overlay removeFromSuperview];
        }];
        return;
    }
    if (_backupOverlay != nil) {
        _backupOverlayLabel.text = message.length == 0 ? YTKACELocalized(@"Please Wait...") : message;
        return;
    }
    UIView *host = self.navigationController.view ?: self.view;
    UIView *overlay = [UIView new];
    overlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.18];
    overlay.translatesAutoresizingMaskIntoConstraints = NO;
    overlay.alpha = 0.0;

    UIView *card = [UIView new];
    card.backgroundColor = YTKACEInterfaceSurfaceColor(self.traitCollection);
    card.layer.cornerRadius = 12.0;
    card.layer.masksToBounds = YES;
    card.translatesAutoresizingMaskIntoConstraints = NO;

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.color = UIColor.labelColor;
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];

    UILabel *label = [UILabel new];
    label.text = message.length == 0 ? YTKACELocalized(@"Please Wait...") : message;
    label.textColor = UIColor.labelColor;
    label.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    label.textAlignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;

    [card addSubview:spinner];
    [card addSubview:label];
    [overlay addSubview:card];
    [host addSubview:overlay];
    [NSLayoutConstraint activateConstraints:@[
        [overlay.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [overlay.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [overlay.topAnchor constraintEqualToAnchor:host.topAnchor],
        [overlay.bottomAnchor constraintEqualToAnchor:host.bottomAnchor],
        [card.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:190.0],
        [card.heightAnchor constraintEqualToConstant:94.0],
        [spinner.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [spinner.topAnchor constraintEqualToAnchor:card.topAnchor constant:17.0],
        [label.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12.0],
        [label.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12.0],
        [label.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-17.0]
    ]];
    _backupOverlay = overlay;
    _backupOverlayLabel = label;
    [UIView animateWithDuration:0.18 animations:^{ overlay.alpha = 1.0; }];
}

- (void)performBackup {
    _backupRunning = NO;
    [self setBackupProgressVisible:NO message:nil];
}

- (void)beginBackup {
    if (_backupRunning) return;
    __weak YTKACEOptionsController *weakSelf = self;
    BOOL shown = YTKACEShowYouTubeConfirmation(
        @"YTKACE",
        YTKACELocalized(@"Do you want to create a backup?"),
        YTKACELocalized(@"Create"),
        ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf performBackup];
            });
        }
    );
    if (!shown) {
        YTKACEShowNotice(YTKACELocalized(@"Backup confirmation unavailable"));
    }
}

- (void)beginRestore {
    if (_restoreRunning) return;
    _pickerMode = 1;
    UTType *zip = [UTType typeWithFilenameExtension:@"zip"] ?: UTTypeData;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[zip] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)beginImportForCategory:(NSString *)category {
    _pickerMode = 2;
    _importCategory = [category copy];
    NSMutableArray<UTType *> *types = [NSMutableArray arrayWithObjects:
        UTTypeMovie, UTTypeAudio, UTTypeImage, nil];
    UTType *srt = [UTType typeWithFilenameExtension:@"srt"];
    UTType *vtt = [UTType typeWithFilenameExtension:@"vtt"];
    if (srt != nil) [types addObject:srt];
    if (vtt != nil) [types addObject:vtt];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)chooseImportCategory {
    YTKACEPresentChoiceMenu(self, self.view, YTKACELocalized(@"Import Media"),
        @[YTKACELocalized(@"Video"), YTKACELocalized(@"Audio"), YTKACELocalized(@"Shorts")],
        @[@"Video", @"Audio", @"Shorts"],
        @"YTKACEImportMediaType", 0, ^(NSUInteger index) {
            NSArray *categories = @[@"Video", @"Audio", @"Shorts"];
            [self beginImportForCategory:categories[index]];
        });
}

- (void)showResult:(NSString *)title message:(NSString *)message {
    NSString *notice = message.length != 0
        ? [NSString stringWithFormat:@"%@\n%@", title, message] : title;
    YTKACEShowNotice(notice);
}

@end

static YTKACEOptionsController *YTKACEPage(NSString *title,
                                           NSArray *sections,
                                           NSArray *sectionTitles) {
    return [[YTKACEOptionsController alloc] initWithTitle:YTKACELocalized(title)
                                                 sections:sections
                                           sectionTitles:YTKACELocalizedList(sectionTitles)];
}

static NSArray<NSString *> *YTKACEQualityTitles(void) {
    return @[YTKACELocalized(@"Auto"), @"2160p60", @"2160p", @"1440p60", @"1440p", @"1080p60",
             @"1080p", @"720p60", @"720p", @"480p", @"360p", @"240p", @"144p"];
}

static NSArray *YTKACEQualityValues(void) {
    return @[@0, @1, @2, @3, @4, @5, @6, @7, @8, @9, @10, @11, @12];
}

static NSDictionary *YTKACEPageDefinition(NSString *pageID,
                                          NSString *title,
                                          NSArray *sections,
                                          NSArray *headers) {
    return @{
        @"id": pageID,
        @"title": title,
        @"sections": sections,
        @"headers": headers
    };
}

static YTKACEOptionsController *YTKACEPageFromDefinition(NSDictionary *definition) {
    return YTKACEPage(definition[@"title"],
                      definition[@"sections"],
                      definition[@"headers"]);
}

UIViewController *YTKACEMakeStartupPickerController(void) {
    return [[YTKACEPickerController alloc]
        initWithTitle:YTKACELocalized(@"Startup Page")
                   key:@"YTKACE.Preference.Tabs.Startup"
                titles:@[YTKACELocalized(@"Home"), YTKACELocalized(@"Explore"), YTKACELocalized(@"Subscriptions"), YTKACELocalized(@"Shorts"), YTKACELocalized(@"You")]
                values:@[@0, @1, @2, @3, @4]
          defaultIndex:0];
}

UIViewController *YTKACEMakeWiFiQualityController(void) {
    return [[YTKACEPickerController alloc] initWithTitle:YTKACELocalized(@"Wi-Fi Quality")
                                                    key:@"YTKACE.Preference.Playback.WiFiQuality"
                                                 titles:YTKACEQualityTitles()
                                                 values:YTKACEQualityValues()
                                           defaultIndex:0];
}

UIViewController *YTKACEMakeCellularQualityController(void) {
    return [[YTKACEPickerController alloc] initWithTitle:YTKACELocalized(@"Cellular Quality")
                                                    key:@"YTKACE.Preference.Playback.CellularQuality"
                                                 titles:YTKACEQualityTitles()
                                                 values:YTKACEQualityValues()
                                           defaultIndex:0];
}

static NSDictionary *YTKACESponsorBlockDefinition(void) {
    NSMutableArray *sections = [NSMutableArray arrayWithObject:@[
        YTKACEToggle(@"Enable", YTKACESponsorBlockKey, @"", @""),
        YTKACEPicker(@"Skip Alerts", @"YTKACE.Preference.SponsorBlock.NotificationMode",
                     @[@"Skip + Unskip", @"Skip Only", @"Silent"],
                     @[@0, @1, @2], 0, @"", @""),
        YTKACEToggle(@"Audio Notification", @"YTKACE.Preference.SponsorBlock.AudioFeedback", @"", @""),
        YTKACESlider(@"Skip Alert Duration", @"YTKACE.Preference.SponsorBlock.SkipAlertSeconds",
                     1.0, 10.0, 1.0, 4.0),
        YTKACESlider(@"Unskip Alert Duration", @"YTKACE.Preference.SponsorBlock.UnskipAlertSeconds",
                     1.0, 10.0, 1.0, 4.0)
    ]];
    NSMutableArray<NSString *> *titles = [NSMutableArray arrayWithObject:YTKACELocalized(@"MAIN")];

    [sections addObject:@[
        YTKACEToggleDetail(@"Thumbnails",
                           @"Replace clickbait thumbnails with community-picked "
                            "frames from DeArrow. Videos without a submission are "
                            "left untouched.",
                           YTKACEDeArrowThumbModeKey),
        YTKACEToggleDetail(@"Titles",
                           @"Replace clickbait titles with community-written ones "
                            "from DeArrow. Videos without a submission keep their "
                            "original title.",
                           YTKACEDeArrowTitlesKey)
    ]];
    [titles addObject:YTKACELocalized(@"DEARROW")];

    for (NSDictionary<NSString *, NSString *> *definition in
         YTKACESponsorCategoryDefinitions()) {
        NSString *category = definition[@"id"];
        [sections addObject:@[
            YTKACEPicker(@"Behavior", YTKACESponsorBehaviorKey(category),
                         @[@"Auto-skip", @"Ask", @"Show Marker", @"Disabled"],
                         @[@0, @1, @3, @2],
                         [category isEqualToString:@"sponsor"] ? 0 : 3,
                         @"", @""),
            YTKACEColor(@"Segment Color", YTKACESponsorColorKey(category),
                        definition[@"color"])
        ]];
        [titles addObject:YTKACELocalized([definition[@"title"] uppercaseString])];
    }
    return YTKACEPageDefinition(@"sponsorblock", @"SponsorBlock", sections, titles);
}

static NSDictionary *YTKACEPlayerControlsDefinition(void) {
    YTKACEAction backup = ^(UIViewController *controller) {
        [(YTKACEOptionsController *)controller beginBackup];
    };
    YTKACEAction restore = ^(UIViewController *controller) {
        [(YTKACEOptionsController *)controller beginRestore];
    };
    YTKACEAction importMedia = ^(UIViewController *controller) {
        [(YTKACEOptionsController *)controller chooseImportCategory];
    };
    YTKACEAction clearCache = ^(UIViewController *controller) {
        NSURL *cache = [YTKACEApplicationSupportDirectory()
            URLByAppendingPathComponent:@"Cache"
                            isDirectory:YES];
        [NSFileManager.defaultManager removeItemAtURL:cache error:nil];
        [(YTKACEOptionsController *)controller showResult:YTKACELocalized(@"Cache Cleared") message:nil];
    };
    NSArray *progressSection = @[
        YTKACESegmentedStacked(@"Progress bar style", @"YTKACE.Preference.Progress.Style",
                               @[@"Default", @"Solid color", @"Gradient"], @[@0, @1, @2], 0),
        YTKACEColor(@"Main color", @"YTKACE.Preference.Progress.MainColor", @"#FF0000"),
        YTKACEColor(@"Gradient highlight", @"YTKACE.Preference.Progress.HighlightColor", @"#8E8EFF"),
        YTKACEColor(@"Scrubber color", @"YTKACE.Preference.Progress.ScrubberColor", @"#FF0000")
    ];
    return YTKACEPageDefinition(@"player", @"Player", @[
        @[
            YTKACEToggle(@"Download Button", YTKACEDownloadKey, @"", @""),
            YTKACEToggle(@"PiP Button", YTKACEPiPKey, @"", @""),
            YTKACEToggle(@"Loop Button", YTKACELoopKey, @"", @""),
            YTKACEToggle(@"Sleep Timer Button", YTKACESleepTimerKey, @"", @""),
            YTKACEToggle(@"Background Audio", YTKACEBackgroundPlaybackKey, @"", @"")
        ],
        @[
            YTKACEToggle(@"Speed Buttons", YTKACESpeedKey, @"", @""),
            YTKACESegmentedStacked(@"Default playback speed",
                                   @"YTKACE.Preference.Player.DefaultRateMode",
                                   @[@"1x", @"Last Used", @"Custom"], @[@0, @1, @2], 0),
            YTKACESpeedSlider(@"Custom speed", @"YTKACE.Preference.Player.DefaultRate",
                              0.25, 5.0, 0.05, 1.0)
        ],
        @[
            YTKACEToggle(@"Remove Ads", YTKACENoAdsKey, @"", @""),
            YTKACEToggleDetail(@"Playback Fix",
                @"Helps recover playback in sideloaded builds.",
                @"YTKACE.Preference.Playback.Recovery")
        ],
        progressSection,
        @[
            YTKACEActionDetail(@"Back Up", @"Save settings and media to a ZIP file.", backup),
            YTKACEActionDetail(@"Restore", @"Open a YTKACE backup from Files.", restore),
            YTKACEActionDetail(@"Import", @"Add video, audio, Shorts, artwork, or subtitles.", importMedia)
        ],
        @[
            YTKACEPicker(@"Clear Cache at Launch", @"YTKACE.Preference.Downloads.ClearOnStartup", @[@"Off", @"On"], @[@NO, @YES], 0, @"", @""),
            YTKACEActionDetail(@"Clear Cache Now", @"Delete temporary download files.", clearCache)
        ]
    ], @[YTKACELocalized(@"BUTTONS"), YTKACELocalized(@"SPEED"), YTKACELocalized(@"PLAYBACK"), YTKACELocalized(@"PROGRESS BAR"), YTKACELocalized(@"FILES"), YTKACELocalized(@"STORAGE")]);
}

UIViewController *YTKACEMakeTabBarOptionsController(void) {
    return nil;
}

static NSDictionary *YTKACEOverlayOptionsDefinition(void) {
    return YTKACEPageDefinition(@"overlay", @"Overlay", @[
        @[
            YTKACEToggle(@"Remove Suggested Videos", @"YTKACE.Preference.Overlay.SuggestedVideosHidden", @"", @""),
            YTKACEToggle(@"Remove Comments", @"YTKACE.Preference.Overlay.CommentsHidden", @"", @""),
            YTKACEToggle(@"Remove Comment Preview", @"YTKACE.Preference.Overlay.CommentPreviewsHidden", @"", @""),
            YTKACEToggle(@"Remove Comment Guidelines", @"YTKACE.Preference.Overlay.CommentGuidelinesHidden", @"", @""),
            YTKACEToggle(@"Remove Paid Promotion Label", @"YTKACE.Preference.Overlay.PaidPromotionHidden", @"", @""),
            YTKACEToggle(@"Remove Products", @"YTKACE.Preference.Overlay.ProductsHidden", @"", @"")
        ],
        @[
            YTKACEToggle(@"Status Bar", @"YTKACE.Preference.Overlay.StatusBarVisible", @"", @""),
            YTKACEToggle(@"Remove Quick Actions", @"YTKACE.Preference.Overlay.QuickActionsHidden", @"", @""),
            YTKACEToggle(@"Stop Continue Watching", @"YTKACE.Preference.Overlay.ContinueWatchingDisabled", @"", @""),
            YTKACEToggle(@"Turn Off Double Tap", @"YTKACE.Preference.Overlay.DoubleTapDisabled", @"", @"")
        ],
        @[
            YTKACEToggle(@"Keep Play Button Visible", @"YTKACE.Preference.Overlay.AlwaysShowPlayPause", @"", @""),
            YTKACEToggle(@"Keep Controls Visible", @"YTKACE.Preference.Overlay.AlwaysShowControls", @"", @""),
            YTKACEToggle(@"Remove Player Dimming", @"YTKACE.Preference.Overlay.DimmingRemoved", @"", @""),
            YTKACEToggle(@"Captions On", @"YTKACE.Preference.Playback.CaptionsAlwaysOn", @"", @""),
            YTKACEToggle(@"Keep Timeline Visible", @"YTKACE.Preference.Overlay.ProgressAlwaysVisible", @"", @"")
        ],
        @[
            YTKACEToggle(@"Lock Previous/Next", @"YTKACE.Preference.Overlay.PreviousNextDisabled", @"", @""),
            YTKACEToggle(@"Smaller Previous/Next", @"YTKACE.Preference.Overlay.CompactPreviousNext", @"", @""),
            YTKACEToggle(@"Remove Previous/Next", @"YTKACE.Preference.Overlay.PreviousNextHidden", @"", @"")
        ],
        @[
            YTKACEToggle(@"Remove Info Cards", @"YTKACE.Preference.Overlay.InfoCardsHidden", @"", @""),
            YTKACEToggle(@"Remove Watermark", @"YTKACE.Preference.Overlay.WatermarkHidden", @"", @""),
            YTKACEToggle(@"Remove Autoplay", @"YTKACE.Preference.Overlay.AutoplayHidden", @"", @""),
            YTKACEToggle(@"Remove Captions Button", @"YTKACE.Preference.Overlay.CaptionsButtonHidden", @"", @""),
            YTKACEToggle(@"Remove Play Button", @"YTKACE.Preference.Overlay.PlayPauseHidden", @"", @""),
            YTKACEToggle(@"Remove Settings Button", @"YTKACE.Preference.Overlay.MoreButtonHidden", @"", @""),
            YTKACEToggle(@"Remove Cast Button", @"YTKACE.Preference.Overlay.CastHidden", @"", @""),
            YTKACEToggle(@"Remove End Screen", @"YTKACE.Preference.Overlay.EndScreenHidden", @"", @""),
            YTKACEToggle(@"Remove Related Videos", @"YTKACE.Preference.Overlay.RelatedVideosHidden", @"", @"")
        ],
        @[
            YTKACEToggle(@"Remove Like", @"YTKACE.Preference.ActionBar.LikeHidden", @"", @""),
            YTKACEToggle(@"Remove Dislike", @"YTKACE.Preference.ActionBar.DislikeHidden", @"", @""),
            YTKACEToggle(@"Remove Share", @"YTKACE.Preference.ActionBar.ShareHidden", @"", @""),
            YTKACEToggle(@"Remove Download", @"YTKACE.Preference.ActionBar.DownloadHidden", @"", @""),
            YTKACEToggle(@"Remove Save", @"YTKACE.Preference.ActionBar.SaveHidden", @"", @""),
            YTKACEToggle(@"Remove Clip", @"YTKACE.Preference.ActionBar.ClipHidden", @"", @""),
            YTKACEToggle(@"Remove Remix", @"YTKACE.Preference.ActionBar.RemixHidden", @"", @""),
            YTKACEToggle(@"Remove Thanks", @"YTKACE.Preference.ActionBar.ThanksHidden", @"", @""),
            YTKACEToggle(@"Remove Hype", @"YTKACE.Preference.ActionBar.HypeHidden", @"", @""),
            YTKACEToggle(@"Remove Report", @"YTKACE.Preference.ActionBar.ReportHidden", @"", @""),
            YTKACEToggle(@"Remove Ask", @"YTKACE.Preference.ActionBar.AskHidden", @"", @"")
        ]
    ], @[YTKACELocalized(@"WATCH PAGE"), YTKACELocalized(@"GESTURES"), YTKACELocalized(@"ALWAYS VISIBLE"), YTKACELocalized(@"PREVIOUS & NEXT"), YTKACELocalized(@"HIDE FROM PLAYER"), YTKACELocalized(@"ACTION BAR")]);
}

static NSDictionary *YTKACEStreamingOptionsDefinition(void) {
    return YTKACEPageDefinition(@"playback", @"Playback", @[
        @[YTKACEToggle(@"Old Quality Menu", @"YTKACE.Preference.Playback.LegacyQualityMenu", @"", @"")],
        @[
            YTKACEToggle(@"Custom Double-Tap Time", @"YTKACE.Preference.Playback.CustomDoubleTap", @"", @""),
            YTKACEStepper(@"Skip Time", @"YTKACE.Preference.Playback.DoubleTapSeconds", 5.0, 60.0, 5.0, 10.0)
        ],
        @[
            YTKACEToggle(@"Stop Autoplay", @"YTKACE.Preference.Playback.AutoplayDisabled", @"", @""),
            YTKACEToggle(@"HD on Mobile Data", @"YTKACE.Preference.Playback.HDOnCellular", @"", @"")
        ]
    ], @[YTKACELocalized(@"QUALITY"), YTKACELocalized(@"DOUBLE TAP"), YTKACELocalized(@"AUTOPLAY & DATA")]);
}

static NSDictionary *YTKACENavigationOptionsDefinition(void) {
    return YTKACEPageDefinition(@"navigation", @"Navigation", @[
        @[
            YTKACEToggle(@"Premium Logo", @"YTKACE.Preference.Navigation.PremiumLogo", @"", @""),
            YTKACEToggle(@"Confirm Before Casting", @"YTKACE.Preference.Navigation.CastConfirmation", @"", @"")
        ],
        @[
            YTKACEToggle(@"Remove YouTube Logo", @"YTKACE.Preference.Navigation.LogoHidden", @"", @""),
            YTKACEToggle(@"Remove Notifications", @"YTKACE.Preference.Navigation.NotificationsHidden", @"", @""),
            YTKACEToggle(@"Remove Messages", @"YTKACE.Preference.Navigation.MessagesHidden",
                         @"Removes the Messages button.", @""),
            YTKACEToggle(@"Remove Account Button", @"YTKACE.Preference.Navigation.AccountHidden", @"", @""),
            YTKACEToggle(@"Remove Search", @"YTKACE.Preference.Navigation.SearchHidden", @"", @""),
            YTKACEToggle(@"Remove Cast", @"YTKACE.Preference.Navigation.CastHidden", @"", @"")
        ],
        @[
            YTKACEToggle(@"Hide Status Bar", @"YTKACE.Preference.Navigation.StatusBarHidden", @"", @""),
            YTKACEToggle(@"Remove Topic Chips", @"YTKACE.Preference.Navigation.TopicsHidden", @"", @"")
        ]
    ], @[YTKACELocalized(@"BRAND & CAST"), YTKACELocalized(@"TOP BUTTONS"), YTKACELocalized(@"PAGE CHROME")]);
}

static NSDictionary *YTKACEShortsOptionsDefinition(void) {
    return YTKACEPageDefinition(@"shorts", @"Shorts", @[
        @[
            YTKACEToggle(@"Progress Bar", @"shortsProgress", @"", @""),
            YTKACEToggle(@"Auto Advance", @"autoSkipShorts", @"", @""),
            YTKACEPicker(@"Download Button Position", @"YTKACE.Preference.Shorts.DownloadPosition",
                         @[YTKACELocalized(@"Top Corner"), YTKACELocalized(@"Action Buttons")],
                         @[@0, @1], 0, @"", @"")
        ],
        @[
            YTKACEToggle(@"Remove Shorts Shelves", @"YTKACE.Preference.Shorts.FeedHidden", @"", @""),
            YTKACEToggle(@"Remove Pause Card", @"YTKACE.Preference.Shorts.PauseCardHidden", @"", @""),
            YTKACEToggle(@"Remove Sticker Ads", @"YTKACE.Preference.Shorts.StickerAdsHidden", @"", @"")
        ],
        @[
            YTKACEToggle(@"Remove Like", @"YTKACE.Preference.Shorts.LikeHidden", @"", @""),
            YTKACEToggle(@"Remove Comments", @"YTKACE.Preference.Shorts.CommentsHidden", @"", @""),
            YTKACEToggle(@"Remove Share", @"YTKACE.Preference.Shorts.ShareHidden", @"", @""),
            YTKACEToggle(@"Remove Remix", @"YTKACE.Preference.Shorts.RemixHidden", @"", @""),
            YTKACEToggle(@"Remove Sound", @"YTKACE.Preference.Shorts.SoundHidden", @"", @"")
        ]
    ], @[YTKACELocalized(@"PLAYBACK"), YTKACELocalized(@"FEED"), YTKACELocalized(@"ACTION BUTTONS")]);
}

static NSDictionary *YTKACEMiscOptionsDefinition(void) {
    return YTKACEPageDefinition(@"other", @"Other", @[
        @[
            YTKACEToggle(@"Remove Community Posts",
                         @"YTKACE.Preference.Feed.CommunityPostsHidden",
                         @"Removes community posts from the feed.", @""),
            YTKACEToggle(@"Remove Mixes",
                         @"YTKACE.Preference.Feed.MixesHidden",
                         @"Removes YouTube Mix playlists from the feed.", @""),
            YTKACEToggle(@"Remove Playables",
                         @"YTKACE.Preference.Feed.PlayablesHidden",
                         @"Removes playable games from the feed.", @"")
        ],
        @[
            YTKACEToggle(@"OLED Black", YTKACEOLEDKey, @"", @""),
            YTKACEToggle(@"Skip Launch Animation", @"YTKACE.Preference.Appearance.LaunchAnimationDisabled",
                         @"Starts YouTube faster", @"")
        ],
        @[
            YTKACEToggle(@"iPad Layout", @"YTKACE.Preference.App.iPadLayout", @"", @""),
            YTKACEToggle(@"Block Drag and Drop", @"YTKACE.Preference.App.DragDropDisabled", @"", @""),
            YTKACEToggle(@"Block RTL Layout", @"YTKACE.Preference.App.RTLDisabled", @"", @"")
        ],
        @[
            YTKACEToggle(@"iOS Share Sheet", @"YTKACE.Preference.Sharing.NativeSheet", @"", @""),
            YTKACEToggle(@"Avatar Preview", @"YTKACE.Preference.Profiles.Preview", @"", @""),
            YTKACEToggle(@"Mini Player for Kids Videos", @"YTKACE.Preference.Playback.KidsMiniPlayer", @"", @"")
        ],
        @[
            YTKACEToggle(@"Don't Save Searches", @"YTKACE.Preference.Privacy.SearchHistoryDisabled", @"", @""),
            YTKACEToggle(@"Block Premium Prompts", @"YTKACE.Preference.Ads.PremiumPromosHidden", @"", @""),
            YTKACEToggle(@"Block Update Prompts", @"YTKACE.Preference.App.UpdatePromptHidden", @"", @""),
            YTKACEToggle(@"Mute HUD Alerts", @"YTKACE.Preference.App.HUDAlertsHidden", @"", @""),
            YTKACEToggle(@"Skip Age Gate", @"YTKACE.Preference.Content.AgeGateBypass", @"", @""),
            YTKACEToggle(@"Captions Off", @"YTKACE.Preference.Playback.CaptionsDisabled", @"", @"")
        ]
    ], @[YTKACELocalized(@"FEED"), YTKACELocalized(@"APPEARANCE"), YTKACELocalized(@"LAYOUT"), YTKACELocalized(@"SYSTEM"), YTKACELocalized(@"PRIVACY & PROMPTS")]);
}

static NSDictionary *YTKACEGestureOptionsDefinition(void) {
    NSArray *actionTitles = @[@"None", @"Brightness", @"Volume", @"Brightness + Volume"];
    NSArray *actionValues = @[@0, @1, @2, @3];
    return YTKACEPageDefinition(@"gestures", @"Gestures", @[
        @[
            YTKACEPercentSlider(@"Activation Area",
                                @"YTKACE.Preference.Gestures.ActivationArea",
                                10.0, 50.0, 5.0, 20.0),
            YTKACEPicker(@"Left Side", @"YTKACE.Preference.Gestures.LeftAction",
                         actionTitles, actionValues, 0, @"", @""),
            YTKACEPicker(@"Right Side", @"YTKACE.Preference.Gestures.RightAction",
                         actionTitles, actionValues, 0, @"", @"")
        ],
        @[
            YTKACEToggleDetail(@"Gesture HUD",
                               @"Show the current brightness or volume level.",
                               @"YTKACE.Preference.Gestures.HUDEnabled"),
            YTKACEPicker(@"HUD Size", @"YTKACE.Preference.Gestures.HUDSize",
                         @[@"Compact", @"Standard", @"Large"], @[@0, @1, @2],
                         1, @"", @""),
            YTKACEPicker(@"HUD Position", @"YTKACE.Preference.Gestures.HUDPosition",
                         @[@"Top", @"Center", @"Bottom"], @[@0, @1, @2],
                         0, @"", @"")
        ],
        @[
            YTKACEToggle(@"Hold to Seek", @"YTKACE.Preference.Gestures.HoldToSeek", @"", @""),
            YTKACESlider(@"Seek Speed", @"YTKACE.Preference.Gestures.HoldSeekSeconds", 1.0, 60.0, 1.0, 10.0),
            YTKACEToggle(@"Tap to Seek", @"YTKACE.Preference.Playback.TapToSeek", @"", @"")
        ]
    ], @[YTKACELocalized(@"EDGE CONTROLS"), YTKACELocalized(@"HUD"),
          YTKACELocalized(@"SEEK")]);
}

UIViewController *YTKACEMakeSponsorBlockController(void) {
    return YTKACEPageFromDefinition(YTKACESponsorBlockDefinition());
}

UIViewController *YTKACEMakePlayerControlsController(void) {
    return YTKACEPageFromDefinition(YTKACEPlayerControlsDefinition());
}

UIViewController *YTKACEMakeOverlayOptionsController(void) {
    return YTKACEPageFromDefinition(YTKACEOverlayOptionsDefinition());
}

UIViewController *YTKACEMakeStreamingOptionsController(void) {
    return YTKACEPageFromDefinition(YTKACEStreamingOptionsDefinition());
}

UIViewController *YTKACEMakeNavigationOptionsController(void) {
    return YTKACEPageFromDefinition(YTKACENavigationOptionsDefinition());
}

UIViewController *YTKACEMakeShortsOptionsController(void) {
    return YTKACEPageFromDefinition(YTKACEShortsOptionsDefinition());
}

UIViewController *YTKACEMakeMiscOptionsController(void) {
    return YTKACEPageFromDefinition(YTKACEMiscOptionsDefinition());
}

UIViewController *YTKACEMakeGestureOptionsController(void) {
    return YTKACEPageFromDefinition(YTKACEGestureOptionsDefinition());
}

NSArray<NSDictionary *> *YTKACEAllPageDefinitions(void) {
    return @[
        YTKACESponsorBlockDefinition(),
        YTKACEPlayerControlsDefinition(),
        YTKACEOverlayOptionsDefinition(),
        YTKACEStreamingOptionsDefinition(),
        YTKACENavigationOptionsDefinition(),
        YTKACEShortsOptionsDefinition(),
        YTKACEMiscOptionsDefinition(),
        YTKACEGestureOptionsDefinition()
    ];
}

UIViewController *YTKACEMakeCreditsController(void) {
    UILabel *label = [UILabel new];
    label.text = YTKACELocalized(@"YTKACE\nClean-room implementation\nMIT licensed code\nBuilt by Epic");
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.secondaryLabelColor;
    UIViewController *controller = [UIViewController new];
    controller.title = YTKACELocalized(@"Credits");
    controller.view.backgroundColor = YTKACESettingsBackground();
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [controller.view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:controller.view.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:controller.view.centerYAnchor],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:controller.view.leadingAnchor constant:24.0],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:controller.view.trailingAnchor constant:-24.0]
    ]];
    return controller;
}

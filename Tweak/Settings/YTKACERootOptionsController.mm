#import "YTKACERootOptionsController.h"
#import "../YTKACE.h"
#import "YTKACESettingsPages.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/Localization.h"
#import "../UI/Assets.h"
#import "../UI/Notice.h"

#import <objc/runtime.h>
#import <stdlib.h>
#import <sys/utsname.h>

static UIColor *YTKACERootBackground(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return YTKACEInterfaceBackgroundColor(traits);
    }];
}

static UIColor *YTKACERootCellBackground(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return YTKACEInterfaceBackgroundColor(traits);
    }];
}

static UIImage *YTKACETemplateImage(NSString *asset, NSString *symbol) {
    return [YTKACEAssetImage(asset, symbol)
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static const void *YTKACEDismissTargetKey = &YTKACEDismissTargetKey;

@interface YTKACEDismissTarget : NSObject
@property(nonatomic, weak) UIViewController *controller;
- (void)dismiss;
- (void)pop;
@end

@implementation YTKACEDismissTarget
- (void)dismiss {
    [self.controller dismissViewControllerAnimated:YES completion:nil];
}
- (void)pop {
    [self.controller.navigationController popViewControllerAnimated:YES];
}
@end

static const void *YTKACEOwnedNavigationKey = &YTKACEOwnedNavigationKey;

BOOL YTKACEOwnsNavigationController(UINavigationController *navigation) {
    if (navigation == nil) return NO;
    return [objc_getAssociatedObject(navigation, YTKACEOwnedNavigationKey) boolValue];
}

void YTKACEApplyAppearance(UIViewController *controller) {
    controller.view.backgroundColor = YTKACERootBackground();
    controller.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    UINavigationController *navigation = controller.navigationController;
    if (!YTKACEOwnsNavigationController(navigation)) {
        if (navigation != nil &&
            controller.navigationItem.leftBarButtonItem == nil &&
            navigation.viewControllers.firstObject != controller) {
            YTKACEDismissTarget *target = [YTKACEDismissTarget new];
            target.controller = controller;
            objc_setAssociatedObject(controller, YTKACEDismissTargetKey, target,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIImageSymbolConfiguration *symbolConfiguration =
                [UIImageSymbolConfiguration configurationWithPointSize:17.0
                                                                  weight:UIImageSymbolWeightSemibold];
            UIImage *chevron =
                [UIImage systemImageNamed:@"chevron.backward"
                        withConfiguration:symbolConfiguration];
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            UIButtonConfiguration *configuration =
                [UIButtonConfiguration plainButtonConfiguration];
            configuration.image = chevron;
            configuration.title = YTKACELocalized(@"Back");
            configuration.imagePadding = 4.0;
            configuration.contentInsets =
                NSDirectionalEdgeInsetsMake(0.0, 8.0, 0.0, 4.0);
            button.configuration = configuration;
            [button addTarget:target action:@selector(pop)
                forControlEvents:UIControlEventTouchUpInside];
            UIBarButtonItem *back =
                [[UIBarButtonItem alloc] initWithCustomView:button];
            controller.navigationItem.leftBarButtonItem = back;
            controller.navigationItem.hidesBackButton = YES;
        }
        return;
    }
    if (@available(iOS 15.0, *)) {
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = YTKACERootBackground();
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: UIColor.labelColor
        };
        navigation.navigationBar.standardAppearance = appearance;
        navigation.navigationBar.scrollEdgeAppearance = appearance;
        navigation.navigationBar.compactAppearance = appearance;
    }
}

NSString *YTKACEDeviceInformationText(void) {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *model = [NSString stringWithUTF8String:systemInfo.machine] ?: @"iOS Device";
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *youtubeVersion = info[@"CFBundleShortVersionString"] ?: @"Unknown";
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"com.google.ios.youtube";
    return [NSString stringWithFormat:@"YouLite+ %@  •  YouTube %@\n%@\n%@  •  iOS %@",
        YTKACEVersion, youtubeVersion, bundleID, model,
        UIDevice.currentDevice.systemVersion];
}

@interface YTKACERootOptionsController ()
@property(nonatomic, strong) UIView *settingsHeader;
@end

@implementation YTKACERootOptionsController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.cellLayoutMarginsFollowReadableWidth = NO;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.sectionHeaderHeight = 22.0;
    self.tableView.sectionFooterHeight = 6.0;
    self.settingsHeader = [self makeSettingsHeader];
    self.tableView.tableHeaderView = self.settingsHeader;
    UILongPressGestureRecognizer *developerHold =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(handleDeveloperHold:)];
    developerHold.minimumPressDuration = 3.0;
    developerHold.cancelsTouchesInView = YES;
    [self.tableView addGestureRecognizer:developerHold];
}

- (void)showDownloadLog {
}

- (void)handleDeveloperHold:(UILongPressGestureRecognizer *)recognizer {
    (void)recognizer;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
    YTKACEApplyAppearance(self);
    self.tableView.backgroundColor = YTKACERootBackground();
    self.settingsHeader.backgroundColor = YTKACERootBackground();
    [self.tableView reloadData];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    CGFloat difference = CGRectGetWidth(self.settingsHeader.frame) - width;
    difference = difference < 0.0 ? -difference : difference;
    if (width > 0.0 && difference > 0.5) {
        CGRect frame = self.settingsHeader.frame;
        frame.size.width = width;
        self.settingsHeader.frame = frame;
        self.tableView.tableHeaderView = self.settingsHeader;
    }
}

- (UIView *)makeSettingsHeader {
    CGFloat width = CGRectGetWidth(self.tableView.bounds);
    if (width <= 0.0) {
        width = CGRectGetWidth(self.view.bounds);
    }
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 122.0)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(8.0, 8.0, 40.0, 40.0);
    [close setImage:YTKACETemplateImage(@"", @"xmark")
            forState:UIControlStateNormal];
    close.tintColor = UIColor.labelColor;
    close.accessibilityLabel = YTKACELocalized(@"Close");
    [close addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:close];

    UIButton *apply = [UIButton buttonWithType:UIButtonTypeSystem];
    apply.frame = CGRectMake(width - 48.0, 8.0, 40.0, 40.0);
    apply.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [apply setImage:YTKACETemplateImage(@"", @"checkmark")
            forState:UIControlStateNormal];
    apply.tintColor = UIColor.labelColor;
    apply.accessibilityLabel = YTKACELocalized(@"Apply Settings");
    [apply addTarget:self action:@selector(applySettings) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:apply];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(56.0, 55.0, width - 112.0, 34.0)];
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    title.text = @"YouLite+";
    title.font = [UIFont systemFontOfSize:28.0 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;
    title.textColor = UIColor.labelColor;
    [header addSubview:title];

    UILabel *version = [[UILabel alloc] initWithFrame:CGRectMake(56.0, 89.0, width - 112.0, 20.0)];
    version.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    version.text = [NSString stringWithFormat:@"v%@", YTKACEVersion];
    version.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    version.textAlignment = NSTextAlignmentCenter;
    version.textColor = UIColor.secondaryLabelColor;
    [header addSubview:version];

    return header;
}- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    switch (section) {
        case 0: return 1;
        case 1: return 4;
        case 2: return 2;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return @[@"", YTKACELocalized(@"FEATURES"), YTKACELocalized(@"ABOUT")][(NSUInteger)section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return nil;
}

- (NSString *)deviceInformationText {
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *model = [NSString stringWithUTF8String:systemInfo.machine] ?: YTKACELocalized(@"iOS Device");
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *youtubeVersion = info[@"CFBundleShortVersionString"] ?: YTKACELocalized(@"Unknown");
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"com.google.ios.youtube";
    return [NSString stringWithFormat:YTKACELocalized(@"YouLite+ %@  •  YouTube %@\n%@\n%@  •  iOS %@"),
        YTKACEVersion, youtubeVersion, bundleID, model,
        UIDevice.currentDevice.systemVersion];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section == 0) return 68.0;
    if (indexPath.section == 2 && indexPath.row == 1) return 92.0;
    return 62.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? 1.0 : 30.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? 40.0 : 8.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section != 0) return nil;
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0,
        CGRectGetWidth(tableView.bounds), 40.0)];
    footer.backgroundColor = YTKACERootBackground();
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(24.0, 0.0,
        MAX(0.0, CGRectGetWidth(tableView.bounds) - 48.0), 18.0)];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.text = YTKACELocalized(@"Tap the checkmark to apply changes.");
    label.font = [UIFont systemFontOfSize:13.0];
    label.textColor = UIColor.secondaryLabelColor;
    [footer addSubview:label];
    return footer;
}

- (UITableViewCell *)baseCellForTableView:(UITableView *)tableView
                                    style:(UITableViewCellStyle)style {
    NSString *identifier = [NSString stringWithFormat:@"YTKACERoot-%ld", (long)style];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:identifier];
    }
    cell.backgroundColor = YTKACERootCellBackground();
    cell.textLabel.text = nil;
    cell.detailTextLabel.text = nil;
    cell.textLabel.font = [UIFont systemFontOfSize:17.0];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.tintColor = UIColor.labelColor;
    cell.imageView.image = nil;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)configureImageForCell:(UITableViewCell *)cell
                         asset:(NSString *)asset
                         symbol:(NSString *)symbol {
    cell.imageView.image = YTKACETemplateImage(asset, symbol);
}

- (void)featureSwitchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, "YTKACEKey");
    if (key.length > 0) {
        YTKACESetPreference(key, sender.isOn);
        if ([key isEqualToString:YTKACEBackgroundPlaybackKey]) {
            YTKACESetPreference(YTKACEPiPKey, sender.isOn);
        }
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView
          cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [self baseCellForTableView:tableView style:UITableViewCellStyleSubtitle];
        cell.textLabel.text = YTKACELocalized(@"Enabled");
        cell.textLabel.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = nil;
        [self configureImageForCell:cell asset:@"" symbol:@"power"];
        UILabel *status = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 0.0, 72.0, 28.0)];
        status.text = YTKACELocalized(@"ACTIVE");
        status.textAlignment = NSTextAlignmentCenter;
        status.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
        status.textColor = UIColor.systemGreenColor;
        status.backgroundColor = [UIColor.systemGreenColor colorWithAlphaComponent:0.14];
        status.layer.cornerRadius = 14.0;
        status.layer.masksToBounds = YES;
        cell.accessoryView = status;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (indexPath.section == 1) {
        NSArray *titles = @[
            YTKACELocalized(@"Block YouTube Ads"),
            YTKACELocalized(@"Background Playback & PiP"),
            YTKACELocalized(@"SponsorBlock & DeArrow"),
            YTKACELocalized(@"Premium Logo")
        ];
        NSArray *details = @[
            YTKACELocalized(@"Remove all native video and banner ads"),
            YTKACELocalized(@"Play audio in background and enable Picture-in-Picture"),
            YTKACELocalized(@"Automatically skip sponsored segments"),
            YTKACELocalized(@"Display YouTube Premium logo")
        ];
        NSArray *keys = @[
            YTKACENoAdsKey,
            YTKACEBackgroundPlaybackKey,
            YTKACESponsorBlockKey,
            @"YTKACE.Preference.Navigation.PremiumLogo"
        ];
        NSArray *symbols = @[@"shield.slash", @"play.rectangle", @"play.shield", @"star"];

        UITableViewCell *cell = [self baseCellForTableView:tableView style:UITableViewCellStyleSubtitle];
        cell.textLabel.text = titles[(NSUInteger)indexPath.row];
        cell.detailTextLabel.text = details[(NSUInteger)indexPath.row];
        [self configureImageForCell:cell asset:@"" symbol:symbols[(NSUInteger)indexPath.row]];

        UISwitch *toggle = [UISwitch new];
        toggle.on = YTKACEFeatureEnabled(keys[(NSUInteger)indexPath.row]);
        objc_setAssociatedObject(toggle, "YTKACEKey", keys[(NSUInteger)indexPath.row], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [toggle addTarget:self action:@selector(featureSwitchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (indexPath.row == 1) {
        UITableViewCell *cell = [self baseCellForTableView:tableView style:UITableViewCellStyleDefault];
        cell.textLabel.text = [self deviceInformationText];
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.textLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightRegular];
        cell.textLabel.numberOfLines = 3;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    UITableViewCell *cell = [self baseCellForTableView:tableView style:UITableViewCellStyleSubtitle];
    cell.textLabel.text = @"hieucocc";
    cell.detailTextLabel.text = YTKACELocalized(@"Forked from YTKACE by itzzace");
    cell.imageView.image = YTKACEAssetImage(@"YTKIco", @"person.crop.circle");
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2 && indexPath.row == 0) {
        NSURL *URL = [NSURL URLWithString:@"https://github.com/hieucocc/YouLitePlus"];
        [UIApplication.sharedApplication openURL:URL options:@{} completionHandler:nil];
    }
}

- (void)masterChanged:(UISwitch *)sender {
    (void)sender;
    YTKACESetPreference(YTKACEMasterEnabledKey, YES);
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                 withRowAnimation:UITableViewRowAnimationNone];
}

- (void)applySettings {
    [NSUserDefaults.standardUserDefaults synchronize];
    [NSNotificationCenter.defaultCenter postNotificationName:@"YTKACEPreferencesDidChange"
                                                      object:nil];
    [NSNotificationCenter.defaultCenter postNotificationName:@"YTKACETabConfigDidChange"
                                                      object:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        exit(0);
    });
}

- (void)closeSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

UINavigationController *YTKACEMakeSettingsNavigationController(void) {
    YTKACERootOptionsController *root = [YTKACERootOptionsController new];
    UINavigationController *navigation = [[UINavigationController alloc]
        initWithRootViewController:root];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    objc_setAssociatedObject(navigation, YTKACEOwnedNavigationKey, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return navigation;
}

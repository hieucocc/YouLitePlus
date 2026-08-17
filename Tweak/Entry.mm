#import "YTKACE.h"
#import "Features/SponsorBlock/DeArrow.h"
#import "Runtime/Preferences.h"

#import <UIKit/UIKit.h>

NSString * const YTKACEVersion = @"1.0.0";

static void YTKACEInstallModules(void) {
    YTKACEInstallSideloadCompatibilityHooks();
    YTKACEInstallAdsHooks();
    YTKACEInstallPromoHooks();
    YTKACEInstallSponsorBlockHooks();
    YTKACEInstallDeArrow();
    YTKACEInstallStartupHooks();
    YTKACEInstallPremiumLogoHooks();
    YTKACEInstallBackgroundPlaybackHooks();
    YTKACEInstallPiPHooks();
    YTKACEInstallSettingsEntryHooks();
    YTKACEInstallNativeSettingsHooks();
}

__attribute__((constructor))
static void YTKACEEntryPoint(void) {
    @autoreleasepool {
        YTKACERegisterDefaults();
        YTKACEInstallModules();
    }
}


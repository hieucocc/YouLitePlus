ARCHS = arm64
TARGET = iphone:clang:latest:16.0
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = YouLitePlus

YouLitePlus_FILES = \
	Tweak/Entry.mm \
	Tweak/Runtime/Hooking.mm \
	Tweak/Runtime/Preferences.mm \
	Tweak/Runtime/Localization.mm \
	Tweak/UI/Assets.mm \
	Tweak/UI/Notice.mm \
	Tweak/UI/OverlayButtonHost.mm \
	Tweak/Features/Ads/AdsHooks.mm \
	Tweak/Features/Ads/PromoHooks.mm \
	Tweak/Features/SponsorBlock/SponsorClient.mm \
	Tweak/Features/SponsorBlock/SponsorPreferences.mm \
	Tweak/Features/SponsorBlock/SponsorHooks.mm \
	Tweak/Features/SponsorBlock/DeArrow.mm \
	Tweak/Features/Appearance/StartupHooks.mm \
	Tweak/Features/Appearance/PremiumLogoHooks.mm \
	Tweak/Features/Playback/BackgroundPlaybackHooks.mm \
	Tweak/Features/Playback/PiPControls.mm \
	Tweak/Features/Compatibility/SideloadCompatibility.mm \
	Tweak/Settings/SettingsEntry.mm \
	Tweak/Settings/NativeSettingsEntry.mm \
	Tweak/Settings/YTKACERootOptionsController.mm \
	Tweak/Settings/YTKACESettingsPages.mm \
	Tweak/Settings/YTKACESettingsSearch.mm

YouLitePlus_CFLAGS = -fobjc-arc -Wall -Wextra -Werror=return-type
YouLitePlus_CFLAGS += -Wno-module-import-in-extern-c
YouLitePlus_CCFLAGS = -std=c++17
YouLitePlus_FRAMEWORKS = Foundation UIKit AVFoundation AVKit AudioToolbox QuartzCore MediaPlayer Security SystemConfiguration CoreMedia
YouLitePlus_LIBRARIES = z
YouLitePlus_LDFLAGS = -Wl,-install_name,@rpath/YouLitePlus.dylib
YouLitePlus_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/library.mk

after-all::
	@mkdir -p "$(THEOS_PROJECT_DIR)/dist"
	@cp "$(THEOS_OBJ_DIR)/YouLitePlus.dylib" "$(THEOS_PROJECT_DIR)/dist/YouLitePlus.dylib"

after-stage::
	@mkdir -p "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries"
	@cp -R "$(THEOS_PROJECT_DIR)/Resources/YTKACE.bundle" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/YTKACE.bundle"
	@cp "$(THEOS_PROJECT_DIR)/YouLitePlus.plist" "$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/YouLitePlus.plist"



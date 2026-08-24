include $(THEOS)/makefiles/common.mk

THEOS_PACKAGE_SCHEME = rootless

BUNDLE_NAME = AppVersionPrefs
AppVersionPrefs_FILES = AVRootListController.m
AppVersionPrefs_INSTALL_PATH = /Library/PreferenceBundles
AppVersionPrefs_CFLAGS = -fobjc-arc
AppVersionPrefs_FRAMEWORKS = UIKit
AppVersionPrefs_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

# PreferenceLoader finds the Settings entry by this plist, not by the bundle.
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/AppVersion.plist$(ECHO_END)

include $(THEOS)/makefiles/common.mk

THEOS_PACKAGE_SCHEME = rootless

BUNDLE_NAME = PseudonymPrefs
PseudonymPrefs_FILES = PSRootListController.m PSApps.m PSPrefsStore.m
PseudonymPrefs_INSTALL_PATH = /Library/PreferenceBundles
PseudonymPrefs_CFLAGS = -fobjc-arc
PseudonymPrefs_FRAMEWORKS = UIKit CoreLocation
PseudonymPrefs_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

# PreferenceLoader finds the Settings entry by this plist, not by the bundle.
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/Pseudonym.plist$(ECHO_END)

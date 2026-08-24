# Separate package from Pseudonym on purpose. Pseudonym refuses com.apple.*
# because spoofing identifiers inside system processes breaks activation and
# push; rewriting one version field in the App Store is a narrow, unrelated
# thing and should not be entangled with the identity logic.
TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = AppStore itunesstored appstored

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AppVersion
AppVersion_FILES = src/AVHooks.x src/AVLog.m src/AVRedact.m
AppVersion_CFLAGS = -fobjc-arc -Isrc
AppVersion_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

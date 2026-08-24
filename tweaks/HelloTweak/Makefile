# Rootless tweak for palera1n on iOS 15-16. Build inside the Docker image
# described in README.md; Theos does not run natively on Windows.
TARGET := iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HelloTweak
HelloTweak_FILES = HelloTweak.x
HelloTweak_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

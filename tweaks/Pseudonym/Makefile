# Rootless tweak for palera1n on iOS 15-16. Build in the Docker image from
# README.md; Theos does not run natively on Windows.
TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Pseudonym
Pseudonym_FILES = src/Tweak.x src/PSConfig.m src/PSIdentity.m src/PSProfile.m \
                  src/PSHooksDevice.x src/PSHooksSysctl.x src/PSHooksKeychain.x
Pseudonym_CFLAGS = -fobjc-arc -Isrc
Pseudonym_FRAMEWORKS = UIKit Foundation Security
Pseudonym_PRIVATE_FRAMEWORKS = AdSupport

include $(THEOS_MAKE_PATH)/tweak.mk

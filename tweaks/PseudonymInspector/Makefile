# Deliberately depends on nothing from Pseudonym. It reads its own identity
# through public APIs only, so with the tweak disabled it shows ground truth and
# with the tweak enabled it shows whatever the hooks actually produce. Sharing
# code with the tweak would let both be wrong in the same direction.
TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = PseudonymInspector
PseudonymInspector_FILES = main.m PIViewController.m
PseudonymInspector_FRAMEWORKS = UIKit AdSupport CoreLocation
PseudonymInspector_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/application.mk

TARGET := iphone:clang:latest:16.0
ARCHS := arm64e
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = XAutoTranslate

XAutoTranslate_FILES = Tweak.x
XAutoTranslate_CFLAGS = -fobjc-arc
XAutoTranslate_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

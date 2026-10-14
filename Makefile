TARGET := iphone:clang:latest:15.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = XAutoTranslate

XAutoTranslate_FILES = Tweak.m
XAutoTranslate_CFLAGS = -fobjc-arc
XAutoTranslate_FRAMEWORKS = UIKit Foundation CoreGraphics
XAutoTranslate_LDFLAGS = -Wl,-no_fixup_chains

include $(THEOS_MAKE_PATH)/library.mk

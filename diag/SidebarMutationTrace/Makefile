TARGET := iphone:clang:16.5:16.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = ChatGPT

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZZZZZChatGPTSidebarTrace
ZZZZZChatGPTSidebarTrace_FILES = Tweak.m
ZZZZZChatGPTSidebarTrace_CFLAGS = -fobjc-arc -fblocks -Wno-deprecated-declarations
ZZZZZChatGPTSidebarTrace_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

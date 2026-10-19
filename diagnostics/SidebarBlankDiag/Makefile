TARGET := iphone:clang:16.5:16.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = ChatGPT

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZZZZChatGPTSidebarBlankDiag
ZZZZChatGPTSidebarBlankDiag_FILES = Tweak.m
ZZZZChatGPTSidebarBlankDiag_CFLAGS = -fobjc-arc -fblocks -Wno-deprecated-declarations
ZZZZChatGPTSidebarBlankDiag_FRAMEWORKS = Foundation UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

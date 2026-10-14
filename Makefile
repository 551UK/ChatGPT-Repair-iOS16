TARGET := iphone:clang:16.5:16.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = ChatGPT

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ChatGPTRepair
ChatGPTRepair_FILES = src/HistoryIsolation.m
ChatGPTRepair_CFLAGS = -fobjc-arc -fblocks -Wno-deprecated-declarations
ChatGPTRepair_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

TARGET := iphone:clang:16.5:16.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = ChatGPT

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ChatGPTRepair
ChatGPTRepair_FILES = src/CompatibilityBoot.m src/CitationCompat.m src/RichMarkupCompat.m src/RendererCitationGuard.m src/ConversationPagingCore.m src/ConversationPagingState.m src/ConversationPagingNetwork.m src/ConversationPagingOlder.m src/ConversationPagingScrollHook.m src/HistoryIsolation.m src/HistoryPageCache.m src/HistoryOriginMerge.m src/PinService.m src/PinnedSectionLayout.m src/PinnedSectionStore.m src/PinnedSidebarView.m src/PinnedLayoutShim.m src/PinnedSidebarIntegration.m src/DirectPinSelection.m src/DirectPinABI.S
ChatGPTRepair_CFLAGS = -fobjc-arc -fblocks -Wno-deprecated-declarations
ChatGPTRepair_FRAMEWORKS = Foundation UIKit CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

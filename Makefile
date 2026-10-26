# Compile all ChatGPTRepair source files into one rootless iOS tweak.
TARGET := iphone:clang:16.5:16.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = ChatGPT

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ChatGPTRepair
ChatGPTRepair_FILES = \
	src/VoiceBridge.m \
	src/RealtimeVoice.m \
	src/NativeVoiceLifecycle.m \
	src/SDPTransform.m \
	src/CopyBridge.m \
	src/ImageBridge.m \
	src/ModelSwitcher.m \
	src/ModelSelectionPersistence.m \
	src/RuntimeResolver.m \
	src/CitationCompat.m \
	src/RichMarkupCompat.m \
	src/RendererCitationGuard.m \
	src/ConversationPagingCore.m \
	src/ConversationPagingState.m \
	src/ConversationPagingNetwork.m \
	src/ConversationLiveSync.m \
	src/ConversationLivePreview.m \
	src/HistoryIsolation.m \
	src/HistoryPageCache.m \
	src/HistoryOriginMerge.m \
	src/PinService.m \
	src/PinnedSectionLayout.m \
	src/PinnedSectionStore.m \
	src/PinnedSidebarView.m \
	src/PinnedLayoutShim.m \
	src/PinnedSidebarIntegration.m \
	src/DirectPinSelection.m \
	src/DirectPinABI.S \
	src/DownloadFix.m \
	src/LinkFix.m
ChatGPTRepair_CFLAGS = -fobjc-arc -fblocks -fvisibility=hidden -Wno-deprecated-declarations
ChatGPTRepair_FRAMEWORKS = Foundation UIKit CoreGraphics AVFoundation
ChatGPTRepair_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

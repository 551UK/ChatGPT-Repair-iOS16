# Compile all ChatGBeFree 2.4.0 and 551UK repair modules into one rootless ChatGPTRepair tweak.
TARGET := iphone:clang:16.5:16.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = ChatGPT

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ChatGPTRepair
ChatGPTRepair_FILES = \
	upstream/chatgbefree/VoiceBridge/LegacyVoiceBridge.m \
	upstream/chatgbefree/VoiceBridge/LegacyRealtimeVoice.m \
	upstream/chatgbefree/VoiceBridge/LegacyNativeVoiceLifecycle.m \
	upstream/chatgbefree/VoiceBridge/LegacySDPTransform.m \
	upstream/chatgbefree/CopyBridge/LegacyCopyBridge.m \
	upstream/chatgbefree/ImageBridge/LegacyImageBridge.m \
	upstream/chatgbefree/ModelSwitcher/LegacyModelSwitcher.m \
	upstream/chatgbefree/ModelSwitcher/LegacyModelSelectionPersistence.m \
	upstream/chatgbefree/Runtime/ChatGPTRuntimeResolver.m \
	src/CitationCompat.m \
	src/RichMarkupCompat.m \
	src/RendererCitationGuard.m \
	src/ConversationPagingCore.m \
	src/ConversationPagingState.m \
	src/ConversationPagingNetwork.m \
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

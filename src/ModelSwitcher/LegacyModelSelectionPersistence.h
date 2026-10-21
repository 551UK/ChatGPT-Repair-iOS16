// ChatGPTRepair: Remembered model selection declarations; based on ChatGBeFree 2.4.0.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Hooks the supported legacy ChatGPT build's ModelContext.select(...) entry
/// point so a picker tap is persisted before the next app launch.
void CGBInstallLegacyModelSelectionPersistenceBridge(void);

NS_ASSUME_NONNULL_END

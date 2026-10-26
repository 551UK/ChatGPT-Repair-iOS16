// The assembly adapters target ONLY the verified 1.2024.200 ARM64 framework.
import Foundation

@_silgen_name("CGNativeRemoteIDThunk")
private func nativeRemoteID(_ coordinator: AnyObject) -> String?

@_silgen_name("CGNativeRefreshThunk")
private func nativeRefresh(_ coordinator: AnyObject) async throws

@_cdecl("CGNativeCoordinatorMatches")
public func coordinatorMatches(_ coordinator: AnyObject, _ identifier: NSString) -> Bool {
    return nativeRemoteID(coordinator) == (identifier as String)
}

@_cdecl("CGNativeStartRefresh")
public func startRefresh(_ coordinator: AnyObject,
                         _ completion: @escaping @convention(block) (Bool) -> Void) {
    // Keep the existing coordinator alive for the entire async operation.
    Task { @MainActor in
        do {
            try await nativeRefresh(coordinator)
            completion(true)
        } catch {
            completion(false)
        }
    }
}

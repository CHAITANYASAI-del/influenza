import LocalAuthentication
import Observation
import SwiftUI

@MainActor
@Observable
final class AppLock {
    var isLocked: Bool
    var lastError: String?

    @ObservationIgnored
    @AppStorage("appLockEnabled") var isEnabled = true

    init() {
        isLocked = UserDefaults.standard.object(forKey: "appLockEnabled") as? Bool ?? true
    }

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    func lockIfNeeded() { if isEnabled { isLocked = true } }

    /// `.deviceOwnerAuthentication` = biometrics with automatic fallback to the
    /// device passcode, so users are never locked out if Face ID fails.
    func unlock() async {
        guard isEnabled else { isLocked = false; return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode set on device: nothing to authenticate against.
            isLocked = false
            return
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                      localizedReason: "Unlock your spending")
            isLocked = !ok
            lastError = nil
        } catch {
            lastError = "Couldn't verify it's you. Try again."
        }
    }
}

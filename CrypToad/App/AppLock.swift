import Foundation
import LocalAuthentication
import Observation

/// Face ID / Touch ID gate for the app.
///
/// Uses `.deviceOwnerAuthentication`, which tries biometrics first and falls back to
/// the device passcode. Biometric data never leaves the Secure Enclave; the app only
/// learns whether authentication succeeded.
@Observable
@MainActor
final class AppLock {
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    private(set) var lastError: String?

    init(startLocked: Bool = false) {
        isLocked = startLocked
    }

    /// "Face ID", "Touch ID", "Optic ID", or "Passcode" depending on the device.
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

    var biometryIcon: String {
        switch biometryName {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default: return "lock"
        }
    }

    func lock() {
        isLocked = true
    }

    func unlock(reason: String = "Unlock CrypToad") async {
        if await authenticate(reason: reason) {
            isLocked = false
        }
    }

    /// Asks the user to authenticate. Returns `true` on success.
    func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No passcode/biometrics set up (common on a fresh simulator).
            // In debug builds let the developer through; in release, refuse.
            #if DEBUG
            lastError = nil
            return true
            #else
            lastError = error?.localizedDescription ?? "Set up a passcode to use this feature."
            return false
            #endif
        }

        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            lastError = nil
            return success
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

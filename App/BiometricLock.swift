import LocalAuthentication

/// Task 10.4's "Optional Face ID lock (`LocalAuthentication`)" for the
/// Clipboard tab.
enum BiometricLock {
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics/passcode enrolled at all — fail open rather
            // than permanently locking someone out of their own clipboard
            // with no way to unlock it.
            return true
        }
        return await (try? context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

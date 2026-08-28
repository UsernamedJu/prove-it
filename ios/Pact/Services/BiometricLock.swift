import Foundation
import LocalAuthentication

/// Face ID / Touch ID app lock — fully functional today on any account tier,
/// unlike Sign in with Apple and HealthKit. No entitlement or paid Developer
/// Program membership is required for `LocalAuthentication`.
@MainActor
enum BiometricLock {
    static func unlock(reason: String = "Unlock Prove it") async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
}

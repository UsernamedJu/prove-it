import Foundation
import HealthKit

/// Reads step count from Apple Health — which is how Apple Watch data
/// reaches this app. There's no separate watchOS companion here: the Watch
/// already writes steps/workouts into Health on its own, so authorizing
/// HealthKit is the entire integration.
///
/// The HealthKit *capability* itself needs to be enabled in the Xcode
/// project's Signing & Capabilities tab, which requires a paid Apple
/// Developer Program membership (the same restriction that applies to
/// Sign in with Apple). This class is safe to ship without that: on a free
/// account, `isHealthDataAvailable` still reports true in the Simulator,
/// but `requestAuthorization` will fail gracefully rather than crash, and
/// every call site here treats "not connected" as a normal, expected state.
@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()

    private var stepType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .stepCount) }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async -> Bool {
        guard isAvailable, let stepType else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [stepType])
            return true
        } catch {
            return false
        }
    }

    /// Today's step count so far, or `nil` if unavailable/unauthorized.
    func fetchTodaySteps() async -> Int? {
        guard isAvailable, let stepType else { return nil }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                let steps = result?.sumQuantity()?.doubleValue(for: .count())
                continuation.resume(returning: steps.map { Int($0) })
            }
            store.execute(query)
        }
    }
}

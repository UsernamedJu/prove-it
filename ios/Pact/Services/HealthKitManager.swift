import Foundation
import HealthKit

/// One real running workout read from Health — not a challenge-progress
/// number, an actual logged run with its own date/distance/duration.
struct RunSummary: Identifiable {
    let id = UUID()
    let date: Date
    let distanceMiles: Double
    let duration: TimeInterval

    var pacePerMile: TimeInterval? {
        guard distanceMiles > 0.05 else { return nil }
        return duration / distanceMiles
    }
}

/// Reads step count and walking/running distance from Apple Health — which
/// is how Apple Watch data reaches this app. There's no separate watchOS
/// companion here: the Watch already writes steps/workouts into Health on
/// its own, so authorizing HealthKit is the entire integration.
///
/// This is what makes "Provyr" mean something: without it, "Log Today" was
/// an honor-system tap that always credited the same fixed amount whether
/// you actually moved or not. With a real Apple Developer Program
/// membership behind the entitlement, a steps or distance challenge's
/// progress can come from what Health actually recorded instead.
///
/// Safe to ship even where the capability isn't fully provisioned yet: on
/// a free account `isHealthDataAvailable` still reports true in the
/// Simulator, but `requestAuthorization` fails gracefully rather than
/// crashing, and every call site here treats "not connected" as a normal,
/// expected state — the manual "Log Today" tap is always the fallback.
@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()

    private var stepType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .stepCount) }
    private var distanceType: HKQuantityType? { HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async -> Bool {
        guard isAvailable, let stepType, let distanceType else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [stepType, distanceType, HKObjectType.workoutType()])
            return true
        } catch {
            return false
        }
    }

    /// The most recent real running workouts, newest first — what actually
    /// backs "track runs" beyond just a cumulative daily distance number.
    /// Every field here (date, distance, duration) is exactly what Health
    /// recorded for that workout, not derived or estimated.
    func fetchRecentRuns(limit: Int = 5) async -> [RunSummary] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForWorkouts(with: .running)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: limit, sortDescriptors: [sort]) { _, samples, _ in
                let runs = (samples as? [HKWorkout] ?? []).map { workout in
                    // `.totalDistance` is deprecated in favor of
                    // `statistics(for:)`, but that newer API only returns
                    // anything for workouts saved via HKWorkoutBuilder with
                    // per-type statistics attached — not guaranteed for
                    // every real workout regardless of source. totalDistance
                    // reliably works for any of them, which matters more
                    // here than clearing one deprecation warning.
                    RunSummary(date: workout.endDate,
                               distanceMiles: workout.totalDistance?.doubleValue(for: .mile()) ?? 0,
                               duration: workout.duration)
                }
                continuation.resume(returning: runs)
            }
            store.execute(query)
        }
    }

    /// Today's step count so far, or `nil` if unavailable/unauthorized.
    func fetchTodaySteps() async -> Int? {
        guard isAvailable, let stepType else { return nil }
        return await todaySum(for: stepType).map { Int($0) }
    }

    /// Today's walking + running distance in miles so far, or `nil` if
    /// unavailable/unauthorized.
    func fetchTodayDistanceMiles() async -> Double? {
        guard isAvailable, let distanceType else { return nil }
        guard let meters = await todaySum(for: distanceType, unit: .meter()) else { return nil }
        return meters / 1609.344
    }

    private func todaySum(for type: HKQuantityType, unit: HKUnit = .count()) async -> Double? {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
}

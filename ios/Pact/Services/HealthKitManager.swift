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

    private var isObserving = false

    /// Registers a live observer + background delivery for steps,
    /// distance, and workouts — this is what makes logging actually
    /// automatic: Health calls this app back the moment it has new data
    /// (whether the app is open or not, given
    /// com.apple.developer.healthkit.background-delivery in the
    /// entitlements), instead of only ever updating when someone
    /// remembers to tap "Sync from Health." Safe to call more than once —
    /// guards against registering duplicate observers if connect is
    /// re-triggered (e.g. a fresh app launch re-verifying a previous
    /// session's connection).
    func startObservingChanges(onUpdate: @escaping () -> Void) {
        guard !isObserving, isAvailable, let stepType, let distanceType else { return }
        isObserving = true
        for type in [stepType, distanceType, HKObjectType.workoutType()] {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, _ in
                onUpdate()
                completionHandler()
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
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
        return await sum(for: stepType, since: Calendar.current.startOfDay(for: Date())).map { Int($0) }
    }

    /// Today's walking + running distance in miles so far, or `nil` if
    /// unavailable/unauthorized.
    func fetchTodayDistanceMiles() async -> Double? {
        guard isAvailable, let distanceType else { return nil }
        guard let meters = await sum(for: distanceType, unit: .meter(), since: Calendar.current.startOfDay(for: Date())) else { return nil }
        return meters / 1609.344
    }

    /// Rolling totals over the last `days` — used for milestones like
    /// "26.2 miles in a month," which need a real cumulative sum over a
    /// window, not a single day's snapshot.
    func fetchTotalSteps(days: Int) async -> Int? {
        guard isAvailable, let stepType else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return await sum(for: stepType, since: start).map { Int($0) }
    }

    func fetchTotalDistanceMiles(days: Int) async -> Double? {
        guard isAvailable, let distanceType else { return nil }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        guard let meters = await sum(for: distanceType, unit: .meter(), since: start) else { return nil }
        return meters / 1609.344
    }

    /// Steps/distance since an arbitrary date — a challenge's own
    /// `startDate` — so progress only ever reflects activity that happened
    /// *after* joining, never whatever steps already existed that day
    /// before the challenge began.
    func fetchTotalSteps(since date: Date) async -> Int? {
        guard isAvailable, let stepType else { return nil }
        return await sum(for: stepType, since: date).map { Int($0) }
    }

    func fetchTotalDistanceMiles(since date: Date) async -> Double? {
        guard isAvailable, let distanceType else { return nil }
        guard let meters = await sum(for: distanceType, unit: .meter(), since: date) else { return nil }
        return meters / 1609.344
    }

    private func sum(for type: HKQuantityType, unit: HKUnit = .count(), since start: Date) async -> Double? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
}

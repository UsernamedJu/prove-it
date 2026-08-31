import Foundation
import CloudKit
import UserNotifications

/// Owns every CKShare-backed challenge this device knows about: ones this
/// iCloud account created (owner, records live in the private database)
/// and ones accepted from someone else's invite (participant, records live
/// in the shared database). See `SharedChallenge.swift` for why this is a
/// separate system from the Fixtures-based `Challenge`/`AppModel.challenges`.
///
/// Formerly-scoped-out limitations, now closed:
/// - **Real-time delivery**: each zone gets a `CKRecordZoneSubscription` on
///   whichever database this account reads it from, with silent push
///   (`shouldSendContentAvailable`). `CloudShareDelegate` registers for
///   remote notifications at launch and refreshes on receipt — CloudKit
///   sends these directly, no server of this app's own involved. Progress
///   from the other participant now shows up without waiting for the app
///   to be foregrounded. A visible local notification ("so-and-so made
///   progress") fires too, once notification permission is granted.
/// - **Cross-device index**: "which shared challenges am I in" now syncs
///   through a second `CloudSyncManager` instance, the same private-data
///   sync AppModel's own profile uses, merged by simple union (these are
///   just record-ID pointers to re-fetch, not opinionated state, so there's
///   no last-write-wins conflict to resolve).
/// - **Fallback discovery**: `refresh()` also enumerates
///   `sharedCloudDatabase.allRecordZones()` for anything CloudKit says is
///   shared with this account that isn't in the known index yet — covers a
///   share accepted some other way, or a lost/never-synced local index.
///
/// What's still out of scope: this is still 1:1 challenge sharing, not the
/// demo crew becoming real, and push delivery can only be verified against
/// a real device with notification permission granted — the Simulator has
/// no APNs token to receive an actual silent push against.
///
/// Same "never crash, never leave the model in a broken state" philosophy
/// as `HealthKitManager` / `CloudSyncManager` for the read paths (`refresh`
/// just leaves `challenges` as it was on failure). `createSharedChallenge`
/// and `acceptShare` are user-initiated actions the caller is actively
/// waiting on, so those throw / set `lastError` instead of failing silently.
@MainActor
@Observable
final class SharedChallengeStore {
    static let shared = SharedChallengeStore()

    private let container = CKContainer(identifier: "iCloud.com.jean.pact")
    private let challengeType = "SharedChallenge"
    private let entryType = "SharedEntry"
    private static let indexDefaultsKey = "com.jean.pact.sharedChallengeIndex"

    var challenges: [SharedChallenge] = []
    var lastError: String?
    var isBusy = false
    /// Cached from the last `refresh`/`acceptShare`/`createSharedChallenge`
    /// call — lets a silent push notification trigger a refresh (see
    /// `CloudShareDelegate`) without needing to plumb "who am I" all the
    /// way from AppModel into a bare UIApplicationDelegate callback.
    private var lastKnownMe: (id: UUID, name: String)?

    private init() {}

    // MARK: Local index — just enough to know what to re-fetch on launch

    private struct IndexEntry: Codable, Equatable {
        var zoneName: String
        var recordName: String
        var isOwnedByMe: Bool
        var shareRecordName: String?
    }

    /// Syncs *which* challenges this account knows about (record IDs only —
    /// CloudKit's own records stay the source of truth for the actual
    /// progress data) across this account's devices, the same way
    /// `CloudSyncManager.shared` syncs AppModel's profile. A distinct
    /// record name so it doesn't collide with that one.
    private let indexSync = CloudSyncManager(recordName: "SharedChallengeIndex", recordType: "SharedChallengeIndexRecord")

    /// Merges the local index with whatever's in this account's synced
    /// copy (a plain union by zone name — these are just pointers to check,
    /// not opinionated state, so there's no last-write-wins conflict to
    /// resolve) and writes the merged result back to both, so a challenge
    /// accepted on one device shows up here on the next launch too.
    private func loadIndex() async -> [IndexEntry] {
        let local = localIndex()
        guard let cloudData = await indexSync.fetch(),
              let cloudEntries = try? JSONDecoder().decode([IndexEntry].self, from: cloudData) else { return local }
        var merged = local
        for entry in cloudEntries where !merged.contains(where: { $0.zoneName == entry.zoneName }) {
            merged.append(entry)
        }
        if merged.count != local.count { writeIndex(merged) }
        return merged
    }

    private func localIndex() -> [IndexEntry] {
        guard let data = UserDefaults.standard.data(forKey: Self.indexDefaultsKey),
              let entries = try? JSONDecoder().decode([IndexEntry].self, from: data) else { return [] }
        return entries
    }

    private func writeIndex(_ entries: [IndexEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.indexDefaultsKey)
        Task { await indexSync.upload(data) }
    }

    private func saveIndex() {
        let entries = challenges.map {
            IndexEntry(zoneName: $0.zoneID.zoneName, recordName: $0.rootRecordID.recordName,
                       isOwnedByMe: $0.isOwnedByMe, shareRecordName: $0.shareRecordID?.recordName)
        }
        writeIndex(entries)
    }

    // MARK: Create + invite

    /// Creates a brand-new zone + root challenge record + this device's own
    /// entry record, shares the root, and returns the URL to send a real
    /// person. Throws on any failure — the caller is a form the user is
    /// actively filling out, so unlike the read paths, failure here needs
    /// to actually surface.
    func createSharedChallenge(title: String, kind: ChallengeKind, venue: String, rules: String,
                                dailyTarget: Int, durationDays: Int, payoff: Payoff,
                                myLocalID: UUID, myName: String) async throws -> URL {
        lastKnownMe = (myLocalID, myName)
        // CKShare specifically needs a real, fully authenticated iCloud
        // account — not just "CloudKit is reachable," which is all
        // `isAvailable` elsewhere in this file checks for the read paths.
        // Without this check, a signed-out/guest device hits a raw,
        // cryptic CKError partway through record creation instead of a
        // message that actually says what to do about it.
        guard (try? await container.accountStatus()) == .available else {
            throw CloudSharingError.notSignedIn
        }
        let zoneID = CKRecordZone.ID(zoneName: "Challenge-\(UUID().uuidString)")
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await container.privateCloudDatabase.save(zone)

        let localID = UUID().uuidString
        let root = CKRecord(recordType: challengeType, recordID: CKRecord.ID(zoneID: zoneID))
        root["localID"] = localID
        root["title"] = title
        root["kindRaw"] = kind.rawValue
        root["venue"] = venue
        root["rules"] = rules
        root["dailyTarget"] = dailyTarget
        root["durationDays"] = durationDays
        root["payoffIcon"] = payoff.icon
        root["payoffText"] = payoff.text
        root["createdAt"] = Date()

        let entry = CKRecord(recordType: entryType, recordID: CKRecord.ID(zoneID: zoneID))
        entry.parent = CKRecord.Reference(record: root, action: .none)
        entry["localID"] = myLocalID.uuidString
        entry["participantName"] = myName
        entry["progress"] = 0.0
        entry["progressHistory"] = [0.0]
        entry["lastLogVerified"] = 0

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        share.publicPermission = .readWrite

        _ = try await container.privateCloudDatabase.modifyRecords(saving: [root, entry, share], deleting: [])

        guard let url = share.url else {
            throw CloudSharingError.noShareURL
        }

        let mine = SharedEntry(localID: myLocalID.uuidString, recordID: entry.recordID,
                                participantName: myName, progress: 0, progressHistory: [0],
                                lastLogVerified: false, isMe: true)
        let challenge = SharedChallenge(localID: localID, rootRecordID: root.recordID, zoneID: zoneID,
                                         isOwnedByMe: true, shareRecordID: share.recordID,
                                         title: title, kind: kind, venue: venue,
                                         rules: rules, dailyTarget: dailyTarget, durationDays: durationDays,
                                         payoff: payoff, createdAt: Date(), entries: [mine])
        challenges.append(challenge)
        saveIndex()
        requestNotificationPermissionIfNeeded()
        await subscribeToZoneChanges(zoneID: zoneID, database: container.privateCloudDatabase)
        return url
    }

    /// Re-fetches the invite link for a challenge I own — needed because
    /// the URL is only ever handed to the caller once, at creation time.
    func shareURL(for challengeLocalID: String) async -> URL? {
        guard let challenge = challenges.first(where: { $0.localID == challengeLocalID }),
              let shareRecordID = challenge.shareRecordID,
              let record = try? await container.privateCloudDatabase.record(for: shareRecordID) as? CKShare else { return nil }
        return record.url
    }

    // MARK: Accept an invite

    /// Accepts a CKShare this device just opened a link for, then fetches
    /// the challenge it points to and adds this device's own entry record
    /// so there's something for the owner to actually see progress from.
    func acceptShare(metadata: CKShare.Metadata, myLocalID: UUID, myName: String) async {
        lastKnownMe = (myLocalID, myName)
        isBusy = true
        defer { isBusy = false }
        do {
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.acceptSharesResultBlock = { result in
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
                container.add(operation)
            }
            try await fetchJoinedChallenge(rootRecordID: metadata.rootRecordID, myLocalID: myLocalID, myName: myName)
            lastError = nil
        } catch {
            lastError = "Couldn't join that challenge: \(error.localizedDescription)"
        }
    }

    private func fetchJoinedChallenge(rootRecordID: CKRecord.ID, myLocalID: UUID, myName: String) async throws {
        let database = container.sharedCloudDatabase
        let root = try await database.record(for: rootRecordID)
        let entries = await ensuringMyEntry(
            in: try await fetchEntries(database: database, zoneID: rootRecordID.zoneID, myLocalID: myLocalID),
            root: root, zoneID: rootRecordID.zoneID, database: database, myLocalID: myLocalID, myName: myName
        )
        let challenge = try challenge(from: root, zoneID: rootRecordID.zoneID, isOwnedByMe: false, shareRecordID: nil, entries: entries)
        challenges.removeAll { $0.localID == challenge.localID }
        challenges.append(challenge)
        saveIndex()
        requestNotificationPermissionIfNeeded()
        await subscribeToZoneChanges(zoneID: rootRecordID.zoneID, database: database)
    }

    /// Bootstraps this account's own progress record into a shared zone if
    /// it isn't there yet — the same "just joined, nothing written for me
    /// here yet" step both the explicit accept flow and the fallback
    /// discovery scan below need.
    private func ensuringMyEntry(in entries: [SharedEntry], root: CKRecord, zoneID: CKRecordZone.ID,
                                  database: CKDatabase, myLocalID: UUID, myName: String) async -> [SharedEntry] {
        guard !entries.contains(where: { $0.isMe }) else { return entries }
        let entry = CKRecord(recordType: entryType, recordID: CKRecord.ID(zoneID: zoneID))
        entry.parent = CKRecord.Reference(record: root, action: .none)
        entry["localID"] = myLocalID.uuidString
        entry["participantName"] = myName
        entry["progress"] = 0.0
        entry["progressHistory"] = [0.0]
        entry["lastLogVerified"] = 0
        guard (try? await database.modifyRecords(saving: [entry], deleting: [])) != nil else { return entries }
        return entries + [SharedEntry(localID: myLocalID.uuidString, recordID: entry.recordID,
                                       participantName: myName, progress: 0, progressHistory: [0],
                                       lastLogVerified: false, isMe: true)]
    }

    /// Finds challenges shared with this iCloud account that this app
    /// never recorded in its own local index — e.g. a share accepted
    /// through some path other than `CloudShareDelegate`'s callback, or a
    /// fresh install that lost the local index. `sharedCloudDatabase`
    /// itself is the authority on what's actually been shared with this
    /// account, so this is a real fallback, not a guess: every zone
    /// returned here is a zone CloudKit says this account can see.
    private func discoverUnknownSharedZones(knownZoneNames: Set<String>, myLocalID: UUID, myName: String) async -> [SharedChallenge] {
        guard let zones = try? await container.sharedCloudDatabase.allRecordZones() else { return [] }
        var discovered: [SharedChallenge] = []
        for zone in zones where !knownZoneNames.contains(zone.zoneID.zoneName) {
            let query = CKQuery(recordType: challengeType, predicate: NSPredicate(value: true))
            guard let result = try? await container.sharedCloudDatabase.records(matching: query, inZoneWith: zone.zoneID),
                  let firstMatch = result.matchResults.first,
                  let root = try? firstMatch.1.get(),
                  let rawEntries = try? await fetchEntries(database: container.sharedCloudDatabase, zoneID: zone.zoneID, myLocalID: myLocalID) else { continue }
            let entries = await ensuringMyEntry(in: rawEntries, root: root, zoneID: zone.zoneID,
                                                 database: container.sharedCloudDatabase, myLocalID: myLocalID, myName: myName)
            guard let found = try? challenge(from: root, zoneID: zone.zoneID, isOwnedByMe: false, shareRecordID: nil, entries: entries) else { continue }
            discovered.append(found)
            await subscribeToZoneChanges(zoneID: zone.zoneID, database: container.sharedCloudDatabase)
        }
        return discovered
    }

    // MARK: Real-time delivery — CKRecordZoneSubscription + silent push

    /// One subscription per zone, on whichever database this account reads
    /// that zone from. Fires (silently, `shouldSendContentAvailable`) for
    /// *any* record change in the zone — since each challenge has its own
    /// dedicated zone, that means "the other participant logged progress,"
    /// which is exactly what should trigger a refresh. A deterministic
    /// subscription ID means calling this again for a zone that's already
    /// subscribed just overwrites the same subscription rather than piling
    /// up duplicates.
    private func subscribeToZoneChanges(zoneID: CKRecordZone.ID, database: CKDatabase) async {
        let subscription = CKRecordZoneSubscription(zoneID: zoneID, subscriptionID: "zone-\(zoneID.zoneName)")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try? await database.save(subscription)
    }

    /// The *visible* notification permission — separate from
    /// `CloudShareDelegate` registering for silent remote notifications at
    /// launch (which needs no user-facing prompt). Asked for at the moment
    /// a shared challenge is actually created or joined, not at cold
    /// launch out of context.
    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Triggered by a silent push (see `CloudShareDelegate`). Uses whichever
    /// identity the last real refresh/create/accept call cached — if
    /// nothing's cached yet (the app was force-quit and a push arrived
    /// before it was ever reopened normally), there's nothing to refresh
    /// with, so this just no-ops; the next normal foreground catches up.
    func refreshFromPush() async {
        guard let me = lastKnownMe else { return }
        await refresh(myLocalID: me.id, myName: me.name)
    }

    /// Compares progress before/after a refresh and schedules a local
    /// notification for any *other* participant's real increase — the part
    /// that makes the silent push actually visible to the user, not just a
    /// background data update they'd never notice. Routed through
    /// `ChallengeNotifier` so the tone (and the Settings opt-out) matches
    /// every other challenge notification in the app, not a separate plain-
    /// text path just because this one comes from a CKShare-backed
    /// challenge instead of a local one.
    private func notifyOfNewProgress(previous: [String: Double], in updated: [SharedChallenge]) {
        for challenge in updated {
            for entry in challenge.otherEntries {
                let key = "\(challenge.localID)-\(entry.localID)"
                guard let old = previous[key], entry.progress > old + 0.001 else { continue }
                ChallengeNotifier.notifyOtherParticipantProgress(name: entry.participantName, challengeTitle: challenge.title)
            }
        }
    }

    // MARK: Refresh — re-pull the latest progress for every known challenge

    /// Re-fetches every challenge already in `challenges` (and anything in
    /// the local index not yet loaded, e.g. right after a cold launch).
    /// Failures per-challenge are dropped silently — a stale card is far
    /// better than the whole list vanishing because one challenge's zone
    /// had a transient fetch error.
    func refresh(myLocalID: UUID, myName: String) async {
        lastKnownMe = (myLocalID, myName)
        guard (try? await container.accountStatus()) == .available else { return }
        let previousProgress: [String: Double] = Dictionary(
            uniqueKeysWithValues: challenges.flatMap { c in c.otherEntries.map { ("\(c.localID)-\($0.localID)", $0.progress) } }
        )
        let known = challenges.isEmpty ? await loadIndex() : []
        var rebuilt: [SharedChallenge] = []
        for entry in known {
            let zoneID = CKRecordZone.ID(zoneName: entry.zoneName)
            let rootID = CKRecord.ID(recordName: entry.recordName, zoneID: zoneID)
            let shareID = entry.shareRecordName.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
            let database = entry.isOwnedByMe ? container.privateCloudDatabase : container.sharedCloudDatabase
            guard let root = try? await database.record(for: rootID),
                  let entries = try? await fetchEntries(database: database, zoneID: zoneID, myLocalID: myLocalID),
                  let rebuilt1 = try? challenge(from: root, zoneID: zoneID, isOwnedByMe: entry.isOwnedByMe, shareRecordID: shareID, entries: entries) else { continue }
            rebuilt.append(rebuilt1)
        }
        for existing in challenges {
            let database = existing.isOwnedByMe ? container.privateCloudDatabase : container.sharedCloudDatabase
            guard let root = try? await database.record(for: existing.rootRecordID),
                  let entries = try? await fetchEntries(database: database, zoneID: existing.zoneID, myLocalID: myLocalID),
                  let updated = try? challenge(from: root, zoneID: existing.zoneID, isOwnedByMe: existing.isOwnedByMe, shareRecordID: existing.shareRecordID, entries: entries) else {
                rebuilt.append(existing)
                continue
            }
            rebuilt.append(updated)
        }

        // Fallback: anything CloudKit says is shared with this account that
        // wasn't already covered above (accepted some other way, or the
        // local index was lost).
        let knownZoneNames = Set((known.map(\.zoneName)) + challenges.map { $0.zoneID.zoneName })
        let discovered = await discoverUnknownSharedZones(knownZoneNames: knownZoneNames, myLocalID: myLocalID, myName: myName)
        rebuilt.append(contentsOf: discovered)

        if !rebuilt.isEmpty {
            notifyOfNewProgress(previous: previousProgress, in: rebuilt)
            challenges = rebuilt
            saveIndex()
        }
    }

    private func fetchEntries(database: CKDatabase, zoneID: CKRecordZone.ID, myLocalID: UUID) async throws -> [SharedEntry] {
        let query = CKQuery(recordType: entryType, predicate: NSPredicate(value: true))
        let result = try await database.records(matching: query, inZoneWith: zoneID)
        return result.matchResults.compactMap { _, recordResult in
            guard let record = try? recordResult.get(),
                  let localIDString = record["localID"] as? String,
                  let name = record["participantName"] as? String else { return nil }
            return SharedEntry(
                localID: localIDString,
                recordID: record.recordID,
                participantName: name,
                progress: record["progress"] as? Double ?? 0,
                progressHistory: record["progressHistory"] as? [Double] ?? [0],
                lastLogVerified: (record["lastLogVerified"] as? Int64 ?? 0) != 0,
                isMe: localIDString == myLocalID.uuidString
            )
        }
    }

    private func challenge(from root: CKRecord, zoneID: CKRecordZone.ID, isOwnedByMe: Bool,
                           shareRecordID: CKRecord.ID?, entries: [SharedEntry]) throws -> SharedChallenge {
        guard let localID = root["localID"] as? String,
              let title = root["title"] as? String,
              let kindRaw = root["kindRaw"] as? String,
              let kind = ChallengeKind(rawValue: kindRaw) else {
            throw CloudSharingError.malformedRecord
        }
        return SharedChallenge(
            localID: localID, rootRecordID: root.recordID, zoneID: zoneID, isOwnedByMe: isOwnedByMe,
            shareRecordID: shareRecordID, title: title, kind: kind,
            venue: root["venue"] as? String ?? "", rules: root["rules"] as? String ?? "",
            dailyTarget: root["dailyTarget"] as? Int ?? 1, durationDays: root["durationDays"] as? Int ?? 1,
            payoff: Payoff(icon: root["payoffIcon"] as? String ?? "trophy.fill", text: root["payoffText"] as? String ?? ""),
            createdAt: root["createdAt"] as? Date ?? Date(), entries: entries
        )
    }

    // MARK: Logging progress

    /// Pulls today's real activity from Health for a shared challenge, same
    /// as `AppModel.syncTodayFromHealth` does for the local/fixture ones.
    /// Falls back to nothing (caller decides whether to log manually
    /// instead) if Health has no data yet.
    func syncTodayFromHealth(challengeLocalID: String, myLocalID: UUID) async {
        guard let challenge = challenges.first(where: { $0.localID == challengeLocalID }) else { return }
        let target = Double(challenge.dailyTarget)
        guard target > 0 else { return }
        let measured: Double?
        switch challenge.kind {
        case .steps: measured = await HealthKitManager.shared.fetchTodaySteps().map(Double.init)
        case .distance: measured = await HealthKitManager.shared.fetchTodayDistanceMiles()
        case .custom: measured = nil
        }
        guard let measured else { return }
        await logProgress(challengeLocalID: challengeLocalID, measuredRatio: measured / target, myLocalID: myLocalID)
    }

    /// Updates *my* entry record for a shared challenge — the real-data
    /// equivalent of `AppModel.logActivity`. Same scaling rule as the local
    /// version: a real HealthKit ratio (0.5x-2x) if provided, otherwise the
    /// flat honor-system increment.
    func logProgress(challengeLocalID: String, measuredRatio: Double?, myLocalID: UUID) async {
        guard let idx = challenges.firstIndex(where: { $0.localID == challengeLocalID }),
              let entryIdx = challenges[idx].entries.firstIndex(where: { $0.isMe }) else { return }
        let scale = measuredRatio.map { min(2.0, max(0.5, $0)) } ?? 1.0
        let next = min(1, challenges[idx].entries[entryIdx].progress + 0.08 * scale)
        challenges[idx].entries[entryIdx].progress = next
        challenges[idx].entries[entryIdx].progressHistory.append(next)
        challenges[idx].entries[entryIdx].lastLogVerified = measuredRatio != nil

        let database = challenges[idx].isOwnedByMe ? container.privateCloudDatabase : container.sharedCloudDatabase
        let recordID = challenges[idx].entries[entryIdx].recordID
        guard let record = try? await database.record(for: recordID) else { return }
        record["progress"] = next
        record["progressHistory"] = challenges[idx].entries[entryIdx].progressHistory
        record["lastLogVerified"] = measuredRatio != nil ? Int64(1) : Int64(0)
        _ = try? await database.modifyRecords(saving: [record], deleting: [])
    }

    enum CloudSharingError: LocalizedError {
        case noShareURL, malformedRecord, notSignedIn
        var errorDescription: String? {
            switch self {
            case .noShareURL: "Couldn't generate an invite link."
            case .malformedRecord: "That challenge's data looked incomplete."
            case .notSignedIn: "Sign in to iCloud in Settings to create a group challenge — sharing needs a real iCloud account, not just being signed into Provyr."
            }
        }
    }
}

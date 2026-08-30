import Foundation
import CloudKit

/// Owns every CKShare-backed challenge this device knows about: ones this
/// iCloud account created (owner, records live in the private database)
/// and ones accepted from someone else's invite (participant, records live
/// in the shared database). See `SharedChallenge.swift` for why this is a
/// separate system from the Fixtures-based `Challenge`/`AppModel.challenges`.
///
/// Scoping notes, honestly stated rather than glossed over:
/// - No push notifications / CKSubscription — updates from the other
///   participant show up on `refresh()`, not automatically the instant
///   they log something. That's a real, separate piece of infrastructure
///   (remote notification registration, subscriptions, background
///   delivery handling) that wasn't part of this pass.
/// - The list of "which shared challenges am I in" is a small local index
///   in UserDefaults (record IDs only, not the actual progress data —
///   CloudKit stays the source of truth for that). It is *not* synced via
///   CloudSyncManager's private-data sync, so accepting an invite on one
///   device doesn't make it appear on your other devices automatically;
///   you'd open the invite link on whichever device you want to use.
/// - Discovery only covers shares accepted through this app's own accept
///   flow (the CKShare URL → `application(_:userDidAcceptCloudKitShareWith:)`
///   path). There's no fallback enumeration of `sharedCloudDatabase` zones
///   for shares that ended up accepted some other way.
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

    private init() {
        loadIndex()
    }

    // MARK: Local index — just enough to know what to re-fetch on launch

    private struct IndexEntry: Codable {
        var zoneName: String
        var recordName: String
        var isOwnedByMe: Bool
        var shareRecordName: String?
    }

    private func loadIndex() -> [IndexEntry] {
        guard let data = UserDefaults.standard.data(forKey: Self.indexDefaultsKey),
              let entries = try? JSONDecoder().decode([IndexEntry].self, from: data) else { return [] }
        return entries
    }

    private func saveIndex() {
        let entries = challenges.map {
            IndexEntry(zoneName: $0.zoneID.zoneName, recordName: $0.rootRecordID.recordName,
                       isOwnedByMe: $0.isOwnedByMe, shareRecordName: $0.shareRecordID?.recordName)
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.indexDefaultsKey)
        }
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
        var entries = try await fetchEntries(database: database, zoneID: rootRecordID.zoneID, myLocalID: myLocalID)

        if !entries.contains(where: { $0.isMe }) {
            let entry = CKRecord(recordType: entryType, recordID: CKRecord.ID(zoneID: rootRecordID.zoneID))
            entry.parent = CKRecord.Reference(record: root, action: .none)
            entry["localID"] = myLocalID.uuidString
            entry["participantName"] = myName
            entry["progress"] = 0.0
            entry["progressHistory"] = [0.0]
            entry["lastLogVerified"] = 0
            _ = try await database.modifyRecords(saving: [entry], deleting: [])
            entries.append(SharedEntry(localID: myLocalID.uuidString, recordID: entry.recordID,
                                        participantName: myName, progress: 0, progressHistory: [0],
                                        lastLogVerified: false, isMe: true))
        }

        let challenge = try challenge(from: root, zoneID: rootRecordID.zoneID, isOwnedByMe: false, shareRecordID: nil, entries: entries)
        challenges.removeAll { $0.localID == challenge.localID }
        challenges.append(challenge)
        saveIndex()
    }

    // MARK: Refresh — re-pull the latest progress for every known challenge

    /// Re-fetches every challenge already in `challenges` (and anything in
    /// the local index not yet loaded, e.g. right after a cold launch).
    /// Failures per-challenge are dropped silently — a stale card is far
    /// better than the whole list vanishing because one challenge's zone
    /// had a transient fetch error.
    func refresh(myLocalID: UUID, myName: String) async {
        guard (try? await container.accountStatus()) == .available else { return }
        let known = challenges.isEmpty ? loadIndex() : []
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
        if !rebuilt.isEmpty {
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
        case noShareURL, malformedRecord
        var errorDescription: String? {
            switch self {
            case .noShareURL: "Couldn't generate an invite link."
            case .malformedRecord: "That challenge's data looked incomplete."
            }
        }
    }
}

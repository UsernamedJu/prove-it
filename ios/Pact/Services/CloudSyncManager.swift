import Foundation
import CloudKit

/// Syncs the signed-in user's own profile/session — name, body profile,
/// settings, mood history — across *their own* devices via CloudKit's
/// private database, and restores it after a reinstall. This is not the
/// multi-user crew/challenge sharing the app still doesn't have: the crew,
/// groups, and challenges are still Fixtures-seeded fresh every launch, and
/// making those real would mean CKShare, participant management, and a much
/// larger data-model change. This is the smaller, safe slice — one iCloud
/// account's own data following them between devices — that the
/// entitlement already sitting in `Pact.entitlements` was declared for but
/// never used.
///
/// Same philosophy as `HealthKitManager`: safe to ship even where iCloud
/// isn't signed in on this device. Every call here treats "no account,"
/// "network unavailable," or "nothing uploaded yet" as normal, expected
/// states — never a crash, never a surfaced error the user has to deal with.
actor CloudSyncManager {
    /// The default instance — AppModel's own profile/settings/mood blob.
    static let shared = CloudSyncManager()

    private let container = CKContainer(identifier: "iCloud.com.jean.pact")
    /// One fixed record per iCloud account per purpose — there's exactly
    /// one of whatever this instance syncs, so there's no query, just a
    /// fetch/save against a well-known ID. A second instance with a
    /// different `recordName` (see `SharedChallengeStore`'s index sync)
    /// gets its own separate record rather than colliding with this one.
    private let recordID: CKRecord.ID
    private let recordType: String
    private let payloadKey = "payload"

    init(recordName: String = "PrimarySession", recordType: String = "UserSession") {
        self.recordID = CKRecord.ID(recordName: recordName)
        self.recordType = recordType
    }

    var isAvailable: Bool {
        get async {
            (try? await container.accountStatus()) == .available
        }
    }

    /// Overwrites the cloud copy with `data` (the same JSON blob already
    /// written to local `UserDefaults`). Returns whether it actually made
    /// it up — the caller uses this only to reflect real status back to the
    /// user, never to decide whether to retry; a dropped upload here isn't
    /// a lost write, just a delayed one, since the next local change tries
    /// again regardless.
    @discardableResult
    func upload(_ data: Data) async -> Bool {
        guard await isAvailable else { return false }
        let database = container.privateCloudDatabase
        let record: CKRecord
        if let existing = try? await database.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }
        record[payloadKey] = data as NSData
        return (try? await database.save(record)) != nil
    }

    /// The most recently uploaded blob for this iCloud account, or `nil` if
    /// there's nothing there yet (first launch on this account) or iCloud
    /// isn't available right now.
    func fetch() async -> Data? {
        guard await isAvailable else { return nil }
        guard let record = try? await container.privateCloudDatabase.record(for: recordID) else { return nil }
        return record[payloadKey] as? Data
    }
}

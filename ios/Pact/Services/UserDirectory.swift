import Foundation
import CloudKit

/// A tiny public directory — the CloudKit *public* database (same
/// container as everything else here, no extra entitlement needed), used
/// only to let one real person be found and added to a crew by an ID they
/// shared, across two different installs. Deliberately minimal: a name and
/// a color, just enough to render an `InitialBadge` for them. Adding
/// someone this way creates a local `Member` entry with their real
/// published name, not a live, bidirectional connection — no different in
/// that respect from every other crew member here, whose "chat" is already
/// a canned reply, not a real one.
@MainActor
final class UserDirectory {
    static let shared = UserDirectory()
    private let container = CKContainer(identifier: "iCloud.com.jean.pact")
    private static let recordType = "ProvyrUser"

    /// Publishes (or updates) this device's own directory entry. Called
    /// whenever the session persists while signed in — see
    /// `AppModel.persistSession`. Silently no-ops without iCloud/network;
    /// being discoverable by ID is a bonus, nothing else here depends on it.
    ///
    /// Fetches the existing record first (same pattern as
    /// `CloudSyncManager.upload`) rather than always constructing a fresh
    /// `CKRecord` — saving a brand-new record object against an ID
    /// CloudKit already has one for (no change tag attached) is the
    /// standard conflict case, and `try?` here was swallowing it silently:
    /// the very first publish after onboarding would succeed, but every
    /// later name/color change would silently fail to actually update it.
    func publish(id: UUID, name: String, colorIndex: Int) async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record: CKRecord
        if let existing = try? await container.publicCloudDatabase.record(for: recordID) {
            record = existing
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }
        record["name"] = name
        record["colorIndex"] = colorIndex
        _ = try? await container.publicCloudDatabase.save(record)
    }

    struct LookupResult { let id: UUID; let name: String; let colorIndex: Int }

    /// The counterpart to `publish` — looks up whoever shared this ID.
    /// Returns `nil` for a malformed ID, one nobody's published yet (they
    /// haven't onboarded, or aren't signed in), or no iCloud/network.
    func lookup(id rawID: String) async -> LookupResult? {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid = UUID(uuidString: trimmed) else { return nil }
        guard let record = try? await container.publicCloudDatabase.record(for: CKRecord.ID(recordName: uuid.uuidString)),
              let name = record["name"] as? String else { return nil }
        return LookupResult(id: uuid, name: name, colorIndex: record["colorIndex"] as? Int ?? 0)
    }
}

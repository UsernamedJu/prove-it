import Foundation
import CloudKit

/// A tiny public directory — the CloudKit *public* database (same
/// container as everything else here, no extra entitlement needed), used
/// to let one real person be found and added to a crew by an ID they
/// shared, across two different installs, and to keep that person's name,
/// color, and profile photo current everywhere they show up in someone
/// else's crew afterward — see `AppModel.refreshCrewProfiles()`. Adding
/// someone this way creates a local `Member` entry with their real
/// published profile, not a live, bidirectional connection — no different
/// in that respect from every other crew member here, whose "chat" is
/// already a canned reply, not a real one.
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
    /// later name/color/photo change would silently fail to actually
    /// update it.
    ///
    /// The photo goes up as a `CKAsset`, not inline `NSData` — CloudKit
    /// record fields cap out around 1MB, which a real photo can exceed;
    /// assets are the correct way to store binary blobs like this one.
    /// `CKAsset` needs a file on disk, so this writes the data to a
    /// temporary file first and always cleans it up afterward, success or
    /// failure.
    func publish(id: UUID, name: String, colorIndex: Int, photoData: Data?) async {
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

        var tempURL: URL?
        if let photoData {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            if (try? photoData.write(to: url)) != nil {
                tempURL = url
                record["photo"] = CKAsset(fileURL: url)
            }
        } else {
            record["photo"] = nil
        }
        defer { if let tempURL { try? FileManager.default.removeItem(at: tempURL) } }

        _ = try? await container.publicCloudDatabase.save(record)
    }

    struct LookupResult { let id: UUID; let name: String; let colorIndex: Int; let photoData: Data? }

    /// The counterpart to `publish` — looks up whoever shared this ID, or
    /// re-checks someone already in the crew for a profile update. Returns
    /// `nil` for a malformed ID, one nobody's published yet (they haven't
    /// onboarded, or aren't signed in), or no iCloud/network.
    func lookup(id rawID: String) async -> LookupResult? {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid = UUID(uuidString: trimmed) else { return nil }
        guard let record = try? await container.publicCloudDatabase.record(for: CKRecord.ID(recordName: uuid.uuidString)),
              let name = record["name"] as? String else { return nil }
        let photoData = (record["photo"] as? CKAsset)?.fileURL.flatMap { try? Data(contentsOf: $0) }
        return LookupResult(id: uuid, name: name, colorIndex: record["colorIndex"] as? Int ?? 0, photoData: photoData)
    }
}

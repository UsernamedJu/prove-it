import Foundation
import CloudKit

/// A real, Apple-hosted invite link — a `CKShare` wrapping a tiny "here's
/// who's inviting you" record, using the exact same CloudKit container and
/// accept-flow infrastructure `SharedChallengeStore` already has for
/// challenge invites (see `CloudShareDelegate` and `PactApp.handleIncomingShare`).
/// CloudKit itself hosts the resulting `icloud.com/share/...` URL — there's
/// no server of this app's own involved, which is what actually makes this
/// "a real backend" rather than a bundled static file: tapping it on a
/// device with iCloud and this app installed opens straight into accepting
/// it and adding the sender to your crew.
///
/// What this still can't do without a real web domain: give someone who
/// doesn't have the app yet anywhere useful to land. Apple's own share
/// preview page is what they'd see instead — a real page, just not one
/// that can install or deep-link into an app that isn't there.
@MainActor
final class CrewInviteService {
    static let shared = CrewInviteService()
    private let container = CKContainer(identifier: "iCloud.com.jean.pact")
    static let recordType = "CrewInvite"

    private init() {}

    /// Creates a fresh invite and returns the real, shareable URL. Throws
    /// the same not-signed-in error `SharedChallengeStore` does — CKShare
    /// needs a real authenticated iCloud account, not just Provyr's own
    /// (optional, unverified) sign-in.
    func createInvite(myID: UUID, myName: String) async throws -> URL {
        guard (try? await container.accountStatus()) == .available else {
            throw SharedChallengeStore.CloudSharingError.notSignedIn
        }
        let zoneID = CKRecordZone.ID(zoneName: "CrewInvite-\(UUID().uuidString)")
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await container.privateCloudDatabase.save(zone)

        let root = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(zoneID: zoneID))
        root["inviterID"] = myID.uuidString
        root["inviterName"] = myName

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Join \(myName) on Provyr" as CKRecordValue
        share.publicPermission = .readWrite

        _ = try await container.privateCloudDatabase.modifyRecords(saving: [root, share], deleting: [])
        guard let url = share.url else { throw SharedChallengeStore.CloudSharingError.noShareURL }
        return url
    }

    /// Accepts a tapped invite and returns who sent it, so the caller can
    /// add them to the crew. No ongoing data to sync afterward — unlike a
    /// challenge share, this is a one-time "here's who this is," not
    /// something `SharedChallengeStore.refresh` needs to keep polling.
    func acceptInvite(metadata: CKShare.Metadata) async -> (id: UUID, name: String)? {
        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        let accepted: Bool = await withCheckedContinuation { continuation in
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success: continuation.resume(returning: true)
                case .failure: continuation.resume(returning: false)
                }
            }
            container.add(operation)
        }
        guard accepted,
              let root = try? await container.sharedCloudDatabase.record(for: metadata.rootRecordID),
              let idString = root["inviterID"] as? String, let id = UUID(uuidString: idString),
              let name = root["inviterName"] as? String else { return nil }
        return (id, name)
    }
}

import Foundation
import CloudKit

/// A challenge shared with one real person via CKShare — genuinely synced
/// between two different iCloud accounts, unlike every other challenge in
/// this app (which is Fixtures-seeded and purely local to one device).
///
/// Deliberately a separate, additive system rather than merged into
/// `Challenge`/`AppModel.challenges`: that model's whole surface
/// (`logActivity`, `resolveChallenge`, standings math) assumes local,
/// synchronous, always-present fixture data. Retrofitting it to be
/// CloudKit-aware everywhere would be a much larger, riskier change than
/// "invite one real person to one real challenge" calls for — the existing
/// demo crew and their challenges are untouched by any of this.
struct SharedChallenge: Identifiable {
    var id: String { localID }
    let localID: String
    let rootRecordID: CKRecord.ID
    let zoneID: CKRecordZone.ID
    /// Whether this challenge lives in *my* private database (I created
    /// it) or in the shared database (I accepted someone else's invite) —
    /// decides which `CKDatabase` reads/writes for it go to.
    let isOwnedByMe: Bool
    /// The CKShare's own record ID — only set when I'm the owner. Kept so
    /// the invite link can be re-fetched later; without this, dismissing
    /// the share sheet at creation time without actually sending it would
    /// strand the invite with no way to get the link back.
    let shareRecordID: CKRecord.ID?
    var title: String
    var kind: ChallengeKind
    var venue: String
    var rules: String
    var dailyTarget: Int
    var durationDays: Int
    var payoff: Payoff
    var createdAt: Date
    var entries: [SharedEntry]

    var myEntry: SharedEntry? { entries.first { $0.isMe } }
    var otherEntries: [SharedEntry] { entries.filter { !$0.isMe } }
}

/// One participant's real, CloudKit-stored progress on a `SharedChallenge`.
struct SharedEntry: Identifiable {
    var id: String { localID }
    let localID: String
    let recordID: CKRecord.ID
    var participantName: String
    var progress: Double
    var progressHistory: [Double]
    var lastLogVerified: Bool
    var isMe: Bool
}

import SwiftUI
import CoreLocation

enum ChallengeKind: String, CaseIterable, Identifiable, Hashable {
    case steps = "Steps"
    case distance = "Distance"
    case custom = "Custom"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .steps: return "footprints"
        case .distance: return "route"
        case .custom: return "target"
        }
    }
    var unit: String {
        switch self {
        case .steps: return "steps"
        case .distance: return "mi"
        case .custom: return "pts"
        }
    }
}

enum ChallengeStatus {
    case active, revealReady, complete
}

/// "The Deal" — a fun, non-monetary payoff instead of a points pot. No cash,
/// no currency — just a real-world consequence everyone agrees to upfront.
struct Payoff: Identifiable, Hashable {
    var id: String { text }
    var icon: String
    var text: String

    static let presets: [Payoff] = [
        Payoff(icon: "trophy.fill", text: "Bragging rights for a week"),
        Payoff(icon: "cup.and.saucer.fill", text: "Loser buys coffee for everyone"),
        Payoff(icon: "figure.strengthtraining.traditional", text: "Loser does 20 burpees on video"),
        Payoff(icon: "tshirt.fill", text: "Loser wears the shame shirt to the next hangout"),
        Payoff(icon: "mic.fill", text: "Loser gives a toast at the next family dinner"),
        Payoff(icon: "car.fill", text: "Winner picks the next challenge"),
        Payoff(icon: "music.note", text: "Loser DJs the next hangout — everyone else vetoes"),
        Payoff(icon: "heart.fill", text: "Winner picks where the group eats next"),
    ]
}

/// One person's position inside a challenge. `progressHistory` is the real,
/// stored day-by-day record a "Log Today" tap appends to — charts read this
/// directly rather than faking a trend line.
struct Standing: Identifiable {
    var id: UUID { member.id }
    var member: Member
    var rank: Int
    var progress: Double // 0...1 toward the challenge's target — always == progressHistory.last
    var trendDelta: String // e.g. "+3" / "-1" / "—"
    var progressHistory: [Double]
    /// True when the most recent log came from a real HealthKit reading
    /// rather than the manual "Log Today" tap — lets the UI show a
    /// "Verified" badge instead of taking every entry on the honor system.
    var lastLogVerified: Bool = false
}

struct Challenge: Identifiable {
    let id: UUID
    var title: String
    var icon: String
    var kind: ChallengeKind
    /// Where it's happening and what it's tied to — the professional,
    /// city/event-grounded framing rather than a generic prototype name.
    var venue: String
    var rules: String
    /// This challenge's own photo, not just a shared per-kind stock image —
    /// every challenge looks distinct.
    var photoName: String
    var durationDays: Int
    var daysLeft: Int
    var dailyTarget: Int
    /// Only set when `kind == .custom` — what the group is actually tracking
    /// (e.g. "push-ups"), overriding the generic "pts" unit for display.
    var customMetric: String? = nil
    var payoff: Payoff
    var standings: [Standing]
    var myMemberID: UUID
    var blindReveal: Bool
    var fairPlay: Bool
    var status: ChallengeStatus
    var routeCoordinates: [CLLocationCoordinate2D]?
    /// Set once `resolveChallenge` runs, so the reveal only ever plays once.
    var winnerName: String?

    var tint: Color { swatchColor(for: title) }
    var displayUnit: String { customMetric?.isEmpty == false ? customMetric! : kind.unit }
    var participantsCount: Int { standings.count }
    var myStanding: Standing? { standings.first { $0.member.id == myMemberID } }
    var isDistanceBased: Bool { kind == .distance }
}

/// A not-yet-created challenge the Home screen proposes — exactly one shown
/// at a time, with a "show me another" to cycle rather than a rail of many.
struct ChallengeSuggestion: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var icon: String
    var kind: ChallengeKind
    var venue: String
    var photoName: String
    var line: String
    var suggestedDuration: Int
    var payoff: Payoff

    static func == (lhs: ChallengeSuggestion, rhs: ChallengeSuggestion) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

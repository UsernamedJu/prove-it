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

    /// A more specific SF Symbol than the generic per-kind default above,
    /// inferred from what the challenge actually is (its own title/venue)
    /// rather than just its kind — so "Petco Park Fan Walk" doesn't share
    /// the same plain icon as every other `.custom` challenge that exists.
    /// Falls back to `icon` when nothing in the name matches anything
    /// specific.
    static func suggestedIcon(title: String, venue: String, kind: ChallengeKind) -> String {
        let text = "\(title) \(venue)".lowercased()
        let keywords: [(terms: [String], icon: String)] = [
            (["marathon", "5k", "10k", "race"], "figure.run"),
            (["bike", "cycle", "cycling"], "figure.outdoor.cycle"),
            (["swim", "pool"], "figure.pool.swim"),
            (["yoga"], "figure.yoga"),
            (["hike", "trail", "canyon"], "figure.hiking"),
            (["gym", "lift", "weight", "strength"], "dumbbell.fill"),
            (["basketball"], "basketball.fill"),
            (["baseball", "petco", "padres"], "baseball.fill"),
            (["soccer", "football"], "soccerball"),
            (["tennis"], "tennis.racket"),
            (["golf"], "figure.golf"),
            (["dance"], "figure.dance"),
            (["stair", "stairs"], "figure.stairs"),
            (["bridge", "road"], "road.lanes"),
            (["beach", "coastal", "bay", "shore", "surf"], "water.waves"),
            (["park", "garden", "zoo"], "leaf.fill"),
            (["target", "store", "shop", "mall"], "cart.fill"),
        ]
        for entry in keywords where entry.terms.contains(where: { text.contains($0) }) {
            return entry.icon
        }
        return kind.icon
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
    /// Real cumulative HealthKit total since the challenge's `startDate`
    /// (steps or miles, matching `kind`) — re-queried and *set* on every
    /// sync rather than incremented, so syncing five times in a row reads
    /// the same real total instead of stacking five separate credits.
    var healthTotal: Double = 0
    /// Sum of finished `LiveTrackingView` sessions' measured distance —
    /// additive, since each one is a genuinely new event that a Health
    /// total-since-start query wouldn't otherwise double as (this app
    /// never writes tracked sessions back into HealthKit as workouts).
    var trackedTotal: Double = 0
    /// The calendar day `progressHistory`'s last entry represents — a
    /// second sync later the same day updates that entry in place instead
    /// of appending a duplicate "day," which is what made a 1-day-old
    /// challenge's Journey chart show several points.
    var lastLoggedDay: Date?
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
    /// When tracking actually began — the baseline every Health sync
    /// measures *since*, so steps or miles from before the challenge
    /// started never count toward it. Defaults to now for the rare
    /// caller (fixtures/previews) that omits it.
    var startDate: Date = Date()
    /// The total steps/miles that auto-wins the challenge for whoever hits
    /// it first — distinct from `dailyTarget`, which is just the day-to-day
    /// pace shown in the UI. `nil` for freeform/custom challenges with no
    /// sensible auto-computed total; falls back to `effectiveGoalTarget`.
    var goalTarget: Double? = nil

    var tint: Color { swatchColor(for: title) }
    var displayUnit: String { customMetric?.isEmpty == false ? customMetric! : kind.unit }
    var participantsCount: Int { standings.count }
    var myStanding: Standing? { standings.first { $0.member.id == myMemberID } }
    var isDistanceBased: Bool { kind == .distance }
    var effectiveGoalTarget: Double { goalTarget ?? Double(dailyTarget) * Double(durationDays) }

    /// The real target a specific member's progress is measured against.
    /// With Fair Play on for a steps challenge, that's *their own* age-band
    /// daily baseline (the same number already shown in "Fair Play
    /// Targets") × duration × the same stretch factor `effectiveGoalTarget`
    /// uses — so racing your own target actually changes what counts as
    /// 100%, not just what a label next to your name says. Falls back to
    /// the one shared goal otherwise: Fair Play off, or a kind
    /// (`.distance`/`.custom`) with no real per-person baseline to scale
    /// from — `AgeBand.fairPlayStepTarget` is specifically a *step* count.
    func goalTarget(for member: Member) -> Double {
        guard fairPlay, kind == .steps else { return effectiveGoalTarget }
        return Double(member.ageBand.fairPlayStepTarget) * Double(durationDays) * 1.15
    }

    /// A distinct color per standing — independent per-name `swatchColor`
    /// calls could (and with a 7-color palette and any real-sized crew,
    /// often would) hash two different people to the same hue by pure
    /// coincidence. "Me" always gets the actual color chosen in Settings,
    /// not a hash of whatever "me"'s display name happens to be; everyone
    /// else gets their own unused slot from the remaining palette, in a
    /// stable order (`standings` is already sorted the same way every
    /// render) so the same person keeps the same color across repeated
    /// calls instead of it shuffling.
    func distinctColor(for memberID: UUID, meColor: Color) -> Color {
        if memberID == myMemberID { return meColor }
        let palette = Theme.Brand.swatch
        let meIndex = palette.firstIndex(of: meColor)
        let available = palette.indices.filter { $0 != meIndex }
        let pool = available.isEmpty ? Array(palette.indices) : available
        let others = standings.map(\.member.id).filter { $0 != myMemberID }
        guard let position = others.firstIndex(of: memberID) else { return swatchColor(for: memberID.uuidString) }
        return palette[pool[position % pool.count]]
    }
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
    /// A real total to race to, e.g. 50,000 steps or 20 miles over the
    /// suggested duration — a stretch relative to a straightforward daily
    /// pace, not a trivial one, but reachable if someone actually pushes.
    var goalTarget: Double
    var goalLabel: String { kind == .distance ? "\(Int(goalTarget)) mi" : "\(Int(goalTarget).formatted()) \(kind.unit)" }

    static func == (lhs: ChallengeSuggestion, rhs: ChallengeSuggestion) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A lifetime achievement derived from real data — challenge results, mood
/// streaks, and Health readings — never a made-up counter. `progress` is
/// always `0...1`, including for unlocked ones (where it's `1`), so a single
/// progress bar can represent both states without a branch at every call site.
struct Milestone: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let isUnlocked: Bool
    let progress: Double
}

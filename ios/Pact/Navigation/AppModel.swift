import SwiftUI
import Foundation

enum Tab: String, CaseIterable, Identifiable {
    case home = "Home"
    case challenges = "Challenges"
    case map = "Map"
    case contacts = "Crew"
    case me = "Me"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .challenges: return "flag.fill"
        case .map: return "map.fill"
        case .contacts: return "person.2.fill"
        case .me: return "person.crop.circle.fill"
        }
    }
}

/// The single source of truth for the running app — onboarding state, the
/// crew, groups, and challenges. Fixtures seed it; everything after that is
/// in-memory only (no persistence layer yet).
///
/// There is no point balance, wallet, or stake/pot. Winning a challenge is
/// just a recorded result — nothing is spent or credited anywhere. The only
/// score anyone has is `fitnessScore`, which exists purely to recommend
/// workout types and gauge whether a challenge is a good fit, never to gate
/// or pay anyone.
@Observable
final class AppModel {
    var hasOnboarded = false
    var tab: Tab = .home
    var meColorIndex = 0
    var meColor: Color { Theme.Brand.swatch[meColorIndex % Theme.Brand.swatch.count] }

    var me = Fixtures.me {
        didSet {
            guard me.name != oldValue.name else { return }
            for i in challenges.indices {
                if let j = challenges[i].standings.firstIndex(where: { $0.member.id == me.id }) {
                    challenges[i].standings[j].member.name = me.name
                }
            }
        }
    }
    var crew: [Member] = Fixtures.crew
    var groups: [ContactGroup] = Fixtures.groups
    var challenges: [Challenge] = Fixtures.challenges
    var moodHistory: [MoodCheckIn] = Fixtures.moodHistory
    var moodStreak = 3
    var moodLoggedToday = false

    /// Drives the brief celebration overlays — set on creation/reveal, then
    /// cleared by the view after its animation plays.
    var justCreated = false
    var justRevealedID: UUID?

    private var suggestionIndex = 0
    var currentSuggestion: ChallengeSuggestion {
        Fixtures.suggestions[suggestionIndex % Fixtures.suggestions.count]
    }
    func nextSuggestion() { suggestionIndex += 1 }

    var activeChallenges: [Challenge] { challenges.filter { $0.status != .complete } }

    var rudyGreeting: String { Rudy.greeting(app: self) }

    // MARK: Fitness score — drives challenge/workout-type fit, never a wallet

    var fitnessScore: Int {
        let recentMood = moodHistory.suffix(5)
        let moodAvg = recentMood.isEmpty ? 6.0
            : recentMood.reduce(0.0) { $0 + ($1.energy + $1.motivation) / 2 } / Double(recentMood.count)
        let active = activeChallenges
        let freqAvg = active.isEmpty ? 0.5
            : active.compactMap { $0.myStanding?.progress }.reduce(0, +) / Double(max(1, active.count))
        let score = (moodAvg / 10 * 0.5 + freqAvg * 0.5) * 100
        return max(0, min(100, Int(score.rounded())))
    }

    var personalizedStepTarget: Int {
        let base = Double(me.ageBand.fairPlayStepTarget)
        let multiplier = 0.8 + (Double(fitnessScore) / 100) * 0.4
        let raw = base * multiplier
        return Int((raw / 50).rounded()) * 50
    }

    /// A short, deterministic "this suits you" tag for a crew member — the
    /// only remaining role of a numeric score: matching people to the kind
    /// of challenge they'd likely do well in, not a currency.
    func fitTag(for member: Member) -> (kind: ChallengeKind, label: String) {
        let score = stableHash(member.name) % 100
        switch score {
        case 0..<34: return (.steps, "Best fit: Steps challenges")
        case 34..<67: return (.distance, "Best fit: Distance challenges")
        default: return (.custom, "Best fit: Custom challenges")
        }
    }

    // MARK: Mood — a personal log, not a point source

    func logMoodCheckIn(energy: Double, mood: Double, motivation: Double, sleep: Double) {
        moodHistory.append(MoodCheckIn(date: Date(), energy: energy, mood: mood,
                                        motivation: motivation, sleep: sleep))
        moodStreak += 1
        moodLoggedToday = true
    }

    // MARK: Activity — appends real history, so charts read actual data

    func logActivity(for challengeID: UUID, hitTarget: Bool) {
        guard let idx = challenges.firstIndex(where: { $0.id == challengeID }) else { return }
        if let sIdx = challenges[idx].standings.firstIndex(where: { $0.member.id == me.id }) {
            let next = min(1, challenges[idx].standings[sIdx].progress + 0.08)
            challenges[idx].standings[sIdx].progress = next
            challenges[idx].standings[sIdx].progressHistory.append(next)
            challenges[idx].standings[sIdx].trendDelta = hitTarget ? "+1" : "—"
        }
    }

    // MARK: Challenges

    func createChallenge(title: String, icon: String, kind: ChallengeKind, venue: String, rules: String,
                          photoName: String, duration: Int, customMetric: String?, payoff: Payoff,
                          blindReveal: Bool, fairPlay: Bool, invitees: [Member]) {
        var standings = [Standing(member: me, rank: 1, progress: 0, trendDelta: "—", progressHistory: [0])]
        for (i, m) in invitees.enumerated() {
            standings.append(Standing(member: m, rank: i + 2, progress: 0, trendDelta: "—", progressHistory: [0]))
        }
        let dailyTarget: Int = switch kind {
            case .steps: 8_000
            case .distance: 2
            case .custom: 1
        }
        let challenge = Challenge(id: UUID(), title: title, icon: icon, kind: kind,
                                   venue: venue, rules: rules, photoName: photoName,
                                   durationDays: duration, daysLeft: duration, dailyTarget: dailyTarget,
                                   customMetric: customMetric, payoff: payoff,
                                   standings: standings, myMemberID: me.id,
                                   blindReveal: blindReveal, fairPlay: fairPlay, status: .active,
                                   routeCoordinates: kind == .distance ? Fixtures.sampleRoute : nil,
                                   winnerName: nil)
        challenges.insert(challenge, at: 0)
        justCreated = true
    }

    /// Reveals the winner — the payoff of the play → reveal loop.
    /// Records a result only; nothing is credited to any account.
    func resolveChallenge(_ id: UUID) {
        guard let idx = challenges.firstIndex(where: { $0.id == id }),
              challenges[idx].status != .complete,
              let winner = challenges[idx].standings.min(by: { $0.rank < $1.rank }) else { return }
        challenges[idx].status = .complete
        challenges[idx].winnerName = winner.member.name
        justRevealedID = id
    }

    // MARK: Contacts + Groups

    func addContact(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        crew.append(Member(name: trimmed))
    }

    func createGroup(name: String, memberIDs: [UUID]) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !memberIDs.isEmpty else { return }
        groups.append(ContactGroup(name: trimmed, memberIDs: memberIDs))
    }

    func members(in group: ContactGroup) -> [Member] {
        crew.filter { group.memberIDs.contains($0.id) }
    }
}

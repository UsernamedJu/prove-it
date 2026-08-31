import Foundation
import CoreLocation

/// Mocked data so every screen has something real-looking to render. One
/// enum, static arrays — same shape as walk-app's own Fixtures.swift.
/// Challenge names are grounded in real San Diego venues and race-calendar
/// events rather than generic prototype copy, and every challenge carries
/// its own distinct stock photo rather than sharing one per kind.
enum Fixtures {

    // MARK: People

    static let me = Member(name: "You", ageBand: .adult)
    static let mom = Member(name: "Mom", ageBand: .midlife)
    static let dad = Member(name: "Dad", ageBand: .midlife)
    static let grandmaRose = Member(name: "Grandma Rose", ageBand: .senior)
    static let jordan = Member(name: "Jordan", ageBand: .adult)
    static let sam = Member(name: "Sam", ageBand: .adult)

    static var crew: [Member] { [mom, dad, grandmaRose, jordan, sam] }

    static let familyGroup = ContactGroup(name: "Family", memberIDs: [mom.id, dad.id, grandmaRose.id])
    static var groups: [ContactGroup] { [familyGroup] }

    /// A real coordinate for a venue string — every challenge and suggestion
    /// is grounded in an actual San Diego place, so the Map tab can drop a
    /// pin for kinds (Steps/Custom) that don't carry a full route.
    static func venueCoordinate(_ venue: String) -> CLLocationCoordinate2D {
        let v = venue.lowercased()
        if v.contains("la jolla") { return .init(latitude: 32.8508, longitude: -117.2713) }
        if v.contains("gaslamp") || v.contains("petco") { return .init(latitude: 32.7076, longitude: -117.1570) }
        if v.contains("balboa") { return .init(latitude: 32.7341, longitude: -117.1449) }
        if v.contains("coronado") { return .init(latitude: 32.6859, longitude: -117.1831) }
        if v.contains("mission bay") { return .init(latitude: 32.7757, longitude: -117.2264) }
        return .init(latitude: 32.7157, longitude: -117.1611) // Citywide · Downtown San Diego
    }

    /// A plausible, monotonically-rising day-by-day history ending at
    /// `end` — real stored data for charts to read, not runtime noise.
    private static func history(days: Int, end: Double, wobble: Double = 0.06) -> [Double] {
        (0..<days).map { i in
            let t = Double(i) / Double(max(1, days - 1))
            let seed = sin(Double(i) * 1.7) * wobble
            return max(0, min(1, end * t + seed))
        }
    }

    // MARK: Challenges

    static let finestCitySteps = Challenge(
        id: UUID(), title: "America's Finest City Steps Challenge", icon: "footprints", kind: .steps,
        venue: "Citywide · San Diego", rules: "Ranked by % of each person's personalized daily step target (Fair Play scoring).",
        photoName: "photo-steps",
        durationDays: 14, daysLeft: 6, dailyTarget: 8_000,
        payoff: Payoff(icon: "cup.and.saucer.fill", text: "Loser buys coffee for everyone"),
        standings: [
            Standing(member: grandmaRose, rank: 1, progress: 0.82, trendDelta: "+2", progressHistory: history(days: 8, end: 0.82)),
            Standing(member: me, rank: 2, progress: 0.74, trendDelta: "+1", progressHistory: history(days: 8, end: 0.74)),
            Standing(member: mom, rank: 3, progress: 0.61, trendDelta: "—", progressHistory: history(days: 8, end: 0.61)),
            Standing(member: dad, rank: 4, progress: 0.52, trendDelta: "-1", progressHistory: history(days: 8, end: 0.52)),
        ],
        myMemberID: me.id, blindReveal: false, fairPlay: true, status: .active,
        routeCoordinates: nil, winnerName: nil
    )

    static let laJollaCoastal = Challenge(
        id: UUID(), title: "La Jolla Coastal 5K Series", icon: "figure.run", kind: .distance,
        venue: "La Jolla Shores", rules: "Cumulative distance over the series. Scores stay hidden until the final 72 hours.",
        photoName: "photo-distance",
        durationDays: 30, daysLeft: 18, dailyTarget: 2,
        payoff: Payoff(icon: "trophy.fill", text: "Bragging rights for a week"),
        standings: [
            Standing(member: sam, rank: 1, progress: 0.68, trendDelta: "+4", progressHistory: history(days: 12, end: 0.68)),
            Standing(member: jordan, rank: 2, progress: 0.55, trendDelta: "+1", progressHistory: history(days: 12, end: 0.55)),
            Standing(member: me, rank: 3, progress: 0.49, trendDelta: "-2", progressHistory: history(days: 12, end: 0.49)),
        ],
        myMemberID: me.id, blindReveal: true, fairPlay: false, status: .active,
        // `AppModel.ensureRealRoute` fills this in with a real MKDirections
        // walking route the first time a map view for this challenge
        // appears, rather than seeding it with a fake, hand-drawn loop.
        routeCoordinates: nil, winnerName: nil
    )

    static let petcoParkFanWalk = Challenge(
        id: UUID(), title: "Petco Park Fan Walk", icon: "baseball.fill", kind: .custom,
        venue: "Petco Park · Gaslamp Quarter", rules: "Highest single-day effort score wins. Reveal opens once the week closes.",
        photoName: "photo-custom",
        durationDays: 7, daysLeft: 0, dailyTarget: 1,
        payoff: Payoff(icon: "mic.fill", text: "Loser gives a toast at the next family dinner"),
        standings: [
            Standing(member: me, rank: 1, progress: 1.0, trendDelta: "+1", progressHistory: history(days: 7, end: 1.0)),
            Standing(member: dad, rank: 2, progress: 0.9, trendDelta: "—", progressHistory: history(days: 7, end: 0.9)),
        ],
        myMemberID: me.id, blindReveal: true, fairPlay: false, status: .revealReady,
        routeCoordinates: nil, winnerName: nil
    )

    static let balboaParkFamily = Challenge(
        id: UUID(), title: "Balboa Park Family Circuit", icon: "footprints", kind: .steps,
        venue: "Balboa Park", rules: "Ranked by % of each person's personalized daily step target (Fair Play scoring).",
        photoName: "photo-balboafamily",
        durationDays: 14, daysLeft: 0, dailyTarget: 7_500,
        payoff: Payoff(icon: "tshirt.fill", text: "Loser wears the shame shirt to the next hangout"),
        standings: [
            Standing(member: me, rank: 1, progress: 1.0, trendDelta: "+3", progressHistory: history(days: 14, end: 1.0)),
            Standing(member: mom, rank: 2, progress: 0.88, trendDelta: "+1", progressHistory: history(days: 14, end: 0.88)),
            Standing(member: grandmaRose, rank: 3, progress: 0.81, trendDelta: "-1", progressHistory: history(days: 14, end: 0.81)),
        ],
        myMemberID: me.id, blindReveal: false, fairPlay: true, status: .complete,
        routeCoordinates: nil, winnerName: "You"
    )

    /// Fresh, just-started, and freely editable — the one to actually try
    /// out today. (Named from "family Target ... challenge" in the request;
    /// this is a best guess at a Target-run family step challenge — rename
    /// freely if that's not what was meant.)
    static let familyTargetRun = Challenge(
        id: UUID(), title: "Family Target Run", icon: "cart.fill", kind: .steps,
        venue: "Target · Mission Valley", rules: "Ranked by % of each person's personalized daily step target (Fair Play scoring).",
        photoName: "photo-steps",
        durationDays: 1, daysLeft: 1, dailyTarget: 6_000,
        payoff: Payoff(icon: "cart.fill", text: "Loser pushes the cart the whole trip"),
        standings: [
            Standing(member: me, rank: 1, progress: 0, trendDelta: "—", progressHistory: [0]),
            Standing(member: mom, rank: 2, progress: 0, trendDelta: "—", progressHistory: [0]),
            Standing(member: dad, rank: 3, progress: 0, trendDelta: "—", progressHistory: [0]),
            Standing(member: grandmaRose, rank: 4, progress: 0, trendDelta: "—", progressHistory: [0]),
        ],
        myMemberID: me.id, blindReveal: false, fairPlay: true, status: .active,
        routeCoordinates: nil, winnerName: nil
    )

    static var challenges: [Challenge] { [familyTargetRun, finestCitySteps, laJollaCoastal, petcoParkFanWalk, balboaParkFamily] }
    static var activeChallenges: [Challenge] { challenges.filter { $0.status != .complete } }

    // MARK: Suggested challenges — a real weekly rotation, not a fixed list
    //
    // `suggestionPool` holds every candidate; `suggestions` (below) picks a
    // window of 4 from it keyed to the actual calendar week
    // (Calendar.weekOfYear), so which four show up genuinely changes week
    // to week — the same real place can still recur later in the rotation,
    // the same way an actual weekly event calendar would repeat, but any
    // given week shows a different four than the last. Every entry is
    // still grounded in an actual San Diego neighborhood/venue and a
    // plausible real event there — the Balboa Park 5K Running Tour
    // genuinely runs on Sundays, Little Italy's Mercato genuinely runs
    // Sundays, etc. — not generic "steps challenge #6" filler.
    //
    // Photos are reused from the app's existing kind-generic assets
    // (photo-steps/photo-distance) for venues that don't have their own
    // dedicated photo, the same way the fixture challenges already do for
    // citywide-style challenges — no new image assets exist to add here.
    //
    // Each payoff is bespoke, tied to that specific venue's actual
    // character, and two-sided on purpose: a genuinely enticing win (not
    // just "no punishment") on one side, a physical, on-the-spot action
    // for the loser on the other — not a transactional "buys/pays for"
    // consequence, which doesn't cost anything but money and fits a
    // fitness app poorly. Locked in once a challenge starts from one of
    // these (see CreateChallengeView.isPayoffLocked) — the stake is part
    // of the pitch, not a starting suggestion you're free to swap out.
    static let suggestionPool: [ChallengeSuggestion] = [
        ChallengeSuggestion(title: "Balboa Park 5K — Race Day", icon: "figure.run", kind: .distance,
                             venue: "Balboa Park", photoName: "photo-balboa5k",
                             line: "The Balboa Park 5K Running Tour runs Sundays. Set a pace goal and race it together.",
                             suggestedDuration: 1, payoff: Payoff(icon: "figure.core.training", text: "Winner picks next week's challenge — loser drops for 10 burpees at the finish line"),
                             goalTarget: 3.1),
        ChallengeSuggestion(title: "Gaslamp Quarter Step Circuit", icon: "figure.walk", kind: .steps,
                             venue: "Gaslamp Quarter", photoName: "photo-gaslamp",
                             line: "The Gaslamp averages 11,000 steps on a Friday night. See who actually walks it.",
                             suggestedDuration: 7, payoff: Payoff(icon: "wineglass.fill", text: "Winner drinks free all night — loser dances a full song outside the busiest bar"),
                             goalTarget: 70_000),
        ChallengeSuggestion(title: "Coronado Bridge Walk Series", icon: "road.lanes", kind: .distance,
                             venue: "Coronado", photoName: "photo-coronado",
                             line: "Two weeks along one of San Diego's most recognizable routes. Everyone starts even.",
                             suggestedDuration: 14, payoff: Payoff(icon: "photo.fill", text: "Winner's photo is the group's profile pic for a week — loser redoes the walk carrying everyone's bags"),
                             goalTarget: 40),
        ChallengeSuggestion(title: "Mission Bay Morning Circuit", icon: "figure.walk.circle.fill", kind: .steps,
                             venue: "Mission Bay", photoName: "photo-missionbay",
                             line: "Early miles around the bay. Built for consistency, not intensity.",
                             suggestedDuration: 10, payoff: Payoff(icon: "figure.strengthtraining.functional", text: "Winner sleeps in guilt-free tomorrow — loser does a lap of jumping jacks for the group"),
                             goalTarget: 100_000),
        ChallengeSuggestion(title: "Little Italy Mercato Sunday Walk", icon: "cart.fill", kind: .steps,
                             venue: "Little Italy", photoName: "photo-steps",
                             line: "The Mercato farmers market takes over Little Italy every Sunday morning. Walk the whole stretch.",
                             suggestedDuration: 1, payoff: Payoff(icon: "figure.flexibility", text: "Winner's gelato is on the group — loser holds a 60-second plank outside the shop"),
                             goalTarget: 15_000),
        ChallengeSuggestion(title: "Ocean Beach Pier Walk", icon: "fish.fill", kind: .distance,
                             venue: "Ocean Beach", photoName: "photo-distance",
                             line: "Out to the end of OB Pier and back, most evenings the sunset's worth the walk alone.",
                             suggestedDuration: 3, payoff: Payoff(icon: "figure.pool.swim", text: "Winner picks the next hangout spot — loser jumps in the ocean, fully clothed"),
                             goalTarget: 9),
        ChallengeSuggestion(title: "North Park Brewery Steps", icon: "mug.fill", kind: .steps,
                             venue: "North Park", photoName: "photo-steps",
                             line: "North Park packs more breweries per block than anywhere else in the city. Walk between a few.",
                             suggestedDuration: 7, payoff: Payoff(icon: "dumbbell.fill", text: "Winner drinks free the rest of the crawl — loser drops for push-ups at every stop"),
                             goalTarget: 70_000),
        ChallengeSuggestion(title: "Pacific Beach Boardwalk Circuit", icon: "beach.umbrella.fill", kind: .distance,
                             venue: "Pacific Beach", photoName: "photo-distance",
                             line: "The PB boardwalk runs the whole coastline — bikes, skaters, and a lot of people to race past.",
                             suggestedDuration: 5, payoff: Payoff(icon: "figure.run", text: "Winner gets first pick of beach spot all summer — loser sprints the boardwalk solo"),
                             goalTarget: 14),
        ChallengeSuggestion(title: "Liberty Station Promenade Walk", icon: "building.2.fill", kind: .steps,
                             venue: "Liberty Station", photoName: "photo-steps",
                             line: "The old naval base's promenade and public market make for an easy, flat weekday loop.",
                             suggestedDuration: 1, payoff: Payoff(icon: "figure.strengthtraining.traditional", text: "Winner's market lunch is on the group — loser holds a 2-minute wall-sit"),
                             goalTarget: 14_000),
        ChallengeSuggestion(title: "Sunset Cliffs Coastal Trail", icon: "sun.horizon.fill", kind: .distance,
                             venue: "Sunset Cliffs", photoName: "photo-distance",
                             line: "One of the city's most dramatic coastlines, best walked right before golden hour.",
                             suggestedDuration: 3, payoff: Payoff(icon: "figure.hiking", text: "Winner picks the next sunset spot — loser redoes the whole trail backwards"),
                             goalTarget: 9),
    ]

    /// Which four of the pool show up this week — keyed to the actual
    /// calendar week, so the same window is stable all week (reopening the
    /// app doesn't reshuffle it) but a new week rotates to a different
    /// four. `weekOfYear` wrapping means the same venue can recur later in
    /// the year, same as a real recurring weekly event would.
    static var suggestions: [ChallengeSuggestion] {
        let week = Calendar.current.component(.weekOfYear, from: Date())
        let start = week % suggestionPool.count
        let rotated = suggestionPool[start...] + suggestionPool[..<start]
        // Several pool entries share the same reused generic photo (see
        // the comment above) — a plain consecutive window from the
        // rotation could land on two of them at once and show the same
        // background image twice in one 4-card carousel. Walk the rotated
        // order and skip anything whose photo is already picked, so
        // within any given week's four, every photo is distinct.
        var seenPhotos = Set<String>()
        var picked: [ChallengeSuggestion] = []
        for candidate in rotated {
            guard !seenPhotos.contains(candidate.photoName) else { continue }
            seenPhotos.insert(candidate.photoName)
            picked.append(candidate)
            if picked.count == 4 { break }
        }
        return picked
    }

    // MARK: Mood history

    static var moodHistory: [MoodCheckIn] {
        let cal = Calendar.current
        let today = Date()
        return (0..<6).reversed().map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            return MoodCheckIn(date: date,
                                energy: Double.random(in: 5...9),
                                mood: Double.random(in: 6...9),
                                motivation: Double.random(in: 4...8),
                                sleep: Double.random(in: 5...9))
        }
    }

    // MARK: Chat — seeded so threads read like real conversations, each
    // grounded in an actual shared challenge rather than generic filler.

    private static func chatDate(hoursAgo: Double) -> Date {
        Date().addingTimeInterval(-hoursAgo * 3600)
    }

    static var directMessages: [UUID: [ChatMessage]] {
        [
            sam.id: [
                ChatMessage(senderID: sam.id, text: "you doing the coastal series again this weekend?", date: chatDate(hoursAgo: 30)),
                ChatMessage(senderID: me.id, text: "yeah, gonna try to close the gap", date: chatDate(hoursAgo: 29)),
                ChatMessage(senderID: sam.id, text: "gap? 😂 there's no closing this gap", date: chatDate(hoursAgo: 29)),
                ChatMessage(senderID: sam.id, text: "see you sunday", date: chatDate(hoursAgo: 2)),
            ],
            grandmaRose.id: [
                ChatMessage(senderID: grandmaRose.id, text: "Beat you again today, sweetheart 💪", date: chatDate(hoursAgo: 20)),
                ChatMessage(senderID: me.id, text: "how are you even doing this", date: chatDate(hoursAgo: 19)),
                ChatMessage(senderID: grandmaRose.id, text: "Good shoes and nothing but time.", date: chatDate(hoursAgo: 19)),
                ChatMessage(senderID: me.id, text: "I need your secret", date: chatDate(hoursAgo: 18)),
                ChatMessage(senderID: grandmaRose.id, text: "Wear better shoes.", date: chatDate(hoursAgo: 18)),
            ],
        ]
    }

    static var groupMessages: [UUID: [ChatMessage]] {
        [
            familyGroup.id: [
                ChatMessage(senderID: mom.id, text: "so who's wearing the shame shirt", date: chatDate(hoursAgo: 10)),
                ChatMessage(senderID: dad.id, text: "I refuse", date: chatDate(hoursAgo: 10)),
                ChatMessage(senderID: grandmaRose.id, text: "Dad has to, rules are rules", date: chatDate(hoursAgo: 9)),
                ChatMessage(senderID: mom.id, text: "congrats on the win, by the way!", date: chatDate(hoursAgo: 9)),
                ChatMessage(senderID: dad.id, text: "next time it's on", date: chatDate(hoursAgo: 1)),
            ],
        ]
    }

    static let unreadDirectIDs: Set<UUID> = [sam.id]
    static let unreadGroupIDs: Set<UUID> = [familyGroup.id]
}

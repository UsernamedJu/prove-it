import Foundation

/// A real, attributed quote from an athlete — shown on Profile, never
/// invented. Kept short enough to quote directly.
struct AthleteQuote: Identifiable {
    let id = UUID()
    var text: String
    var athlete: String
}

enum Quotes {
    static let athletes: [AthleteQuote] = [
        .init(text: "You miss 100% of the shots you don't take.", athlete: "Wayne Gretzky"),
        .init(text: "I've failed over and over and over again in my life, and that is why I succeed.", athlete: "Michael Jordan"),
        .init(text: "It's not whether you get knocked down; it's whether you get up.", athlete: "Vince Lombardi"),
        .init(text: "Champions keep playing until they get it right.", athlete: "Billie Jean King"),
        .init(text: "Hard work beats talent when talent doesn't work hard.", athlete: "Tim Notke"),
        .init(text: "I hated every minute of training, but I said, 'Don't quit. Suffer now and live the rest of your life as a champion.'", athlete: "Muhammad Ali"),
        .init(text: "Set your goals high, and don't stop till you get there.", athlete: "Bo Jackson"),
        .init(text: "The most important thing is to try and inspire people so that they can be great in whatever they want to do.", athlete: "Kobe Bryant"),
    ]

    /// Deterministic by day, so it doesn't reshuffle on every render.
    static func ofTheDay() -> AthleteQuote {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return athletes[day % athletes.count]
    }
}

/// "Rudy" — the app's sarcastic-but-motivational voice. Every line
/// references something real about the user's own state (a rank, a margin,
/// a streak) rather than being generic filler.
enum Rudy {
    @MainActor
    static func greeting(app: AppModel) -> String {
        let name = app.me.name

        if let behind = app.activeChallenges
            .compactMap({ c -> (Challenge, Standing, Int)? in
                guard let mine = c.myStanding, mine.rank > 1,
                      let leader = c.standings.min(by: { $0.rank < $1.rank }) else { return nil }
                let margin = Int((leader.progress - mine.progress) * 100)
                return margin > 0 ? (c, leader, margin) : nil
            })
            .max(by: { $0.2 < $1.2 }) {
            return "\(behind.1.member.name) is beating you by \(behind.2)% in \(behind.0.title). Bold strategy, \(name)."
        }

        if let leading = app.activeChallenges.first(where: { $0.myStanding?.rank == 1 }) {
            return "You're #1 in \(leading.title). Don't get comfortable."
        }

        if app.moodLoggedToday {
            return "\(app.moodStreak)-day mood streak. Emotionally you're winning. We'll see about the rest."
        }

        if app.moodStreak >= 3 {
            return "Still on a \(app.moodStreak)-day streak — log today before it resets on you."
        }

        return "Another day, another chance to not skip it."
    }
}

/// Canned auto-replies for chat threads — there's no real backend, so a
/// sent message gets a short reply after a beat instead of vanishing into
/// silence. Leans into the same competitive, grounded-in-real-state tone
/// as Rudy: when the two of you share an active challenge, the reply
/// references it directly; otherwise it falls back to general banter.
enum ChatBanter {
    private static let general = [
        "Ha, we'll see about that.",
        "Bold talk for someone who hasn't logged today.",
        "I'm not losing this one.",
        "Deal. Loser buys coffee ☕",
        "You're on.",
        "Nice try — still winning though.",
        "Okay now I actually have to go walk.",
        "Love the confidence. Misplaced, but I love it.",
        "See you on the leaderboard.",
        "That's cute. Anyway.",
    ]

    static func reply(from member: Member, sharedChallenge: (title: String, theirRank: Int, myRank: Int?)?, seed: Int) -> String {
        if let sc = sharedChallenge {
            if sc.theirRank == 1 {
                return "Still #1 in \(sc.title). Just saying."
            }
            if let myRank = sc.myRank, myRank < sc.theirRank {
                return "Fine, you're ahead in \(sc.title). For now."
            }
        }
        let idx = abs((member.name + String(seed)).hashValue) % general.count
        return general[idx]
    }
}

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

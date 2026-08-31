import Foundation
import UserNotifications

/// Local, on-device notifications about real challenge-state changes — rank
/// moves, closing in on the goal, landing in last place. There's no server
/// here, so these fire the moment this device itself detects the change
/// (a Health sync, a Track Live session ending), not a true server push;
/// still real alerts about real state, not a stub. Every line leans
/// sarcastic on purpose — the one hard rule is blind-reveal challenges:
/// they only ever get a vague nudge when you've slipped behind, and never
/// so much as a hint when you're ahead, since telling you that would give
/// away the exact thing blind mode exists to hide.
enum ChallengeNotifier {
    static func requestPermissionIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private static func send(title: String, body: String, enabled: Bool) {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            UNUserNotificationCenter.current().add(request)
        }
    }

    /// `oldRank`/`newRank` are 1-based standing positions. Only called when
    /// they actually differ — the caller (`AppModel.recomputeRanks`)
    /// already edge-triggers this, so there's no per-sync spam.
    static func notifyRankChange(challengeTitle: String, blindReveal: Bool, oldRank: Int, newRank: Int, enabled: Bool) {
        let improved = newRank < oldRank
        if blindReveal {
            // The whole point of blind mode is that nobody sees the board —
            // an "ahead" notification would just leak the thing it's
            // supposed to hide, so that case is silently dropped. A "behind"
            // nudge stays deliberately vague: no rank number, no margin.
            guard !improved else { return }
            let lines = [
                "You might want to check in on \(challengeTitle). No pressure. Okay, some pressure.",
                "Something's shifting in \(challengeTitle) and it's not obviously in your favor.",
                "A little bird says \(challengeTitle) isn't going great for you right now.",
            ]
            send(title: "Psst — \(challengeTitle)", body: lines.randomElement()!, enabled: enabled)
            return
        }
        if improved {
            let lines = [
                "You climbed to #\(newRank) in \(challengeTitle). Try to act surprised when everyone notices.",
                "#\(newRank) in \(challengeTitle) now. Momentum's a beautiful thing — don't waste it on a rest day.",
                "You passed someone in \(challengeTitle). They'll pretend they didn't notice. They noticed.",
            ]
            send(title: "Moving up 📈", body: lines.randomElement()!, enabled: enabled)
        } else {
            let lines = [
                "You dropped to #\(newRank) in \(challengeTitle). The couch isn't going to walk itself.",
                "Someone just passed you in \(challengeTitle). Rude of them. Correct, but rude.",
                "#\(newRank) now in \(challengeTitle). This is usually the part where people start caring.",
            ]
            send(title: "Slipping a bit 📉", body: lines.randomElement()!, enabled: enabled)
        }
    }

    /// Fired once, on the crossing into "close enough that finishing today
    /// is realistic" — never blind-gated, since being close to winning is
    /// exactly the kind of thing a blind challenge is fine revealing to the
    /// leader, it just can't reveal it to everyone else.
    static func notifyAboutToWin(challengeTitle: String, enabled: Bool) {
        let lines = [
            "You're one solid push away from winning \(challengeTitle). Don't choke now.",
            "\(challengeTitle) is basically yours. \"Basically.\" Finish it.",
            "So close on \(challengeTitle) you can probably taste it. Go taste it for real.",
        ]
        send(title: "Almost there 🏁", body: lines.randomElement()!, enabled: enabled)
    }

    /// Fired once, the moment you newly become last place — not blind-
    /// gated either, on the theory that "you're last" is information about
    /// your own effort, not a leak of the leaderboard's shape.
    static func notifyLastPlace(challengeTitle: String, enabled: Bool) {
        let lines = [
            "You're in last place in \(challengeTitle). Someone has to be — didn't think it'd be you though.",
            "Dead last in \(challengeTitle) right now. Character building, allegedly.",
            "Last place in \(challengeTitle). The good news: nowhere to go but up. The bad news: everywhere else.",
        ]
        send(title: "Rough spot 🐌", body: lines.randomElement()!, enabled: enabled)
    }
}

import Foundation

/// One day's Mood Check-in — four 1–10 sliders. Purely a personal wellness
/// log, same as the reference app's check-in screen — it doesn't feed any
/// point economy.
struct MoodCheckIn: Identifiable, Codable {
    // `var`, not `let` — a `let` with a default value is silently skipped by
    // synthesized Decodable, so every restored/synced entry would mint a
    // fresh random id instead of round-tripping the one it was encoded with.
    var id = UUID()
    var date: Date
    var energy: Double
    var mood: Double
    var motivation: Double
    var sleep: Double

    var average: Double { (energy + mood + motivation + sleep) / 4 }
}

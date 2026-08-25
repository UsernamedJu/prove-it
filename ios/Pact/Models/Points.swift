import Foundation

/// One day's Mood Check-in — four 1–10 sliders. Purely a personal wellness
/// log, same as the reference app's check-in screen — it doesn't feed any
/// point economy.
struct MoodCheckIn: Identifiable {
    let id = UUID()
    var date: Date
    var energy: Double
    var mood: Double
    var motivation: Double
    var sleep: Double

    var average: Double { (energy + mood + motivation + sleep) / 4 }
}

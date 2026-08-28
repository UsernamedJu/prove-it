import Foundation

enum Sex: String, CaseIterable, Identifiable {
    case female = "Female"
    case male = "Male"
    case other = "Prefer not to say"
    var id: String { rawValue }
}

/// Drives both the calorie-burn estimate (a real multiplier) and a gentler
/// nudge on the step-count target — steps don't scale with activity the way
/// calories do, so the two multipliers below are deliberately different.
enum ActivityLevel: String, CaseIterable, Identifiable {
    case sedentary = "Sedentary"
    case light = "Lightly active"
    case moderate = "Moderately active"
    case active = "Active"
    case veryActive = "Very active"
    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .sedentary: return "Desk job, little to no exercise"
        case .light: return "Light exercise 1–3 days a week"
        case .moderate: return "Moderate exercise 3–5 days a week"
        case .active: return "Hard exercise 6–7 days a week"
        case .veryActive: return "Physical job, or training twice a day"
        }
    }

    /// Standard Mifflin-St Jeor / Harris-Benedict TDEE activity factor.
    var tdeeMultiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }

    var stepMultiplier: Double {
        switch self {
        case .sedentary: return 0.85
        case .light: return 1.0
        case .moderate: return 1.1
        case .active: return 1.25
        case .veryActive: return 1.4
        }
    }
}

enum UnitSystem: String, CaseIterable, Identifiable {
    case imperial = "Imperial"
    case metric = "Metric"
    var id: String { rawValue }
}

/// Everything used to personalize a step target and a calorie estimate for
/// the signed-in user. Kept separate from `Member` since crew members never
/// need this — only "me" does.
struct BodyProfile: Hashable {
    var heightCm: Double = 170
    var weightKg: Double = 70
    var sex: Sex = .other
    var age: Int = 30
    var activityLevel: ActivityLevel = .moderate

    var heightFeetInches: (feet: Int, inches: Int) {
        let totalInches = heightCm / 2.54
        let feet = Int(totalInches / 12)
        let inches = Int(totalInches.truncatingRemainder(dividingBy: 12).rounded())
        return (feet, inches)
    }
    mutating func setHeight(feet: Int, inches: Int) {
        heightCm = (Double(feet) * 12 + Double(inches)) * 2.54
    }

    var weightLb: Double { weightKg * 2.20462 }
    mutating func setWeightLb(_ lb: Double) { weightKg = lb / 2.20462 }

    var bmi: Double {
        let heightM = heightCm / 100
        guard heightM > 0 else { return 0 }
        return weightKg / (heightM * heightM)
    }

    /// Mifflin-St Jeor resting BMR scaled by activity — a real formula, not
    /// an invented one. `.other` uses the midpoint of the male/female offset
    /// rather than defaulting to either.
    var estimatedDailyCalories: Int {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        let bmr: Double
        switch sex {
        case .male: bmr = base + 5
        case .female: bmr = base - 161
        case .other: bmr = base - 78
        }
        return Int((bmr * activityLevel.tdeeMultiplier).rounded())
    }

    /// The Fair Play age-band baseline, nudged by activity level and a
    /// gentle BMI adjustment — transparent inputs, not a black box.
    func personalizedStepTarget(ageBand: AgeBand) -> Int {
        var target = Double(ageBand.fairPlayStepTarget) * activityLevel.stepMultiplier
        if bmi >= 30 { target *= 1.05 }
        else if bmi > 0 && bmi < 18.5 { target *= 0.95 }
        return Int((target / 250).rounded()) * 250
    }
}

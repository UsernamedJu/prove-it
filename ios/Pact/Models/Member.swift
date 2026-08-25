import Foundation

/// Age band drives Fair Play scoring — the mechanic that lets very different
/// people compete as equals by racing a personalized target instead of a
/// raw number.
enum AgeBand: String, CaseIterable, Identifiable {
    case teen = "13–19"
    case adult = "20–39"
    case midlife = "40–59"
    case senior = "60+"
    var id: String { rawValue }

    var fairPlayStepTarget: Int {
        switch self {
        case .teen: return 10_000
        case .adult: return 9_000
        case .midlife: return 8_000
        case .senior: return 6_500
        }
    }
}

/// A person in your crew. No avatar image or generated illustration — people
/// are represented everywhere by an `InitialBadge` colored off their name.
///
/// There is no point balance / wallet — that was explicitly removed. The
/// only numeric score a member has is a fit score (see `AppModel.fitScore`),
/// used purely to recommend which workout types and challenges suit them —
/// never spent, never a currency.
struct Member: Identifiable, Hashable {
    let id: UUID
    var name: String
    var ageBand: AgeBand

    init(id: UUID = UUID(), name: String, ageBand: AgeBand = .adult) {
        self.id = id
        self.name = name
        self.ageBand = ageBand
    }
}

/// A named group of contacts — lets a challenge be created for "the whole
/// family" in one tap instead of picking people one at a time.
struct ContactGroup: Identifiable {
    let id: UUID
    var name: String
    var memberIDs: [UUID]

    init(id: UUID = UUID(), name: String, memberIDs: [UUID]) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
    }
}

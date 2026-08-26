import Foundation

enum Route: Hashable {
    case challenge(UUID)
    case createChallenge(ChallengeSuggestion?)
    case moodSurvey
    case group(UUID)
    case member(UUID)
    case chatList
    case directChat(UUID)
    case groupChat(UUID)
}

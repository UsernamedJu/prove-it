import Foundation

/// One message in a direct or group thread. `senderID` is `app.me.id` for
/// anything the user sent, or a crew member's id otherwise — no separate
/// "isMe" flag needed since identity is already unambiguous from the id.
struct ChatMessage: Identifiable, Hashable {
    let id: UUID
    var senderID: UUID
    var text: String
    var date: Date

    init(id: UUID = UUID(), senderID: UUID, text: String, date: Date = Date()) {
        self.id = id
        self.senderID = senderID
        self.text = text
        self.date = date
    }
}

/// Which thread a chat screen is showing — a 1:1 with a crew member, or a
/// group conversation. Kept separate from `Route` so chat views can be
/// previewed and reasoned about without pulling in navigation.
enum ChatThreadKind: Hashable {
    case direct(UUID)
    case group(UUID)
}

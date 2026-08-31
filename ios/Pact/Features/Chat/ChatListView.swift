import SwiftUI

/// Every conversation — a 1:1 with each crew member, plus one per group —
/// sorted by most recent activity. Reached from the message icon on Home.
struct ChatListView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let id: UUID
        let route: Route
        let title: String
        let subtitle: String
        let date: Date?
        let unread: Bool
        let isGroup: Bool
    }

    private func preview(_ message: ChatMessage?, isGroup: Bool) -> String {
        guard let message else { return "Say hi 👋" }
        guard isGroup else { return message.text }
        let sender = message.senderID == app.me.id ? "You" : (app.crew.first { $0.id == message.senderID }?.name ?? "")
        return "\(sender): \(message.text)"
    }

    private var rows: [Row] {
        let direct = app.crew.map { member -> Row in
            let last = app.lastMessage(directWith: member.id)
            return Row(id: member.id, route: .directChat(member.id), title: member.name,
                       subtitle: preview(last, isGroup: false), date: last?.date,
                       unread: app.unreadDirectIDs.contains(member.id), isGroup: false)
        }
        let groupRows = app.groups.map { group -> Row in
            let last = app.lastMessage(inGroup: group.id)
            return Row(id: group.id, route: .groupChat(group.id), title: group.name,
                       subtitle: preview(last, isGroup: true), date: last?.date,
                       unread: app.unreadGroupIDs.contains(group.id), isGroup: true)
        }
        return (direct + groupRows).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Messages").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                    .padding(.top, Theme.Space.md)
                if rows.isEmpty {
                    Text("No conversations yet — add someone to your Crew, or invite a real buddy to a challenge.")
                        .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                } else {
                    ForEach(rows) { row in
                        NavigationLink(value: row.route) {
                            rowView(row)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Theme.Space.lg)
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(PactBackground())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Ink.secondary)
                        .frame(width: 40, height: 40)
                        .glassSurface(cornerRadius: 20)
                        .clipShape(Circle())
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.xs)
        }
    }

    private func rowView(_ row: Row) -> some View {
        PactCard(tint: row.isGroup ? Theme.Brand.cyan : swatchColor(for: row.title)) {
            HStack(spacing: Theme.Space.sm) {
                if row.isGroup {
                    ZStack {
                        Circle().fill(Theme.Brand.cyan.opacity(0.2)).frame(width: 44, height: 44)
                        Image(systemName: "person.3.fill").foregroundStyle(Theme.Brand.cyan)
                    }
                } else {
                    InitialBadge(name: row.title, size: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                    Text(row.subtitle)
                        .font(Theme.Font.caption())
                        .foregroundStyle(row.unread ? Theme.Ink.primary : Theme.Ink.tertiary)
                        .fontWeight(row.unread ? .semibold : .regular)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    if let date = row.date {
                        Text(date.formatted(.relative(presentation: .named)))
                            .font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                    }
                    if row.unread {
                        Circle().fill(Theme.Brand.pink).frame(width: 9, height: 9)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack { ChatListView() }.environment(AppModel())
}

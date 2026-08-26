import SwiftUI

/// A single conversation — direct or group. No real backend: sending
/// appends your message immediately, and `AppModel` schedules a canned
/// reply a beat later so the thread never just goes silent.
struct ChatThreadView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let kind: ChatThreadKind

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var isGroup: Bool { if case .group = kind { return true } else { return false } }

    private var title: String {
        switch kind {
        case .direct(let id): return app.crew.first { $0.id == id }?.name ?? "Chat"
        case .group(let id): return app.groups.first { $0.id == id }?.name ?? "Chat"
        }
    }

    private var messages: [ChatMessage] {
        switch kind {
        case .direct(let id): return app.directMessages[id] ?? []
        case .group(let id): return app.groupMessages[id] ?? []
        }
    }

    private func senderName(_ id: UUID) -> String {
        id == app.me.id ? app.me.name : (app.crew.first { $0.id == id }?.name ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.sm) {
                        if messages.isEmpty {
                            emptyState
                        }
                        ForEach(messages) { message in
                            bubble(message).id(message.id)
                        }
                    }
                    .padding(Theme.Space.lg)
                }
                .onAppear {
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation(Theme.Motion.settle) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            inputBar
        }
        .background(PactBackground())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { markRead() }
        .onDisappear { clearOpen() }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.sm) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Ink.secondary)
                    .frame(width: 40, height: 40)
                    .glassSurface(cornerRadius: 20)
                    .clipShape(Circle())
            }
            if isGroup {
                ZStack {
                    Circle().fill(Theme.Brand.cyan.opacity(0.2)).frame(width: 36, height: 36)
                    Image(systemName: "person.3.fill").font(.system(size: 14)).foregroundStyle(Theme.Brand.cyan)
                }
            } else {
                InitialBadge(name: title, size: 36)
            }
            Text(title).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
            Spacer()
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.vertical, Theme.Space.sm)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No messages yet").font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
            Text("Say hi 👋").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.xxl)
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let mine = message.senderID == app.me.id
        return VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            if isGroup && !mine {
                Text(senderName(message.senderID))
                    .font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                    .padding(.horizontal, 4)
            }
            Text(message.text)
                .font(Theme.Font.body())
                .foregroundStyle(mine ? Theme.Ink.onBrand : Theme.Ink.primary)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 10)
                .background(mine ? Theme.Brand.purple : Theme.Surface.card)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: mine ? Theme.Radius.lg : 4,
                    bottomLeadingRadius: Theme.Radius.lg,
                    bottomTrailingRadius: mine ? 4 : Theme.Radius.lg,
                    topTrailingRadius: Theme.Radius.lg))
                .overlay {
                    if !mine {
                        UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: Theme.Radius.lg,
                                                bottomTrailingRadius: Theme.Radius.lg, topTrailingRadius: Theme.Radius.lg)
                            .stroke(Theme.Surface.border, lineWidth: 1)
                    }
                }
            Text(message.date.formatted(date: .omitted, time: .shortened))
                .font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var inputBar: some View {
        HStack(spacing: Theme.Space.sm) {
            TextField("Message", text: $draft, axis: .vertical)
                .font(Theme.Font.body())
                .foregroundStyle(Theme.Ink.primary)
                .lineLimit(1...4)
                .padding(.horizontal, Theme.Space.md)
                .padding(.vertical, 12)
                .glassSurface(cornerRadius: Theme.Radius.lg)
                .focused($focused)
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.Ink.tertiary : Theme.Brand.purple)
                    .clipShape(Circle())
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.top, Theme.Space.sm)
        .padding(.bottom, 76)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(Theme.Motion.pop) {
            switch kind {
            case .direct(let id): app.sendDirectMessage(to: id, text: text)
            case .group(let id): app.sendGroupMessage(to: id, text: text)
            }
            draft = ""
        }
    }

    private func markRead() {
        switch kind {
        case .direct(let id):
            app.unreadDirectIDs.remove(id)
            app.openDirectChatID = id
        case .group(let id):
            app.unreadGroupIDs.remove(id)
            app.openGroupChatID = id
        }
    }

    private func clearOpen() {
        switch kind {
        case .direct: app.openDirectChatID = nil
        case .group: app.openGroupChatID = nil
        }
    }
}

#Preview {
    NavigationStack { ChatThreadView(kind: .direct(Fixtures.sam.id)) }.environment(AppModel())
}

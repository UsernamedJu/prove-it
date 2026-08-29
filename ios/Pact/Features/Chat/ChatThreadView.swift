import SwiftUI
import PhotosUI

/// A single conversation — direct or group. No real backend: sending
/// appends your message immediately, and `AppModel` schedules a canned
/// reply a beat later so the thread never just goes silent.
struct ChatThreadView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let kind: ChatThreadKind

    @State private var draft = ""
    @FocusState private var focused: Bool
    @State private var pickedImageItem: PhotosPickerItem?
    @State private var pickedImageData: Data?

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
        let bubbleShape = UnevenRoundedRectangle(
            topLeadingRadius: mine ? Theme.Radius.lg : 4,
            bottomLeadingRadius: Theme.Radius.lg,
            bottomTrailingRadius: mine ? 4 : Theme.Radius.lg,
            topTrailingRadius: Theme.Radius.lg)
        return VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            if isGroup && !mine {
                Text(senderName(message.senderID))
                    .font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                    .padding(.horizontal, 4)
            }
            if let imageData = message.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 200, height: 200)
                    .clipShape(bubbleShape)
                    .overlay { if !mine { bubbleShape.stroke(Theme.Surface.border, lineWidth: 1) } }
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .font(Theme.Font.body())
                    .foregroundStyle(mine ? Theme.Ink.onBrand : Theme.Ink.primary)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, 10)
                    .background(mine ? Theme.Brand.purple : Theme.Surface.card)
                    .clipShape(bubbleShape)
                    .overlay { if !mine { bubbleShape.stroke(Theme.Surface.border, lineWidth: 1) } }
            }
            Text(message.date.formatted(date: .omitted, time: .shortened))
                .font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            if let pickedImageData, let uiImage = UIImage(data: pickedImageData) {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                    Button {
                        self.pickedImageData = nil
                        self.pickedImageItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, Theme.Ink.primary.opacity(0.8))
                    }
                    .offset(x: 6, y: -6)
                }
                .padding(.horizontal, Theme.Space.md)
            }
            HStack(spacing: Theme.Space.sm) {
                PhotosPicker(selection: $pickedImageItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Ink.secondary)
                        .frame(width: 44, height: 44)
                        .background(Theme.Surface.card)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.Surface.border, lineWidth: 1.2))
                }
                .onChange(of: pickedImageItem) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self) { pickedImageData = data }
                    }
                }
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
                        .background(canSend ? Theme.Brand.purple : Theme.Ink.tertiary)
                        .clipShape(Circle())
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .padding(.top, Theme.Space.sm)
        .padding(.bottom, 76)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pickedImageData != nil
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        withAnimation(Theme.Motion.pop) {
            switch kind {
            case .direct(let id): app.sendDirectMessage(to: id, text: text, imageData: pickedImageData)
            case .group(let id): app.sendGroupMessage(to: id, text: text, imageData: pickedImageData)
            }
            draft = ""
            pickedImageData = nil
            pickedImageItem = nil
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

import SwiftUI
import CloudKit

/// The Home-screen surface for real, CKShare-backed challenges — the one
/// part of this app where progress is genuinely synced between two
/// different iCloud accounts instead of Fixtures-seeded. Deliberately its
/// own section rather than folded into "Your Challenges": mixing real data
/// with the demo crew's fake progress in one list would make it hard to
/// tell which is which.
struct SharedChallengesSection: View {
    @Environment(AppModel.self) private var app
    @Environment(SharedChallengeStore.self) private var store
    @State private var showingCreate = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Group Challenges")
            Text("Invite one buddy — synced over iCloud, not the demo crew.")
                .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)

            if let error = store.lastError {
                Text(error).font(Theme.Font.caption()).foregroundStyle(Theme.Brand.coral)
            }

            ForEach(store.challenges) { challenge in
                SharedChallengeCard(challenge: challenge)
            }

            Button {
                showingCreate = true
            } label: {
                HStack(spacing: 6) { Image(systemName: "person.badge.plus"); Text("Invite a Buddy") }
            }
            .buttonStyle(PactButtonStyle(kind: .outline))
        }
        .task {
            await store.refresh(myLocalID: app.me.id, myName: app.me.name)
        }
        .sheet(isPresented: $showingCreate) {
            CreateSharedChallengeSheet()
        }
    }
}

private struct SharedChallengeCard: View {
    @Environment(AppModel.self) private var app
    @Environment(SharedChallengeStore.self) private var store
    let challenge: SharedChallenge
    @State private var shareURL: URL?
    @State private var isLogging = false

    private var mine: SharedEntry? { challenge.myEntry }
    private var others: [SharedEntry] { challenge.otherEntries }

    var body: some View {
        PactCard(tint: swatchColor(for: challenge.title)) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(challenge.title).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        Text(challenge.venue).font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                    Spacer()
                    TagBadge(text: "Live", icon: "icloud.fill", tint: Theme.Brand.cyan, filled: true)
                }

                participantRow(name: "You", entry: mine)
                if others.isEmpty {
                    Text("Waiting for them to accept your invite…")
                        .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                } else {
                    ForEach(others) { entry in
                        participantRow(name: entry.participantName, entry: entry)
                    }
                }

                HStack(spacing: Theme.Space.sm) {
                    let syncsFromHealth = app.healthKitConnected && challenge.kind != .custom
                    Button {
                        isLogging = true
                        Task {
                            if syncsFromHealth {
                                await store.syncTodayFromHealth(challengeLocalID: challenge.localID, myLocalID: app.me.id)
                            } else {
                                await store.logProgress(challengeLocalID: challenge.localID, measuredRatio: nil, myLocalID: app.me.id)
                            }
                            isLogging = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: syncsFromHealth ? "heart.fill" : "plus.circle.fill")
                            Text(syncsFromHealth ? "Sync from Health" : "Log Today")
                        }
                    }
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Brand.purple)
                    .disabled(isLogging)

                    if challenge.isOwnedByMe {
                        Spacer()
                        Button {
                            Task { shareURL = await store.shareURL(for: challenge.localID) }
                        } label: {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                        }
                        .foregroundStyle(Theme.Ink.tertiary)
                    }
                }
            }
        }
        .sheet(item: Binding(get: { shareURL.map { ShareURLBox(url: $0) } }, set: { shareURL = $0?.url })) { box in
            ShareLink(item: box.url) { Label("Send Invite Link", systemImage: "square.and.arrow.up") }
                .padding()
                .presentationDetents([.height(120)])
        }
    }

    private func participantRow(name: String, entry: SharedEntry?) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Text(name).font(Theme.Font.caption()).foregroundStyle(Theme.Ink.secondary).frame(width: 56, alignment: .leading)
            ProgressPill(progress: entry?.progress ?? 0, tint: swatchColor(for: challenge.title), height: 6)
            if entry?.lastLogVerified == true {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 11)).foregroundStyle(Theme.Brand.lime)
            }
        }
    }
}

private struct ShareURLBox: Identifiable {
    let url: URL
    var id: URL { url }
}

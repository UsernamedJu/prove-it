import SwiftUI

struct ChallengesListView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Challenges").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                    Text("Everything you're in, active or settled.")
                        .font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                }
                .padding(.top, Theme.Space.md)

                NavigationLink(value: Route.createChallenge(nil)) {
                    HStack(spacing: 6) { Image(systemName: "plus"); Text("New Challenge") }
                }
                .buttonStyle(PactButtonStyle(kind: .primary))

                if app.challenges.isEmpty {
                    Text("No challenges yet. Start one above, or swipe through the suggestions on Home.")
                        .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                } else {
                    ForEach(app.challenges) { challenge in
                        SwipeToDeleteRow(onDelete: { app.deleteChallenge(challenge.id) }) {
                            ChallengeRow(challenge: challenge)
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                    // Keyed to the actual membership/order, not every
                    // incidental re-render — a freshly-sent challenge
                    // (always inserted at index 0) now visibly settles
                    // into the top of the list instead of just appearing.
                    .animation(Theme.Motion.pop, value: app.challenges.map(\.id))
                }
            }
            .padding(Theme.Space.lg)
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(PactBackground())
        .toolbar(.hidden, for: .navigationBar)
        // Time-based auto-completion otherwise only gets checked at app
        // launch and whenever a Health sync happens to fire — someone who
        // disconnects Health after creating a challenge and just leaves
        // the app open could otherwise have an expired challenge sit
        // unresolved indefinitely. This is the cheapest reliable catch-all:
        // whoever opens the list to actually look at their challenges
        // triggers the same check.
        .onAppear { app.checkExpiredChallenges() }
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .challenge(let id): ChallengeDetailView(challengeID: id)
            case .createChallenge(let seed): CreateChallengeView(seed: seed)
            case .moodSurvey: MoodSurveyView()
            case .group(let id): GroupDetailView(groupID: id)
            case .member(let id): MemberDetailView(memberID: id)
            case .chatList: ChatListView()
            case .directChat(let id): ChatThreadView(kind: .direct(id))
            case .groupChat(let id): ChatThreadView(kind: .group(id))
            }
        }
    }
}

#Preview {
    NavigationStack { ChallengesListView() }.environment(AppModel())
}

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

                ForEach(app.challenges) { challenge in
                    ChallengeRow(challenge: challenge)
                }
            }
            .padding(Theme.Space.lg)
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(PactBackground())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .challenge(let id): ChallengeDetailView(challengeID: id)
            case .createChallenge(let seed): CreateChallengeView(seed: seed)
            case .moodSurvey: MoodSurveyView()
            case .group(let id): GroupDetailView(groupID: id)
            case .member(let id): MemberDetailView(memberID: id)
            }
        }
    }
}

#Preview {
    NavigationStack { ChallengesListView() }.environment(AppModel())
}

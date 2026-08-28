import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @State private var showSettings = false

    private var completed: [Challenge] { app.challenges.filter { $0.status == .complete } }
    private var wins: Int { completed.filter { $0.winnerName == app.me.name }.count }
    private var losses: Int { completed.count - wins }
    private var quote: AthleteQuote { Quotes.ofTheDay() }

    private var shareURL: URL? { Bundle.main.url(forResource: "PactShare", withExtension: "html") }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.lg) {
                header
                fitnessCard
                HStack(spacing: Theme.Space.sm) {
                    StatChip(label: "Wins", value: "\(wins)", tint: Theme.Brand.lime)
                    StatChip(label: "Losses", value: "\(losses)", tint: Theme.Brand.coral)
                    StatChip(label: "Mood Streak", value: "\(app.moodStreak)d", tint: Theme.Brand.gold)
                }
                quoteCard
                if let shareURL {
                    ShareLink(item: shareURL) {
                        HStack(spacing: 6) { Image(systemName: "square.and.arrow.up"); Text("Share Pact with Friends & Family") }
                    }
                    .buttonStyle(PactButtonStyle(kind: .outline))
                }
                recentSection
            }
            .padding(Theme.Space.lg)
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(PactBackground())
        .sheet(isPresented: $showSettings) { SettingsView(app: app) }
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

    private var header: some View {
        VStack(spacing: Theme.Space.sm) {
            HStack {
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Ink.secondary)
                        .frame(width: 40, height: 40)
                        .glassSurface(cornerRadius: 20)
                        .clipShape(Circle())
                }
            }
            InitialBadge(name: app.me.name, size: 72, overrideColor: app.meColor, photoData: app.myProfilePhotoData)
            Text(app.me.name).font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
            Text(app.me.ageBand.rawValue).font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
        }
        .padding(.top, Theme.Space.lg)
        .frame(maxWidth: .infinity)
    }

    private var fitnessCard: some View {
        let fit = app.fitTag(for: app.me)
        return PactCard(tint: Theme.Brand.cyan) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack {
                    Text("Fitness Score").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                    Spacer()
                    Text("\(app.fitnessScore)").font(Theme.Font.number(22)).foregroundStyle(Theme.Brand.cyan)
                }
                ProgressPill(progress: Double(app.fitnessScore) / 100, tint: Theme.Brand.cyan, height: 8)
                Text("From your recent mood trend and how often you're logging progress. Used only to recommend workout types and gauge challenge fit — not a currency.")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                Divider().overlay(Theme.Surface.border)
                HStack {
                    Image(systemName: fit.kind.icon).foregroundStyle(Theme.Brand.cyan)
                    Text(fit.label).font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                    Spacer()
                }
                HStack {
                    Text("Personalized step goal").font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                    Spacer()
                    Text("\(app.personalizedStepTarget.formatted())/day").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                }
                HStack {
                    Text("Estimated daily burn").font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                    Spacer()
                    Text("\(app.myBodyProfile.estimatedDailyCalories.formatted()) cal").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                }
            }
        }
    }

    private var quoteCard: some View {
        PactCard(tint: Theme.Brand.gold) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Image(systemName: "quote.opening").font(.system(size: 20)).foregroundStyle(Theme.Brand.gold)
                Text(quote.text).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                Text("— \(quote.athlete)").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Recent Challenges")
            if completed.isEmpty {
                Text("Nothing settled yet — your first result will show up here.")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
            }
            ForEach(completed) { challenge in
                let won = challenge.winnerName == app.me.name
                NavigationLink(value: Route.challenge(challenge.id)) {
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: won ? "trophy.fill" : "hands.clap.fill")
                            .foregroundStyle(won ? Theme.Brand.gold : Theme.Ink.tertiary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(challenge.title).font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                            Text("\(challenge.venue) · \(challenge.payoff.text)").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(won ? "Won" : "Settled")
                                .font(Theme.Font.caption())
                                .foregroundStyle(won ? Theme.Brand.lime : Theme.Ink.tertiary)
                            Text("Details").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.Ink.tertiary)
                    }
                    .padding(.vertical, Theme.Space.xs)
                }
                .buttonStyle(.plain)
                Divider().overlay(Theme.Surface.border)
            }
        }
    }
}

#Preview {
    NavigationStack { ProfileView() }.environment(AppModel())
}

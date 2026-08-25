import SwiftUI
import MapKit

struct HomeView: View {
    @Environment(AppModel.self) private var app

    private var distanceChallenge: Challenge? {
        app.activeChallenges.first { $0.isDistanceBased }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                header
                moodBubble
                suggestedCard
                if let dc = distanceChallenge { mapPreview(dc) }
                activeSection
            }
            .padding(Theme.Space.lg)
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(PactBackground())
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if app.justCreated {
                CelebrationOverlay(icon: "sparkles", tint: Theme.Brand.purple, title: "Challenge sent!", subtitle: nil) {
                    app.justCreated = false
                }
            }
        }
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

    // MARK: Header — the Pact mark + Rudy's sarcastic-but-real greeting

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                PactMark(size: 22)
                Spacer()
                InitialBadge(name: app.me.name, size: 44, overrideColor: app.meColor)
            }
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.Brand.gold)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rudy").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Brand.gold)
                    Text(app.rudyGreeting).font(Theme.Font.h2()).foregroundStyle(Theme.Ink.primary)
                }
            }
        }
        .padding(.top, Theme.Space.md)
    }

    // MARK: Mood — a single tappable bubble, not an inline form

    private var moodBubble: some View {
        NavigationLink(value: Route.moodSurvey) {
            PactCard(tint: Theme.Brand.pink) {
                HStack(spacing: Theme.Space.sm) {
                    ZStack {
                        Circle().fill(Theme.Brand.pink.opacity(0.22)).frame(width: 44, height: 44)
                        Image(systemName: app.moodLoggedToday ? "checkmark.circle.fill" : "face.smiling")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.Brand.pink)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.moodLoggedToday ? "Mood logged for today" : "How are you feeling today?")
                            .font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        Text(app.moodLoggedToday ? "\(app.moodStreak)d streak — tap to see it" : "Tap for the 10-second check-in")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.Ink.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Suggested challenge — exactly one, never a rail

    private var suggestedCard: some View {
        let s = app.currentSuggestion
        return PactCard(tint: Theme.Brand.purple) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Image(s.photoName)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
                    .clipped()

                HStack {
                    TagBadge(text: "SUGGESTED FOR YOU", tint: Theme.Brand.purple, filled: true)
                    Spacer()
                    KindIcon(systemName: s.icon, size: 26, tint: Theme.Brand.purple)
                }
                Text(s.title).font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                Text(s.venue).font(Theme.Font.caption()).foregroundStyle(Theme.Brand.cyan)
                Text(s.line).font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)

                HStack(spacing: Theme.Space.sm) {
                    StatChip(label: "Duration", value: "\(s.suggestedDuration)d", tint: Theme.Brand.blue)
                    StatChip(label: "Kind", value: s.kind.rawValue, tint: Theme.Brand.cyan)
                }
                HStack(spacing: 6) {
                    Image(systemName: s.payoff.icon).font(.system(size: 13)).foregroundStyle(Theme.Brand.gold)
                    Text(s.payoff.text).font(Theme.Font.caption()).foregroundStyle(Theme.Brand.gold)
                }

                HStack(spacing: Theme.Space.sm) {
                    NavigationLink(value: Route.createChallenge(s)) {
                        Text("Start This Challenge")
                    }
                    .buttonStyle(PactButtonStyle(kind: .primary))

                    Button {
                        withAnimation(Theme.Motion.pop) { app.nextSuggestion() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.Ink.primary)
                            .frame(width: 56, height: 56)
                            .glassSurface(cornerRadius: Theme.Radius.md)
                    }
                }
            }
        }
    }

    // MARK: Map preview

    private func mapPreview(_ challenge: Challenge) -> some View {
        NavigationLink(value: Route.challenge(challenge.id)) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionHeader(title: "On the Map")
                ZStack(alignment: .bottomLeading) {
                    Map(initialPosition: .region(region(for: challenge)), interactionModes: []) {
                        if let coords = challenge.routeCoordinates {
                            MapPolyline(coordinates: coords).stroke(Theme.Brand.cyan, lineWidth: 4)
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
                    .frame(height: 150)
                    .allowsHitTesting(false)
                    .colorScheme(.dark)
                    .overlay(
                        LinearGradient(colors: [Theme.Brand.purpleDeep.opacity(0.28), .clear, Color.black.opacity(0.35)],
                                       startPoint: .top, endPoint: .bottom)
                    )

                    Text("\(challenge.title) · \(challenge.daysLeft)d left")
                        .font(Theme.Font.caption())
                        .foregroundStyle(Theme.Ink.onBrand)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Capsule())
                        .padding(Theme.Space.sm)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.5), Theme.Brand.cyan.opacity(0.14)],
                                            startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
            }
        }
        .buttonStyle(.plain)
    }

    private func region(for challenge: Challenge) -> MKCoordinateRegion {
        guard let coords = challenge.routeCoordinates, !coords.isEmpty else {
            return MKCoordinateRegion(center: .init(latitude: 32.8328, longitude: -117.2713),
                                       span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02))
        }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                             longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.012, (lats.max()! - lats.min()!) * 1.6),
                                     longitudeDelta: max(0.012, (lons.max()! - lons.min()!) * 1.6))
        return MKCoordinateRegion(center: center, span: span)
    }

    // MARK: Active challenges

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Your Challenges")
            ForEach(app.activeChallenges) { challenge in
                ChallengeRow(challenge: challenge)
            }
        }
    }
}

/// Compact challenge card used on Home and the Challenges tab.
struct ChallengeRow: View {
    @Environment(AppModel.self) private var app
    let challenge: Challenge

    private var mine: Standing? { challenge.myStanding }

    var body: some View {
        NavigationLink(value: Route.challenge(challenge.id)) {
            PactCard(tint: challenge.tint) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack(spacing: Theme.Space.sm) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(challenge.photoName)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
                                .clipped()
                            ZStack {
                                Circle().fill(challenge.tint).frame(width: 22, height: 22)
                                KindIcon(systemName: challenge.icon, size: 11, tint: .white)
                            }
                            .overlay(Circle().stroke(Theme.Surface.bgFlat, lineWidth: 2))
                            .offset(x: 5, y: 5)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(challenge.title).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                            Text("\(challenge.venue) · \(challenge.daysLeft)d left")
                                .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("RANK").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                            Text("#\(mine?.rank ?? 0)").font(Theme.Font.number(22)).foregroundStyle(challenge.tint)
                        }
                    }
                    ProgressPill(progress: mine?.progress ?? 0, tint: challenge.tint)

                    HStack {
                        if challenge.blindReveal && challenge.status == .active {
                            TagBadge(text: "Blind Reveal", icon: "eye.slash.fill", tint: Theme.Brand.pink)
                        }
                        if challenge.fairPlay { TagBadge(text: "Fair Play", icon: "scalemass.fill", tint: Theme.Brand.blue) }
                        Spacer()
                        switch challenge.status {
                        case .active:
                            Button { app.logActivity(for: challenge.id, hitTarget: true) } label: {
                                HStack(spacing: 4) { Image(systemName: "plus.circle.fill"); Text("Log Today") }
                            }
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Brand.purple)
                        case .revealReady:
                            TagBadge(text: "Reveal!", icon: "sparkles", tint: Theme.Brand.lime, filled: true)
                        case .complete:
                            TagBadge(text: "Complete", icon: "checkmark.circle.fill", tint: Theme.Ink.tertiary)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack { HomeView() }.environment(AppModel())
}

import SwiftUI
import MapKit

struct ChallengeDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let challengeID: UUID

    @State private var subTab = 0

    private var challenge: Challenge? { app.challenges.first { $0.id == challengeID } }

    var body: some View {
        if let challenge {
            content(challenge)
        } else {
            Text("This challenge is gone.").foregroundStyle(Theme.Ink.secondary)
        }
    }

    private func content(_ challenge: Challenge) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                hero(challenge)

                if challenge.status == .revealReady {
                    revealBanner(challenge)
                } else if challenge.status == .complete, let winner = challenge.winnerName {
                    settledBanner(challenge, winner: winner)
                }

                tabs(challenge)
                    .padding(.top, Theme.Space.md)

                switch subTab {
                case 0: BoardTab(challenge: challenge)
                case 1: ProgressTab(challenge: challenge)
                case 2: StatsTab(challenge: challenge)
                case 3: DetailsTab(challenge: challenge)
                default: MapTab(challenge: challenge)
                }
            }
        }
        .background(PactBackground())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Ink.onBrand)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.3))
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                Spacer()
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.xs)
        }
        .overlay {
            if app.justRevealedID == challenge.id {
                CelebrationOverlay(icon: "trophy.fill", tint: Theme.Brand.gold,
                                    title: "\(challenge.winnerName ?? "Someone") wins!",
                                    subtitle: challenge.payoff.text) {
                    app.justRevealedID = nil
                }
            }
        }
    }

    private func hero(_ challenge: Challenge) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            KindIcon(systemName: challenge.icon, size: 40, tint: .white)
            Text(challenge.title).font(Theme.Font.display(25)).foregroundStyle(.white)
            Text("\(challenge.venue) · \(challenge.participantsCount) people · \(challenge.daysLeft)d left")
                .font(Theme.Font.body()).foregroundStyle(.white.opacity(0.85))
            HStack {
                TagBadge(text: challenge.kind.rawValue, icon: challenge.kind.icon, tint: challenge.tint, filled: true)
                if challenge.blindReveal { TagBadge(text: "Blind Reveal", icon: "eye.slash.fill", tint: .white.opacity(0.25), filled: true) }
                if challenge.fairPlay { TagBadge(text: "Fair Play", icon: "scalemass.fill", tint: .white.opacity(0.25), filled: true) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.lg)
        .padding(.top, Theme.Space.xxl)
        .background(
            ZStack {
                Image(challenge.photoName).resizable().scaledToFill()
                LinearGradient(colors: [challenge.tint.opacity(0.80), Color.black.opacity(0.55)],
                                startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        )
        .clipped()
    }

    private func revealBanner(_ challenge: Challenge) -> some View {
        HStack(spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to reveal").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                Text("Scores are locked. Reveal to see the final standings.")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
            }
            Spacer()
            Button {
                withAnimation(Theme.Motion.pop) { app.resolveChallenge(challenge.id) }
            } label: {
                HStack(spacing: 6) { Image(systemName: "sparkles"); Text("Reveal") }
            }
            .buttonStyle(PactButtonStyle(kind: .tinted(Theme.Brand.lime), height: 44))
            .fixedSize()
        }
        .padding(Theme.Space.md)
        .background(Theme.Surface.glassBright)
    }

    private func settledBanner(_ challenge: Challenge, winner: String) -> some View {
        let loser = challenge.standings.max(by: { $0.rank < $1.rank })
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: "trophy.fill").font(.system(size: 20)).foregroundStyle(Theme.Brand.lime)
                Text("\(winner) won this challenge.")
                    .font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                Spacer()
            }
            if let loser {
                HStack(spacing: 6) {
                    Image(systemName: challenge.payoff.icon).font(.system(size: 13)).foregroundStyle(Theme.Brand.gold)
                    Text("\(loser.member.name): \(challenge.payoff.text)")
                        .font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                }
            }
        }
        .padding(Theme.Space.md)
        .background(Theme.Brand.lime.opacity(0.16))
    }

    private func tabs(_ challenge: Challenge) -> some View {
        var titles = ["Board", "Progress", "Stats", "Details"]
        if challenge.isDistanceBased { titles.append("Map") }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.lg) {
                ForEach(titles.indices, id: \.self) { i in
                    VStack(spacing: 6) {
                        Text(titles[i]).font(Theme.Font.h3())
                            .foregroundStyle(subTab == i ? Theme.Brand.purple : Theme.Ink.tertiary)
                        Rectangle()
                            .fill(subTab == i ? Theme.Brand.purple : .clear)
                            .frame(height: 3)
                    }
                    .onTapGesture { withAnimation(Theme.Motion.pop) { subTab = i } }
                }
            }
            .padding(.horizontal, Theme.Space.lg)
        }
    }
}

// MARK: - Board

private struct BoardTab: View {
    let challenge: Challenge

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            if challenge.blindReveal && challenge.status == .active {
                PactCard(tint: Theme.Brand.pink) {
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: "eye.slash.fill").font(.system(size: 18)).foregroundStyle(Theme.Brand.pink)
                        Text("Blind Mode Active — everyone else's score is hidden until reveal.")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.secondary)
                    }
                }
            }
            ForEach(challenge.standings.sorted { $0.rank < $1.rank }) { standing in
                BoardRow(standing: standing, isMe: standing.member.id == challenge.myMemberID,
                         blind: challenge.blindReveal && challenge.status == .active)
            }
        }
        .padding(Theme.Space.lg)
    }
}

private struct BoardRow: View {
    let standing: Standing
    let isMe: Bool
    let blind: Bool

    private var hideScore: Bool { blind && !isMe }

    var body: some View {
        PactCard(tint: isMe ? Theme.Brand.blue : swatchColor(for: standing.member.name)) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    medal
                    InitialBadge(name: standing.member.name, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(standing.member.name).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                            if isMe { Image(systemName: "hand.point.left.fill").font(.system(size: 12)).foregroundStyle(Theme.Ink.tertiary) }
                        }
                        Text("\(standing.trendDelta) this week")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(Int(standing.progress * 100))%")
                            .font(Theme.Font.number(20))
                            .foregroundStyle(swatchColor(for: standing.member.name))
                            .blur(radius: hideScore ? 6 : 0)
                        Text("progress").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                    }
                }
                ProgressPill(progress: standing.progress, tint: swatchColor(for: standing.member.name),
                             blurred: hideScore)
            }
        }
    }

    @ViewBuilder private var medal: some View {
        switch standing.rank {
        case 1: Image(systemName: "medal.fill").font(.system(size: 20)).foregroundStyle(Theme.Brand.gold).frame(width: 28)
        case 2: Image(systemName: "medal.fill").font(.system(size: 20)).foregroundStyle(Color(white: 0.75)).frame(width: 28)
        case 3: Image(systemName: "medal.fill").font(.system(size: 20)).foregroundStyle(Color(red: 0.8, green: 0.5, blue: 0.2)).frame(width: 28)
        default:
            Text("#\(standing.rank)").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.tertiary)
                .frame(width: 28)
        }
    }
}

// MARK: - Progress — a day-by-day log of the challenge, distinct from Stats

private struct ProgressTab: View {
    let challenge: Challenge

    private var mine: Standing? { challenge.myStanding }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            PactCard(tint: challenge.tint) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack {
                        Text("Your Progress").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        Spacer()
                        Text("\(Int((mine?.progress ?? 0) * 100))%").font(Theme.Font.number(20)).foregroundStyle(challenge.tint)
                    }
                    ProgressPill(progress: mine?.progress ?? 0, tint: challenge.tint, height: 10)
                    Text("\(challenge.durationDays - challenge.daysLeft) of \(challenge.durationDays) days in")
                        .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionHeader(title: "Daily Log")
                let history = mine?.progressHistory ?? []
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(history.enumerated()), id: \.offset) { i, v in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(challenge.tint.opacity(i == history.count - 1 ? 1 : 0.55))
                                .frame(width: max(6, 200 / CGFloat(max(history.count, 1)) - 5), height: max(4, v * 80))
                            Text("\(i + 1)").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                        }
                    }
                }
                .frame(height: 110, alignment: .bottom)
                if history.isEmpty {
                    Text("No days logged yet — tap Log Today from the challenge list to start your streak.")
                        .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                }
            }
        }
        .padding(Theme.Space.lg)
    }
}

// MARK: - Stats

private struct StatsTab: View {
    let challenge: Challenge

    private var mine: Standing? { challenge.myStanding }
    private var hideOthers: Bool { challenge.blindReveal && challenge.status == .active }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack(spacing: Theme.Space.sm) {
                StatChip(label: "My Progress", value: "\(Int((mine?.progress ?? 0) * 100))%", tint: challenge.tint)
                StatChip(label: "Days Left", value: "\(challenge.daysLeft)", tint: Theme.Brand.blue)
                StatChip(label: "Daily Target", value: "\(challenge.dailyTarget) \(challenge.displayUnit)", tint: Theme.Brand.lime)
            }

            PactCard(tint: challenge.tint) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Momentum").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                    Text("Real logged history, day by day — not a simulation.")
                        .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    RivalryChart(lines: challenge.standings.map { s in
                        let hide = hideOthers && s.member.id != challenge.myMemberID
                        return .init(name: s.member.name, color: hide ? Theme.Ink.tertiary : swatchColor(for: s.member.name),
                                     points: s.progressHistory)
                    })
                    .blur(radius: hideOthers ? 4 : 0)
                    HStack(spacing: Theme.Space.sm) {
                        ForEach(challenge.standings) { s in
                            HStack(spacing: 4) {
                                Circle().fill(swatchColor(for: s.member.name)).frame(width: 8, height: 8)
                                Text(s.member.name).font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                            }
                        }
                    }
                }
            }

            if challenge.fairPlay {
                PactCard(tint: Theme.Brand.blue) {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        HStack(spacing: 6) {
                            Image(systemName: "scalemass.fill").foregroundStyle(Theme.Brand.blue)
                            Text("Fair Play Targets").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        }
                        ForEach(challenge.standings) { s in
                            HStack {
                                Text(s.member.name).font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                                Spacer()
                                Text("\(s.member.ageBand.fairPlayStepTarget.formatted())/day")
                                    .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(Theme.Space.lg)
    }
}

// MARK: - Details — rules, venue, and the roster

private struct DetailsTab: View {
    @Environment(AppModel.self) private var app
    let challenge: Challenge

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            AccordionSection(title: "The Deal", icon: challenge.payoff.icon, tint: Theme.Brand.gold, initiallyOpen: true) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.payoff.text).font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                    Text(challenge.status == .complete ? "Settled — someone pays up." : "Settles once the challenge is revealed.")
                        .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                }
            }

            AccordionSection(title: "How it's scored", tint: challenge.tint) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(challenge.rules).font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                    Divider().overlay(Theme.Surface.border)
                    row("Venue", challenge.venue)
                    row("Kind", challenge.kind.rawValue)
                    row("Duration", "\(challenge.durationDays) days")
                }
            }

            AccordionSection(title: "Who's In (\(challenge.standings.count))", tint: Theme.Brand.blue) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    ForEach(challenge.standings) { s in
                        HStack(spacing: Theme.Space.sm) {
                            InitialBadge(name: s.member.name, size: 34)
                            Text(s.member.name).font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                            Spacer()
                            if s.member.id == challenge.myMemberID {
                                TagBadge(text: "You", tint: Theme.Brand.blue)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if challenge.status == .revealReady {
                Button {
                    withAnimation(Theme.Motion.pop) { app.resolveChallenge(challenge.id) }
                } label: {
                    HStack(spacing: 6) { Image(systemName: "sparkles"); Text("Reveal Results") }
                }
                .buttonStyle(PactButtonStyle(kind: .primary))
            }
        }
        .padding(Theme.Space.lg)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
            Spacer()
            Text(value).font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
        }
    }
}

// MARK: - Map — real MapKit tiles, a live route, and every participant pinned

private struct MapTab: View {
    let challenge: Challenge

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            if let coords = challenge.routeCoordinates, !coords.isEmpty {
                ZStack {
                    Map(initialPosition: .region(region(coords))) {
                        MapPolyline(coordinates: coords).stroke(Theme.Brand.cyan, lineWidth: 5)
                        ForEach(Array(challenge.standings.enumerated()), id: \.element.id) { i, s in
                            let point = coords[i % coords.count]
                            Marker(s.member.name, coordinate: point)
                                .tint(swatchColor(for: s.member.name))
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
                    .colorScheme(.dark)
                    .allowsHitTesting(true)
                    LinearGradient(colors: [Theme.Brand.purpleDeep.opacity(0.22), .clear, Color.black.opacity(0.3)],
                                   startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.5), Theme.Brand.cyan.opacity(0.14)],
                                            startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
            } else {
                Text("No route for this challenge yet.").foregroundStyle(Theme.Ink.tertiary)
            }
        }
        .padding(Theme.Space.lg)
    }

    private func region(_ coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                             longitude: (lons.min()! + lons.max()!) / 2)
        return MKCoordinateRegion(center: center,
                                   span: .init(latitudeDelta: max(0.015, (lats.max()! - lats.min()!) * 1.8),
                                               longitudeDelta: max(0.015, (lons.max()! - lons.min()!) * 1.8)))
    }
}

#Preview {
    NavigationStack { ChallengeDetailView(challengeID: Fixtures.laJollaCoastal.id) }
        .environment(AppModel())
}

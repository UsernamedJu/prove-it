import SwiftUI
import MapKit

/// Every challenge on one real map — live ones (solid, glowing pins, real
/// routes where a kind has one) and pending ones (the suggestions you
/// haven't started yet, shown as dashed outline pins). Styled after
/// walk-app's `Route3DMapView` (dark under-stroke + tinted polyline, a white
/// start dot and a glowing tinted end marker) but themed to Pact's palette.
struct MapExploreView: View {
    @Environment(AppModel.self) private var app
    @State private var position: MapCameraPosition = .automatic

    private var liveChallenges: [Challenge] { app.challenges.filter { $0.status != .complete } }
    private var pending: [ChallengeSuggestion] { Fixtures.suggestions }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                ForEach(liveChallenges) { challenge in
                    if let coords = challenge.routeCoordinates, !coords.isEmpty {
                        MapPolyline(coordinates: coords)
                            .stroke(.black.opacity(0.55), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                        MapPolyline(coordinates: coords)
                            .stroke(challenge.tint, style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))
                        if let start = coords.first {
                            Annotation("", coordinate: start) {
                                Circle().fill(.white).frame(width: 9, height: 9)
                                    .overlay(Circle().strokeBorder(.black.opacity(0.5), lineWidth: 1.5))
                            }
                        }
                        Annotation(challenge.title, coordinate: coords.last ?? Fixtures.venueCoordinate(challenge.venue)) {
                            NavigationLink(value: Route.challenge(challenge.id)) {
                                LivePin(challenge: challenge)
                            }
                        }
                    } else {
                        Annotation(challenge.title, coordinate: Fixtures.venueCoordinate(challenge.venue)) {
                            NavigationLink(value: Route.challenge(challenge.id)) {
                                LivePin(challenge: challenge)
                            }
                        }
                    }
                }

                ForEach(pending) { suggestion in
                    Annotation(suggestion.title, coordinate: Fixtures.venueCoordinate(suggestion.venue)) {
                        NavigationLink(value: Route.createChallenge(suggestion)) {
                            PendingPin(suggestion: suggestion)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControlVisibility(.hidden)
            .colorScheme(.dark)
            .ignoresSafeArea(edges: .bottom)
            .onAppear { fitCamera() }

            header
        }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Map").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                Text("Everything happening, everything you could start.")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.secondary)
            }
            HStack(spacing: Theme.Space.md) {
                legendItem(color: Theme.Brand.lime, label: "Live", dashed: false)
                legendItem(color: Theme.Brand.purple, label: "Pending", dashed: true)
            }
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.25))
    }

    private func legendItem(color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 3] : []))
                .background(Circle().fill(dashed ? .clear : color))
                .frame(width: 12, height: 12)
            Text(label).font(Theme.Font.caption()).foregroundStyle(Theme.Ink.secondary)
        }
    }

    private func fitCamera() {
        var coords: [CLLocationCoordinate2D] = []
        for c in liveChallenges {
            if let r = c.routeCoordinates, !r.isEmpty { coords.append(contentsOf: r) }
            else { coords.append(Fixtures.venueCoordinate(c.venue)) }
        }
        for s in pending { coords.append(Fixtures.venueCoordinate(s.venue)) }
        guard !coords.isEmpty else { return }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                             longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.06, (lats.max()! - lats.min()!) * 1.5),
                                     longitudeDelta: max(0.06, (lons.max()! - lons.min()!) * 1.5))
        position = .region(MKCoordinateRegion(center: center, span: span))
    }
}

private struct LivePin: View {
    let challenge: Challenge
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(challenge.tint).frame(width: 34, height: 34)
                    .shadow(color: challenge.tint.opacity(0.7), radius: 8)
                Image(systemName: challenge.icon).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            }
            .overlay(Circle().stroke(.white, lineWidth: 2))
            Text(challenge.title)
                .font(Theme.Font.eyebrow()).foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
        }
    }
}

private struct PendingPin: View {
    let suggestion: ChallengeSuggestion
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().fill(Theme.Surface.glassBright).frame(width: 28, height: 28)
                Image(systemName: "plus").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.Brand.purple)
            }
            .overlay(Circle().strokeBorder(Theme.Brand.purple, style: StrokeStyle(lineWidth: 1.6, dash: [3, 3])))
            Text(suggestion.title)
                .font(Theme.Font.eyebrow()).foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
        }
    }
}

#Preview {
    NavigationStack { MapExploreView() }.environment(AppModel())
}

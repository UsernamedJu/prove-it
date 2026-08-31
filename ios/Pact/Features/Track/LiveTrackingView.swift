import SwiftUI
import MapKit
import CoreLocation

/// Live GPS recording for a single challenge session — draws the real trail
/// as it's walked or run, keeps a running distance/duration, and calls
/// walking vs. running from actual GPS speed (see `LocationTracker`). On
/// finish, the trail and a measured progress log are handed to
/// `AppModel.applyTrackedSession`. Needs a real device in motion to say
/// anything meaningful; the Simulator can drive it with a dragged or
/// scripted location, but won't produce a realistic moving trail on its own.
struct LiveTrackingView: View {
    let challengeID: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var tracker = LocationTracker()
    @State private var showingSummary = false
    @State private var summary: TrackedSession?

    private var challenge: Challenge? { app.challenges.first { $0.id == challengeID } }

    var body: some View {
        ZStack {
            PactBackground()
            VStack(spacing: 0) {
                mapArea
                statsPanel
            }
        }
        .navigationTitle("Track Live")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    if tracker.isTracking { tracker.stop() }
                    dismiss()
                }
                .foregroundStyle(Theme.Ink.secondary)
            }
        }
        .onAppear { tracker.requestPermission() }
        .alert("Location Access Needed", isPresented: .constant(tracker.authorizationStatus == .denied || tracker.authorizationStatus == .restricted)) {
            Button("OK") { dismiss() }
        } message: {
            Text("Turn on location access for Provyr in Settings to track a real walk or run.")
        }
        .sheet(isPresented: $showingSummary) {
            if let summary {
                TrackingSummaryView(session: summary, challenge: challenge) {
                    app.applyTrackedSession(summary, to: challengeID)
                    showingSummary = false
                    dismiss()
                }
            }
        }
    }

    private var mapArea: some View {
        Map(position: .constant(cameraPosition)) {
            if tracker.coordinates.count > 1 {
                MapPolyline(coordinates: tracker.coordinates).stroke(challenge?.tint ?? Theme.Brand.cyan, lineWidth: 5)
            }
            if let last = tracker.coordinates.last {
                Marker("You", coordinate: last).tint(challenge?.tint ?? Theme.Brand.cyan)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .frame(maxWidth: .infinity)
        .frame(height: 420)
    }

    private var cameraPosition: MapCameraPosition {
        guard let last = tracker.coordinates.last else {
            return .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 32.7157, longitude: -117.1611),
                                               span: .init(latitudeDelta: 0.05, longitudeDelta: 0.05)))
        }
        return .region(MKCoordinateRegion(center: last, span: .init(latitudeDelta: 0.006, longitudeDelta: 0.006)))
    }

    private var statsPanel: some View {
        VStack(spacing: Theme.Space.lg) {
            HStack(spacing: Theme.Space.xl) {
                stat("DISTANCE", String(format: "%.2f mi", tracker.distanceMiles))
                stat("TIME", elapsedText)
                VStack(alignment: .leading, spacing: 1) {
                    Text("STATUS").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                    HStack(spacing: 4) {
                        Image(systemName: tracker.classification.icon).font(.system(size: 14, weight: .semibold))
                        Text(tracker.classification.rawValue).font(Theme.Font.number(18))
                    }
                    .foregroundStyle(Theme.Ink.primary)
                }
                Spacer()
            }

            if !tracker.canTrack {
                Text("Waiting on location permission…").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
            }

            Button {
                if tracker.isTracking {
                    let session = tracker.stop()
                    summary = session
                    showingSummary = true
                } else {
                    tracker.start()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: tracker.isTracking ? "stop.fill" : "play.fill")
                    Text(tracker.isTracking ? "Finish" : "Start Tracking")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PactButtonStyle(kind: tracker.isTracking ? .tinted(Theme.Brand.coral) : .primary))
            .disabled(!tracker.canTrack)
        }
        .padding(Theme.Space.lg)
        .background(.ultraThinMaterial)
    }

    private var elapsedText: String {
        guard let start = tracker.startDate else { return "0:00" }
        let seconds = Int(Date().timeIntervalSince(start))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
            Text(value).font(Theme.Font.number(18)).foregroundStyle(Theme.Ink.primary)
        }
    }
}

/// Shown once tracking stops — the actual measured result, before it's
/// applied to the challenge, so a false start (a couple seconds, near-zero
/// distance) can be discarded instead of logged as real progress.
private struct TrackingSummaryView: View {
    let session: TrackedSession
    let challenge: Challenge?
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PactBackground()
                VStack(spacing: Theme.Space.lg) {
                    Image(systemName: session.classification.icon)
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(challenge?.tint ?? Theme.Brand.cyan)
                        .padding(.top, Theme.Space.xl)
                    Text(session.classification.rawValue).font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                    PactCard(tint: challenge?.tint ?? Theme.Brand.cyan) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Distance").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                                Text(String(format: "%.2f mi", session.distanceMiles)).font(Theme.Font.h2()).foregroundStyle(Theme.Ink.primary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("Duration").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                                Text(durationText).font(Theme.Font.h2()).foregroundStyle(Theme.Ink.primary)
                            }
                        }
                    }
                    if let challenge {
                        Text("This will log real progress toward \"\(challenge.title)\" and replace its map with the route you just recorded.")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Space.lg)
                    }
                    Spacer()
                    Button("Save & Log Progress") { onSave() }
                        .buttonStyle(PactButtonStyle(kind: .primary))
                    Button("Discard") { dismiss() }
                        .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                        .padding(.bottom, Theme.Space.lg)
                }
                .padding(Theme.Space.lg)
            }
        }
    }

    private var durationText: String {
        let seconds = Int(session.duration)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

import SwiftUI
import MapKit
import CoreLocation

/// Live recording for a single challenge session — draws the real trail as
/// it's walked or run, keeps a running distance/step count/duration, and
/// calls walking vs. running from actual GPS speed (see `LocationTracker`).
/// Backed by `LocationTracker.shared`, not a screen-owned instance —
/// closing this view (the toolbar "Close") only dismisses the screen; the
/// recording keeps running until "Finish" is tapped, from here or after
/// reopening this same screen later. On finish, the trail and a measured
/// progress log are handed to `AppModel.applyTrackedSession`. Needs a real
/// device in motion to say anything meaningful; the Simulator can drive
/// location with a dragged or scripted point but has no real step data at
/// all.
struct LiveTrackingView: View {
    let challengeID: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    private let tracker = LocationTracker.shared
    @State private var showingSummary = false
    @State private var summary: TrackedSession?

    private var challenge: Challenge? { app.challenges.first { $0.id == challengeID } }
    /// True when some *other* challenge's session is already running —
    /// only one live recording at a time, since it's one phone's GPS/steps.
    private var trackingElsewhere: Bool { tracker.isTracking && tracker.challengeID != challengeID }

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
                Button("Close") { dismiss() }
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
            HStack(spacing: Theme.Space.lg) {
                stat("DISTANCE", String(format: "%.2f mi", tracker.distanceMiles))
                stat("STEPS", tracker.steps.formatted())
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
            } else if trackingElsewhere {
                Text("Already tracking another challenge — finish that one first.")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
            }

            Button {
                if tracker.isTracking {
                    let session = tracker.stop()
                    summary = session
                    showingSummary = true
                } else {
                    tracker.start(for: challengeID)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: tracker.isTracking ? "stop.fill" : "play.fill")
                    Text(tracker.isTracking ? "Finish" : "Start Tracking")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PactButtonStyle(kind: tracker.isTracking ? .tinted(Theme.Brand.coral) : .primary))
            .disabled(!tracker.canTrack || trackingElsewhere)
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
                VStack(spacing: Theme.Space.md) {
                    ZStack {
                        Circle().fill((challenge?.tint ?? Theme.Brand.cyan).opacity(0.15)).frame(width: 76, height: 76)
                        Image(systemName: session.classification.icon)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(challenge?.tint ?? Theme.Brand.cyan)
                    }
                    .padding(.top, Theme.Space.lg)
                    Text(session.classification.rawValue).font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                    PactCard(tint: challenge?.tint ?? Theme.Brand.cyan) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Distance").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                                Text(String(format: "%.2f mi", session.distanceMiles)).font(Theme.Font.h2()).foregroundStyle(Theme.Ink.primary)
                            }
                            Spacer()
                            VStack(alignment: .center, spacing: 1) {
                                Text("Steps").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                                Text(session.steps.formatted()).font(Theme.Font.h2()).foregroundStyle(Theme.Ink.primary)
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
                    Button("Save & Log Progress") { onSave() }
                        .buttonStyle(PactButtonStyle(kind: .primary))
                        .padding(.top, Theme.Space.xs)
                    Button("Discard") { dismiss() }
                        .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                }
                .padding(Theme.Space.lg)
                .padding(.bottom, Theme.Space.lg)
            }
        }
        .presentationDetents([.medium])
    }

    private var durationText: String {
        let seconds = Int(session.duration)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

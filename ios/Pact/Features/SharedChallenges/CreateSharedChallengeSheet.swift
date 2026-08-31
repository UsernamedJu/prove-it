import SwiftUI

/// The creation form for a real, CKShare-backed challenge. Deliberately
/// separate from `CreateChallengeView` (which is built entirely around
/// picking invitees from the demo crew) rather than retrofitted — this one
/// has no invitee picker at all; the "invite" is the link generated after
/// saving, sent to whoever the user shares it with.
struct CreateSharedChallengeSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(SharedChallengeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var venue = ""
    @State private var kind: ChallengeKind = .steps
    @State private var duration = 7
    @State private var payoffIdx = 0
    @State private var isCreating = false
    @State private var errorText: String?
    @State private var shareURL: URL?

    private let durationOptions = [3, 7, 14]

    var body: some View {
        NavigationStack {
            ZStack {
                PactBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        Text("A real, CloudKit-synced challenge for one buddy — not the demo crew.")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)

                        TextField("Challenge title", text: $title)
                            .font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                            .padding(.horizontal, Theme.Space.md).frame(height: 48)
                            .glassSurface(cornerRadius: Theme.Radius.md)

                        TextField("Venue or neighborhood", text: $venue)
                            .font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                            .padding(.horizontal, Theme.Space.md).frame(height: 48)
                            .glassSurface(cornerRadius: Theme.Radius.md)

                        PillRow(options: ChallengeKind.allCases.map { ($0, $0.rawValue) }, selection: $kind)

                        Text("DURATION").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                        PillRow(options: durationOptions.map { ($0, "\($0)d") }, selection: $duration)

                        Text("THE DEAL").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                        VStack(spacing: Theme.Space.xs) {
                            ForEach(Array(Payoff.presets.enumerated()), id: \.offset) { i, p in
                                let on = payoffIdx == i
                                Button {
                                    withAnimation(Theme.Motion.pop) { payoffIdx = i }
                                } label: {
                                    HStack(spacing: Theme.Space.sm) {
                                        Image(systemName: p.icon).font(.system(size: 15)).foregroundStyle(Theme.Brand.purple)
                                        Text(p.text).font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                                        Spacer()
                                        if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Brand.purple) }
                                    }
                                    .padding(Theme.Space.sm)
                                    .glassSurface(cornerRadius: Theme.Radius.sm, tint: on ? Theme.Brand.purple : nil)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let errorText {
                            Text(errorText).font(Theme.Font.caption()).foregroundStyle(Theme.Brand.coral)
                        }

                        Button {
                            create()
                        } label: {
                            if isCreating { ProgressView() } else { Text("Create & Get Invite Link") }
                        }
                        .buttonStyle(PactButtonStyle(kind: .primary))
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || venue.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                    }
                    .padding(Theme.Space.lg)
                }
            }
            .navigationTitle("Group Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(item: Binding(get: { shareURL.map { ShareURLBox(url: $0) } }, set: { newValue in
            shareURL = newValue?.url
            if newValue == nil { dismiss() } // sent (or dismissed) the invite — the form's done its job
        })) { box in
            VStack(spacing: Theme.Space.md) {
                Text("Challenge created!").font(Theme.Font.h2()).foregroundStyle(Theme.Ink.primary)
                Text("Send this link to the person you're challenging.")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                ShareLink(item: box.url) { Label("Send Invite Link", systemImage: "square.and.arrow.up") }
                    .buttonStyle(PactButtonStyle(kind: .primary))
            }
            .padding(Theme.Space.lg)
            .presentationDetents([.height(220)])
        }
    }

    private func create() {
        isCreating = true
        errorText = nil
        Task {
            do {
                let url = try await store.createSharedChallenge(
                    title: title, kind: kind, venue: venue,
                    rules: "First to hit the daily target each day keeps their streak alive.",
                    dailyTarget: kind == .steps ? 8_000 : (kind == .distance ? 2 : 1),
                    durationDays: duration, payoff: Payoff.presets[payoffIdx],
                    myLocalID: app.me.id, myName: app.me.name
                )
                shareURL = url
            } catch let error as SharedChallengeStore.CloudSharingError {
                // Already a complete, actionable sentence — no need for a
                // generic "couldn't create that challenge" prefix on top.
                errorText = error.localizedDescription
            } catch {
                errorText = "Couldn't create that challenge: \(error.localizedDescription)"
            }
            isCreating = false
        }
    }
}

private struct ShareURLBox: Identifiable {
    let url: URL
    var id: URL { url }
}

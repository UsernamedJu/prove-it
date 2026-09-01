import SwiftUI
import UIKit

struct CreateChallengeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// Drives the Send button's own send-off animation — a haptic tap,
    /// the label sliding out and fading as a spinner crosses in, then the
    /// actual creation + dismiss once that's had a moment to read.
    @State private var isSending = false

    @State private var title: String
    @State private var kind: ChallengeKind
    @State private var venue: String
    @State private var duration: Int
    @State private var customMetric = ""
    @State private var payoffIdx: Int
    @State private var useCustomPayoff: Bool
    @State private var customPayoff: String
    @State private var blindReveal = false
    @State private var fairPlay = true
    @State private var selectedInvitees: Set<UUID> = []
    @State private var selectedGroup: ContactGroup?
    /// `nil` until someone actually taps +/- on the goal — at that point
    /// it takes over from `suggestedGoal` as the number that actually
    /// gets sent.
    @State private var customGoal: Double?
    @State private var step = 0
    @State private var navigatingBack = false
    private let photoName: String

    private let totalSteps = 3
    private let durationOptions = [3, 7, 14, 30]
    /// A suggestion's payoff is its whole hook — picking "Coronado Bridge
    /// Walk Series" because the winner's photo becomes the group's profile
    /// pic shouldn't let you then quietly swap that for "bragging rights."
    /// Locked whenever this challenge started from a suggestion; free to
    /// pick or write your own otherwise.
    private let isPayoffLocked: Bool
    private let seedID: UUID?
    private let seedGoal: Double?

    init(seed: ChallengeSuggestion?) {
        seedID = seed?.id
        seedGoal = seed?.goalTarget
        _title = State(initialValue: seed?.title ?? "")
        _kind = State(initialValue: seed?.kind ?? .steps)
        _venue = State(initialValue: seed?.venue ?? "Citywide · San Diego")
        _duration = State(initialValue: seed?.suggestedDuration ?? 14)
        photoName = seed?.photoName ?? "photo-steps"
        isPayoffLocked = seed != nil
        if let seedPayoff = seed?.payoff, let idx = Payoff.presets.firstIndex(of: seedPayoff) {
            _payoffIdx = State(initialValue: idx)
            _useCustomPayoff = State(initialValue: false)
            _customPayoff = State(initialValue: "")
        } else {
            _payoffIdx = State(initialValue: 0)
            _useCustomPayoff = State(initialValue: seed != nil)
            _customPayoff = State(initialValue: seed?.payoff.text ?? "")
        }
    }

    private var locationTracker: LocationTracker { LocationTracker.shared }
    /// A challenge's whole value here is that progress is measured, not
    /// self-reported — that needs both Health (steps/distance/runs) and
    /// location (the GPS trail + step count Track Live records) actually
    /// turned on before a challenge exists to log progress against.
    private var prerequisitesMet: Bool { app.healthKitConnected && locationTracker.canTrack }

    var body: some View {
        ZStack {
            PactBackground()
            if prerequisitesMet {
                VStack(spacing: Theme.Space.lg) {
                    FlowHeader(step: step, total: totalSteps,
                               onBack: { step == 0 ? dismiss() : goTo(step - 1) })
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.top, Theme.Space.md)

                    Group {
                        switch step {
                        case 0: basicsStep
                        case 1: peopleStep
                        default: reviewStep
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: navigatingBack ? .leading : .trailing),
                        removal: .move(edge: navigatingBack ? .trailing : .leading)
                    ))
                }
            } else {
                requirementsGate
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var requirementsGate: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer()
            Image(systemName: "checklist").font(.system(size: 44, weight: .bold)).foregroundStyle(Theme.Brand.cyan)
            Text("A Couple Things First").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
            Text("Challenges here run on real measured progress, not the honor system — connect Health and allow location so a challenge can actually log itself.")
                .font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Space.xl)
            VStack(spacing: Theme.Space.sm) {
                requirementRow(met: app.healthKitConnected, label: "Apple Health") {
                    Task { await app.connectHealthKit() }
                }
                // requestPermission() alone silently does nothing once
                // iOS has already recorded a denial — requestPermissionOr-
                // OpenSettings sends them to Settings instead in that
                // case, since re-prompting isn't possible anymore.
                requirementRow(met: locationTracker.canTrack,
                                label: "Location Access",
                                buttonTitle: locationTracker.authorizationStatus == .notDetermined ? "Allow" : "Open Settings") {
                    locationTracker.requestPermissionOrOpenSettings()
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            Spacer()
            Button("Cancel") { dismiss() }
                .font(Theme.Font.body()).foregroundStyle(Theme.Ink.tertiary)
                .padding(.bottom, Theme.Space.lg)
        }
    }

    private func requirementRow(met: Bool, label: String, buttonTitle: String = "Allow", action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? Theme.Brand.lime : Theme.Ink.tertiary)
            Text(label).font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
            Spacer()
            if !met {
                Button(buttonTitle) { action() }.font(Theme.Font.caption()).foregroundStyle(Theme.Brand.purple)
            }
        }
        .padding(Theme.Space.md)
        .frame(height: 52)
        .glassSurface(cornerRadius: Theme.Radius.md, tint: met ? Theme.Brand.lime : nil)
    }

    /// Direction-aware slide instead of a bouncy fade — matches the Onboarding flow.
    private func goTo(_ target: Int) {
        navigatingBack = target < step
        withAnimation(Theme.Motion.push) { step = target }
    }

    // MARK: Step 0 — basics: name, kind, venue, duration

    private var basicsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                stepHeader("The basics", "Name it and pick what you're tracking.")

                TextField("e.g. La Jolla Coastal 5K", text: $title)
                    .font(Theme.Font.h2())
                    .foregroundStyle(Theme.Ink.primary)
                    .padding(.horizontal, Theme.Space.md)
                    .frame(height: 56)
                    .glassSurface(cornerRadius: Theme.Radius.md)

                TextField("Venue or neighborhood", text: $venue)
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Ink.primary)
                    .padding(.horizontal, Theme.Space.md)
                    .frame(height: 48)
                    .glassSurface(cornerRadius: Theme.Radius.md)

                PillRow(options: ChallengeKind.allCases.map { ($0, $0.rawValue) }, selection: $kind)

                if kind == .custom {
                    TextField("What are you tracking? e.g. push-ups, pages read", text: $customMetric)
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Ink.primary)
                        .padding(.horizontal, Theme.Space.md)
                        .frame(height: 48)
                        .glassSurface(cornerRadius: Theme.Radius.md)
                }

                Text("DURATION").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                PillRow(options: durationOptions.map { ($0, "\($0)d") }, selection: $duration)

                if isPayoffLocked {
                    Text("THE DEAL — locked in with this challenge").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: "lock.fill").font(.system(size: 15)).foregroundStyle(Theme.Brand.gold)
                        Text(customPayoff).font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                        Spacer()
                    }
                    .padding(Theme.Space.sm)
                    .glassSurface(cornerRadius: Theme.Radius.sm, tint: Theme.Brand.gold)
                } else {
                    Text("THE DEAL — winner vs. loser, no cash involved").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                    VStack(spacing: Theme.Space.xs) {
                        ForEach(Array(Payoff.presets.enumerated()), id: \.offset) { i, p in
                            let on = !useCustomPayoff && payoffIdx == i
                            Button {
                                withAnimation(Theme.Motion.pop) { useCustomPayoff = false; payoffIdx = i }
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
                        Button {
                            withAnimation(Theme.Motion.pop) { useCustomPayoff = true }
                        } label: {
                            HStack(spacing: Theme.Space.sm) {
                                Image(systemName: "sparkles").font(.system(size: 15)).foregroundStyle(Theme.Brand.purple)
                                Text("Write your own").font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                                Spacer()
                                if useCustomPayoff { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Brand.purple) }
                            }
                            .padding(Theme.Space.sm)
                            .glassSurface(cornerRadius: Theme.Radius.sm, tint: useCustomPayoff ? Theme.Brand.purple : nil)
                        }
                        .buttonStyle(.plain)
                    }
                    if useCustomPayoff {
                        TextField("e.g. Loser walks the dog for a month", text: $customPayoff)
                            .font(Theme.Font.body())
                            .foregroundStyle(Theme.Ink.primary)
                            .padding(.horizontal, Theme.Space.md)
                            .frame(height: 48)
                            .glassSurface(cornerRadius: Theme.Radius.md)
                    }
                }

                continueButton(disabled: title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.xl)
        }
    }

    // MARK: Step 1 — people + rules

    private var peopleStep: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            stepHeader("Who's in?", "Pick a group or tap people one at a time.")

            if !app.groups.isEmpty {
                Text("GROUPS").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.xs) {
                        ForEach(app.groups) { group in
                            let isOn = selectedGroup?.id == group.id
                            Button {
                                withAnimation(Theme.Motion.pop) {
                                    selectedGroup = isOn ? nil : group
                                    selectedInvitees = isOn ? [] : Set(group.memberIDs)
                                }
                            } label: {
                                let label = HStack(spacing: 6) {
                                    Image(systemName: "person.3.fill")
                                    Text("\(group.name) (\(group.memberIDs.count))")
                                }
                                .font(Theme.Font.h3())
                                .padding(.horizontal, Theme.Space.md).frame(height: 44)

                                if isOn {
                                    label.foregroundStyle(.white)
                                        .background(Theme.Brand.purple)
                                        .clipShape(Capsule())
                                } else {
                                    label.foregroundStyle(Theme.Ink.secondary)
                                        .glassSurface(cornerRadius: 22)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text("PEOPLE").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
            VStack(spacing: Theme.Space.xs) {
                ForEach(app.crew) { member in
                    let on = selectedInvitees.contains(member.id)
                    Button {
                        withAnimation(Theme.Motion.pop) {
                            selectedGroup = nil
                            if on { selectedInvitees.remove(member.id) } else { selectedInvitees.insert(member.id) }
                        }
                    } label: {
                        HStack(spacing: Theme.Space.sm) {
                            InitialBadge(name: member.name, size: 36, photoData: member.photoData)
                            Text(member.name).font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(on ? Theme.Brand.purple : Theme.Ink.tertiary)
                        }
                        .padding(Theme.Space.sm)
                        .glassSurface(cornerRadius: Theme.Radius.sm, tint: on ? Theme.Brand.purple : nil)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: Theme.Space.sm) {
                toggleRow("Blind Reveal", "Hide scores until the final 72 hours.", "eye.slash.fill", $blindReveal)
                toggleRow("Fair Play", "Score by % of each person's own daily target.", "scalemass.fill", $fairPlay)
            }

            continueButton(disabled: false)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.xl)
        }
    }

    private func toggleRow(_ label: String, _ caption: String, _ icon: String, _ isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(Theme.Ink.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                Text(caption).font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.Brand.purple)
        }
        .padding(Theme.Space.sm)
        .glassSurface(cornerRadius: Theme.Radius.sm)
    }

    // MARK: Step 2 — review

    private var selectedPayoff: Payoff {
        useCustomPayoff
            ? Payoff(icon: "sparkles", text: customPayoff.trimmingCharacters(in: .whitespaces).isEmpty ? "Loser's choice — decide later" : customPayoff)
            : Payoff.presets[payoffIdx]
    }

    private var participantMembers: [Member] {
        [app.me] + app.crew.filter { selectedInvitees.contains($0.id) }
    }

    /// The realistic, Health-informed starting point — mirrors the same
    /// formula `AppModel.createChallenge` falls back to (this specific
    /// group's own typical pace via `app.personalizedStepTarget`/
    /// `personalizedDistanceTarget`, both of which blend in a real
    /// trailing-30-day Health average once one exists, not just a generic
    /// age/weight constant) — see `createChallenge` for why it's not
    /// scaled by participant count. `customGoal`, once someone actually
    /// adjusts it below, takes over from here.
    private var suggestedGoal: Double? {
        if let seedGoal { return seedGoal }
        switch kind {
        case .steps: return Double(app.personalizedStepTarget) * Double(duration) * 1.15
        case .distance: return app.personalizedDistanceTarget * Double(duration) * 1.15
        case .custom: return nil
        }
    }
    private var finalGoal: Double? { customGoal ?? suggestedGoal }
    private func goalText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return kind == .distance ? "\(Int(value)) mi" : "\(Int(value).formatted()) \(kind.unit)"
    }
    /// How much a tap on the +/- control moves the goal — coarse enough
    /// that it takes a handful of taps to matter, not one for a single step.
    private var goalStep: Double { kind == .distance ? 1 : 500 }

    private var reviewStep: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            stepHeader("Review & send", "Double-check it, then send the pact.")
            PactCard(tint: Theme.Brand.purple) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack(spacing: Theme.Space.sm) {
                        KindIcon(systemName: kind.icon, size: 28, tint: Theme.Brand.purple)
                        Text(title.isEmpty ? "Untitled Challenge" : title).font(Theme.Font.h2()).foregroundStyle(Theme.Ink.primary)
                    }
                    Text(venue).font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    Divider().overlay(Theme.Surface.border)
                    row("Duration", "\(duration) days")
                    if suggestedGoal != nil { goalRow }
                    if blindReveal { row("Blind Reveal", "On") }
                    if fairPlay { row("Fair Play", "On") }
                }
            }
            PactCard(tint: Theme.Brand.gold) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: selectedPayoff.icon).font(.system(size: 22)).foregroundStyle(Theme.Brand.gold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("THE DEAL").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                            Text(selectedPayoff.text).font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                        }
                        Spacer()
                    }
                    if isPayoffLocked {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill").font(.system(size: 10))
                            Text("Locked in with this challenge").font(Theme.Font.eyebrow())
                        }
                        .foregroundStyle(Theme.Ink.tertiary)
                    }
                    Divider().overlay(Theme.Surface.border)
                    Text("WHO'S IN").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                    HStack(spacing: Theme.Space.sm) {
                        HStack(spacing: -12) {
                            ForEach(participantMembers) { member in
                                InitialBadge(name: member.name, size: 36,
                                             overrideColor: member.id == app.me.id ? app.meColor : nil,
                                             photoData: member.id == app.me.id ? app.myProfilePhotoData : member.photoData)
                                    .overlay(Circle().stroke(Theme.Surface.card, lineWidth: 2))
                            }
                        }
                        Text(participantMembers.map(\.name).joined(separator: ", "))
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.secondary)
                            .lineLimit(2)
                        Spacer()
                    }
                }
            }
            Button {
                guard !isSending else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.easeIn(duration: 0.3)) { isSending = true }
                Task {
                    try? await Task.sleep(for: .seconds(0.35))
                    send()
                }
            } label: {
                ZStack {
                    HStack(spacing: 6) { Image(systemName: "paperplane.fill"); Text("Send Challenge") }
                        .offset(x: isSending ? 40 : 0)
                        .opacity(isSending ? 0 : 1)
                    if isSending {
                        ProgressView().tint(.white).transition(.opacity)
                    }
                }
            }
            .buttonStyle(PactButtonStyle(kind: .primary))
            .disabled(isSending)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.xl)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
            Spacer()
            Text(value).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
        }
    }

    /// Editable, not just a readout — the suggested value is a real,
    /// Health-informed starting point, but "customizable" means someone
    /// can actually push it further or ease off, not just look at a
    /// number `AppModel.createChallenge` was always going to pick anyway.
    private var goalRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Goal to Win").font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                Spacer()
                Button {
                    let base = customGoal ?? suggestedGoal ?? 0
                    customGoal = max(0, base - goalStep)
                } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 20))
                }
                Text(goalText(finalGoal)).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                    .frame(minWidth: 64)
                Button {
                    let base = customGoal ?? suggestedGoal ?? 0
                    customGoal = base + goalStep
                } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 20))
                }
            }
            .foregroundStyle(Theme.Brand.purple)
            if customGoal != nil, let suggestedGoal {
                HStack(spacing: 4) {
                    Text("Suggested: \(goalText(suggestedGoal)) based on your real average.")
                    Button("Reset") { customGoal = nil }
                }
                .font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
            }
        }
    }

    // MARK: Helpers

    private func stepHeader(_ heading: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(heading).font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
            Text(sub).font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
        }
        .padding(.top, Theme.Space.md)
    }

    private func continueButton(disabled: Bool) -> some View {
        Button("Continue →") { goTo(step + 1) }
            .buttonStyle(PactButtonStyle(kind: .primary))
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
    }

    private func send() {
        let invitees = app.crew.filter { selectedInvitees.contains($0.id) }
        let rules = fairPlay
            ? "Ranked by % of each person's personalized daily step target (Fair Play scoring)."
            : "Ranked by cumulative progress toward the challenge target."
        app.createChallenge(title: title, icon: ChallengeKind.suggestedIcon(title: title, venue: venue, kind: kind), kind: kind, venue: venue, rules: rules,
                             photoName: photoName, duration: duration,
                             customMetric: kind == .custom ? customMetric : nil, payoff: selectedPayoff,
                             blindReveal: blindReveal, fairPlay: fairPlay, invitees: invitees, goalTarget: finalGoal)
        if let seedID { app.usedSuggestionIDs.insert(seedID) }
        dismiss()
    }
}

#Preview {
    NavigationStack { CreateChallengeView(seed: nil) }.environment(AppModel())
}

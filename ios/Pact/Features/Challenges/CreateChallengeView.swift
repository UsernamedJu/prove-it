import SwiftUI

struct CreateChallengeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

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
    @State private var step = 0
    @State private var navigatingBack = false
    private let photoName: String

    private let totalSteps = 3
    private let durationOptions = [7, 14, 30]

    init(seed: ChallengeSuggestion?) {
        _title = State(initialValue: seed?.title ?? "")
        _kind = State(initialValue: seed?.kind ?? .steps)
        _venue = State(initialValue: seed?.venue ?? "Citywide · San Diego")
        _duration = State(initialValue: seed?.suggestedDuration ?? 14)
        photoName = seed?.photoName ?? "photo-steps"
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

    var body: some View {
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
        .background(PactBackground())
        .toolbar(.hidden, for: .navigationBar)
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

                continueButton(disabled: title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.xl)
        }
    }

    // MARK: Step 1 — people + rules

    private var peopleStep: some View {
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
                            InitialBadge(name: member.name, size: 36)
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

            Spacer()
            continueButton(disabled: false)
        }
        .padding(.horizontal, Theme.Space.lg)
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

    private var reviewStep: some View {
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
                    row("People", "\(1 + selectedInvitees.count)")
                    if blindReveal { row("Blind Reveal", "On") }
                    if fairPlay { row("Fair Play", "On") }
                }
            }
            PactCard(tint: Theme.Brand.gold) {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: selectedPayoff.icon).font(.system(size: 20)).foregroundStyle(Theme.Brand.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("THE DEAL").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                        Text(selectedPayoff.text).font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                    }
                }
            }
            Spacer()
            Button {
                send()
            } label: {
                HStack(spacing: 6) { Image(systemName: "paperplane.fill"); Text("Send Challenge") }
            }
            .buttonStyle(PactButtonStyle(kind: .primary))
        }
        .padding(.horizontal, Theme.Space.lg)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
            Spacer()
            Text(value).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
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
        app.createChallenge(title: title, icon: kind.icon, kind: kind, venue: venue, rules: rules,
                             photoName: photoName, duration: duration,
                             customMetric: kind == .custom ? customMetric : nil, payoff: selectedPayoff,
                             blindReveal: blindReveal, fairPlay: fairPlay, invitees: invitees)
        dismiss()
    }
}

#Preview {
    NavigationStack { CreateChallengeView(seed: nil) }.environment(AppModel())
}

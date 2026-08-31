import SwiftUI
import PhotosUI
import UIKit

struct OnboardingFlow: View {
    @Environment(AppModel.self) private var app

    @State private var step = 0
    @State private var name = ""
    @State private var colorIndex = 0
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var bodyProfile = BodyProfile()
    @State private var units: UnitSystem = .imperial
    @State private var motivation: Motivation?
    @State private var crewName = ""
    @State private var invitedCrew: [String] = []
    @State private var connectingHealth = false
    @State private var celebrated = false
    /// Drives which edge each step slides in/out from, so Back visibly
    /// reverses Continue instead of every step sliding the same direction.
    @State private var navigatingBack = false

    private let totalSteps = 9
    @State private var locationTracker = LocationTracker.shared

    enum Motivation: String, CaseIterable, Identifiable {
        case family = "Stay accountable with family"
        case friends = "Friendly competition with friends"
        case habit = "Build a daily habit"
        case fun = "Just here to have fun"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .family: return "house.fill"
            case .friends: return "flame.fill"
            case .habit: return "repeat"
            case .fun: return "sparkles"
            }
        }
    }

    var body: some View {
        ZStack {
            PactBackground()
            VStack(spacing: Theme.Space.lg) {
                if step > 0 {
                    FlowHeader(step: step, total: totalSteps, onBack: { goTo(step - 1) })
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.top, Theme.Space.md)
                }

                Group {
                    switch step {
                    case 0: setupStep
                    case 1: aboutYouStep
                    case 2: activityStep
                    case 3: healthSetupStep
                    case 4: locationSetupStep
                    case 5: motivationStep
                    case 6: addCrewStep
                    case 7: reviewStep
                    default: doneStep
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.asymmetric(
                    insertion: .move(edge: navigatingBack ? .leading : .trailing),
                    removal: .move(edge: navigatingBack ? .trailing : .leading)
                ))
                .id(step)
            }
        }
    }

    /// Advances or retreats the flow with a direction-aware slide instead of
    /// a bouncy fade — a plain push/pop feel, closer to `UINavigationController`.
    private func goTo(_ target: Int) {
        navigatingBack = target < step
        withAnimation(Theme.Motion.push) { step = target }
    }

    // MARK: Step 0 — name, photo, color

    private var setupStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                PactMark(size: 30)
                Text("Let's set you up").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                Text("A few quick things, then you're in.").font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
            }
            .padding(.top, Theme.Space.xl)

            HStack(spacing: Theme.Space.md) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        InitialBadge(name: name.isEmpty ? "?" : name, size: 60, overrideColor: Theme.Brand.swatch[colorIndex], photoData: photoData)
                        ZStack {
                            Circle().fill(Theme.Ink.primary)
                            Image(systemName: "camera.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        }
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Theme.Surface.bg, lineWidth: 2))
                    }
                }
                .onChange(of: photoItem) { _, item in
                    Task {
                        if let data = try? await item?.loadTransferable(type: Data.self) { photoData = data }
                    }
                }
                TextField("Your name", text: $name)
                    .font(Theme.Font.h2())
                    .foregroundStyle(Theme.Ink.primary)
                    .padding(.horizontal, Theme.Space.md)
                    .frame(height: 56)
                    .glassSurface(cornerRadius: Theme.Radius.md)
            }

            Text("COLOR").font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
            HStack(spacing: Theme.Space.sm) {
                ForEach(Theme.Brand.swatch.indices, id: \.self) { i in
                    Circle()
                        .fill(Theme.Brand.swatch[i])
                        .frame(width: 36, height: 36)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 13, weight: .black)).foregroundStyle(.white).opacity(colorIndex == i ? 1 : 0))
                        .overlay(Circle().stroke(Theme.Ink.primary, lineWidth: colorIndex == i ? 3 : 0).padding(-4))
                        .onTapGesture { withAnimation(Theme.Motion.pop) { colorIndex = i } }
                }
            }

            Spacer()
            Button("Continue →") { goTo(1) }
                .buttonStyle(PactButtonStyle(kind: .primary))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, Theme.Space.lg)
    }

    // MARK: Step 1 — height, weight, sex, age

    private var aboutYouStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("About you").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                    Text("This is what turns a generic step count into your step count.").font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                }
                .padding(.top, Theme.Space.xl)

                BodyProfileEditor(profile: $bodyProfile, units: $units)

                Spacer(minLength: Theme.Space.xl)
                Button("Continue →") { goTo(2) }
                    .buttonStyle(PactButtonStyle(kind: .primary))
            }
            .padding(.horizontal, Theme.Space.lg)
        }
    }

    // MARK: Step 2 — activity level

    private var activityStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("How active are you day to day?").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                Text("Outside of challenges — your normal week.").font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
            }
            .padding(.top, Theme.Space.xl)

            ActivityLevelPicker(level: $bodyProfile.activityLevel)

            Spacer()
            Button("Continue →") { goTo(3) }
                .buttonStyle(PactButtonStyle(kind: .primary))
        }
        .padding(.horizontal, Theme.Space.lg)
    }

    // MARK: Step 3 — the actual data source challenges verify progress
    // against. Framed as expected setup, not a buried Settings toggle, but
    // still skippable — a hard block here would strand anyone who declines
    // the system permission dialog or is on a device where HealthKit
    // genuinely isn't available.

    /// A full redesign, not a tweak of the previous version — a big
    /// pulsing hero icon instead of a cramped info row, with the three
    /// things actually being read shown as their own glass rows that
    /// visibly check off once connected.
    private var healthSetupStep: some View {
        VStack(spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Connect Apple Health").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                Text("So challenge progress is real, not self-reported.")
                    .font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Space.xl)

            Spacer(minLength: Theme.Space.md)

            ZStack {
                Circle().fill((app.healthKitConnected ? Theme.Brand.lime : Theme.Brand.cyan).opacity(0.12))
                    .frame(width: 176, height: 176)
                Circle().fill((app.healthKitConnected ? Theme.Brand.lime : Theme.Brand.cyan).opacity(0.22))
                    .frame(width: 124, height: 124)
                Image(systemName: app.healthKitConnected ? "checkmark.circle.fill" : "heart.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(app.healthKitConnected ? Theme.Brand.lime : Theme.Brand.cyan)
                    .symbolEffect(.pulse, options: .repeating, isActive: !app.healthKitConnected)
            }

            VStack(spacing: Theme.Space.sm) {
                healthReadRow(icon: "shoeprints.fill", label: "Steps")
                healthReadRow(icon: "location.fill", label: "Distance")
                healthReadRow(icon: "figure.run", label: "Runs")
            }

            Spacer(minLength: Theme.Space.md)

            if app.healthKitConnected {
                Button("Continue →") { goTo(4) }
                    .buttonStyle(PactButtonStyle(kind: .primary))
            } else {
                Button {
                    connectingHealth = true
                    Task {
                        await app.connectHealthKit()
                        connectingHealth = false
                    }
                } label: {
                    if connectingHealth {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 6) { Image(systemName: "heart.fill"); Text("Connect Health") }
                    }
                }
                .buttonStyle(PactButtonStyle(kind: .primary))
                .disabled(connectingHealth)

                Button("Skip for now →") { goTo(4) }
                    .font(Theme.Font.body()).foregroundStyle(Theme.Ink.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
    }

    private func healthReadRow(icon: String, label: String) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: icon).font(.system(size: 16)).frame(width: 22)
                .foregroundStyle(app.healthKitConnected ? Theme.Brand.lime : Theme.Brand.cyan)
            Text(label).font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Brand.lime)
                .opacity(app.healthKitConnected ? 1 : 0)
        }
        .padding(.horizontal, Theme.Space.md)
        .frame(height: 48)
        .glassSurface(cornerRadius: Theme.Radius.sm, tint: app.healthKitConnected ? Theme.Brand.lime : nil)
    }

    // MARK: Step 4 — background location, so Track Live can keep recording a
    // walk or run without the app staying open and on-screen the whole time.

    private var locationSetupStep: some View {
        let granted = locationTracker.authorizationStatus == .authorizedAlways || locationTracker.authorizationStatus == .authorizedWhenInUse
        return VStack(spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Track in the Background").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                Text("So a challenge keeps recording your walk or run even with your phone locked or the app closed — Health connected plus this is what Track Live needs to work.")
                    .font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Theme.Space.xl)

            Spacer(minLength: Theme.Space.md)

            ZStack {
                Circle().fill((granted ? Theme.Brand.lime : Theme.Brand.cyan).opacity(0.12)).frame(width: 176, height: 176)
                Circle().fill((granted ? Theme.Brand.lime : Theme.Brand.cyan).opacity(0.22)).frame(width: 124, height: 124)
                Image(systemName: granted ? "checkmark.circle.fill" : "location.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(granted ? Theme.Brand.lime : Theme.Brand.cyan)
                    .symbolEffect(.pulse, options: .repeating, isActive: !granted)
            }

            Spacer(minLength: Theme.Space.md)

            if granted {
                Button("Continue →") { goTo(5) }
                    .buttonStyle(PactButtonStyle(kind: .primary))
            } else {
                // Once iOS has recorded a denial, calling
                // requestPermission() again does nothing at all — no
                // prompt, no error, this button would just silently stop
                // working. requestPermissionOrOpenSettings sends them to
                // Settings instead in that case, which is the only way
                // back at that point.
                Button {
                    locationTracker.requestPermissionOrOpenSettings()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                        Text(locationTracker.authorizationStatus == .notDetermined ? "Allow Location Access" : "Open Settings to Allow")
                    }
                }
                .buttonStyle(PactButtonStyle(kind: .primary))

                Button("Skip for now →") { goTo(5) }
                    .font(Theme.Font.body()).foregroundStyle(Theme.Ink.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
    }

    // MARK: Step 5 — why they're here, which quietly steers the recommendation later

    private var motivationStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("What brings you to Prove it?").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                Text("Pick what fits best — it shapes what we suggest.").font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
            }
            .padding(.top, Theme.Space.xl)

            VStack(spacing: Theme.Space.sm) {
                ForEach(Motivation.allCases) { m in
                    let on = motivation == m
                    Button {
                        withAnimation(Theme.Motion.pop) { motivation = m }
                    } label: {
                        HStack(spacing: Theme.Space.sm) {
                            Image(systemName: m.icon).font(.system(size: 16)).foregroundStyle(on ? Theme.Brand.purple : Theme.Ink.secondary)
                            Text(m.rawValue).font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                            Spacer()
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Theme.Brand.purple : Theme.Ink.tertiary)
                        }
                        .padding(Theme.Space.md)
                        .glassSurface(cornerRadius: Theme.Radius.md, tint: on ? Theme.Brand.purple : nil)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
            Button("Continue →") { goTo(6) }
                .buttonStyle(PactButtonStyle(kind: .primary))
                .disabled(motivation == nil)
                .opacity(motivation == nil ? 0.5 : 1)
        }
        .padding(.horizontal, Theme.Space.lg)
    }

    // MARK: Step 5 — add your crew for real, not just a note on the last screen

    private var addCrewStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Who's coming with you?").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                Text("Add a few people now, or skip and do it later.").font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
            }
            .padding(.top, Theme.Space.xl)

            HStack(spacing: Theme.Space.sm) {
                TextField("Add a name", text: $crewName)
                    .font(Theme.Font.body())
                    .foregroundStyle(Theme.Ink.primary)
                    .padding(.horizontal, Theme.Space.md)
                    .frame(height: 50)
                    .glassSurface(cornerRadius: Theme.Radius.md)
                    .onSubmit(addCrewName)
                Button {
                    addCrewName()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Theme.Brand.purple)
                        .clipShape(Circle())
                }
            }

            if invitedCrew.isEmpty {
                Text("Nobody added yet — that's fine, the Crew tab is always there.")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
            } else {
                VStack(spacing: Theme.Space.xs) {
                    ForEach(invitedCrew, id: \.self) { crewMemberName in
                        HStack(spacing: Theme.Space.sm) {
                            InitialBadge(name: crewMemberName, size: 36)
                            Text(crewMemberName).font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                            Spacer()
                            Button {
                                withAnimation(Theme.Motion.pop) { invitedCrew.removeAll { $0 == crewMemberName } }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Ink.tertiary)
                            }
                        }
                        .padding(Theme.Space.sm)
                        .glassSurface(cornerRadius: Theme.Radius.sm)
                    }
                }
            }

            Spacer()
            Button(invitedCrew.isEmpty ? "Skip for now →" : "Continue →") { goTo(7) }
                .buttonStyle(PactButtonStyle(kind: invitedCrew.isEmpty ? .outline : .primary))
        }
        .padding(.horizontal, Theme.Space.lg)
    }

    private func addCrewName() {
        let trimmed = crewName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !invitedCrew.contains(trimmed) else { return }
        withAnimation(Theme.Motion.pop) { invitedCrew.append(trimmed) }
        crewName = ""
    }

    // MARK: Step 6 — a computed overview before finishing

    private var ageBand: AgeBand { AgeBand.forAge(bodyProfile.age) }

    private var recommendedKind: (ChallengeKind, String) {
        if motivation == .friends {
            return (.distance, "You're motivated by competition — distance challenges give the clearest head-to-head numbers.")
        }
        switch ageBand {
        case .senior:
            return (.steps, "Low-impact and easy to sustain — perfect for building a daily habit without overdoing it.")
        case .teen:
            return (.distance, "You've got room to push — distance challenges will keep it interesting.")
        default:
            return (.steps, "A steady daily step goal is the easiest place to start a streak.")
        }
    }

    private var reviewStep: some View {
        let (kind, blurb) = recommendedKind
        let stepTarget = bodyProfile.personalizedStepTarget(ageBand: ageBand)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Here's your overview, \(name.isEmpty ? "champ" : name)").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                    Text("Calculated from what you just told us — not a generic number.").font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                }
                .padding(.top, Theme.Space.xl)

                PactCard(tint: Theme.Brand.cyan) {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        HStack(spacing: 6) {
                            Image(systemName: "figure.walk").foregroundStyle(Theme.Brand.cyan)
                            Text("Your daily step target").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        }
                        HoloNumber(text: "\(stepTarget.formatted())", size: 32)
                        Text("From your age band (\(ageBand.rawValue)) and activity level (\(bodyProfile.activityLevel.rawValue)) — this is what challenges race you against, not a raw leaderboard number.")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                }

                PactCard(tint: Theme.Brand.gold) {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill").foregroundStyle(Theme.Brand.gold)
                            Text("Estimated daily burn").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        }
                        HoloNumber(text: "\(bodyProfile.estimatedDailyCalories.formatted()) cal", size: 26)
                        Text("A Mifflin-St Jeor estimate from your height, weight, age, and activity level — a ballpark, not a diagnosis.")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                }

                PactCard(tint: Theme.Brand.purple) {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        HStack(spacing: 6) {
                            Image(systemName: kind.icon).foregroundStyle(Theme.Brand.purple)
                            Text("What to work on first").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        }
                        Text("Start with **\(kind.rawValue)** challenges.").font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                        Text(blurb).font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                }

                Text("All of this updates automatically as you log mood check-ins and challenge progress.")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)

                Spacer(minLength: Theme.Space.xl)
                Button("Continue →") { goTo(8) }
                    .buttonStyle(PactButtonStyle(kind: .primary))
            }
            .padding(.horizontal, Theme.Space.lg)
        }
    }

    // MARK: Step 7 — celebration

    private var doneStep: some View {
        VStack(spacing: Theme.Space.lg) {
            ZStack(alignment: .bottom) {
                Image("photo-onboarding")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                    .frame(height: 200)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(Theme.Surface.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            .padding(.top, Theme.Space.md)

            Image(systemName: "sparkles").font(.system(size: 44)).foregroundStyle(Theme.Brand.gold)
                .symbolEffect(.bounce, value: celebrated)
            HoloNumber(text: "You're in, \(name.isEmpty ? "champ" : name)!", size: 27)
                .multilineTextAlignment(.center)
            Text(invitedCrew.isEmpty
                 ? "Add your crew from the Crew tab whenever you're ready — or invite a real buddy from a challenge's share link."
                 : "\(invitedCrew.count) crew member\(invitedCrew.count == 1 ? "" : "s") added — find them in the Crew tab.")
                .font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: Theme.Space.sm) {
                StatChip(label: "Step Goal", value: "\(bodyProfile.personalizedStepTarget(ageBand: ageBand).formatted())", tint: Theme.Brand.blue)
                StatChip(label: "Crew", value: "\(invitedCrew.count)", tint: Theme.Brand.purple)
                StatChip(label: "Health", value: app.healthKitConnected ? "On" : "Off", tint: app.healthKitConnected ? Theme.Brand.lime : Theme.Ink.tertiary)
            }
            Spacer()
            Button {
                finish()
            } label: {
                HStack(spacing: 6) { Text("Let's Go"); Image(systemName: "arrow.right") }
            }
            .buttonStyle(PactButtonStyle(kind: .primary))
        }
        .padding(.horizontal, Theme.Space.lg)
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            celebrated = true
        }
    }

    // MARK: Helpers

    private func finish() {
        app.me.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? "You" : name
        app.me.ageBand = ageBand
        app.meColorIndex = colorIndex
        app.myProfilePhotoData = photoData
        app.myBodyProfile = bodyProfile
        app.unitSystem = units
        app.profileAnniversary = Date()
        for crewMemberName in invitedCrew { app.addContact(name: crewMemberName) }
        withAnimation(Theme.Motion.fade) { app.hasOnboarded = true }
    }
}

#Preview {
    OnboardingFlow().environment(AppModel())
}

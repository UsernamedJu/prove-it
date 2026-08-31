import SwiftUI
import PhotosUI

/// Personalization + account controls. Reached from the gear icon on Me; a
/// plain sheet, not a Route, since nothing else links here.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var colorIndex: Int
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var bodyProfile: BodyProfile
    @State private var units: UnitSystem
    @State private var showAgeRange: Bool
    @State private var connectingHealth = false

    init(app: AppModel) {
        _name = State(initialValue: app.me.name)
        _colorIndex = State(initialValue: Theme.Brand.swatch.firstIndex(of: app.meColor) ?? 0)
        _photoData = State(initialValue: app.myProfilePhotoData)
        _bodyProfile = State(initialValue: app.myBodyProfile)
        _units = State(initialValue: app.unitSystem)
        _showAgeRange = State(initialValue: app.showAgeRangeOnProfile)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PactBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.xl) {
                        profileSection
                        bodyProfileSection
                        healthSection
                        iCloudSection
                        appearanceSection
                        notificationsSection
                        securitySection
                        demoSection
                        accountSection

                        Spacer(minLength: Theme.Space.md)
                        Button("Save Changes") { save() }
                            .buttonStyle(PactButtonStyle(kind: .primary))
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(Theme.Space.lg)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Ink.secondary)
                }
                ToolbarItem(placement: .principal) {
                    Text("Settings").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                }
            }
        }
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "Profile")
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
            if photoData != nil {
                Button("Remove Photo") { photoData = nil; photoItem = nil }
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Brand.coral)
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

            PactCard(tint: Theme.Ink.tertiary, showsAccent: false) {
                Toggle(isOn: $showAgeRange) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Show age range on profile").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        Text("Displays your age band (e.g. \"\(AgeBand.forAge(bodyProfile.age).rawValue)\") under your name.")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                }
                .tint(Theme.Brand.purple)
            }
        }
    }

    private var bodyProfileSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "Body & Activity")
            BodyProfileEditor(profile: $bodyProfile, units: $units, allowsIdentityEditing: false)
            ActivityLevelPicker(level: $bodyProfile.activityLevel)
            PactCard(tint: Theme.Brand.cyan) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Personalized step goal").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                        Text("\(bodyProfile.personalizedStepTarget(ageBand: AgeBand.forAge(bodyProfile.age)).formatted())/day").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Est. daily burn").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                        Text("\(bodyProfile.estimatedDailyCalories.formatted()) cal").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                    }
                }
            }
        }
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "Apple Health")
            PactCard(tint: app.healthKitConnected ? Theme.Brand.lime : Theme.Brand.cyan) {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "heart.fill").foregroundStyle(app.healthKitConnected ? Theme.Brand.lime : Theme.Brand.cyan)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.healthKitConnected ? "Connected" : "Not connected").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        Text("Reads your steps, distance, and runs — including everything your Apple Watch logs — and updates challenge progress on its own the moment Health has something new.")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                    Spacer()
                    Toggle(isOn: Binding(
                        get: { app.healthKitConnected },
                        set: { newValue in
                            if newValue {
                                connectingHealth = true
                                Task { await app.connectHealthKit(); connectingHealth = false }
                            } else {
                                app.healthKitConnected = false
                            }
                        }
                    )) { EmptyView() }
                    .labelsHidden()
                    .tint(Theme.Brand.lime)
                    .scaleEffect(0.8)
                    .disabled(connectingHealth)
                }
            }
        }
    }

    /// No toggle here — unlike HealthKit this isn't something the user
    /// opts into, it's just a status readout of whether this iCloud
    /// account's own data (name, body profile, mood history) is following
    /// them across devices. See CloudSyncManager for what this does and
    /// doesn't cover — crew/challenges still aren't shared this way.
    private var iCloudSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "iCloud Sync")
            PactCard(tint: cloudStatusTint) {
                HStack(spacing: Theme.Space.sm) {
                    Image(systemName: "icloud.fill").foregroundStyle(cloudStatusTint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cloudStatusTitle).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        Text("Your profile and mood history follow you to your other devices and survive a reinstall. Crew, groups, and challenges aren't synced this way yet.")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                    Spacer()
                }
            }
        }
    }

    private var cloudStatusTint: Color {
        switch app.cloudSyncStatus {
        case .synced: Theme.Brand.lime
        case .syncing: Theme.Brand.cyan
        case .unavailable, .unknown: Theme.Ink.tertiary
        case .failed: Theme.Brand.coral
        }
    }

    private var cloudStatusTitle: String {
        switch app.cloudSyncStatus {
        case .unknown: "Checking…"
        case .unavailable: "Not signed into iCloud"
        case .syncing: "Syncing…"
        case .synced(let date): "Synced \(date.formatted(date: .omitted, time: .shortened))"
        case .failed: "Sync failed — will retry"
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "Appearance")
            PactCard(tint: Theme.Brand.purple, showsAccent: false) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("Theme").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                    Picker("Theme", selection: Binding(get: { app.appearance }, set: { app.appearance = $0 })) {
                        ForEach(AppearancePreference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "Notifications")
            PactCard(tint: Theme.Brand.pink, showsAccent: false) {
                Toggle(isOn: Binding(get: { app.pushNotificationsEnabled }, set: { app.pushNotificationsEnabled = $0 })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Challenge Notifications").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        Text("Rank changes, close calls, and last place — on-device alerts, sent with a bit of attitude. Blind-reveal challenges only ever hint that you might be behind, never that you're ahead.")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                }
                .tint(Theme.Brand.pink)
            }
        }
    }

    /// Lets someone see what a fully-engaged account looks like — an
    /// active crew, challenges mid-race, real mood history — without that
    /// ever being the default a new sign-up sees. Reversible: exiting
    /// restores whatever was actually here before, exactly.
    private var demoSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "Demo Account")
            PactCard(tint: Theme.Brand.gold, showsAccent: false) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.isDemoMode ? "Viewing Demo Data" : "Preview Full Engagement").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        Text(app.isDemoMode
                             ? "Showing a sample crew, active challenges, and history. Your own data is safe and comes right back."
                             : "Temporarily loads a sample crew, active challenges, and mood history so you can see how the app looks once someone's actually using it.")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                    Spacer()
                }
                Button(app.isDemoMode ? "Exit Demo" : "Load Demo Data") {
                    if app.isDemoMode { app.exitDemoMode() } else { app.enterDemoMode() }
                    dismiss()
                }
                .buttonStyle(PactButtonStyle(kind: app.isDemoMode ? .tinted(Theme.Brand.coral) : .outline))
            }
        }
    }

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "Security")
            PactCard(tint: Theme.Brand.purple) {
                Toggle(isOn: Binding(
                    get: { app.appLockEnabled },
                    set: { app.appLockEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Require Face ID / Touch ID").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        Text("Locks Prove it whenever it's reopened.").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                }
                .tint(Theme.Brand.purple)
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "Account")
            PactCard(tint: Theme.Ink.tertiary, showsAccent: false) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.signedInName ?? app.me.name).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        Text(app.signInMethod.map { "Signed in with \($0)" } ?? "Not signed in").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                    Spacer()
                    Button("Sign Out") {
                        // Deliberately does NOT touch hasOnboarded — signing
                        // out ends the session, not the account. A returning
                        // user who signs back in (or continues as a guest)
                        // should land straight back in their existing
                        // profile, not redo the entire setup flow.
                        // explicitlySignedOut is what actually makes Sign
                        // Out show the sign-in screen at all — see its
                        // declaration in AppModel for why that's needed.
                        app.isSignedIn = false
                        app.isGuestSession = false
                        app.signInMethod = nil
                        app.explicitlySignedOut = true
                        dismiss()
                    }
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Brand.coral)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { app.me.name = trimmed }
        app.meColorIndex = colorIndex
        app.myProfilePhotoData = photoData
        app.myBodyProfile = bodyProfile
        app.unitSystem = units
        app.me.ageBand = AgeBand.forAge(bodyProfile.age)
        app.showAgeRangeOnProfile = showAgeRange
        dismiss()
    }
}

#Preview {
    SettingsView(app: AppModel()).environment(AppModel())
}

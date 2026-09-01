import SwiftUI
import Foundation
import CoreLocation

enum AppearancePreference: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    /// `nil` for `.system` — that's what tells `.preferredColorScheme(_:)`
    /// to stop overriding and defer back to the OS setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Tab: String, CaseIterable, Identifiable {
    case home = "Home"
    case challenges = "Challenges"
    case map = "Map"
    case contacts = "Crew"
    case me = "Me"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .challenges: return "flag.fill"
        case .map: return "map.fill"
        case .contacts: return "person.2.fill"
        case .me: return "person.crop.circle.fill"
        }
    }
}

/// The single source of truth for the running app — onboarding state, the
/// crew, groups, and challenges. Fixtures seed the social graph (crew,
/// challenges, chat) fresh every launch — there's still no backend for that.
/// The session itself (signed in / onboarded / who "me" is) now survives a
/// relaunch via `PersistedSession`, below, so reopening the app doesn't
/// dump a returning user back on the sign-in screen.
///
/// There is no point balance, wallet, or stake/pot. Winning a challenge is
/// just a recorded result — nothing is spent or credited anywhere. The only
/// score anyone has is `fitnessScore`, which exists purely to recommend
/// workout types and gauge whether a challenge is a good fit, never to gate
/// or pay anyone.
@MainActor
@Observable
final class AppModel {
    var hasOnboarded = false { didSet { persistSession() } }
    var tab: Tab = .home
    var meColorIndex = 0 { didSet { persistSession() } }
    var meColor: Color { Theme.Brand.swatch[meColorIndex % Theme.Brand.swatch.count] }
    /// Off by default — the age band drives personalization (step target,
    /// Fair Play scoring) whether or not it's ever shown; this only governs
    /// whether it's printed under the name on Profile.
    var showAgeRangeOnProfile = false { didSet { persistSession() } }

    var me = Fixtures.me {
        didSet {
            if me.name != oldValue.name {
                for i in challenges.indices {
                    if let j = challenges[i].standings.firstIndex(where: { $0.member.id == me.id }) {
                        challenges[i].standings[j].member.name = me.name
                    }
                }
            }
            persistSession()
        }
    }
    // A real clean slate, not the demo cast — a brand-new account starts
    // with none of Sam/Mom/Dad/Grandma Rose's fixture challenges or crew.
    // Those were never actually a "preview" a new user could tell was fake;
    // they showed up looking exactly like the new user's own data, which
    // is exactly the confusion "why do I already have 5 crew members and
    // 5 active challenges I never created" comes from.
    var crew: [Member] = []
    var groups: [ContactGroup] = []
    var challenges: [Challenge] = []
    /// Which suggestion carousel cards have already spawned a real
    /// challenge — swaps that card's CTA so re-swiping back to it doesn't
    /// read as a fresh, never-used suggestion. Session-only on purpose:
    /// the pool itself rotates weekly, so there's nothing worth persisting.
    var usedSuggestionIDs: Set<UUID> = []
    var moodHistory: [MoodCheckIn] = [] { didSet { persistSession() } }
    var moodStreak = 0
    var moodLoggedToday = false

    // MARK: Demo mode — lets someone see what a fully-engaged account looks
    // like (an active crew, challenges mid-race, mood history) without
    // that ever being what a real new sign-up sees by default. In-memory
    // only: never written through `persistSession()`, so it can't leak
    // into CloudKit or survive a relaunch by accident. Snapshots the real
    // state once on entry and restores it exactly on exit, rather than
    // resetting to another clean slate — someone's actual in-progress data
    // shouldn't be at risk just from peeking at the demo.
    var isDemoMode = false

    private struct DemoSnapshot {
        var crew: [Member]
        var groups: [ContactGroup]
        var challenges: [Challenge]
        var moodHistory: [MoodCheckIn]
        var moodStreak: Int
        var directMessages: [UUID: [ChatMessage]]
        var groupMessages: [UUID: [ChatMessage]]
        var unreadDirectIDs: Set<UUID>
        var unreadGroupIDs: Set<UUID>
    }
    private var preDemoSnapshot: DemoSnapshot?

    func enterDemoMode() {
        guard !isDemoMode else { return }
        preDemoSnapshot = DemoSnapshot(crew: crew, groups: groups, challenges: challenges, moodHistory: moodHistory,
                                        moodStreak: moodStreak, directMessages: directMessages, groupMessages: groupMessages,
                                        unreadDirectIDs: unreadDirectIDs, unreadGroupIDs: unreadGroupIDs)
        isDemoMode = true
        // moodHistory is the one field here CloudKit-syncs on write (see
        // persistSession) — suppressed the same way restoring a saved
        // session is, so a crash mid-demo can't leave demo data persisted
        // as if it were real.
        isApplyingRestoredSession = true
        crew = Fixtures.crew
        groups = Fixtures.groups
        challenges = Fixtures.challenges
        moodHistory = Fixtures.moodHistory
        moodStreak = 6
        directMessages = Fixtures.directMessages
        groupMessages = Fixtures.groupMessages
        unreadDirectIDs = Fixtures.unreadDirectIDs
        unreadGroupIDs = Fixtures.unreadGroupIDs
        isApplyingRestoredSession = false
    }

    func exitDemoMode() {
        guard isDemoMode, let snapshot = preDemoSnapshot else { return }
        isDemoMode = false
        isApplyingRestoredSession = true
        crew = snapshot.crew
        groups = snapshot.groups
        challenges = snapshot.challenges
        moodHistory = snapshot.moodHistory
        moodStreak = snapshot.moodStreak
        directMessages = snapshot.directMessages
        groupMessages = snapshot.groupMessages
        unreadDirectIDs = snapshot.unreadDirectIDs
        unreadGroupIDs = snapshot.unreadGroupIDs
        isApplyingRestoredSession = false
        preDemoSnapshot = nil
    }

    // MARK: Personalization — height/weight/sex/age/activity, feeding the
    // step-target and calorie-burn calculations. "Me" only; crew don't need it.
    var myBodyProfile = BodyProfile() { didSet { persistSession() } }
    var myProfilePhotoData: Data? { didSet { persistSession() } }
    var unitSystem: UnitSystem = .imperial { didSet { persistSession() } }
    /// Set once, the moment onboarding captures an age — there's no real
    /// birthdate on file, so this stands in as the yearly clock age
    /// advances on. See `advanceAgeIfAnniversaryPassed()`.
    var profileAnniversary: Date? { didSet { persistSession() } }

    // MARK: Apple Health / Watch — see HealthKitManager for why this stays
    // fully functional to toggle even before the capability is provisioned.
    // Persisted locally, deliberately outside persistSession's synced blob —
    // HealthKit authorization is inherently per-device, so syncing "true"
    // to a second device that was never actually authorized there would
    // just show "Connected" with no real access behind it. Local storage
    // still matters: re-calling requestAuthorization() to actually restore
    // the connection (and re-arm the change observer below) has to happen
    // once per fresh launch either way, since HKObserverQuery registrations
    // don't survive a relaunch on their own — this is just what tells
    // init() that it should bother trying.
    /// Local-only, same reasoning as `healthKitConnected` below — a display
    /// preference is inherently per-screen/per-device, not something
    /// worth round-tripping through CloudKit. Defaults to dark rather than
    /// following the system — a deliberate app-identity choice, not just
    /// "whatever the phone happens to be set to." Still fully overridable
    /// in Settings.
    var appearance: AppearancePreference = .dark {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceDefaultsKey) }
    }
    private static let appearanceDefaultsKey = "com.jean.pact.appearance"

    /// Local-only opt-in for the rank-change/behind/about-to-win local
    /// notifications (see `NotificationCopy` + `checkChallengeCompletion`'s
    /// callers) — off leaves challenge state exactly as informative, just
    /// silent.
    var pushNotificationsEnabled = false {
        didSet { UserDefaults.standard.set(pushNotificationsEnabled, forKey: ChallengeNotifier.notificationsEnabledDefaultsKey) }
    }

    /// Off stops both directions — no upload from `persistSession`, no
    /// download in `reconcileWithCloud` — rather than just hiding the
    /// status readout while still syncing underneath it. Local-only, same
    /// reasoning as the other device-level toggles here: whether *this*
    /// device should sync isn't itself something worth syncing.
    var iCloudSyncEnabled = true {
        didSet { UserDefaults.standard.set(iCloudSyncEnabled, forKey: Self.iCloudSyncEnabledDefaultsKey) }
    }
    private static let iCloudSyncEnabledDefaultsKey = "com.jean.pact.iCloudSyncEnabled"

    var healthKitConnected = false {
        didSet { UserDefaults.standard.set(healthKitConnected, forKey: Self.healthKitConnectedDefaultsKey) }
    }
    private static let healthKitConnectedDefaultsKey = "com.jean.pact.healthKitConnected"

    // MARK: iCloud sync — see CloudSyncManager. Transient, never persisted
    // itself (it describes the *state* of persistence, not data to restore).
    enum CloudSyncStatus: Equatable {
        case unknown, unavailable, syncing, synced(Date), failed
    }
    var cloudSyncStatus: CloudSyncStatus = .unknown

    // MARK: Sign in with Apple + Face ID / Touch ID app lock. Both are real,
    // working security — Sign in with Apple just needs the paid Developer
    // Program membership to actually authenticate (same restriction as
    // HealthKit); the biometric lock works today on any account.
    var isSignedIn = false { didSet { persistSession() } }
    /// Set by "Continue without signing in" — deliberately **not**
    /// persisted. There's no real identity behind it, so unlike a genuine
    /// sign-in it shouldn't be remembered across a relaunch: it exists only
    /// to get through the current session without repeating the prompt on
    /// every screen, not to skip the sign-in screen forever.
    var isGuestSession = false
    /// Set only by an explicit "Sign Out" tap, never persisted, and reset
    /// back to false the instant a sign-in (real or guest) succeeds again.
    /// Exists purely so RootView can tell "user chose to sign out, actually
    /// show them Sign In" apart from "cold launch, isGuestSession simply
    /// didn't persist, but they're still the same onboarded user" — without
    /// it, hasOnboarded's normal priority (see RootView) would make Sign
    /// Out a no-op, since it stays true across sign-out.
    var explicitlySignedOut = false
    var signedInName: String? { didSet { persistSession() } }
    /// How they got signed in — shown in Settings. Email/phone sign-in has
    /// no backend to verify against, so it's an identity label, not a
    /// verified credential; framed that way rather than faking security.
    var signInMethod: String? { didSet { persistSession() } }
    /// The actual identity behind a sign-in: Apple's stable per-app `user`
    /// string for Sign in with Apple, or the typed email/phone itself for
    /// that path — unlike `signedInName` (just a display label, and the
    /// same "Jean" could belong to two different Apple IDs), this is what
    /// `bindSignedInIdentity` compares against to tell "the same person
    /// signing back in" apart from "someone else signing in on this
    /// device, who should never silently inherit whatever profile happens
    /// to already be in memory."
    var signedInIdentifier: String? { didSet { persistSession() } }
    var appLockEnabled = false { didSet { persistSession() } }
    var isUnlocked = true

    /// Runs on every successful sign-in with the identifier that just
    /// authenticated. If it's different from whoever last signed in on
    /// this device, this is a different person — resets to a real clean
    /// slate instead of handing them the previous person's crew,
    /// challenges, and history just because it was sitting in memory.
    func bindSignedInIdentity(_ identifier: String, name: String?, method: String) {
        if let existing = signedInIdentifier, existing != identifier {
            resetToCleanSlate()
        }
        signedInIdentifier = identifier
        signInMethod = method
        if let name, !name.isEmpty {
            signedInName = name
            me.name = name
        }
        isSignedIn = true
        explicitlySignedOut = false
    }

    /// Wipes everything a *different* identity shouldn't inherit — crew,
    /// groups, challenges, mood history, chat, and reverts "me" to a fresh
    /// profile — while leaving device-local settings (appearance,
    /// notifications, HealthKit connection) alone, since those describe
    /// this phone, not this account.
    private func resetToCleanSlate() {
        isApplyingRestoredSession = true
        me = Member(name: "You", ageBand: .adult)
        meColorIndex = 0
        myProfilePhotoData = nil
        myBodyProfile = BodyProfile()
        showAgeRangeOnProfile = false
        profileAnniversary = nil
        crew = []
        groups = []
        challenges = []
        moodHistory = []
        moodStreak = 0
        moodLoggedToday = false
        directMessages = [:]
        groupMessages = [:]
        unreadDirectIDs = []
        unreadGroupIDs = []
        hasOnboarded = false
        isApplyingRestoredSession = false
    }

    // MARK: Chat — keyed by Member.id / ContactGroup.id. No real backend:
    // sending appends immediately, then a canned reply lands a beat later.
    // Empty by default, same clean-slate reasoning as crew/groups/challenges
    // above — these used to default straight to Fixtures' demo threads,
    // which meant a brand-new user's nav bar could show an unread dot for a
    // conversation with "Sam" they never had, from a crew member they never
    // added.
    var directMessages: [UUID: [ChatMessage]] = [:]
    var groupMessages: [UUID: [ChatMessage]] = [:]
    var unreadDirectIDs: Set<UUID> = []
    var unreadGroupIDs: Set<UUID> = []
    /// The thread currently on screen, if any — suppresses the unread
    /// badge for a reply that lands while you're already looking at it.
    var openDirectChatID: UUID?
    var openGroupChatID: UUID?

    var totalUnreadChats: Int { unreadDirectIDs.count + unreadGroupIDs.count }

    /// Drives the brief celebration overlays — set on creation/reveal, then
    /// cleared by the view after its animation plays.
    var justCreated = false
    var justRevealedID: UUID?
    /// Set right after a *blind-reveal* challenge resolves, only when "me"
    /// is the one who lost it — the trigger for offering to send the
    /// winner a proof photo. Never set for a challenge I won, or for a
    /// non-blind-reveal one (there's no "proof" ritual for those).
    var pendingProofChallengeID: UUID?

    /// Not private — Home binds a paging `TabView` directly to this so
    /// suggestions are swiped through like a real horizontal track instead
    /// of stepped one at a time with a refresh button.
    var suggestionIndex = 0
    var currentSuggestion: ChallengeSuggestion {
        Fixtures.suggestions[suggestionIndex % Fixtures.suggestions.count]
    }

    var activeChallenges: [Challenge] { challenges.filter { $0.status != .complete } }

    var rudyGreeting: String { Rudy.greeting(app: self) }

    // MARK: Fitness score — drives challenge/workout-type fit, never a wallet

    var fitnessScore: Int {
        let recentMood = moodHistory.suffix(5)
        let moodAvg = recentMood.isEmpty ? 6.0
            : recentMood.reduce(0.0) { $0 + ($1.energy + $1.motivation) / 2 } / Double(recentMood.count)
        let active = activeChallenges
        let freqAvg = active.isEmpty ? 0.5
            : active.compactMap { $0.myStanding?.progress }.reduce(0, +) / Double(max(1, active.count))
        let score = (moodAvg / 10 * 0.5 + freqAvg * 0.5) * 100
        return max(0, min(100, Int(score.rounded())))
    }

    /// A short, specific coaching note — not a generic "great job"/"needs
    /// work" tier, but which of the two things the score is actually built
    /// from (recent mood, or how often progress is actually getting
    /// logged) is driving it right now, so it reads as feedback on real
    /// behavior rather than a comment on a number.
    var fitnessCoachNote: String {
        let recentMood = moodHistory.suffix(5)
        let moodAvg = recentMood.isEmpty ? 6.0
            : recentMood.reduce(0.0) { $0 + ($1.energy + $1.motivation) / 2 } / Double(recentMood.count)
        let active = activeChallenges
        let freqAvg = active.isEmpty ? 0.5
            : active.compactMap { $0.myStanding?.progress }.reduce(0, +) / Double(max(1, active.count))
        let moodLow = moodAvg < 5
        let freqLow = freqAvg < 0.4

        switch (moodLow, freqLow) {
        case (true, true):
            return "Energy's been low and progress has stalled — a short walk today usually moves both."
        case (true, false):
            return "You're showing up for challenges even on low-energy days. That consistency matters more than how you feel right now."
        case (false, true):
            return "Mood's solid, but you're not logging much yet — the momentum's there, it just needs a nudge to actually start."
        case (false, false):
            return fitnessScore >= 80
                ? "Strong across the board — good mood, real progress. Keep the streak going."
                : "Steady on both fronts. A bit more consistency and this climbs fast."
        }
    }

    /// The profile-based formula (age/weight/activity level) is a
    /// reasonable starting point for someone with no history yet, but it's
    /// still a guess — once there's a real trailing-30-day Health average,
    /// that's better evidence of what this specific person's daily pace
    /// actually is. Only ever adjusts the target *up* to a bit past that
    /// real average, never down to it: someone who's been inactive doesn't
    /// get an easier goal just because of that, but someone who's already
    /// beating the generic formula gets a target that keeps up with them.
    var personalizedStepTarget: Int {
        let formulaTarget = myBodyProfile.personalizedStepTarget(ageBand: me.ageBand)
        guard healthKitConnected, let monthlySteps else { return formulaTarget }
        let realAverage = Double(monthlySteps) / 30.0
        guard realAverage > 0 else { return formulaTarget }
        let stretched = Int((realAverage * 1.05 / 250).rounded()) * 250
        return max(formulaTarget, stretched)
    }

    /// The distance equivalent of `personalizedStepTarget` — a flat 3
    /// mi/day baseline for someone with no history yet, nudged up past a
    /// real trailing-30-day Health average once there is one (that total
    /// already covers both walking and running distance, so it reflects
    /// actual runs as much as steps, not a separate blend of the two).
    var personalizedDistanceTarget: Double {
        let baseline = 3.0
        guard healthKitConnected, let monthlyDistanceMiles else { return baseline }
        let realAverage = monthlyDistanceMiles / 30.0
        guard realAverage > 0 else { return baseline }
        return max(baseline, (realAverage * 1.05 * 10).rounded() / 10)
    }

    /// A short, deterministic "this suits you" tag for a crew member — the
    /// only remaining role of a numeric score: matching people to the kind
    /// of challenge they'd likely do well in, not a currency.
    func fitTag(for member: Member) -> (kind: ChallengeKind, label: String) {
        let score = stableHash(member.name) % 100
        switch score {
        case 0..<34: return (.steps, "Best fit: Steps challenges")
        case 34..<67: return (.distance, "Best fit: Distance challenges")
        default: return (.custom, "Best fit: Custom challenges")
        }
    }

    // MARK: Mood — a personal log, not a point source

    func logMoodCheckIn(energy: Double, mood: Double, motivation: Double, sleep: Double) {
        moodHistory.append(MoodCheckIn(date: Date(), energy: energy, mood: mood,
                                        motivation: motivation, sleep: sleep))
        moodStreak += 1
        moodLoggedToday = true
    }

    // MARK: Apple Health

    /// Today's step count and distance, and recent real runs — a general
    /// activity picture independent of any specific challenge. `nil`/empty
    /// until `refreshHealthActivity()` runs; never a placeholder value.
    var todaySteps: Int?
    var todayDistanceMiles: Double?
    var recentRuns: [RunSummary] = []
    var monthlySteps: Int?
    var monthlyDistanceMiles: Double?

    func connectHealthKit() async {
        healthKitConnected = await HealthKitManager.shared.requestAuthorization()
        guard healthKitConnected else { return }
        await refreshHealthActivity()
        // From here on, "Log Today" stops being something anyone has to
        // remember to tap for a steps/distance challenge — Health calling
        // back the moment it has something new *is* the log.
        HealthKitManager.shared.startObservingChanges { [weak self] in
            Task { @MainActor in await self?.autoSyncFromHealth() }
        }
    }

    /// Runs automatically whenever HealthKit reports new steps, distance,
    /// or a finished workout (see HealthKitManager.startObservingChanges) —
    /// updates the general activity picture and logs real progress against
    /// every challenge Health can actually verify, both the local fixture
    /// ones and any real CKShare-backed ones from SharedChallengeStore.
    /// Custom-metric challenges are untouched; Health has nothing to verify
    /// them against.
    func autoSyncFromHealth() async {
        await refreshHealthActivity()
        for challenge in activeChallenges where challenge.kind != .custom {
            await syncTodayFromHealth(for: challenge.id)
        }
        for shared in SharedChallengeStore.shared.challenges where shared.kind != .custom {
            await SharedChallengeStore.shared.syncTodayFromHealth(challengeLocalID: shared.localID, myLocalID: me.id)
        }
        checkExpiredChallenges()
    }

    /// Pulls today's totals and recent runs — called whenever a screen
    /// showing them appears, not on a timer, since there's no push
    /// mechanism for HealthKit data the way CloudKit has subscriptions.
    func refreshHealthActivity() async {
        guard healthKitConnected else {
            todaySteps = nil
            todayDistanceMiles = nil
            recentRuns = []
            monthlySteps = nil
            monthlyDistanceMiles = nil
            return
        }
        async let steps = HealthKitManager.shared.fetchTodaySteps()
        async let distance = HealthKitManager.shared.fetchTodayDistanceMiles()
        async let runs = HealthKitManager.shared.fetchRecentRuns()
        async let monthSteps = HealthKitManager.shared.fetchTotalSteps(days: 30)
        async let monthDistance = HealthKitManager.shared.fetchTotalDistanceMiles(days: 30)
        todaySteps = await steps
        todayDistanceMiles = await distance
        recentRuns = await runs
        monthlySteps = await monthSteps
        monthlyDistanceMiles = await monthDistance
    }

    // MARK: Milestones

    /// Lifetime achievements built entirely from data already on the
    /// device — challenge outcomes, the running mood streak, and (where
    /// connected) real Health totals. Nothing here is a synthetic counter;
    /// an unlocked milestone always traces back to something that actually
    /// happened.
    var milestones: [Milestone] {
        let completed = challenges.filter { $0.status == .complete }
        let wins = completed.filter { $0.winnerName == me.name }.count
        let bestRunMiles = recentRuns.map(\.distanceMiles).max() ?? 0
        let todayStepCount = todaySteps ?? 0
        let monthMiles = monthlyDistanceMiles ?? 0

        func milestone(_ id: String, _ title: String, _ detail: String, _ icon: String, count: Double, goal: Double) -> Milestone {
            Milestone(id: id, title: title, detail: detail, icon: icon, isUnlocked: count >= goal, progress: min(1, count / goal))
        }

        return [
            milestone("first-win", "First Win", "Win your first challenge", "trophy.fill", count: Double(wins), goal: 1),
            milestone("hat-trick", "Hat Trick", "Win 3 challenges", "trophy.fill", count: Double(wins), goal: 3),
            milestone("five-completed", "Five Down", "Complete 5 challenges", "checkmark.seal.fill", count: Double(completed.count), goal: 5),
            milestone("week-streak", "Week One", "Log your mood 7 days running", "flame.fill", count: Double(moodStreak), goal: 7),
            milestone("month-streak", "Consistency Is Key", "Log your mood 30 days running", "flame.fill", count: Double(moodStreak), goal: 30),
            milestone("5k", "5K Finisher", "Log a real 5K (3.1 mi) run", "figure.run", count: bestRunMiles, goal: 3.1),
            milestone("10k-steps", "10K Day", "Hit 10,000 real steps in a day", "shoeprints.fill", count: Double(todayStepCount), goal: 10_000),
            milestone("marathon-month", "Marathon Month", "26.2 real miles in 30 days", "map.fill", count: monthMiles, goal: 26.2),
        ]
    }

    /// Pulls the *real cumulative total* since this challenge started —
    /// not "today's" total — so progress only ever reflects steps/miles
    /// that happened after joining. Sets `healthTotal` to that absolute
    /// number every time rather than adding to it, so a Health sync that
    /// fires five times in a row (background delivery, a screen re-
    /// appearing, a manual re-tap) reads the same real progress instead of
    /// crediting the same steps five times over.
    func syncTodayFromHealth(for challengeID: UUID) async {
        guard healthKitConnected, let challenge = challenges.first(where: { $0.id == challengeID }) else { return }
        let measured: Double?
        switch challenge.kind {
        case .steps: measured = await HealthKitManager.shared.fetchTotalSteps(since: challenge.startDate).map(Double.init)
        case .distance: measured = await HealthKitManager.shared.fetchTotalDistanceMiles(since: challenge.startDate)
        case .custom: measured = nil
        }
        guard let measured else { return }
        applyMeasuredTotal(for: challengeID, healthTotal: measured)
    }

    /// Logs a just-finished `LiveTrackingView` recording against a
    /// challenge, and replaces the map's route with the trail actually
    /// walked or run — a real GPS path is more honest there than the
    /// generic directions-to-venue line `ensureRealRoute` draws before
    /// anyone has moved. Distance challenges log the tracked miles
    /// directly; steps challenges convert distance using the common
    /// ~2,000-steps-per-mile estimate, since GPS has no way to count
    /// footfalls directly. Added on top of (never replacing) the Health
    /// total, since this app doesn't write tracked sessions back into
    /// HealthKit as workouts — a synced Health total wouldn't otherwise
    /// know this session happened. Custom challenges have nothing GPS can
    /// verify, so the session still saves the trail but skips progress.
    func applyTrackedSession(_ session: TrackedSession, to challengeID: UUID) {
        guard let idx = challenges.firstIndex(where: { $0.id == challengeID }) else { return }
        if !session.coordinates.isEmpty {
            challenges[idx].routeCoordinates = session.coordinates
            recordTrailLeg(session.coordinates)
        }
        let measured: Double?
        switch challenges[idx].kind {
        // Real pedometer steps when available — falls back to the
        // ~2,000-steps-per-mile GPS estimate only if CMPedometer had
        // nothing (e.g. unsupported hardware), since actual step data
        // beats an estimate derived from distance the GPS may have barely
        // registered on a short walk.
        case .steps: measured = session.steps > 0 ? Double(session.steps) : session.distanceMiles * 2000
        case .distance: measured = session.distanceMiles
        case .custom: measured = nil
        }
        guard let measured, measured > 0 else { return }
        applyMeasuredTotal(for: challengeID, addTrackedAmount: measured)
    }

    // MARK: Today's trail — every real GPS leg Track Live recorded today,
    // for the general Map tab (distinct from a specific challenge's own
    // route line on its own detail screen).

    private var storedTrailLegs: [[CLLocationCoordinate2D]] = []
    private var storedTrailDate: Date?

    /// Each finished Track Live session is its own separate leg, not
    /// stitched to the last one — two unrelated walks across town
    /// shouldn't be joined by a straight line cutting across the map.
    /// Resets to empty on read once the calendar day rolls over, so
    /// yesterday's trail never lingers as if it were today's, even if the
    /// app's been open since before midnight.
    var todayTrailLegs: [[CLLocationCoordinate2D]] {
        storedTrailDate == Calendar.current.startOfDay(for: Date()) ? storedTrailLegs : []
    }

    private func recordTrailLeg(_ coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return }
        let today = Calendar.current.startOfDay(for: Date())
        if storedTrailDate != today {
            storedTrailLegs = []
            storedTrailDate = today
        }
        storedTrailLegs.append(coordinates)
    }

    // MARK: Activity — appends real history, so charts read actual data

    /// The manual honor-system path — one flat, once-a-day-feeling notch
    /// per tap, unrelated to any real measurement. This is the only path
    /// left that's additive by design: someone tapping "Log Today" by hand
    /// has no real total to set progress *to*, only a "yes, I did
    /// something today" to credit.
    func logActivity(for challengeID: UUID, hitTarget: Bool, measuredRatio: Double? = nil) {
        guard let idx = challenges.firstIndex(where: { $0.id == challengeID }) else { return }
        if let sIdx = challenges[idx].standings.firstIndex(where: { $0.member.id == me.id }) {
            let previous = challenges[idx].standings[sIdx].progress
            let scale = measuredRatio.map { min(2.0, max(0.5, $0)) } ?? 1.0
            let next = min(1, previous + 0.08 * scale)
            challenges[idx].standings[sIdx].progress = next
            challenges[idx].standings[sIdx].progressHistory.append(next)
            challenges[idx].standings[sIdx].trendDelta = hitTarget ? "+1" : "—"
            challenges[idx].standings[sIdx].lastLogVerified = measuredRatio != nil
            recomputeRanks(at: idx)
            checkAboutToWin(at: idx, sIdx: sIdx, previous: previous, next: next)
        } else {
            recomputeRanks(at: idx)
        }
        checkChallengeCompletion(at: idx)
    }

    /// Fires once, right on the crossing into "close enough that finishing
    /// today is realistic" — a repeat sync that keeps progress above 90%
    /// doesn't re-fire, since `previous` was already past the line too.
    private func checkAboutToWin(at idx: Int, sIdx: Int, previous: Double, next: Double) {
        guard previous < 0.9, next >= 0.9, challenges[idx].standings[sIdx].rank == 1 else { return }
        ChallengeNotifier.notifyAboutToWin(challengeTitle: challenges[idx].title)
    }

    /// The absolute-measurement path — HealthKit sync and Track Live both
    /// go through here. `healthTotal`, when passed, *replaces* the stored
    /// value (idempotent — the same real total always produces the same
    /// progress); `addTrackedAmount` accumulates, since each finished
    /// tracking session is a genuinely new, distinct event. Progress is
    /// `max`'d against whatever it already was rather than overwritten
    /// outright, so real evidence only ever raises it — the same way a
    /// trip odometer doesn't run backwards. One entry gets appended to
    /// `progressHistory` per real calendar day; a second sync the same day
    /// updates that entry in place instead of appending a duplicate.
    private func applyMeasuredTotal(for challengeID: UUID, healthTotal: Double? = nil, addTrackedAmount: Double = 0) {
        guard let idx = challenges.firstIndex(where: { $0.id == challengeID }),
              let sIdx = challenges[idx].standings.firstIndex(where: { $0.member.id == me.id }) else { return }
        if let healthTotal { challenges[idx].standings[sIdx].healthTotal = healthTotal }
        if addTrackedAmount > 0 { challenges[idx].standings[sIdx].trackedTotal += addTrackedAmount }
        let combined = challenges[idx].standings[sIdx].healthTotal + challenges[idx].standings[sIdx].trackedTotal
        let ratio = min(1, combined / challenges[idx].goalTarget(for: me))
        let previous = challenges[idx].standings[sIdx].progress
        let next = max(previous, ratio)
        guard next != previous || addTrackedAmount > 0 else { return }
        challenges[idx].standings[sIdx].progress = next
        challenges[idx].standings[sIdx].lastLogVerified = true
        let deltaPct = Int(((next - previous) * 100).rounded())
        challenges[idx].standings[sIdx].trendDelta = deltaPct == 0 ? "—" : String(format: "%+d%%", deltaPct)

        let today = Calendar.current.startOfDay(for: Date())
        if let lastDay = challenges[idx].standings[sIdx].lastLoggedDay, Calendar.current.isDate(lastDay, inSameDayAs: today) {
            let lastIdx = challenges[idx].standings[sIdx].progressHistory.count - 1
            if lastIdx >= 0 { challenges[idx].standings[sIdx].progressHistory[lastIdx] = next }
        } else {
            challenges[idx].standings[sIdx].progressHistory.append(next)
            challenges[idx].standings[sIdx].lastLoggedDay = today
        }
        recomputeRanks(at: idx)
        checkAboutToWin(at: idx, sIdx: sIdx, previous: previous, next: next)
        checkChallengeCompletion(at: idx)
    }

    /// Auto-resolves a challenge the moment either condition is real: the
    /// goal's been hit outright (first past the post wins immediately,
    /// same beat as a real race), or the duration's run out with nobody
    /// reaching it (highest real progress wins instead of leaving it
    /// hanging forever — `resolveChallenge` already picks that winner by
    /// actual progress). Called after anything that could change progress,
    /// plus a periodic sweep from `autoSyncFromHealth` so a challenge whose
    /// last day passes without a fresh log still actually ends.
    private func checkChallengeCompletion(at idx: Int) {
        guard challenges[idx].status == .active else { return }
        let goalHit = challenges[idx].standings.contains { $0.progress >= 1 }
        let daysElapsed = Calendar.current.dateComponents([.day], from: challenges[idx].startDate, to: Date()).day ?? 0
        let timeUp = daysElapsed >= challenges[idx].durationDays
        guard goalHit || timeUp else { return }
        resolveChallenge(challenges[idx].id)
    }

    /// Sweeps every active challenge for the time-based completion case —
    /// unlike the goal-hit case, nothing else naturally triggers a check
    /// on the exact day a challenge's duration runs out if nobody happens
    /// to log anything that day, so this needs its own periodic call.
    func checkExpiredChallenges() {
        for challenge in challenges where challenge.status == .active {
            if let idx = challenges.firstIndex(where: { $0.id == challenge.id }) {
                checkChallengeCompletion(at: idx)
            }
        }
    }

    /// `rank` was only ever set once, at challenge creation, and never
    /// touched again as progress actually changed — meaning every "RANK #"
    /// badge, the board's sort order, and who resolveChallenge would have
    /// picked as winner could all silently drift out of sync with real
    /// progress the moment anyone logged anything. Re-sorts by actual
    /// progress and reassigns 1...N after every progress-changing call.
    private func recomputeRanks(at idx: Int) {
        let myOldRank = challenges[idx].standings.first { $0.member.id == me.id }?.rank
        let order = challenges[idx].standings.indices.sorted {
            challenges[idx].standings[$0].progress > challenges[idx].standings[$1].progress
        }
        for (newRank, standingIdx) in order.enumerated() {
            challenges[idx].standings[standingIdx].rank = newRank + 1
        }
        guard challenges[idx].standings.count > 1,
              let myOldRank, let myNewRank = challenges[idx].standings.first(where: { $0.member.id == me.id })?.rank,
              myOldRank != myNewRank else { return }
        ChallengeNotifier.notifyRankChange(challengeTitle: challenges[idx].title, blindReveal: challenges[idx].blindReveal,
                                            oldRank: myOldRank, newRank: myNewRank)
        if myNewRank == challenges[idx].standings.count {
            ChallengeNotifier.notifyLastPlace(challengeTitle: challenges[idx].title)
        }
    }

    // MARK: Challenges

    /// `goalTarget`, when passed (a suggestion's own "hit 50,000 steps this
    /// week to win"), is used as-is. Otherwise it's computed here from this
    /// specific group's own typical daily pace — `personalizedStepTarget`
    /// for steps, a moderate 3 mi/day baseline for distance — times the
    /// duration, stretched 15% past a straightforward pace so it takes
    /// real, sustained effort to win outright rather than making it a
    /// given. Not scaled by participant count: it's an individual target
    /// everyone races toward independently, not a pooled group total.
    func createChallenge(title: String, icon: String, kind: ChallengeKind, venue: String, rules: String,
                          photoName: String, duration: Int, customMetric: String?, payoff: Payoff,
                          blindReveal: Bool, fairPlay: Bool, invitees: [Member], goalTarget: Double? = nil) {
        var standings = [Standing(member: me, rank: 1, progress: 0, trendDelta: "—", progressHistory: [0])]
        for (i, m) in invitees.enumerated() {
            standings.append(Standing(member: m, rank: i + 2, progress: 0, trendDelta: "—", progressHistory: [0]))
        }
        let dailyTarget: Int = switch kind {
            case .steps: 8_000
            case .distance: 2
            case .custom: 1
        }
        let stretchFactor = 1.15
        let resolvedGoal: Double? = goalTarget ?? {
            switch kind {
            case .steps: return Double(personalizedStepTarget) * Double(duration) * stretchFactor
            case .distance: return personalizedDistanceTarget * Double(duration) * stretchFactor
            case .custom: return nil
            }
        }()
        let challenge = Challenge(id: UUID(), title: title, icon: icon, kind: kind,
                                   venue: venue, rules: rules, photoName: photoName,
                                   durationDays: duration, dailyTarget: dailyTarget,
                                   customMetric: customMetric, payoff: payoff,
                                   standings: standings, myMemberID: me.id,
                                   blindReveal: blindReveal, fairPlay: fairPlay, status: .active,
                                   routeCoordinates: nil, winnerName: nil, startDate: Date(), goalTarget: resolvedGoal)
        challenges.insert(challenge, at: 0)
        // Delayed rather than set the instant the challenge exists —
        // this is always called from a screen that's about to dismiss
        // and pop back to Home, and setting it synchronously meant
        // CelebrationOverlay's own entrance (scale-in, sparkle burst)
        // started playing while that pop transition was still visibly
        // sliding — two competing animations at once, which is what read
        // as "a little buggy." A short pause lets the pop settle first.
        Task {
            try? await Task.sleep(for: .seconds(0.45))
            justCreated = true
        }
    }

    /// Fetches (or reuses the cached) real walking route for a distance
    /// challenge's actual venue — see `RouteService`. A no-op for
    /// steps/custom challenges, which never render a route line, and for
    /// anything that already has one, so this is safe to call from a
    /// view's `.task` every time it appears.
    func ensureRealRoute(for challengeID: UUID) async {
        guard let idx = challenges.firstIndex(where: { $0.id == challengeID }),
              challenges[idx].kind == .distance, challenges[idx].routeCoordinates == nil else { return }
        let coords = await RouteService.shared.route(for: challenges[idx].venue)
        guard let idx2 = challenges.firstIndex(where: { $0.id == challengeID }) else { return }
        challenges[idx2].routeCoordinates = coords
    }

    /// Reveals the winner — the payoff of the play → reveal loop.
    /// Records a result only; nothing is credited to any account. Picks
    /// the winner by actual progress, not the `rank` field directly —
    /// belt-and-suspenders alongside `recomputeRanks`, so this is correct
    /// even if something else ever mutates a standing without going
    /// through logActivity. On an exact tie for the top progress, prefers
    /// whoever isn't "me" — relevant specifically when forfeitChallenge
    /// drops my own progress to 0 and nobody else has logged anything yet
    /// either, which would otherwise still let a plain `max(by:)` pick me.
    func resolveChallenge(_ id: UUID) {
        guard let idx = challenges.firstIndex(where: { $0.id == id }),
              challenges[idx].status != .complete else { return }
        let standings = challenges[idx].standings
        let topProgress = standings.map(\.progress).max() ?? 0
        guard let winner = standings.first(where: { $0.progress == topProgress && $0.member.id != me.id })
            ?? standings.first(where: { $0.progress == topProgress }) else { return }
        challenges[idx].status = .complete
        challenges[idx].winnerName = winner.member.name
        justRevealedID = id
        // A blind-reveal challenge's whole hook is the real-world payoff —
        // if "me" is the one who lost, that's the moment to actually
        // collect on it: a real photo, sent to whoever won. Never set for
        // a challenge I won (nothing to send), or a non-blind-reveal one
        // (there's no surprise/stakes ritual to it).
        if challenges[idx].blindReveal && winner.member.id != me.id {
            pendingProofChallengeID = id
        }
    }

    /// Sends the loser's captured proof photo to whoever won, via the same
    /// direct-message chat every other 1:1 conversation in the app already
    /// uses — there's no separate "proof" delivery mechanism, this rides
    /// the existing chat thread with the winner.
    func sendProofPhoto(for challengeID: UUID, imageData: Data) {
        guard let challenge = challenges.first(where: { $0.id == challengeID }),
              let winner = challenge.standings.max(by: { $0.progress < $1.progress }) else { return }
        sendDirectMessage(to: winner.member.id,
                           text: "Proof, as promised — you got me on \"\(challenge.title).\"",
                           imageData: imageData)
        pendingProofChallengeID = nil
    }

    /// Bows out of an active challenge early instead of letting it run its
    /// full course — forfeiting always means losing this one, regardless
    /// of current progress (dropping to 0 before resolving, rather than
    /// letting whatever progress was already logged possibly still win).
    /// Ends the challenge immediately, same reveal/proof-photo flow as a
    /// natural resolution.
    func forfeitChallenge(_ id: UUID) {
        guard let idx = challenges.firstIndex(where: { $0.id == id }),
              challenges[idx].status == .active,
              let sIdx = challenges[idx].standings.firstIndex(where: { $0.member.id == me.id }) else { return }
        challenges[idx].standings[sIdx].progress = 0
        recomputeRanks(at: idx)
        if challenges[idx].standings.count == 1 {
            // Nobody to lose *to* — a solo challenge (no one else was ever
            // invited) has no opponent for resolveChallenge's "highest
            // progress wins" to crown, which meant its only real option
            // was the person who just forfeited. That looked like tapping
            // Forfeit did nothing, or worse, declared a win. Ends the
            // challenge with no winner instead.
            challenges[idx].status = .complete
            challenges[idx].winnerName = nil
            justRevealedID = id
        } else {
            // resolveChallenge's own tie-break (prefer not-me on an exact
            // progress tie) is what actually guarantees this loses even if
            // nobody else has logged anything yet either — not a special
            // negative value here, which would've shown up as a literal
            // "-1%" in the handful of progress displays that don't clamp.
            resolveChallenge(id)
        }
    }

    /// Removes a challenge outright — swipe-to-delete on its row. Distinct
    /// from forfeiting: forfeiting ends an active challenge as a loss but
    /// keeps its result on record (in "Recent Challenges," in the win/loss
    /// count); this just takes it off the list entirely, active or
    /// already settled, with nothing left behind.
    func deleteChallenge(_ id: UUID) {
        challenges.removeAll { $0.id == id }
    }

    /// Declines to send a proof photo right now — doesn't retract the loss
    /// or the stakes, just dismisses the prompt without sending anything.
    func skipProofPhoto() {
        pendingProofChallengeID = nil
    }

    // MARK: Contacts + Groups

    func addContact(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        crew.append(Member(name: trimmed))
    }

    /// Adds someone found via `UserDirectory.lookup` — keeps their real
    /// published ID rather than minting a new local one, and no-ops if
    /// they're already in the crew (or would somehow resolve to "me").
    func addMember(id: UUID, name: String, photoData: Data? = nil) {
        guard id != me.id, !crew.contains(where: { $0.id == id }) else { return }
        crew.append(Member(id: id, name: name, photoData: photoData))
    }

    /// Re-fetches the current published name/photo for every crew member
    /// who has a real Provyr ID behind them — called whenever a screen
    /// that shows their photo appears (Crew, a group's orbit, a
    /// challenge's board), so someone else updating their own profile
    /// picture actually reaches everywhere they show up here instead of
    /// freezing at whatever it was the moment they were added. A plain
    /// locally-typed crew name has no real record to look up, so this is
    /// a harmless no-op for them — `UserDirectory.lookup` just returns nil.
    func refreshCrewProfiles() async {
        for member in crew {
            guard let result = await UserDirectory.shared.lookup(id: member.id.uuidString) else { continue }
            guard let idx = crew.firstIndex(where: { $0.id == member.id }) else { continue }
            crew[idx].name = result.name
            crew[idx].photoData = result.photoData
        }
    }

    func createGroup(name: String, memberIDs: [UUID]) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !memberIDs.isEmpty else { return }
        groups.append(ContactGroup(name: trimmed, memberIDs: memberIDs))
    }

    func members(in group: ContactGroup) -> [Member] {
        crew.filter { group.memberIDs.contains($0.id) }
    }

    // MARK: Chat

    func lastMessage(directWith memberID: UUID) -> ChatMessage? { directMessages[memberID]?.last }
    func lastMessage(inGroup groupID: UUID) -> ChatMessage? { groupMessages[groupID]?.last }

    private func sharedChallengeContext(for memberID: UUID) -> (title: String, theirRank: Int, myRank: Int?)? {
        guard let challenge = challenges.first(where: { c in
            c.status == .active && c.standings.contains { $0.member.id == memberID }
        }), let standing = challenge.standings.first(where: { $0.member.id == memberID }) else { return nil }
        return (challenge.title, standing.rank, challenge.myStanding?.rank)
    }

    func sendDirectMessage(to memberID: UUID, text: String, imageData: Data? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || imageData != nil, let member = crew.first(where: { $0.id == memberID }) else { return }
        directMessages[memberID, default: []].append(ChatMessage(senderID: me.id, text: trimmed, imageData: imageData))
        let seed = directMessages[memberID]?.count ?? 0
        let context = sharedChallengeContext(for: memberID)
        Task {
            try? await Task.sleep(for: .seconds(Double.random(in: 1.1...2.4)))
            // Signing into a different identity or toggling Demo Mode
            // during this delay wholesale-replaces `crew` — without this
            // check, the reply lands under a member ID that may no longer
            // exist in the new crew, and ChatListView (which only ever
            // iterates `app.crew`) could never surface it, while the
            // unread dot it sets below still counts it forever.
            guard crew.contains(where: { $0.id == memberID }) else { return }
            let reply = imageData != nil ? "Nice pic." : ChatBanter.reply(from: member, sharedChallenge: context, seed: seed)
            directMessages[memberID, default: []].append(ChatMessage(senderID: memberID, text: reply))
            if openDirectChatID != memberID { unreadDirectIDs.insert(memberID) }
        }
    }

    func sendGroupMessage(to groupID: UUID, text: String, imageData: Data? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || imageData != nil, let group = groups.first(where: { $0.id == groupID }),
              let replier = members(in: group).randomElement() else { return }
        groupMessages[groupID, default: []].append(ChatMessage(senderID: me.id, text: trimmed, imageData: imageData))
        let seed = groupMessages[groupID]?.count ?? 0
        let context = sharedChallengeContext(for: replier.id)
        Task {
            try? await Task.sleep(for: .seconds(Double.random(in: 1.2...2.6)))
            // Same reasoning as sendDirectMessage's reply — a different
            // identity signing in or Demo Mode toggling during this delay
            // wholesale-replaces `groups`, and this group may not exist in
            // the new one at all.
            guard groups.contains(where: { $0.id == groupID }) else { return }
            let reply = imageData != nil ? "Nice pic." : ChatBanter.reply(from: replier, sharedChallenge: context, seed: seed)
            groupMessages[groupID, default: []].append(ChatMessage(senderID: replier.id, text: reply))
            if openGroupChatID != groupID { unreadGroupIDs.insert(groupID) }
        }
    }

    // MARK: Session persistence — just enough state to skip the sign-in and
    // onboarding screens on a returning launch, plus enough of "you" (name,
    // body profile, settings, mood history) to be worth syncing. The crew,
    // groups, challenges, and chat are still Fixtures-seeded fresh every
    // launch — making *those* real needs CKShare and a lot more
    // infrastructure than one account's own private data. See
    // CloudSyncManager for the CloudKit side of this.
    //
    // Sync strategy is deliberately simple: whole-blob last-write-wins,
    // compared by `savedAt`. There's no field-level merge — if you changed
    // your name on one device and your weight on another before either one
    // synced, whichever device saved most recently wins outright and the
    // other device's unsynced change is lost. Fine for one person moving
    // between their own devices; not a real conflict-resolution system.

    private static let sessionDefaultsKey = "com.jean.pact.session"

    private struct PersistedSession: Codable {
        var isSignedIn: Bool
        var hasOnboarded: Bool
        var signedInName: String?
        var signInMethod: String?
        var signedInIdentifier: String?
        var appLockEnabled: Bool
        var showAgeRangeOnProfile: Bool
        var meName: String
        var meAgeBand: AgeBand
        var meColorIndex: Int
        var myProfilePhotoData: Data?
        var myBodyProfile: BodyProfile
        var unitSystem: UnitSystem
        var profileAnniversary: Date?
        var moodHistory: [MoodCheckIn]
        /// When this blob was written — the only thing that decides which
        /// of two conflicting copies (local vs. iCloud) wins.
        var savedAt: Date
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.sessionDefaultsKey),
           let saved = try? JSONDecoder().decode(PersistedSession.self, from: data) {
            apply(saved)
        }
        if let raw = UserDefaults.standard.string(forKey: Self.appearanceDefaultsKey), let pref = AppearancePreference(rawValue: raw) {
            appearance = pref
        }
        pushNotificationsEnabled = UserDefaults.standard.bool(forKey: ChallengeNotifier.notificationsEnabledDefaultsKey)
        // Only override the `true` default if this key was actually
        // written before — `bool(forKey:)` alone returns false for a
        // never-set key, which would flip every fresh install to "off."
        if UserDefaults.standard.object(forKey: Self.iCloudSyncEnabledDefaultsKey) != nil {
            iCloudSyncEnabled = UserDefaults.standard.bool(forKey: Self.iCloudSyncEnabledDefaultsKey)
        }
        if iCloudSyncEnabled {
            Task { await reconcileWithCloud() }
        } else {
            cloudSyncStatus = .unavailable
        }
        if UserDefaults.standard.bool(forKey: Self.healthKitConnectedDefaultsKey) {
            // Re-verifies (near-instant, no re-prompt, since it's already
            // granted) and re-arms the change observer for this launch —
            // see connectHealthKit().
            Task { await connectHealthKit() }
        }
        // Catches a challenge whose duration ran out while the app was
        // closed, so it doesn't just sit at .active forever until someone
        // happens to log something again.
        checkExpiredChallenges()
    }

    /// Suppresses `persistSession()` while `apply(_:)` is bulk-assigning
    /// restored fields — without this, restoring ~10 `didSet`-observed
    /// properties one at a time would re-save (and re-upload to CloudKit)
    /// the same blob up to 10 times on every single launch.
    private var isApplyingRestoredSession = false

    private func apply(_ saved: PersistedSession) {
        isApplyingRestoredSession = true
        defer { isApplyingRestoredSession = false }
        isSignedIn = saved.isSignedIn
        hasOnboarded = saved.hasOnboarded
        signedInName = saved.signedInName
        signInMethod = saved.signInMethod
        signedInIdentifier = saved.signedInIdentifier
        appLockEnabled = saved.appLockEnabled
        showAgeRangeOnProfile = saved.showAgeRangeOnProfile
        me.name = saved.meName
        me.ageBand = saved.meAgeBand
        meColorIndex = saved.meColorIndex
        myProfilePhotoData = saved.myProfilePhotoData
        myBodyProfile = saved.myBodyProfile
        unitSystem = saved.unitSystem
        profileAnniversary = saved.profileAnniversary
        moodHistory = saved.moodHistory
        advanceAgeIfAnniversaryPassed()
        recomputeMoodStreakState()
    }

    /// Re-checks iCloud availability and re-syncs — exposed so Settings can
    /// call this itself every time the iCloud Sync section actually
    /// appears. The one-shot call at cold launch (below) can catch
    /// `CKContainer.accountStatus()` before CloudKit has finished
    /// initializing and get back `.couldNotDetermine` even on a device
    /// that's genuinely signed in, and nothing was ever re-checking it —
    /// so a transient false negative at launch meant "Not signed into
    /// iCloud" stuck for the rest of the session regardless of the real
    /// state. Safe to call repeatedly: it only actually pushes/pulls
    /// anything when the compared timestamps say one side is genuinely
    /// newer.
    func refreshCloudStatus() async {
        guard iCloudSyncEnabled else { return }
        await reconcileWithCloud()
    }

    /// Compares the local copy against whatever's in the user's private
    /// CloudKit database and keeps whichever is newer — covers both
    /// directions: a fresh reinstall with nothing local yet pulls the cloud
    /// copy down, and a device that's ahead pushes its copy up. Runs once
    /// per launch, after the local restore already happened synchronously
    /// above, so the app never waits on the network just to open.
    private func reconcileWithCloud() async {
        guard await CloudSyncManager.shared.isAvailable else {
            cloudSyncStatus = .unavailable
            return
        }
        cloudSyncStatus = .syncing
        let localData = UserDefaults.standard.data(forKey: Self.sessionDefaultsKey)
        let local = localData.flatMap { try? JSONDecoder().decode(PersistedSession.self, from: $0) }
        guard let cloudData = await CloudSyncManager.shared.fetch(),
              let cloud = try? JSONDecoder().decode(PersistedSession.self, from: cloudData) else {
            // Nothing in the cloud yet — push what we have locally, if any,
            // so the very next device to reconcile finds something.
            if let localData {
                cloudSyncStatus = await CloudSyncManager.shared.upload(localData) ? .synced(Date()) : .failed
            } else {
                cloudSyncStatus = .synced(Date())
            }
            return
        }
        if let local, local.savedAt >= cloud.savedAt {
            cloudSyncStatus = .synced(Date())
            return
        }
        // The cloud copy is newer (or there was no local copy at all, e.g.
        // right after a reinstall) — adopt it, and cache it locally too so
        // the next offline launch already has it without a network round
        // trip. `apply` suppresses persistSession's own upload while it
        // runs, so this explicit write is the only place this direction
        // actually lands on disk.
        apply(cloud)
        UserDefaults.standard.set(cloudData, forKey: Self.sessionDefaultsKey)
        cloudSyncStatus = .synced(Date())
    }

    /// Derives `moodStreak`/`moodLoggedToday` from the real history instead
    /// of trusting stored flags that could drift out of sync with it (e.g.
    /// a streak counted on a device that's since had days restored from an
    /// older or newer cloud copy).
    private func recomputeMoodStreakState() {
        let cal = Calendar.current
        moodLoggedToday = moodHistory.last.map { cal.isDateInToday($0.date) } ?? false
        let days = Set(moodHistory.map { cal.startOfDay(for: $0.date) })
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) {
            // Haven't logged yet today — that alone shouldn't zero out an
            // existing streak, only a missed day should.
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        moodStreak = streak
    }

    /// There's no real birthdate to check against, so a full year elapsed
    /// since `profileAnniversary` (set once, when onboarding first captured
    /// an age) is the stand-in "birthday." Bumps `myBodyProfile.age` by
    /// however many whole years have actually passed — not just +1 — so
    /// someone who skips a year of launches still lands on the right age,
    /// then re-anchors the anniversary so the same years aren't counted twice.
    func advanceAgeIfAnniversaryPassed() {
        guard let anniversary = profileAnniversary else { return }
        let years = Calendar.current.dateComponents([.year], from: anniversary, to: Date()).year ?? 0
        guard years > 0 else { return }
        myBodyProfile.age += years
        me.ageBand = AgeBand.forAge(myBodyProfile.age)
        profileAnniversary = Calendar.current.date(byAdding: .year, value: years, to: anniversary)
    }

    private func persistSession() {
        guard !isApplyingRestoredSession else { return }
        let saved = PersistedSession(
            isSignedIn: isSignedIn, hasOnboarded: hasOnboarded, signedInName: signedInName,
            signInMethod: signInMethod, signedInIdentifier: signedInIdentifier,
            appLockEnabled: appLockEnabled, showAgeRangeOnProfile: showAgeRangeOnProfile,
            meName: me.name, meAgeBand: me.ageBand, meColorIndex: meColorIndex,
            myProfilePhotoData: myProfilePhotoData, myBodyProfile: myBodyProfile, unitSystem: unitSystem,
            profileAnniversary: profileAnniversary, moodHistory: moodHistory, savedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: Self.sessionDefaultsKey)
        if isSignedIn && hasOnboarded {
            let id = me.id, name = me.name, colorIndex = meColorIndex, photo = myProfilePhotoData
            Task { await UserDirectory.shared.publish(id: id, name: name, colorIndex: colorIndex, photoData: photo) }
        }
        guard iCloudSyncEnabled else {
            cloudSyncStatus = .unavailable
            return
        }
        Task {
            let succeeded = await CloudSyncManager.shared.upload(data)
            cloudSyncStatus = succeeded ? .synced(Date()) : (await CloudSyncManager.shared.isAvailable ? .failed : .unavailable)
        }
    }
}

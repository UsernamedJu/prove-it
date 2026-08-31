import SwiftUI
import Foundation

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
    var crew: [Member] = Fixtures.crew
    var groups: [ContactGroup] = Fixtures.groups
    var challenges: [Challenge] = Fixtures.challenges
    var moodHistory: [MoodCheckIn] = Fixtures.moodHistory { didSet { persistSession() } }
    var moodStreak = 3
    var moodLoggedToday = false

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
    var healthKitConnected = false

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
    var signedInName: String? { didSet { persistSession() } }
    /// How they got signed in — shown in Settings. Email/phone sign-in has
    /// no backend to verify against, so it's an identity label, not a
    /// verified credential; framed that way rather than faking security.
    var signInMethod: String? { didSet { persistSession() } }
    var appLockEnabled = false { didSet { persistSession() } }
    var isUnlocked = true

    // MARK: Chat — keyed by Member.id / ContactGroup.id. No real backend:
    // sending appends immediately, then a canned reply lands a beat later.
    var directMessages: [UUID: [ChatMessage]] = Fixtures.directMessages
    var groupMessages: [UUID: [ChatMessage]] = Fixtures.groupMessages
    var unreadDirectIDs: Set<UUID> = Fixtures.unreadDirectIDs
    var unreadGroupIDs: Set<UUID> = Fixtures.unreadGroupIDs
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

    var personalizedStepTarget: Int {
        myBodyProfile.personalizedStepTarget(ageBand: me.ageBand)
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

    func connectHealthKit() async {
        healthKitConnected = await HealthKitManager.shared.requestAuthorization()
    }

    /// Pulls today's real activity from Health — steps or distance,
    /// whichever the challenge tracks — and logs it in place of the manual
    /// "Log Today" tap. Falls back to doing nothing if Health isn't
    /// connected or has no data yet; the caller decides whether to fall
    /// back to a manual log in that case.
    func syncTodayFromHealth(for challengeID: UUID) async {
        guard healthKitConnected, let challenge = challenges.first(where: { $0.id == challengeID }) else { return }
        let target = Double(challenge.dailyTarget)
        guard target > 0 else { return }
        let measured: Double?
        switch challenge.kind {
        case .steps: measured = await HealthKitManager.shared.fetchTodaySteps().map(Double.init)
        case .distance: measured = await HealthKitManager.shared.fetchTodayDistanceMiles()
        case .custom: measured = nil
        }
        guard let measured else { return }
        logActivity(for: challengeID, hitTarget: measured >= target, measuredRatio: measured / target)
    }

    // MARK: Activity — appends real history, so charts read actual data

    /// `measuredRatio` is how much of the daily target a real HealthKit
    /// reading actually covered (1.0 == exactly hit it) — when present, the
    /// day's progress scales with it instead of always crediting the same
    /// fixed amount, and the entry is marked verified. Manual "Log Today"
    /// taps pass `nil` and keep the flat honor-system increment.
    func logActivity(for challengeID: UUID, hitTarget: Bool, measuredRatio: Double? = nil) {
        guard let idx = challenges.firstIndex(where: { $0.id == challengeID }) else { return }
        if let sIdx = challenges[idx].standings.firstIndex(where: { $0.member.id == me.id }) {
            let scale = measuredRatio.map { min(2.0, max(0.5, $0)) } ?? 1.0
            let next = min(1, challenges[idx].standings[sIdx].progress + 0.08 * scale)
            challenges[idx].standings[sIdx].progress = next
            challenges[idx].standings[sIdx].progressHistory.append(next)
            challenges[idx].standings[sIdx].trendDelta = hitTarget ? "+1" : "—"
            challenges[idx].standings[sIdx].lastLogVerified = measuredRatio != nil
        }
    }

    // MARK: Challenges

    func createChallenge(title: String, icon: String, kind: ChallengeKind, venue: String, rules: String,
                          photoName: String, duration: Int, customMetric: String?, payoff: Payoff,
                          blindReveal: Bool, fairPlay: Bool, invitees: [Member]) {
        var standings = [Standing(member: me, rank: 1, progress: 0, trendDelta: "—", progressHistory: [0])]
        for (i, m) in invitees.enumerated() {
            standings.append(Standing(member: m, rank: i + 2, progress: 0, trendDelta: "—", progressHistory: [0]))
        }
        let dailyTarget: Int = switch kind {
            case .steps: 8_000
            case .distance: 2
            case .custom: 1
        }
        let challenge = Challenge(id: UUID(), title: title, icon: icon, kind: kind,
                                   venue: venue, rules: rules, photoName: photoName,
                                   durationDays: duration, daysLeft: duration, dailyTarget: dailyTarget,
                                   customMetric: customMetric, payoff: payoff,
                                   standings: standings, myMemberID: me.id,
                                   blindReveal: blindReveal, fairPlay: fairPlay, status: .active,
                                   routeCoordinates: nil, winnerName: nil)
        challenges.insert(challenge, at: 0)
        justCreated = true
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
    /// Records a result only; nothing is credited to any account.
    func resolveChallenge(_ id: UUID) {
        guard let idx = challenges.firstIndex(where: { $0.id == id }),
              challenges[idx].status != .complete,
              let winner = challenges[idx].standings.min(by: { $0.rank < $1.rank }) else { return }
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
              let winner = challenge.standings.min(by: { $0.rank < $1.rank }) else { return }
        sendDirectMessage(to: winner.member.id,
                           text: "Proof, as promised — you got me on \"\(challenge.title).\"",
                           imageData: imageData)
        pendingProofChallengeID = nil
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
        Task { await reconcileWithCloud() }
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
            signInMethod: signInMethod, appLockEnabled: appLockEnabled, showAgeRangeOnProfile: showAgeRangeOnProfile,
            meName: me.name, meAgeBand: me.ageBand, meColorIndex: meColorIndex,
            myProfilePhotoData: myProfilePhotoData, myBodyProfile: myBodyProfile, unitSystem: unitSystem,
            profileAnniversary: profileAnniversary, moodHistory: moodHistory, savedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(saved) else { return }
        UserDefaults.standard.set(data, forKey: Self.sessionDefaultsKey)
        Task {
            let succeeded = await CloudSyncManager.shared.upload(data)
            cloudSyncStatus = succeeded ? .synced(Date()) : (await CloudSyncManager.shared.isAvailable ? .failed : .unavailable)
        }
    }
}

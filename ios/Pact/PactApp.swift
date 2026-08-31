import SwiftUI
import UIKit
import CloudKit

/// `NavigationStack`'s underlying `UINavigationController` defaults to a
/// plain white view behind the two view controllers it's animating between
/// — invisible once a screen has laid out, but visible as a white flash
/// along the transition seam during the push/pop itself, especially since
/// every screen here hides the system nav bar (no bar chrome to mask it).
/// Overriding `viewDidLoad` globally is the standard SwiftUI/UIKit-interop
/// fix: every `UINavigationController` SwiftUI creates picks it up.
extension UINavigationController {
    open override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(Theme.Surface.bg)
    }
}

@main
struct PactApp: App {
    @State private var app = AppModel()
    @State private var sharedChallenges = SharedChallengeStore.shared
    @UIApplicationDelegateAdaptor(CloudShareDelegate.self) private var cloudShareDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(sharedChallenges)
                .preferredColorScheme(app.appearance.colorScheme)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(SharedChallengeStore.self) private var sharedChallenges
    @Environment(\.scenePhase) private var scenePhase
    /// Shown for a beat on cold launch, then fades into whichever screen
    /// below actually applies — the logo-first-then-app sequence most
    /// native apps open with, instead of jumping straight to content.
    @State private var showSplash = true

    var body: some View {
        @Bindable var app = app
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
            } else if app.appLockEnabled && !app.isUnlocked {
                LockScreenView()
                    .transition(.opacity)
            } else if app.hasOnboarded && !app.explicitlySignedOut {
                // A completed profile always wins, regardless of how this
                // session got signed in — someone who already has an
                // account shouldn't be routed back through sign-in (or
                // onboarding) just because a guest session didn't persist.
                // The explicitlySignedOut check is the one exception: an
                // actual "Sign Out" tap needs to still show Sign In, not
                // be silently absorbed by this same priority.
                MainTabView()
                    .transition(majorScreenTransition)
            } else if !app.isSignedIn && !app.isGuestSession {
                SignInView()
                    .transition(.opacity)
            } else {
                OnboardingFlow()
                    .transition(majorScreenTransition)
            }
        }
        .animation(Theme.Motion.fade, value: showSplash)
        // A plain opacity cross-fade reads as a jump cut for a full-screen
        // context change this big (sign-in's full-bleed photo behind
        // onboarding's plain background, onboarding behind the whole app)
        // — the slower spring plus a subtle scale below is what makes it
        // read as "arriving somewhere new" instead of an abrupt swap.
        .animation(Theme.Motion.settle, value: app.hasOnboarded)
        .animation(Theme.Motion.settle, value: app.isSignedIn)
        .animation(Theme.Motion.settle, value: app.isGuestSession)
        .animation(Theme.Motion.settle, value: app.explicitlySignedOut)
        .animation(Theme.Motion.fade, value: app.isUnlocked)
        .task {
            try? await Task.sleep(for: .seconds(1.1))
            showSplash = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && app.appLockEnabled { app.isUnlocked = false }
        }
        .task {
            // Cold-launch case: the app wasn't running when a share link
            // was tapped, so this picks up whatever CloudShareDelegate
            // already stashed before this view ever appeared.
            if let metadata = CloudShareDelegate.pendingMetadata {
                CloudShareDelegate.pendingMetadata = nil
                await handleIncomingShare(metadata)
            }
            if app.hasOnboarded {
                await sharedChallenges.refresh(myLocalID: app.me.id, myName: app.me.name)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CloudShareDelegate.didReceiveShareMetadata)) { note in
            guard let metadata = note.object as? CKShare.Metadata else { return }
            Task { await handleIncomingShare(metadata) }
        }
    }

    /// A gentle fade-and-settle instead of a plain cross-fade — the
    /// incoming screen eases up from 97% scale as it fades in, which reads
    /// as a deliberate arrival rather than a swap, for the two transitions
    /// that matter most: sign-in finishing into onboarding, and onboarding
    /// finishing into the real app.
    private var majorScreenTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.97))
    }

    private func handleIncomingShare(_ metadata: CKShare.Metadata) async {
        guard app.hasOnboarded else { return } // no "me" identity to accept as yet
        // The root record's type is populated as part of the metadata
        // fetched when the link was opened, before either accept path runs
        // — that's what lets one shared-link handler serve two different
        // kinds of invite (a crew invite vs. a challenge invite) correctly.
        if metadata.rootRecord?.recordType == CrewInviteService.recordType {
            if let inviter = await CrewInviteService.shared.acceptInvite(metadata: metadata) {
                app.addMember(id: inviter.id, name: inviter.name)
            }
            return
        }
        await sharedChallenges.acceptShare(metadata: metadata, myLocalID: app.me.id, myName: app.me.name)
    }
}

/// The logo-first moment every polished app opens with — a brief branded
/// beat before the real screen takes over, not a blank flash straight into
/// content. Kept intentionally plain (flat background, no photo) since a
/// splash is system chrome, not a "hero" screen like Sign In.
struct SplashView: View {
    @State private var scale: CGFloat = 0.82
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Theme.Surface.bg.ignoresSafeArea()
            VStack(spacing: Theme.Space.sm) {
                PactMark(size: 52, animated: false)
                Text("Provyr")
                    .font(Theme.Font.wordmark(28))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.Ink.primary)
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
                scale = 1
                opacity = 1
            }
        }
    }
}

/// Hand-rolled tab switch instead of `TabView`, so the bottom bar can be the
/// floating pill from `PillTabBar` rather than a system tab bar — mirrors
/// the web build's own state-driven tab switch.
struct MainTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            switch app.tab {
            case .home: NavigationStack { HomeView() }
            case .challenges: NavigationStack { ChallengesListView() }
            case .map: NavigationStack { MapExploreView() }
            case .contacts: NavigationStack { ContactsView() }
            case .me: NavigationStack { ProfileView() }
            }
        }
        // A soft cross-fade between tabs instead of the instant cut this
        // used to force — the switch's onSelect already wraps the state
        // change in withAnimation(Theme.Motion.push), which is what
        // actually drives this now that nothing here cancels it out.
        .transition(.opacity)
        .safeAreaInset(edge: .bottom) {
            PillTabBar(selection: app.tab, onSelect: { tab in withAnimation(Theme.Motion.push) { app.tab = tab } })
                .padding(.horizontal, Theme.Space.xs)
                .padding(.bottom, Theme.Space.xs)
        }
        .background(Theme.Surface.bg.ignoresSafeArea())
        .tint(Theme.Brand.purple)
    }
}

#Preview {
    RootView().environment(AppModel())
}

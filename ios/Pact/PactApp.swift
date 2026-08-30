import SwiftUI
import UIKit

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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
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
            } else if app.hasOnboarded {
                // A completed profile always wins, regardless of how this
                // session got signed in — someone who already has an
                // account shouldn't be routed back through sign-in (or
                // onboarding) just because a guest session didn't persist.
                MainTabView()
                    .transition(.opacity)
            } else if !app.isSignedIn && !app.isGuestSession {
                SignInView()
                    .transition(.opacity)
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.fade, value: showSplash)
        .animation(Theme.Motion.fade, value: app.hasOnboarded)
        .animation(Theme.Motion.fade, value: app.isSignedIn)
        .animation(Theme.Motion.fade, value: app.isGuestSession)
        .animation(Theme.Motion.fade, value: app.isUnlocked)
        .task {
            try? await Task.sleep(for: .seconds(1.1))
            showSplash = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && app.appLockEnabled { app.isUnlocked = false }
        }
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
                PactMark(size: 52)
                Text("Prove it")
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
        // The screen itself cuts instantly, like the system Health app or
        // Strava — the lateral slide lives entirely in the tab bar's own
        // highlight pill (see `PillTabBar`), not the page behind it.
        .transition(.identity)
        .transaction { $0.animation = nil }
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

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

    var body: some View {
        @Bindable var app = app
        Group {
            if app.appLockEnabled && !app.isUnlocked {
                LockScreenView()
            } else if !app.isSignedIn {
                SignInView()
            } else if app.hasOnboarded {
                MainTabView()
            } else {
                OnboardingFlow()
            }
        }
        .animation(Theme.Motion.fade, value: app.hasOnboarded)
        .animation(Theme.Motion.fade, value: app.isSignedIn)
        .animation(Theme.Motion.fade, value: app.isUnlocked)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && app.appLockEnabled { app.isUnlocked = false }
        }
    }
}

/// Hand-rolled tab switch instead of `TabView`, so the bottom bar can be the
/// floating pill from `PillTabBar` rather than a system tab bar — mirrors
/// the web build's own state-driven tab switch.
struct MainTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Group {
            switch app.tab {
            case .home: NavigationStack { HomeView() }
            case .challenges: NavigationStack { ChallengesListView() }
            case .map: NavigationStack { MapExploreView() }
            case .contacts: NavigationStack { ContactsView() }
            case .me: NavigationStack { ProfileView() }
            }
        }
        // Tab switches are instant, like the system Health app — this
        // transaction guard guarantees no ambient animation ever sneaks in
        // and fades the content, regardless of what triggered the switch.
        .transaction { $0.animation = nil }
        .safeAreaInset(edge: .bottom) {
            PillTabBar(selection: $app.tab)
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

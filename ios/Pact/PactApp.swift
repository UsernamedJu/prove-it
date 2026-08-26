import SwiftUI

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

    var body: some View {
        @Bindable var app = app
        Group {
            if app.hasOnboarded {
                MainTabView()
            } else {
                OnboardingFlow()
            }
        }
        .animation(Theme.Motion.fade, value: app.hasOnboarded)
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

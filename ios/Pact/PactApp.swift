import SwiftUI

@main
struct PactApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
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

struct MainTabView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            NavigationStack { HomeView() }
                .tabItem { Label(Tab.home.rawValue, systemImage: Tab.home.icon) }
                .tag(Tab.home)

            NavigationStack { ChallengesListView() }
                .tabItem { Label(Tab.challenges.rawValue, systemImage: Tab.challenges.icon) }
                .tag(Tab.challenges)

            NavigationStack { MapExploreView() }
                .tabItem { Label(Tab.map.rawValue, systemImage: Tab.map.icon) }
                .tag(Tab.map)

            NavigationStack { ContactsView() }
                .tabItem { Label(Tab.contacts.rawValue, systemImage: Tab.contacts.icon) }
                .tag(Tab.contacts)

            NavigationStack { ProfileView() }
                .tabItem { Label(Tab.me.rawValue, systemImage: Tab.me.icon) }
                .tag(Tab.me)
        }
        .tint(Theme.Brand.purple)
    }
}

#Preview {
    RootView().environment(AppModel())
}

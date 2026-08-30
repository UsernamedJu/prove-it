import UIKit
import CloudKit

/// The one piece of this app that can't be done in pure SwiftUI: accepting
/// a tapped CKShare link arrives as a dedicated UIKit app-delegate callback
/// (`application(_:userDidAcceptCloudKitShareWith:)`), not as a generic
/// `NSUserActivity` or URL that `.onOpenURL` would see. `PactApp` attaches
/// this via `@UIApplicationDelegateAdaptor` just to catch that one callback
/// and hand it off — everything else about the app stays SwiftUI-native.
///
/// Posts a notification rather than reaching into `AppModel`/
/// `SharedChallengeStore` directly, since an `NSObject`-based delegate has
/// no clean way to hold a `@MainActor @Observable` reference at init time
/// (the App's own `@State` models don't exist yet when the delegate class
/// is instantiated). Whoever's listening — `RootView`, in this app — pairs
/// the metadata with `AppModel.me` to actually accept it.
final class CloudShareDelegate: NSObject, UIApplicationDelegate {
    static let didReceiveShareMetadata = Notification.Name("CloudShareDelegate.didReceiveShareMetadata")

    /// Covers the cold-launch case: the app wasn't running yet when the
    /// share link was tapped, so nothing was around yet to observe the
    /// notification below. `RootView` checks this once on appear.
    static var pendingMetadata: CKShare.Metadata?

    /// Registering here (not gated behind ever creating/joining a shared
    /// challenge first) is what makes silent CloudKit push actually work —
    /// a device token has to exist before `SharedChallengeStore`'s
    /// CKRecordZoneSubscriptions can deliver anything to it. This alone
    /// doesn't prompt the user for anything visible; the *visible*
    /// notification permission (for the "so-and-so made progress" alert)
    /// is requested separately, at the point a shared challenge is
    /// actually created or joined, not at cold launch out of context.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Self.pendingMetadata = cloudKitShareMetadata
        NotificationCenter.default.post(name: Self.didReceiveShareMetadata, object: cloudKitShareMetadata)
    }

    /// A silent push from one of `SharedChallengeStore`'s CKRecordZone
    /// subscriptions — CloudKit itself sends these the instant the other
    /// participant's progress record changes, no server of this app's own
    /// involved. Refreshing here is what makes that real-time: without it,
    /// the same data would still arrive eventually, just only the next
    /// time the app happens to be foregrounded.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                      fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }
        Task {
            await SharedChallengeStore.shared.refreshFromPush()
            completionHandler(.newData)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // No APNs token available (offline, simulator without push
        // support, or the account isn't provisioned for it yet) — refresh-
        // on-foreground still covers the same data, just not instantly.
    }
}

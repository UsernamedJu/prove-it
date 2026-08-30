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

    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Self.pendingMetadata = cloudKitShareMetadata
        NotificationCenter.default.post(name: Self.didReceiveShareMetadata, object: cloudKitShareMetadata)
    }
}

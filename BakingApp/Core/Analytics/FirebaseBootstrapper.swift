import Foundation
import FirebaseCore
import FirebaseCrashlytics

enum FirebaseBootstrapper {
    static func configure(hasPlist: Bool) {
        guard hasPlist else { return }
        FirebaseApp.configure()

        #if DEBUG
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        #else
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        #endif
    }
}


import Foundation

enum AppSettings {

    static let defaults = UserDefaults.standard

    private enum Key {
        static let didShowOnboarding = "settings.didShowOnboarding"
        static let notificationLeadDays = "settings.notificationLeadDays"
        static let weeklyDigestEnabled = "settings.weeklyDigestEnabled"
    }

    static var didShowOnboarding: Bool {
        get { defaults.bool(forKey: Key.didShowOnboarding) }
        set { defaults.set(newValue, forKey: Key.didShowOnboarding) }
    }

    static var notificationLeadDays: Set<Int> {
        get {
            let stored = defaults.array(forKey: Key.notificationLeadDays) as? [Int]
            return Set(stored ?? [0, 1])
        }
        set {
            defaults.set(Array(newValue).sorted(), forKey: Key.notificationLeadDays)
        }
    }

    static var weeklyDigestEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.weeklyDigestEnabled) != nil else { return true }
            return defaults.bool(forKey: Key.weeklyDigestEnabled)
        }
        set { defaults.set(newValue, forKey: Key.weeklyDigestEnabled) }
    }

}

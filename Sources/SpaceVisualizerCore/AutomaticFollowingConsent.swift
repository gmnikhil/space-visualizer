import Foundation

/// Stores only the user's intent to enable automatic following. It deliberately
/// does not represent, infer, or migrate the current macOS TCC authorization.
public protocol AutomaticFollowingConsentStoring: AnyObject {
    var automaticFollowingEnabled: Bool { get set }
}

public final class InMemoryAutomaticFollowingConsentStore: AutomaticFollowingConsentStoring {
    public var automaticFollowingEnabled: Bool

    public init(automaticFollowingEnabled: Bool = false) {
        self.automaticFollowingEnabled = automaticFollowingEnabled
    }
}

public final class UserDefaultsAutomaticFollowingConsentStore: AutomaticFollowingConsentStoring {
    public static let key = "com.spacevisualizer.app.automaticFollowingEnabled"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsAutomaticFollowingConsentStore.key) {
        self.defaults = defaults
        self.key = key
    }

    public var automaticFollowingEnabled: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}

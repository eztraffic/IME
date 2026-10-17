import Foundation

/// Candidate window layout orientation.
public enum CandidateOrientation: String, Codable, Sendable {
    case horizontal = "horizontal"
    case vertical = "vertical"
}

/// Centralized preferences management with UserDefaults persistence and notification broadcasting.
public final class HaoZhuyinPreferences: @unchecked Sendable {
    public static let shared = HaoZhuyinPreferences()

    public static let candidateOrientationKey = "HaoZhuyin.CandidateOrientation"
    public static let spatialToleranceKey = "HaoZhuyin.SpatialToleranceEnabled"
    public static let didChangeNotification = Notification.Name("HaoZhuyin.PreferencesDidChange")

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Candidate window layout orientation (horizontal or vertical).
    public var candidateOrientation: CandidateOrientation {
        get {
            let val = userDefaults.string(forKey: Self.candidateOrientationKey) ?? "horizontal"
            return (val == "vertical") ? .vertical : .horizontal
        }
        set {
            let oldVal = candidateOrientation
            userDefaults.set(newValue.rawValue, forKey: Self.candidateOrientationKey)
            if oldVal != newValue {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            }
        }
    }

    /// Whether adjacent keyboard spatial error tolerance (手滑相鄰按鍵自動修正) is active.
    /// Defaults to `false` (預設未啟用).
    public var isSpatialToleranceEnabled: Bool {
        get {
            if userDefaults.object(forKey: Self.spatialToleranceKey) == nil {
                return false
            }
            return userDefaults.bool(forKey: Self.spatialToleranceKey)
        }
        set {
            let oldVal = isSpatialToleranceEnabled
            userDefaults.set(newValue, forKey: Self.spatialToleranceKey)
            if oldVal != newValue {
                NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            }
        }
    }
}

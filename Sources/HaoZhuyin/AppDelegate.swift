import Cocoa
import InputMethodKit
import ZhuyinEngine

@objc(HaoZhuyinAppDelegate)
public final class HaoZhuyinAppDelegate: NSObject, NSApplicationDelegate {
    public private(set) var server: IMKServer?
    public static private(set) var sharedEngine: ZhuyinEngine = ZhuyinEngine.production()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String ?? "HaoZhuyin_1_Connection"
        let bundleID = Bundle.main.bundleIdentifier ?? "org.antigravity.inputmethod.HaoZhuyin"

        server = IMKServer(name: connectionName, bundleIdentifier: bundleID)
        NSLog("[HaoZhuyin] IMKServer initialized: connectionName=%@, bundleID=%@", connectionName, bundleID)

        // Preload engine in background to eliminate first-keystroke latency
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Self.sharedEngine.lexicon.entries.count
            NSLog("[HaoZhuyin] ZhuyinEngine ready with %ld vocabulary entries.", Self.sharedEngine.lexicon.entries.count)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        Self.sharedEngine.userLexicon.flushSync()
        NSLog("[HaoZhuyin] Flushed user lexicon on app termination.")
    }
}

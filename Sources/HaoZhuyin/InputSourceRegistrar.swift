import Carbon
import Foundation

/// 安裝/移除輔助：讓安裝腳本與 pkg postinstall 直接呼叫 App 本身完成 TIS 註冊，
/// 不再依賴 `swift -e`（使用者電腦不一定有 Swift 工具鏈）。
///
/// 用法：
///   HaoZhuyin.app/Contents/MacOS/HaoZhuyin --register     註冊並啟用輸入來源（冪等）
///   HaoZhuyin.app/Contents/MacOS/HaoZhuyin --unregister   停用所有本輸入法的輸入來源
///   HaoZhuyin.app/Contents/MacOS/HaoZhuyin --status       列出目前 TIS 狀態
enum InputSourceRegistrar {
    static let bundleID = Bundle.main.bundleIdentifier ?? "org.antigravity.inputmethod.HaoZhuyin"

    /// Info.plist 中宣告的可見輸入模式 ID。
    static var modeIDs: [String] {
        let modeDict = Bundle.main.infoDictionary?["ComponentInputModeDict"] as? [String: Any]
        let ordered = modeDict?["tsVisibleInputModeOrderedArrayKey"] as? [String]
        return ordered ?? ["\(bundleID).Zhuyin"]
    }

    /// 處理命令列參數；若為安裝輔助指令則回傳結束碼，否則回傳 nil（正常啟動 IMK 伺服器）。
    static func handle(arguments: [String]) -> Int32? {
        guard arguments.count >= 2 else { return nil }
        switch arguments[1] {
        case "--register": return register()
        case "--unregister": return unregister()
        case "--status": printStatus(); return 0
        default: return nil
        }
    }

    // MARK: - Commands

    static func register() -> Int32 {
        let url = Bundle.main.bundleURL
        let status = TISRegisterInputSource(url as CFURL)
        print("[HaoZhuyin] TISRegisterInputSource(\(url.path)) = \(status)")
        guard status == noErr else { return 1 }

        // TIS 在註冊後可能需要短暫時間才看得到新來源。
        var enabledAny = false
        for _ in 0..<30 {
            let list = sources()
            if !list.isEmpty {
                // 先啟用容器（輸入法本體），再啟用模式；已啟用者略過，避免重複寫入 AppleEnabledInputSources。
                for src in list where sourceType(src) == (kTISTypeKeyboardInputMethodModeEnabled as String) {
                    enableIfNeeded(src)
                }
                for src in list where modeIDs.contains(id(of: src) ?? "") {
                    enableIfNeeded(src)
                    enabledAny = true
                }
                if enabledAny { break }
            }
            usleep(100_000)
        }

        if !enabledAny {
            print("[HaoZhuyin] ⚠️ 找不到可啟用的輸入模式，請登出後再登入，或手動至「系統設定 > 鍵盤 > 輸入方式」加入。")
            return 2
        }
        printStatus()
        return 0
    }

    static func unregister() -> Int32 {
        // TIS 沒有公開的「取消註冊」API；停用所有來源即可讓它從選單與設定中消失。
        for src in sources().reversed() where bool(src, kTISPropertyInputSourceIsEnabled) {
            let err = TISDisableInputSource(src)
            print("[HaoZhuyin] 停用 \(id(of: src) ?? "?") = \(err)")
        }
        return 0
    }

    static func printStatus() {
        let list = sources()
        print("[HaoZhuyin] TIS 來源共 \(list.count) 筆：")
        for src in list {
            print("    \(id(of: src) ?? "?")  enabled=\(bool(src, kTISPropertyInputSourceIsEnabled))  type=\(sourceType(src))")
        }
    }

    // MARK: - Helpers

    private static func sources() -> [TISInputSource] {
        let props = [kTISPropertyBundleID as String: bundleID] as CFDictionary
        return (TISCreateInputSourceList(props, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
    }

    private static func enableIfNeeded(_ src: TISInputSource) {
        guard !bool(src, kTISPropertyInputSourceIsEnabled) else {
            print("[HaoZhuyin] 已啟用（略過）: \(id(of: src) ?? "?")")
            return
        }
        let err = TISEnableInputSource(src)
        print("[HaoZhuyin] 啟用 \(id(of: src) ?? "?") = \(err)")
    }

    private static func property(_ src: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    }

    private static func id(of src: TISInputSource) -> String? {
        property(src, kTISPropertyInputSourceID) as? String
    }

    private static func sourceType(_ src: TISInputSource) -> String {
        (property(src, kTISPropertyInputSourceType) as? String) ?? "?"
    }

    private static func bool(_ src: TISInputSource, _ key: CFString) -> Bool {
        guard let value = property(src, key) else { return false }
        return CFBooleanGetValue((value as! CFBoolean))
    }
}

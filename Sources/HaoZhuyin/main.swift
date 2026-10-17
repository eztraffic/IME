import Cocoa
import InputMethodKit

// 安裝輔助指令（--register / --unregister / --status）：執行後直接結束，不啟動 IMK 伺服器。
if let exitCode = InputSourceRegistrar.handle(arguments: CommandLine.arguments) {
    exit(exitCode)
}

let app = NSApplication.shared
let delegate = HaoZhuyinAppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

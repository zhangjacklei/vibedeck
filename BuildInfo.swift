//
//  BuildInfo.swift
//  vibedeck
//
//  构建身份：界面、菜单栏、日志、--diag 四处显示同一个 build 号，
//  避免"改了代码但跑的是旧包/旧进程"这种问题无法分辨。
//

import Foundation

enum BuildInfo {
    /// 命令行运行时没有 Info.plist；退而从同目录的 .app 读取，保证版本号一致
    private static func plistValue(_ key: String) -> String? {
        if let v = Bundle.main.object(forInfoDictionaryKey: key) as? String { return v }
        let exe = CommandLine.arguments.first ?? ""
        let dir = (exe as NSString).deletingLastPathComponent
        let plist = dir + "/vibedeck.app/Contents/Info.plist"
        return NSDictionary(contentsOfFile: plist)?[key] as? String
    }

    /// 语义版本（每次发布递增）
    static let version: String = plistValue("CFBundleShortVersionString") ?? "dev"

    /// 唯一构建号，由 create_app_bundle.sh 用时间戳生成
    static let build: String = plistValue("CFBundleVersion") ?? "CLI"

    /// 侧边栏 / 菜单栏 / 日志统一显示
    static var short: String { "v\(version) · \(build)" }

    static var isAppBundle: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    static var bundlePath: String { Bundle.main.bundlePath }

    /// 可执行文件落盘时间：即使从 CLI 启动（读不到 Info.plist）也能核对新旧
    static var binaryStamp: String {
        let path = Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else { return "unknown" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    /// 启动时写日志，方便事后确认用户看到的是哪个包
    static func logStartup() {
        PermissionPrimer.log("📦 vibedeck \(short) | bundle=\(bundlePath) | binary=\(binaryStamp)")
    }
}

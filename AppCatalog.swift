//
//  AppCatalog.swift
//  vibedeck
//
//  扫描系统里已安装的 App，供「打开 App」直接选择，不再让用户手填。
//

import Foundation
import AppKit
import Combine

struct InstalledApp: Identifiable, Hashable {
    let id: String          // bundle id（没有则为路径）
    let name: String        // 显示名
    let path: String        // .app 路径
    var icon: NSImage? { NSWorkspace.shared.icon(forFile: path) }
}

final class AppCatalog: ObservableObject {
    static let shared = AppCatalog()

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var loading = false

    private var loaded = false

    /// 常见安装位置（用户级 + 系统级 + 工具目录）
    private let searchPaths: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications"
    ]

    private init() {}

    /// 首次使用时扫描一次；reload() 可强制重扫
    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        reload()
    }

    func reload() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var found: [String: InstalledApp] = [:]

            for root in self.searchPaths {
                guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
                for entry in entries where entry.hasSuffix(".app") {
                    let path = root + "/" + entry
                    let url = URL(fileURLWithPath: path)
                    guard let bundle = Bundle(url: url) else { continue }
                    // 仅保留可启动的普通 App（跳过 background-only / 无界面组件）
                    if let background = bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool, background {
                        continue
                    }
                    let bundleID = bundle.bundleIdentifier ?? path
                    let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                        ?? entry.replacingOccurrences(of: ".app", with: "")
                    if found[bundleID] == nil {
                        found[bundleID] = InstalledApp(id: bundleID, name: name, path: path)
                    }
                }
            }

            let sorted = found.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            DispatchQueue.main.async {
                self.apps = sorted
                self.loading = false
                PermissionPrimer.log("📦 已载入 \(sorted.count) 个可启动 App")
            }
        }
    }

    /// 按 bundle id / 名称 / 路径反查，用于把已存的旧值显示成友好名称
    func app(matching value: String) -> InstalledApp? {
        guard !value.isEmpty else { return nil }
        if let exact = apps.first(where: { $0.id == value }) { return exact }
        if let byPath = apps.first(where: { $0.path == value }) { return byPath }
        let lower = value.lowercased()
        return apps.first { $0.name.lowercased() == lower }
    }
}

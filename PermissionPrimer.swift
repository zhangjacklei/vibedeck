//
//  PermissionPrimer.swift
//  vibedeck
//
//  启动时主动向 TCC 登记本二进制并弹出系统授权框。
//  没有这一步，用户必须在「系统设置 ▸ 隐私与安全性」里手动点 “+” 找到
//  Remotastic.app 才会出现在列表里——这是同类项目最常见的卡点。
//

import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

enum PermissionPrimer {
    /// 简单文件日志：用 `open` 启动时 stdout 会被丢弃，权限状态只能靠这个查。
    static func log(_ message: String) {
        print(message)
        let path = "/tmp/vibedeck.log"
        let line = "[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] \(message)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    static func promptIfNeeded() {
        // 辅助功能（移动指针 / 点击 / 注入按键）
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
            log("🔐 Accessibility prompt shown (trusted now: \(trusted))")
        } else {
            log("🔐 Accessibility: already granted")
        }

        // 输入监控（读取遥控器 HID 按键事件）
        // 与界面/诊断共用 PermissionCenter：监听通道实测可用就不再重复弹授权框
        let center = PermissionCenter.shared
        center.refreshSync()
        if !center.inputMonitoringGranted {
            _ = CGRequestListenEventAccess()
            center.refreshSync()
            let granted = center.inputMonitoringGranted
            log("🔐 Input Monitoring requested (effective now: \(granted))")
            if !granted {
                log("   ↳ 若系统设置里开关已开：把 vibedeck 的开关关掉再打开一次（必要时移除后重加），")
                log("     用于刷新已失效的旧签名记录；bundle id = \(Bundle.main.bundleIdentifier ?? "?")")
            }
        } else {
            log("🔐 Input Monitoring: already granted")
        }
    }
}

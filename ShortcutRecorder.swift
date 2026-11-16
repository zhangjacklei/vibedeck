//
//  ShortcutRecorder.swift
//  vibedeck
//
//  「录制按键」：点一下按钮，直接在实体键盘上按出想要的键或组合，
//  自动回填成 cmd+shift+p 这种字符串，不必记键名。
//  只监听本 App 的键盘事件，不申请全局输入监控权限。
//

import AppKit
import SwiftUI
import Combine
import CoreGraphics

final class ShortcutRecorder: ObservableObject {
    static let shared = ShortcutRecorder()

    @Published private(set) var isRecording = false

    private var monitor: Any?
    private var onCapture: ((String) -> Void)?

    func start(capture: @escaping (String) -> Void) {
        stop()
        onCapture = capture
        isRecording = true

        // 保证设置窗口在前且能接收键盘事件
        SettingsWindowController.shared.show()

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }

            // 只按下修饰键时继续等待主键
            if event.type == .flagsChanged { return event }

            // Esc 本身也是常用按键，允许正常录制；取消请点界面上的按钮
            if let combo = ShortcutRecorder.combo(from: event) {
                let captured = combo
                DispatchQueue.main.async {
                    self.onCapture?(captured)
                    self.stop()
                }
            } else {
                PermissionPrimer.log("⌨️ 录制失败：无法识别 keyCode=\(event.keyCode)")
            }
            // 吞掉事件，避免落到背后的输入框里
            return nil
        }
    }

    func stop() {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onCapture = nil
        if isRecording { isRecording = false }
    }

    /// NSEvent → 规范 combo 字符串
    static func combo(from event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []
        if flags.contains(.command) { parts.append("cmd") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.option) { parts.append("opt") }
        if flags.contains(.control) { parts.append("ctrl") }
        // 注意：.function 是 F1–F12 自带的标记，不能再加 fn 修饰
        // .capsLock 不参与组合

        let code = CGKeyCode(event.keyCode)
        guard !KeySender.modifierKeyCodes.contains(code),
              let name = KeySender.nameByCode[code] else { return nil }
        parts.append(name)
        return parts.joined(separator: "+")
    }
}

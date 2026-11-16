//
//  KeySender.swift
//  vibedeck
//
//  键盘事件合成：任意按键 / 任意组合 / 多组连续动作。
//  全部走 CGEvent，需要「辅助功能」授权（应用启动时已引导）。
//
//  写法支持：
//   - 单键        j、esc、f5、space、up
//   - 组合        cmd+shift+p、ctrl+alt+right、fn+f5
//   - 符号写法    ⌘⇧P、⌃C、⌥⎋
//   - 连续多组    cmd+c, cmd+v  （也可用 ; 、| 或中文逗号分隔）
//   - 常用别名    command/control/option/alt/enter/del/pgup/arrowleft…
//   - 符号键      plus (= shift+=)、问号等用别名 plus
//

import Foundation
import AppKit
import CoreGraphics

enum KeySender {
    static let modifiers: [String: CGKeyCode] = [
        "cmd": 55, "command": 55,
        "shift": 56,
        "caps": 57, "capslock": 57,
        "opt": 58, "option": 58, "alt": 58,
        "ctrl": 59, "control": 59,
        "fn": 63
    ]

    static let keys: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51,
        "backspace": 51, "forwarddelete": 117,
        "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126
    ]

    static let prettyNames: [String: String] = [
        "return": "↩", "enter": "↩", "escape": "esc", "esc": "esc",
        "space": "空格", "tab": "⇥", "delete": "⌫", "backspace": "⌫",
        "forwarddelete": "⌦", "home": "↖", "end": "↘",
        "pageup": "⇞", "pagedown": "⇟",
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "cmd": "⌘", "command": "⌘", "shift": "⇧", "opt": "⌥", "option": "⌥",
        "alt": "⌥", "ctrl": "⌃", "control": "⌃", "fn": "fn"
    ]

    /// 用户可能写出的别名 → 规范 token（值里可以带 "+"，会展开成多个 token）
    static let aliases: [String: String] = [
        "command": "cmd", "⌘": "cmd",
        "control": "ctrl", "ctl": "ctrl", "⌃": "ctrl",
        "option": "opt", "alt": "opt", "⌥": "opt",
        "shift": "shift", "⇧": "shift",
        "function": "fn", "fn": "fn",
        "escape": "escape", "esc": "escape", "⎋": "escape",
        "enter": "return", "⏎": "return", "↵": "return",
        "⇥": "tab", "spacebar": "space", "空格": "space",
        "del": "delete", "backspace": "delete", "⌫": "delete",
        "⌦": "forwarddelete", "fwddelete": "forwarddelete",
        "pgup": "pageup", "pgdn": "pagedown",
        "arrowleft": "left", "arrowright": "right",
        "arrowup": "up", "arrowdown": "down",
        "←": "left", "→": "right", "↑": "up", "↓": "down",
        // 需要 Shift 才能打出的符号，直接展开成标准组合
        "plus": "shift+=", "加号": "shift+="
    ]

    /// 键码 → 规范键名（供「录制按键」反查）
    static let nameByCode: [CGKeyCode: String] = {
        var out: [CGKeyCode: String] = [:]
        for (name, code) in keys where out[code] == nil { out[code] = name }
        let preferred: [CGKeyCode: String] = [
            36: "return", 48: "tab", 49: "space", 51: "delete", 53: "escape",
            117: "forwarddelete", 115: "home", 119: "end",
            116: "pageup", 121: "pagedown",
            123: "left", 124: "right", 125: "down", 126: "up",
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
            98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12"
        ]
        for (code, name) in preferred { out[code] = name }
        return out
    }()

    static var modifierKeyCodes: Set<CGKeyCode> { Set(modifiers.values) }

    // MARK: - 规范化 / 校验

    /// 把任意写法统一成 `cmd+shift+p,cmd+v` 形式
    static func normalize(_ combo: String) -> String {
        var text = combo.trimmingCharacters(in: .whitespacesAndNewlines)
        // 注意：不能把 "→" 当分隔符，它是右方向键的写法
        text = text.replacingOccurrences(of: ";", with: ",")
                   .replacingOccurrences(of: "，", with: ",")
                   .replacingOccurrences(of: "|", with: ",")

        // 修饰键符号自带分隔符，方便 ⌘⇧P 这种连写
        let symbolPrefix: [Character: String] = [
            "⌘": "cmd+", "⇧": "shift+", "⌥": "opt+", "⌃": "ctrl+"
        ]
        var expanded = ""
        for ch in text {
            if let repl = symbolPrefix[ch] { expanded += repl }
            else { expanded.append(ch) }
        }

        let steps = expanded.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        var result: [String] = []
        for step in steps where !step.isEmpty {
            let rawParts = step.split(separator: "+", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            var parts: [String] = []
            for raw in rawParts {
                let mapped = aliases[raw] ?? raw
                parts.append(contentsOf: mapped.split(separator: "+").map(String.init))
            }
            if !parts.isEmpty { result.append(parts.joined(separator: "+")) }
        }
        return result.joined(separator: ",")
    }

    /// 返回错误说明；nil 表示可以正常发送
    static func validate(_ combo: String) -> String? {
        guard !combo.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        for step in normalize(combo).split(separator: ",") {
            let parts = step.split(separator: "+").map(String.init)
            guard let main = parts.last else { continue }
            guard keys[main] != nil else { return "未知按键「\(main)」" }
            for mod in parts.dropLast() where modifiers[mod] == nil {
                return "未知修饰键「\(mod)」"
            }
        }
        return nil
    }

    /// "cmd+shift+p" → "⌘⇧P"；多组用空格分隔
    static func prettyCombo(_ combo: String) -> String {
        normalize(combo).split(separator: ",")
            .map { prettyOne(String($0)) }
            .joined(separator: "  ")
    }

    private static func prettyOne(_ step: String) -> String {
        let parts = step.split(separator: "+").map { String($0).lowercased() }
        guard let last = parts.last else { return step }
        var out = ""
        for part in parts.dropLast() { out += prettyNames[part] ?? part }
        return out + (prettyNames[last] ?? last.uppercased())
    }

    // MARK: - 发送

    @discardableResult
    static func send(combo: String) -> Bool {
        let steps = normalize(combo).split(separator: ",").map(String.init)
        guard !steps.isEmpty else { return false }
        var allOK = true
        for (index, step) in steps.enumerated() {
            if index > 0 { usleep(70_000) }
            if !sendOne(step) { allOK = false }
        }
        return allOK
    }

    private static func sendOne(_ step: String) -> Bool {
        if let problem = validate(step) {
            PermissionPrimer.log("⌨️ 快捷键无效：\(step)（\(problem)）")
            return false
        }
        let parts = step.split(separator: "+").map { String($0).lowercased() }
        guard let mainName = parts.last, let mainCode = keys[mainName] else { return false }

        var flags: CGEventFlags = []
        var extraModifiers: [CGKeyCode] = []
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default:
                if let code = modifiers[part] { extraModifiers.append(code) }
            }
        }

        let source = CGEventSource(stateID: .hidSystemState)
        for code in extraModifiers {
            CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
        }
        if let down = CGEvent(keyboardEventSource: source, virtualKey: mainCode, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        usleep(12_000)
        if let up = CGEvent(keyboardEventSource: source, virtualKey: mainCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
        for code in extraModifiers.reversed() {
            CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
        }
        return true
    }

    /// 逐字输入（不受键盘布局影响）
    static func type(text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for scalar in text.unicodeScalars {
            var buffer = Array(String(scalar).utf16)
            guard !buffer.isEmpty else { continue }
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
                up.post(tap: .cghidEventTap)
            }
            usleep(4_000)
        }
    }

    /// 通过剪贴板 + ⌘V 粘贴（中文等长文本比逐字输入快且不乱序）
    static func paste(text: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        usleep(30_000)
        send(combo: "cmd+v")
        // 还原剪贴板（避免污染用户内容），延迟一点等粘贴完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if let previous = previous {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }
}

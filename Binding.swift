//
//  Binding.swift
//  Remotastic (local fork)
//
//  按键映射模型：替换原先受限的 ButtonAction 枚举。
//  支持任意键盘组合、文本、媒体键、鼠标、听写、启动 App、shell。
//

import Foundation
import Combine

enum BindingKind: String, Codable, CaseIterable, Identifiable {
    case none
    case keystroke
    case text
    case playPause
    case nextTrack
    case previousTrack
    case volumeUp
    case volumeDown
    case mute
    case click
    case rightClick
    case scrollUp
    case scrollDown
    case missionControl
    case dictation
    case launchApp
    case shell

    var id: String { rawValue }

    /// 面向中文界面的显示名
    var title: String {
        switch self {
        case .none: return "不执行"
        case .keystroke: return "键盘快捷键"
        case .text: return "输入文本"
        case .playPause: return "播放 / 暂停"
        case .nextTrack: return "下一首"
        case .previousTrack: return "上一首"
        case .volumeUp: return "音量 +"
        case .volumeDown: return "音量 −"
        case .mute: return "静音"
        case .click: return "鼠标左键"
        case .rightClick: return "鼠标右键"
        case .scrollUp: return "向上滚动"
        case .scrollDown: return "向下滚动"
        case .missionControl: return "调度中心"
        case .dictation: return "按住语音输入"
        case .launchApp: return "打开 App"
        case .shell: return "运行命令"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "slash.circle"
        case .keystroke: return "keyboard"
        case .text: return "text.cursor"
        case .playPause: return "playpause.fill"
        case .nextTrack: return "forward.fill"
        case .previousTrack: return "backward.fill"
        case .volumeUp: return "speaker.plus.fill"
        case .volumeDown: return "speaker.minus.fill"
        case .mute: return "speaker.slash.fill"
        case .click: return "cursorarrow.click"
        case .rightClick: return "cursorarrow.click.2"
        case .scrollUp: return "arrow.up.circle"
        case .scrollDown: return "arrow.down.circle"
        case .missionControl: return "rectangle.3.group"
        case .dictation: return "mic.fill"
        case .launchApp: return "app.badge"
        case .shell: return "terminal"
        }
    }

    /// 值的语义分组：切换动作时只有同组才保留旧值
    var valueGroup: String {
        switch self {
        case .keystroke: return "key"
        case .text: return "text"
        case .launchApp: return "app"
        case .shell: return "shell"
        default: return "none"
        }
    }

    /// 需要用户再填一个值（快捷键/文本/App/命令）
    var needsValue: Bool {
        switch self {
        case .keystroke, .text, .launchApp, .shell: return true
        default: return false
        }
    }

    var valuePlaceholder: String {
        switch self {
        case .keystroke: return "直接输入或点录制 · 例 cmd+shift+p、j、f5、cmd+c, cmd+v"
        case .text: return "要逐字输入的文本"
        case .launchApp: return "App 名称，如 Terminal / Xcode"
        case .shell: return "shell 命令，如 open -a Terminal"
        default: return ""
        }
    }
}

struct ButtonBinding: Codable, Equatable {
    var kind: BindingKind = .none
    var value: String = ""

    static let none = ButtonBinding()

    /// 菜单 / 卡片上的一行摘要
    var summary: String {
        switch kind {
        case .none: return "未设置"
        case .keystroke: return value.isEmpty ? "未指定快捷键" : KeySender.prettyCombo(value)
        case .text: return value.isEmpty ? "未指定文本" : "“\(value)”"
        case .launchApp:
            if value.isEmpty { return "未指定 App" }
            return AppCatalog.shared.app(matching: value)?.name ?? value
        case .shell: return value.isEmpty ? "未指定命令" : value
        default: return kind.title
        }
    }
}

/// 遥控器上的可配置热区。顺序即 UI 中的排列顺序。
enum RemoteButton: String, Codable, CaseIterable, Identifiable {
    case power
    case mute
    case volumeUp
    case volumeDown
    case playPause
    case menu
    case tv
    case siri
    case ringUp
    case ringDown
    case ringLeft
    case ringRight
    case select

    var id: String { rawValue }

    var title: String {
        switch self {
        case .power: return "电源"
        case .mute: return "静音"
        case .volumeUp: return "音量 +"
        case .volumeDown: return "音量 −"
        case .playPause: return "播放 / 暂停"
        case .menu: return "返回 ‹"
        case .tv: return "TV / 主页"
        case .siri: return "语音（Siri 键）"
        case .ringUp: return "圆环 · 上"
        case .ringDown: return "圆环 · 下"
        case .ringLeft: return "圆环 · 左"
        case .ringRight: return "圆环 · 右"
        case .select: return "触控板点按"
        }
    }

    var hint: String {
        switch self {
        case .power: return "macOS 的 loginwindow 会先截获电源键，应用层基本无法拦截"
        case .mute: return "遥控器侧面的静音键"
        case .volumeUp: return "遥控器右侧音量键"
        case .volumeDown: return "遥控器右侧音量键"
        case .playPause: return "触控板下方的播放/暂停"
        case .menu: return "触控板左上角的返回键"
        case .tv: return "触控板左上角的 TV 键"
        case .siri: return "遥控器右侧的语音键，默认按住说话"
        case .ringUp, .ringDown, .ringLeft, .ringRight: return "按圆环的四个方向"
        case .select: return "按下触控板中心"
        }
    }
}

/// 全局映射仓库（UserDefaults 持久化，兼容旧的 buttonMappings 字符串）
final class BindingStore: ObservableObject {
    static let shared = BindingStore()

    private let storageKey = "bindings.v2"
    private let legacyKey = "buttonMappings"

    @Published private(set) var bindings: [String: ButtonBinding] = [:]

    private init() {
        load()
    }

    static let defaults: [RemoteButton: ButtonBinding] = [
        .playPause: ButtonBinding(kind: .keystroke, value: "return"),
        .menu: ButtonBinding(kind: .keystroke, value: "escape"),
        .tv: ButtonBinding(kind: .missionControl),
        .siri: ButtonBinding(kind: .dictation),
        .select: ButtonBinding(kind: .click),
        .volumeUp: ButtonBinding(kind: .volumeUp),
        .volumeDown: ButtonBinding(kind: .volumeDown),
        .mute: ButtonBinding(kind: .mute),
        .power: ButtonBinding(kind: .none),
        .ringUp: ButtonBinding(kind: .keystroke, value: "up"),
        .ringDown: ButtonBinding(kind: .keystroke, value: "down"),
        .ringLeft: ButtonBinding(kind: .keystroke, value: "left"),
        .ringRight: ButtonBinding(kind: .keystroke, value: "right")
    ]

    func binding(for button: String) -> ButtonBinding {
        bindings[button] ?? .none
    }

    func set(_ binding: ButtonBinding, for button: String) {
        bindings[button] = binding
        save()
    }

    func resetToDefaults() {
        bindings = [:]
        for (button, binding) in BindingStore.defaults {
            bindings[button.rawValue] = binding
        }
        save()
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: ButtonBinding].self, from: data) {
            bindings = sanitize(decoded)
            fillMissing()
            return
        }
        // 迁移旧 bundle id 域下的配置（改名/换 identifier 后不该丢用户设置）
        if let legacySuite = UserDefaults(suiteName: "com.remotastic.app"),
           let data = legacySuite.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: ButtonBinding].self, from: data) {
            bindings = sanitize(decoded)
            fillMissing()
            save()
            PermissionPrimer.log("⚙️ 已从旧 bundle id 域迁移 \(decoded.count) 条按键配置")
            return
        }

        // 迁移旧格式（ButtonAction 的 rawValue 字符串）
        if let legacy = UserDefaults.standard.dictionary(forKey: legacyKey) as? [String: String] {
            var migrated: [String: ButtonBinding] = [:]
            for (button, raw) in legacy {
                migrated[button] = BindingStore.migrateLegacy(raw)
            }
            bindings = migrated
            fillMissing()
            save()
            return
        }
        resetToDefaults()
    }

    /// 清理历史遗留的无效值：例如「打开 App」下残留的 "return" 这类快捷键值
    private func sanitize(_ input: [String: ButtonBinding]) -> [String: ButtonBinding] {
        var output = input
        for (key, binding) in input where binding.kind == .launchApp {
            let value = binding.value
            let looksLikeApp = value.contains(".") || value.contains("/")
            if !value.isEmpty && !looksLikeApp {
                output[key] = ButtonBinding(kind: .launchApp, value: "")
            }
        }
        return output
    }

    private func fillMissing() {
        for (button, binding) in BindingStore.defaults where bindings[button.rawValue] == nil {
            bindings[button.rawValue] = binding
        }
    }

    private static func migrateLegacy(_ raw: String) -> ButtonBinding {
        switch raw {
        case "None": return ButtonBinding(kind: .none)
        case "Play/Pause": return ButtonBinding(kind: .playPause)
        case "Next Track": return ButtonBinding(kind: .nextTrack)
        case "Previous Track": return ButtonBinding(kind: .previousTrack)
        case "Volume Up": return ButtonBinding(kind: .volumeUp)
        case "Volume Down": return ButtonBinding(kind: .volumeDown)
        case "Mute": return ButtonBinding(kind: .mute)
        case "Mouse Click": return ButtonBinding(kind: .click)
        case "Right Click": return ButtonBinding(kind: .rightClick)
        case "Escape": return ButtonBinding(kind: .keystroke, value: "escape")
        case "Space": return ButtonBinding(kind: .keystroke, value: "space")
        case "Enter": return ButtonBinding(kind: .keystroke, value: "return")
        case "Mission Control": return ButtonBinding(kind: .missionControl)
        default: return ButtonBinding(kind: .none)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(bindings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        // 同步一份旧键，方便旧版菜单/兼容逻辑读取
        var legacy: [String: String] = [:]
        for (button, binding) in bindings {
            legacy[button] = binding.kind.rawValue
        }
        UserDefaults.standard.set(legacy, forKey: legacyKey)
    }
}

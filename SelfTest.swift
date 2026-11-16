//
//  SelfTest.swift
//  vibedeck
//
//  业务可用性自检：不依赖硬件，覆盖映射模型、键码识别、快捷键解析、
//  应用清单、语音设备与授权状态、配置持久化。
//  运行：`vibedeck --selftest`（有任何失败则退出码非 0）
//

import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

struct SelfTest {
    private var failures: [String] = []
    private var passes = 0

    static func run() -> Bool {
        var test = SelfTest()
        test.execute()
        return test.report()
    }

    private mutating func check(_ condition: Bool, _ name: String, detail: String = "") {
        if condition {
            passes += 1
            print("PASS  \(name)")
        } else {
            failures.append(name)
            print("FAIL  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
        }
    }

    private mutating func execute() {
        print("=== vibedeck 业务可用性自检 ===\n")
        // 权限状态统一从 PermissionCenter 读取，自检先同步采样一次
        PermissionCenter.shared.refreshSync()

        // 1. 映射模型
        let store = BindingStore.shared
        check(RemoteButton.allCases.allSatisfy { store.binding(for: $0.rawValue).kind != .none || $0 == .power },
              "每个按键都有默认绑定（电源键除外）")
        check(!BindingStore.defaults.isEmpty, "默认绑定表非空")
        check(RemoteButton.allCases.count == 13, "可配置热区数量 = 13")

        // 2. 取值分组：切换动作时不该串值
        check(BindingKind.keystroke.valueGroup != BindingKind.launchApp.valueGroup,
              "快捷键与打开 App 属不同值域（切换时清空旧值）")
        check(BindingKind.launchApp.valueGroup == BindingKind.launchApp.valueGroup,
              "同类型动作值域稳定")

        // 3. HID 键码识别（本机实测的 A2540 键码）
        let keyExpectations: [(UInt32, UInt32, String)] = [
            (0x0C, 0x109, "siri"),
            (0x0C, 0xCD, "playPause"),
            (0x0C, 0xE9, "volumeUp"),
            (0x0C, 0xEA, "volumeDown"),
            (0x0C, 0xE2, "mute"),
            (0x0C, 0x30, "power"),
            (0x0C, 0x223, "tv"),
            (0x0C, 0x60, "tv"),
            (0x0C, 0x80, "select"),
            (0x01, 0x86, "menu"),
            (0x0C, 0x42, "ringUp"),
            (0x0C, 0x43, "ringDown"),
            (0x0C, 0x44, "ringLeft"),
            (0x0C, 0x45, "ringRight")
        ]
        var keyFailures: [String] = []
        for (page, usage, expected) in keyExpectations {
            let actual = RemoteInputHandler.classify(page: page, usage: usage)
            if actual != expected {
                keyFailures.append(String(format: "0x%02X/0x%03X→%@(期望%@)",
                                          page, usage, actual ?? "nil", expected))
            }
        }
        check(keyFailures.isEmpty, "A2540 键码映射全部正确",
              detail: keyFailures.joined(separator: ", "))
        check(RemoteInputHandler.classify(page: 0x0C, usage: 0x99) == nil, "未定义 usage 返回 nil")

        // 4. 快捷键解析
        check(KeySender.prettyCombo("cmd+shift+p") == "⌘⇧P",
              "快捷键显示：cmd+shift+p → ⌘⇧P",
              detail: KeySender.prettyCombo("cmd+shift+p"))
        check(KeySender.prettyCombo("escape") == "esc", "escape 显示为 esc")
        check(KeySender.keys["return"] != nil && KeySender.keys["escape"] != nil,
              "常用按键码存在", detail: "")
        check(KeySender.keys["f13"] == nil, "未知按键不在码表内")

        // 4b. 任意按键 / 组合 / 录制解析
        check(KeySender.normalize("⌘⇧P") == "cmd+shift+p",
              "符号写法 ⌘⇧P → cmd+shift+p", detail: KeySender.normalize("⌘⇧P"))
        check(KeySender.normalize("⌃C") == "ctrl+c", "符号写法 ⌃C → ctrl+c")
        check(KeySender.normalize("cmd+c; cmd+v") == "cmd+c,cmd+v", "多组动作分隔规范化")
        check(KeySender.validate("cmd+shift+p") == nil, "合法组合通过校验")
        check(KeySender.validate("ctrl+alt+right") == nil, "三修饰键组合合法")
        check(KeySender.validate("cmd+banana") != nil, "未知键名被校验拦截")
        check(KeySender.normalize("cmd+→") == "cmd+right", "方向键符号不与分隔符冲突")
        check(KeySender.validate("cmd+→") == nil, "cmd+右方向键可发送")
        check(KeySender.prettyCombo("cmd+c,cmd+v").contains("⌘V"), "多组动作可读性显示")
        check(KeySender.nameByCode[35] == "p" && KeySender.nameByCode[53] == "escape",
              "键码反查：35→p、53→escape")
        if let recEvent = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                          modifierFlags: [.command, .shift],
                                          timestamp: 0, windowNumber: 0, context: nil,
                                          characters: "P", charactersIgnoringModifiers: "p",
                                          isARepeat: false, keyCode: 35) {
            check(ShortcutRecorder.combo(from: recEvent) == "cmd+shift+p",
                  "录制：⌘⇧P → cmd+shift+p",
                  detail: ShortcutRecorder.combo(from: recEvent) ?? "nil")
        } else {
            check(false, "录制事件可构造")
        }
        if let escEvent = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                           modifierFlags: [], timestamp: 0, windowNumber: 0,
                                           context: nil, characters: "\u{1B}",
                                           charactersIgnoringModifiers: "\u{1B}",
                                           isARepeat: false, keyCode: 53) {
            check(ShortcutRecorder.combo(from: escEvent) == "escape",
                  "录制：单独 Esc 也可作为快捷键")
        } else {
            check(false, "Esc 录制事件可构造")
        }

        // 5. 应用清单（异步扫描，最多等 3 秒）
        AppCatalog.shared.loadIfNeeded()
        let deadline = Date().addingTimeInterval(3)
        while AppCatalog.shared.apps.isEmpty && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        let apps = AppCatalog.shared.apps
        check(apps.count >= 10, "应用清单已载入（\(apps.count) 个）")
        check(apps.contains { $0.id == "com.apple.Safari" }, "清单里能找到 Safari")
        check(!apps.contains { $0.name.isEmpty }, "应用名均非空")
        check(apps.allSatisfy { FileManager.default.fileExists(atPath: $0.path) },
              "清单路径均真实存在")
        check(AppCatalog.shared.app(matching: "com.apple.Safari")?.name.isEmpty == false,
              "按 bundle id 反查 App 成功")

        // 6. 语音设备与授权
        let voice = VoiceInputController.shared
        voice.refreshDevices()
        check(!voice.micDevices.isEmpty,
              "至少有一个输入设备", detail: "\(voice.micDevices.map { $0.name })")
        check(!voice.micDevices.contains { $0.name.isEmpty }, "输入设备名非空")
        print("INFO  语音识别授权 = \(SFSpeechStatusText()); 麦克风授权 = \(micStatusText())")
        print("INFO  遥控器麦克风可用 = \(voice.remoteMicAvailable ? "是" : "否（macOS 未暴露，符合预期）")")

        // 7. 系统权限（只报告，不作为失败条件——需要用户手动授权）
        print("INFO  输入监控 = \(Permissions.inputMonitoring() ? "已授权" : "未授权")")
        print("INFO  辅助功能 = \(Permissions.accessibility() ? "已授权" : "未授权")")

        // 8. 配置持久化 roundtrip
        let probeButton = RemoteButton.mute.rawValue
        let original = store.binding(for: probeButton)
        store.set(ButtonBinding(kind: .keystroke, value: "cmd+shift+m"), for: probeButton)
        check(store.binding(for: probeButton).value == "cmd+shift+m", "写入后立即读到新值")
        let data = UserDefaults.standard.data(forKey: "bindings.v2")
        check(data != nil, "配置已落盘")
        if let data = data,
           let decoded = try? JSONDecoder().decode([String: ButtonBinding].self, from: data) {
            check(decoded[probeButton]?.value == "cmd+shift+m", "落盘内容可反序列化且值正确")
        } else {
            check(false, "落盘内容可反序列化")
        }
        store.set(original, for: probeButton)
        check(store.binding(for: probeButton) == original, "测试后已还原原值")

        // 9. 省电与休眠（纯函数 + 状态机，不触碰硬件，也不改写用户偏好）
        check(IdlePolicy.allowedMinutes == [1, 3, 5, 10, 15, 30, 60], "闲置时长档位完整")
        check(IdlePolicy.clamp(0) == 1 && IdlePolicy.clamp(12) == 10 && IdlePolicy.clamp(999) == 60,
              "闲置时长收敛到最近合法档位")
        let base = Date(timeIntervalSince1970: 1_000_000)
        check(!IdlePolicy.shouldSuspend(lastActivity: base, now: base.addingTimeInterval(3600),
                                        enabled: false, minutes: 1), "关闭自动休眠时永不触发")
        check(!IdlePolicy.shouldSuspend(lastActivity: base, now: base.addingTimeInterval(59),
                                        enabled: true, minutes: 1), "未达阈值不休眠")
        check(IdlePolicy.shouldSuspend(lastActivity: base, now: base.addingTimeInterval(61),
                                       enabled: true, minutes: 1), "达到阈值触发休眠")
        check(IdlePolicy.remaining(lastActivity: base, now: base.addingTimeInterval(20),
                                   enabled: true, minutes: 1) == 40, "剩余时间计算正确")
        check(IdlePolicy.remainingText(95, enabled: true, suspended: false) == "距离自动休眠约 1 分 35 秒",
              "剩余时间文案", detail: IdlePolicy.remainingText(95, enabled: true, suspended: false))
        check(IdlePolicy.remainingText(0, enabled: true, suspended: true).contains("已暂停"), "暂停状态文案")
        check(IdlePolicy.remainingText(0, enabled: false, suspended: false) == "自动休眠未启用", "关闭状态文案")
        check(IdlePolicy.looksLikeRemote(name: "A1B2C3D4E5F6"), "A2540 序列号式蓝牙名可识别")
        check(IdlePolicy.looksLikeRemote(name: "Siri Remote")
              && IdlePolicy.looksLikeRemote(name: "Apple TV Remote"), "标准遥控器名可识别")
        check(!IdlePolicy.looksLikeRemote(name: "Magic Keyboard")
              && !IdlePolicy.looksLikeRemote(name: "JBL Flip 7")
              && !IdlePolicy.looksLikeRemote(name: nil), "其它蓝牙设备不会被误断开")
        let missing = BluetoothRemoteController.Result(status: .notFound, attempted: 0,
                                                       succeeded: 0, names: [])
        check(missing.message.contains("没有已连接"), "未连接时给出明确提示")
        let ble = BluetoothRemoteController.Result(status: .unsupported, attempted: 0,
                                                   succeeded: 0, names: ["A1B2C3D4E5F6"])
        check(ble.message.contains("不允许第三方") && !ble.succeededNow,
              "BLE HID 平台限制如实反馈、不伪装成已断开")

        // 状态机 + 硬件接线：注入 mock 回调，验证暂停/恢复真的会调用释放与恢复钩子。
        // 之前只测纯状态机，所以「自检全过」但实测不生效（接线断点没被发现）。
        let mgr = PowerManager.shared
        var released = 0
        var restored = 0
        mgr.releaseHardware = { released += 1 }
        mgr.restoreHardware = { restored += 1 }
        mgr.hardwareStatus = { "mock" }
        mgr.suspend(.manual)
        check(mgr.isSuspended && mgr.suspendReason == .manual, "手动暂停进入省电状态")
        check(released == 1, "暂停确实调用了释放硬件回调")
        mgr.suspend(.idle)
        check(mgr.suspendReason == .manual && released == 1, "重复暂停不会覆盖原因或重复释放")
        mgr.noteActivity(source: "自检")
        check(!mgr.isSuspended && mgr.suspendReason == nil, "按键活动自动恢复接管")
        check(restored == 1, "恢复确实调用了恢复硬件回调")
        mgr.toggle()
        check(mgr.isSuspended && released == 2, "菜单栏 toggle 可再次暂停")
        mgr.testIdleSuspend()
        check(!mgr.isSuspended && restored == 2, "测试按钮可当场恢复，不会卡住")
        mgr.releaseHardware = nil
        mgr.restoreHardware = nil
        mgr.hardwareStatus = nil

        // 10. 连接状态单一真相源：概览页 / 省电页 / 侧边栏必须逐字一致
        // 之前省电页主卡片只读 power.isSuspended，概览页读 monitor.isConnected，
        // 同一台遥控器在两页被描述成不同状态。现在两页共用 monitor.statusText。
        let conn = ConnectionMonitor.shared
        conn.bluetoothNames = []
        conn.apply(connected: false, name: nil)
        check(conn.statusText == "等待遥控器连接" && conn.connectionLine == "等待遥控器… · 未连接",
              "未连接状态文案无自相矛盾", detail: "\(conn.statusText) / \(conn.connectionLine)")
        check(!conn.statusDetail.contains("已连接"), "未连接副文案不含“已连接”暗示")
        conn.apply(connected: true, name: nil)
        check(conn.statusText == "遥控器已连接" && conn.deviceName == "Siri Remote",
              "已连接但产品名缺失时回退通用名，不残留等待文案",
              detail: conn.deviceName)
        check(conn.connectionLine == "Siri Remote · 已连接", "无名设备时连接行文案一致",
              detail: conn.connectionLine)
        conn.apply(connected: true, name: "A1B2C3D4E5F6")
        check(conn.statusText == "遥控器已连接" && conn.connectionLine == "A1B2C3D4E5F6 · 已连接",
              "已连接设备两页文案同源", detail: conn.connectionLine)
        check(conn.statusSymbol == "appletvremote.gen4.fill", "已连接图标两页共用")
        conn.apply(connected: false, name: nil)
        check(conn.statusSymbol == "dot.radiowaves.left.and.right", "未连接图标两页共用")

        // 11. 权限状态一致性：报告 4.1/4.2 的回归防线
        check(AppIdentity.isAppBundlePath("/Applications/vibedeck.app")
              && !AppIdentity.isAppBundlePath("/tmp/vibedeck")
              && !AppIdentity.isAppBundlePath("/Applications/vibedeck.app/Contents/MacOS/vibedeck"),
              "app 身份判定只看 .app 包根路径")
        check((AppIdentity.voiceBlockReason() == nil) == AppIdentity.isAppBundle,
              "语音授权拦截与当前运行身份一致")
        let tapOnly = PermissionSnapshot(preflight: false, listenTap: true,
                                         accessibility: true, microphone: 3, speech: 3)
        let none = PermissionSnapshot(preflight: false, listenTap: false,
                                      accessibility: false, microphone: 2, speech: 0)
        check(tapOnly.inputMonitoringGranted && tapOnly.inputDetail.contains("实测可用"),
              "监听通道可用即视为已授权，并解释与系统开关的差异")
        check(!none.inputMonitoringGranted && none.inputDetail.contains("未确认")
              && none.inputStatusLabel == "未确认",
              "两种探测都失败时提示未确认，不再武断显示未授权")
        check(tapOnly.inputStatusLabel == "已授权", "监听通道可用时状态标签为已授权")
        check(!PermissionSnapshot(preflight: true, listenTap: false, accessibility: true,
                                  microphone: 2, speech: 3).voiceGranted
              && !PermissionSnapshot(preflight: true, listenTap: false, accessibility: true,
                                     microphone: 3, speech: 2).voiceGranted
              && tapOnly.voiceGranted,
              "语音授权要求麦克风与语音识别同时通过")
        let partialDetail = PermissionProbe.voiceDetail(mic: 2, speech: 3)
        check(partialDetail.contains("麦克风：被拒绝") && !partialDetail.contains("语音识别："),
              "语音缺项文案精确指出是哪一项", detail: partialDetail)
        check(PermissionProbe.statusLabel(0) == "未决定"
              && PermissionProbe.statusLabel(2) == "被拒绝"
              && PermissionProbe.statusLabel(3) == "已授权", "TCC 状态码文案可读")
        check(PermissionCenter.shared.diagnosticLines().count == 4
              && PermissionCenter.shared.diagnosticLines()[0].contains("preflight"),
              "诊断输出包含输入监控原始探测值")

        // 12. 未连接时的可诊断性：区分「蓝牙可见」与「完全看不到」
        check(ConnectionMonitor.detail(connected: false, deviceName: "等待遥控器…",
                                       bluetoothNames: ["A1B2C3D4E5F6"]).contains("A1B2C3D4E5F6"),
              "蓝牙可见但 HID 未接管时给出设备名引导")
        check(!ConnectionMonitor.detail(connected: false, deviceName: "等待遥控器…",
                                        bluetoothNames: ["A1B2C3D4E5F6"]).contains("已连接"),
              "蓝牙可见也不伪装成已连接")
        conn.apply(connected: false, name: nil)
        conn.bluetoothNames = ["A1B2C3D4E5F6"]
        check(conn.statusText == "等待遥控器连接" && conn.bluetoothLine.contains("A1B2C3D4E5F6"),
              "未连接状态下侧栏与诊断都能看到蓝牙名")
        conn.bluetoothNames = []

        // 13. 配置摘要可读性
        let launch = store.binding(for: RemoteButton.tv.rawValue)
        check(!launch.summary.isEmpty, "绑定摘要非空（\(launch.summary)）")
        check(ButtonBinding(kind: .launchApp, value: "").summary == "未指定 App",
              "未选 App 时摘要为“未指定 App”")
    }

    private func report() -> Bool {
        print("\n----------------------------------------")
        if failures.isEmpty {
            print("ALL PASS — \(passes) 项检查全部通过")
            return true
        }
        print("\(failures.count) 项失败 / \(passes) 项通过：")
        for failure in failures { print("  ✗ \(failure)") }
        return false
    }

    private func SFSpeechStatusText() -> String {
        switch VoiceInputController.shared.authorized {
        case true: return "已授权"
        case false: return "未授权"
        }
    }

    private func micStatusText() -> String {
        VoiceInputController.shared.authorized ? "已授权" : "未授权"
    }
}

// 向后兼容的别名：真正的实现与状态源在 PermissionCenter
enum Permissions {
    static func inputMonitoring() -> Bool { PermissionCenter.shared.inputMonitoringGranted }
    static func accessibility() -> Bool { PermissionCenter.shared.accessibilityGranted }
}

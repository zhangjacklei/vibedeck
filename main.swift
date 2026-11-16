//
//  main.swift
//  Remotastic
//
//  Application entry point
//

import AppKit
import AVFoundation
import Speech
import IOBluetooth

// 无界面自检：`./vibedeck.app/Contents/MacOS/vibedeck --voice-test [秒数]`
// 用于确认麦克风 + 语音识别链路是否可用（结果写入 /tmp/vibedeck.log）。
// 测试报告 4.3：直接从 shell 跑裸二进制会在请求 TCC 时 SIGABRT，
// 这里在任何语音对象初始化之前就拦截，改为可读提示 + 非 0 退出码。
if CommandLine.arguments.contains("--voice-test") {
    if let reason = AppIdentity.voiceBlockReason() {
        PermissionPrimer.log("🧪 voice-test 已跳过：\(reason)")
        exit(2)
    }
    let seconds = CommandLine.arguments.compactMap { Double($0) }.first ?? 6.0
    PermissionPrimer.log("🧪 voice-test start (duration \(Int(seconds))s)")
    let voice = VoiceInputController.shared
    var finished = false
    // TCC 弹窗若被长时间忽略，不要挂死自动化脚本
    DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) {
        guard !finished else { return }
        finished = true
        PermissionPrimer.log("🧪 voice-test timeout: 授权请求未在 20 秒内完成")
        exit(3)
    }
    voice.requestAuthorization {
        PermissionPrimer.log("🧪 authorized=\(voice.authorized) mics=\(voice.micDevices.map { $0.name })")
        voice.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            voice.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                PermissionPrimer.log("🧪 voice-test end, transcript=\(voice.transcript)")
                finished = true
                exit(0)
            }
        }
    }
    RunLoop.main.run()
}

// 业务可用性自检：`./vibedeck --selftest`
if CommandLine.arguments.contains("--selftest") {
    let ok = SelfTest.run()
    exit(ok ? 0 : 1)
}

// 权限诊断：`./vibedeck --diag`（打印身份与授权状态）
if CommandLine.arguments.contains("--diag") {
    let bundleID = Bundle.main.bundleIdentifier ?? "?"
    print("版本            : \(BuildInfo.short)")
    print("Bundle ID      : \(bundleID)")
    print("App 路径        : \(Bundle.main.bundlePath)")
    print("可执行文件      : \(Bundle.main.executablePath ?? "?")")
    print("二进制落盘时间  : \(BuildInfo.binaryStamp)")
    let perms = PermissionCenter.shared
    perms.refreshSync()
    for line in perms.diagnosticLines() { print(line) }
    if !perms.snapshot.preflight && perms.snapshot.listenTap {
        print("权限说明        : 系统开关显示不一致，但监听通道实测可用，GUI 以实测结果为准")
    }
    print("遥控器麦克风    : \(VoiceInputController.shared.remoteMicAvailable ? "可用" : "系统未暴露")")
    let power = PowerManager.shared
    print("省电状态        : \(power.isSuspended ? "已暂停（\(power.suspendReason?.rawValue ?? "")）" : "运行中") · 闲置\(power.idleEnabled ? " \(power.idleMinutes) 分钟" : "未启用")")
    let visible = BluetoothRemoteController.connectedRemotes()
    if visible.isEmpty {
        print("系统蓝牙遥控器  : 未连接")
    } else {
        print("系统蓝牙遥控器  : " + visible.map {
            "\($0.name)\($0.isBLE ? " [BLE HID · 第三方 App 无法精确断开]" : "")"
        }.joined(separator: "、"))
    }
    let ioPaired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
    print("IOBluetooth 可见: \(ioPaired.filter { IdlePolicy.looksLikeRemote(name: $0.name) }.count) 个遥控器（BLE HID 通常不在此列表）")
    if !BuildInfo.isAppBundle {
        print("")
        print("⚠️  当前是命令行运行，上面的权限属于「终端」身份，不代表 vibedeck.app。")
        print("   请改用 app 包内二进制核查：./vibedeck.app/Contents/MacOS/vibedeck --diag")
    }
    exit(0)
}

// 浮窗几何/焦点自检（不录音）：`./vibedeck --hud-demo`
if CommandLine.arguments.contains("--hud-demo") {
    let demoApp = NSApplication.shared
    demoApp.appearance = NSAppearance(named: .aqua)
    demoApp.setActivationPolicy(.accessory)
    VoiceHUDController.shared.show()
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
        VoiceHUDController.shared.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { exit(0) }
    }
    RunLoop.main.run()
}

// 浮窗行为自检：`./vibedeck --hud-test`（显示 4 秒后自动收起）
if CommandLine.arguments.contains("--hud-test") {
    // 必须先初始化 NSApplication，否则 NSPanel 无法创建
    let hudApp = NSApplication.shared
    hudApp.appearance = NSAppearance(named: .aqua)
    hudApp.setActivationPolicy(.accessory)
    let voice = VoiceInputController.shared
    voice.requestAuthorization {
        voice.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            voice.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { exit(0) }
        }
    }
    RunLoop.main.run()
}

// Create the application instance
let app = NSApplication.shared

// Create and set the delegate
let delegate = AppDelegate()
app.delegate = delegate

// Run the application
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

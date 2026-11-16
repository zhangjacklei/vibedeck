//
//  PermissionCenter.swift
//  vibedeck
//
//  权限状态单一真相源。
//
//  背景：系统设置里「输入监控」开关与 CGPreflightListenEventAccess() 的返回值
//  在 GUI / 命令行进程里出现过不一致（TCC 按负责进程判定）。对业务而言真正
//  重要的是「能不能建出监听通道」，所以这里同时做 preflight 与真实 listen-only
//  tap 探测：任一成功即视为可用，并在界面/诊断里保留原始探测值便于排障。
//
//  语音识别同理：麦克风与语音识别是两项独立 TCC 权限，必须分开显示与修复，
//  不能共用一个布尔值让用户不知道到底缺哪一项。
//

import Foundation
import Combine
import AppKit
import ApplicationServices
import CoreGraphics
import Speech
import AVFoundation

// MARK: - App 身份

enum AppIdentity {
    static var isAppBundle: Bool { isAppBundlePath(Bundle.main.bundlePath) }

    /// 纯函数，供自检覆盖
    static func isAppBundlePath(_ path: String) -> Bool { path.hasSuffix(".app") }

    /// 非 .app 身份下语音识别会触发 TCC abort，调用前必须先检查
    static func voiceBlockReason() -> String? {
        isAppBundle ? nil : "语音识别必须在 app 内运行。请打开 vibedeck.app，或用 app 包内二进制运行该测试。"
    }
}

// MARK: - 底层探测（纯静态，便于自检）

enum PermissionProbe {
    static func inputMonitoringPreflight() -> Bool { CGPreflightListenEventAccess() }

    /// 真正尝试建立一个只读事件通道；成功即说明按键监听能力可用。
    /// 不派发到 runloop，立刻失效，不会改变事件流，也不会弹出授权框。
    static func listenTapAvailable() -> Bool {
        let mask = CGEventMask(1) << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap,
                                          place: .headInsertEventTap,
                                          options: .listenOnly,
                                          eventsOfInterest: mask,
                                          callback: { _, _, _, _ in nil },
                                          userInfo: nil) else { return false }
        CFMachPortInvalidate(tap)
        return true
    }

    static func inputMonitoringEffective() -> Bool {
        inputMonitoringPreflight() || listenTapAvailable()
    }

    static func accessibility() -> Bool { AXIsProcessTrusted() }

    // TCC 在同一次进程里反复读取语音/麦克风状态会偶发 SIGABRT
    // （崩溃报告：kTCCServiceSpeechRecognition + 找不到 usage description）。
    // 每个进程只读取一次并缓存；只有用户主动请求授权或点「重新检测」时才失效重读。
    private static let cacheLock = NSLock()
    private static var cachedMic: Int?
    private static var cachedSpeech: Int?

    static func invalidateCachedStatuses() {
        cacheLock.lock(); defer { cacheLock.unlock() }
        cachedMic = nil
        cachedSpeech = nil
    }

    static func microphoneRaw() -> Int {
        cacheLock.lock()
        if let cached = cachedMic { cacheLock.unlock(); return cached }
        cacheLock.unlock()
        let value = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
        cacheLock.lock(); cachedMic = value; cacheLock.unlock()
        return value
    }

    static func speechRaw() -> Int {
        cacheLock.lock()
        if let cached = cachedSpeech { cacheLock.unlock(); return cached }
        cacheLock.unlock()
        let value = SFSpeechRecognizer.authorizationStatus().rawValue
        cacheLock.lock(); cachedSpeech = value; cacheLock.unlock()
        return value
    }

    static func statusLabel(_ raw: Int) -> String {
        switch raw {
        case 0: return "未决定"
        case 1: return "受限"
        case 2: return "被拒绝"
        case 3: return "已授权"
        default: return "未知(\(raw))"
        }
    }

    /// 拆分说明到底缺哪一项，避免只显示「需要授权」让用户无从下手
    static func voiceDetail(mic: Int, speech: Int) -> String {
        if mic == 3 && speech == 3 { return "麦克风与语音识别均已授权" }
        var missing: [String] = []
        if mic != 3 { missing.append("麦克风：\(statusLabel(mic))") }
        if speech != 3 { missing.append("语音识别：\(statusLabel(speech))") }
        return "待处理 → " + missing.joined(separator: "；")
    }
}

// MARK: - 快照（自检可构造，不依赖真实 TCC）

struct PermissionSnapshot {
    let preflight: Bool
    let listenTap: Bool
    let accessibility: Bool
    let microphone: Int
    let speech: Int

    var inputMonitoringGranted: Bool { preflight || listenTap }
    var voiceGranted: Bool { microphone == 3 && speech == 3 }

    var inputDetail: String {
        if preflight { return "读取遥控器按键与触摸事件" }
        if listenTap { return "系统开关显示未授权，但监听通道实测可用（以本 App 为准）" }
        return "本进程未确认授权；若按键无响应，请到系统设置把输入监控关→开一次"
    }

    /// 不是简单的是/否：TCC 按负责进程判定，本进程探测不到时只能说「未确认」
    var inputStatusLabel: String { inputMonitoringGranted ? "已授权" : "未确认" }

    static func capture() -> PermissionSnapshot {
        PermissionSnapshot(preflight: PermissionProbe.inputMonitoringPreflight(),
                           listenTap: PermissionProbe.listenTapAvailable(),
                           accessibility: PermissionProbe.accessibility(),
                           microphone: PermissionProbe.microphoneRaw(),
                           speech: PermissionProbe.speechRaw())
    }
}

// MARK: - 可观测中心

final class PermissionCenter: ObservableObject {
    static let shared = PermissionCenter()

    @Published private(set) var snapshot = PermissionSnapshot(preflight: false, listenTap: false,
                                                              accessibility: false,
                                                              microphone: 0, speech: 0)
    @Published private(set) var lastChecked: Date = .distantPast

    var inputMonitoringGranted: Bool { snapshot.inputMonitoringGranted }
    var inputMonitoringDetail: String { snapshot.inputDetail }
    var accessibilityGranted: Bool { snapshot.accessibility }
    var microphoneRaw: Int { snapshot.microphone }
    var speechRaw: Int { snapshot.speech }
    var microphoneGranted: Bool { snapshot.microphone == 3 }
    var speechGranted: Bool { snapshot.speech == 3 }
    var voiceGranted: Bool { snapshot.voiceGranted }
    var voiceDetail: String { PermissionProbe.voiceDetail(mic: snapshot.microphone,
                                                          speech: snapshot.speech) }

    /// 界面用：异步刷新，避免在主线程做 tap 探测阻塞绘制
    func refresh() {
        let captured = PermissionSnapshot.capture()
        DispatchQueue.main.async { self.apply(captured) }
    }

    /// CLI / 自检用：同步刷新并立即读取
    @discardableResult
    func refreshSync() -> PermissionSnapshot {
        let captured = PermissionSnapshot.capture()
        apply(captured)
        return captured
    }

    func apply(_ snapshot: PermissionSnapshot) {
        self.snapshot = snapshot
        self.lastChecked = Date()
    }

    func requestInputMonitoring() {
        if !PermissionProbe.inputMonitoringPreflight() { _ = CGRequestListenEventAccess() }
        refresh()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    /// 诊断输出：把原始探测值也带上，解释 GUI 与系统设置显示不一致的原因
    func diagnosticLines() -> [String] {
        let s = snapshot
        return [
            "输入监控        : \(s.inputStatusLabel)（preflight=\(s.preflight ? "true" : "false") 监听通道=\(s.listenTap ? "可用" : "不可用")）",
            "辅助功能        : \(s.accessibility ? "已授权" : "未授权")",
            "麦克风          : \(PermissionProbe.statusLabel(s.microphone))",
            "语音识别        : \(PermissionProbe.statusLabel(s.speech))"
        ]
    }
}

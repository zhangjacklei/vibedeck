//
//  PowerManager.swift
//  vibedeck
//
//  省电与休眠：
//   · 闲置 N 分钟后自动释放 HID 独占 + 停止触控板轮询，遥控器可进入深睡
//   · 保留被动按键监听 / 设备重新枚举 / 媒体键三条唤醒路径
//   · 菜单栏 / 设置页可手动暂停、恢复、睡前一键释放
//
//  平台限制（本机实测 2026-11-15）：A2540 是 BLE HID，出现在
//  `system_profiler SPBluetoothDataType` 的 device_connected 里（Service: BLE），
//  但**不**出现在 IOBluetoothDevice.pairedDevices / configuredDevices /
//  connectedDevices 中，按地址构造的对象 isConnected=false。
//  即 macOS 不向第三方 App 暴露可 closeConnection 的系统级 BLE HID 连接。
//  因此「一键断开」改为：立即释放全部资源让遥控器自行深睡 + 尽力精确断开，
//  做不到时给出明确说明并引导到蓝牙设置面板手动断开。
//

import Foundation
import AppKit
import Combine
import IOKit
import IOBluetooth

// MARK: - 纯函数策略（脱离硬件也可自检）

enum IdlePolicy {
    /// 可选的闲置时长（分钟）
    static let allowedMinutes: [Int] = [1, 3, 5, 10, 15, 30, 60]

    /// 把任意输入收敛到最近的合法档位
    static func clamp(_ minutes: Int) -> Int {
        allowedMinutes.min { abs($0 - minutes) < abs($1 - minutes) } ?? 5
    }

    static func shouldSuspend(lastActivity: Date, now: Date, enabled: Bool, minutes: Int) -> Bool {
        guard enabled else { return false }
        return now.timeIntervalSince(lastActivity) >= Double(max(1, minutes) * 60)
    }

    static func remaining(lastActivity: Date, now: Date, enabled: Bool, minutes: Int) -> TimeInterval {
        guard enabled else { return 0 }
        return max(0, Double(max(1, minutes) * 60) - now.timeIntervalSince(lastActivity))
    }

    static func remainingText(_ seconds: TimeInterval, enabled: Bool, suspended: Bool) -> String {
        if suspended { return "已暂停接管，按遥控器任意键或点「恢复接管」即可恢复" }
        guard enabled else { return "自动休眠未启用" }
        let total = Int(seconds.rounded(.up))
        if total <= 0 { return "即将自动休眠" }
        let m = total / 60
        let s = total % 60
        if m > 0 {
            return s > 0 ? "距离自动休眠约 \(m) 分 \(s) 秒" : "距离自动休眠约 \(m) 分"
        }
        return "距离自动休眠约 \(s) 秒"
    }

    /// A2540 在 macOS 里常以 12 位大写序列号出现（如 A1B2C3D4E5F6），
    /// 其它固件版本则叫 "Siri Remote" / "Apple TV Remote"。
    static func looksLikeRemote(name: String?) -> Bool {
        guard let raw = name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return false
        }
        let lower = raw.lowercased()
        if lower.contains("remote") || lower.contains("siri")
            || lower.contains("apple tv") || lower.contains("appletv") {
            return true
        }
        let compact = raw.replacingOccurrences(of: "-", with: "")
                         .replacingOccurrences(of: ":", with: "")
        guard compact.count == 12 else { return false }
        return compact.unicodeScalars.allSatisfy {
            CharacterSet.uppercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
    }
}

// MARK: - 蓝牙：连接探测 + 尽力断开

enum BluetoothRemoteController {

    /// 断开结果。unsupported 是本机 A2540 的真实情况，必须如实告诉用户，
    /// 不能伪装成「已断开」，否则用户会以为功能生效了。
    enum Status {
        case disconnected
        case notFound
        case unsupported
        case failed
    }

    struct Result {
        let status: Status
        let attempted: Int
        let succeeded: Int
        let names: [String]

        var succeededNow: Bool { status == .disconnected }

        var message: String {
            switch status {
            case .disconnected:
                return "已断开 \(names.joined(separator: "、"))。遥控器将进入休眠；按任意键或点「恢复接管」可重新连回。"
            case .notFound:
                return "系统蓝牙里当前没有已连接的遥控器（可能已自行休眠）。HID 与触控板轮询已全部释放。"
            case .unsupported:
                return "已释放全部 HID 与触控板轮询，遥控器会在静置几分钟后自行深睡。注意：A2540 是 BLE HID，macOS 不允许第三方 App 直接断开系统级蓝牙连接；要彻底断开，请点「蓝牙设置」手动断开，或合盖让 Mac 睡眠。"
            case .failed:
                return "已对 \(names.joined(separator: "、")) 发起断开，但系统未返回成功。HID 与轮询已释放；如需彻底断开请点「蓝牙设置」。"
            }
        }
    }

    /// system_profiler 能看见 BLE HID，IOBluetooth 的经典设备列表看不见。
    struct ConnectedRemote {
        let name: String
        let address: String
        let services: String
        var isBLE: Bool { services.uppercased().contains("BLE") }
    }

    static func connectedRemotes() -> [ConnectedRemote] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let top = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = top["device_connected"] as? [[String: Any]] else { return [] }

        var result: [ConnectedRemote] = []
        for entry in connected {
            for (name, raw) in entry {
                guard IdlePolicy.looksLikeRemote(name: name),
                      let info = raw as? [String: Any] else { continue }
                var address = ""
                var services = ""
                for (key, value) in info {
                    let lower = key.lowercased()
                    if lower.contains("address") { address = "\(value)" }
                    if lower.contains("service") { services = "\(value)" }
                }
                result.append(ConnectedRemote(name: name, address: address, services: services))
            }
        }
        return result
    }

    /// 所有能枚举到的 IOBluetoothDevice（含私有 connectedDevices / configuredDevices）。
    private static func enumerableDevices() -> [IOBluetoothDevice] {
        var seen = Set<String>()
        var all: [IOBluetoothDevice] = []
        let collect: ([IOBluetoothDevice]?) -> Void = { list in
            for dev in list ?? [] {
                let key = dev.addressString ?? dev.name ?? UUID().uuidString
                if seen.insert(key).inserted { all.append(dev) }
            }
        }
        collect(IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])
        for selector in ["configuredDevices", "connectedDevices"] {
            let sel = NSSelectorFromString(selector)
            guard IOBluetoothDevice.responds(to: sel),
                  let ret = IOBluetoothDevice.perform(sel)?.takeUnretainedValue() else { continue }
            if let array = ret as? [IOBluetoothDevice] { collect(array) }
            else if let set = ret as? Set<IOBluetoothDevice> { collect(Array(set)) }
            else if let set = ret as? NSSet { collect(set.allObjects as? [IOBluetoothDevice]) }
        }
        return all
    }

    /// 尽力精确断开。找不到可操作对象时返回 .unsupported（BLE HID 平台限制）。
    static func disconnect(preferredName: String? = nil) -> Result {
        let visible = connectedRemotes()
        let preferred = (preferredName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted: (String) -> Bool = { name in
            if !preferred.isEmpty && preferred != "等待遥控器…" && name == preferred { return true }
            return IdlePolicy.looksLikeRemote(name: name)
        }

        var succeeded = 0
        var attempted = 0
        var names: [String] = []

        for dev in enumerableDevices() {
            let name = dev.name ?? ""
            let address = dev.addressString ?? ""
            let matches = wanted(name) || visible.contains {
                !$0.address.isEmpty && address.replacingOccurrences(of: "-", with: ":") == $0.address
            }
            guard matches else { continue }
            attempted += 1
            names.append(name.isEmpty ? address : name)
            if dev.closeConnection() == kIOReturnSuccess { succeeded += 1 }
        }

        if attempted > 0 {
            return Result(status: succeeded > 0 ? .disconnected : .failed,
                          attempted: attempted, succeeded: succeeded, names: names)
        }
        if visible.isEmpty {
            return Result(status: .notFound, attempted: 0, succeeded: 0, names: [])
        }
        // 系统能看到连接的遥控器，但第三方 API 拿不到可断开的对象 —— BLE HID
        return Result(status: .unsupported, attempted: 0, succeeded: 0,
                      names: visible.map { $0.name })
    }

    /// 恢复接管时尽力把已配对的遥控器重新连回来（BLE HID 通常由按键自动重连）。
    static func reconnect() -> String {
        var opened = 0
        for dev in enumerableDevices() where IdlePolicy.looksLikeRemote(name: dev.name) && !dev.isConnected() {
            _ = dev.openConnection()
            opened += 1
        }
        if opened > 0 { return "已请求重新连接 \(opened) 个遥控器设备" }
        return "BLE HID 遥控器由 macOS 管理；按一下遥控器按键即可自动重连并恢复接管。"
    }

    static func openSettings() {
        for value in ["x-apple.systempreferences:com.apple.BluetoothSettings",
                      "x-apple.systempreferences:com.apple.preference.bluetooth"] {
            if let url = URL(string: value) { NSWorkspace.shared.open(url); return }
        }
    }
}

// MARK: - 状态机

enum SuspendReason: String {
    case manual = "手动暂停"
    case idle = "闲置自动休眠"
    case disconnect = "睡前一键释放"
    case test = "休眠测试"
}

final class PowerManager: ObservableObject {
    static let shared = PowerManager()

    private enum Key {
        static let idleEnabled = "power.idleEnabled.v1"
        static let idleMinutes = "power.idleMinutes.v1"
    }

    // 设置
    @Published private(set) var idleEnabled: Bool
    @Published private(set) var idleMinutes: Int

    // 状态
    @Published private(set) var isSuspended = false
    @Published private(set) var suspendReason: SuspendReason?
    @Published private(set) var suspendedAt: Date?
    @Published private(set) var remainingText = ""
    @Published private(set) var lastBluetoothResult = ""
    @Published private(set) var lastActivityText = ""

    /// 由 AppDelegate 注入：真正释放 / 恢复硬件资源
    var releaseHardware: (() -> Void)?
    var restoreHardware: (() -> Void)?
    /// 供诊断/日志读取实际硬件状态
    var hardwareStatus: (() -> String)?
    /// 状态或设置变化后刷新菜单栏
    var onStateChanged: (() -> Void)?

    private let lock = NSLock()
    private var lastActivityAt = Date()
    private var monitorTimer: Timer?
    private var started = false
    /// 仅在「精确断开确实成功」后短暂抑制设备自动重连，避免暂停立刻被撤销。
    /// 之前固定 60 秒会把用户按任意键唤醒一起挡掉，是「按不动」的主因。
    private var arrivalWakeSuppressedUntil = Date.distantPast

    private init() {
        let defaults = UserDefaults.standard
        idleEnabled = defaults.object(forKey: Key.idleEnabled) as? Bool ?? true
        idleMinutes = IdlePolicy.clamp(defaults.object(forKey: Key.idleMinutes) as? Int ?? 10)
    }

    // MARK: 生命周期

    func start() {
        guard !started else { return }
        started = true
        markActivity()
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
        refreshRemainingText()
        PermissionPrimer.log("🔋 省电管理启动：闲置自动休眠\(idleEnabled ? "（\(idleMinutes) 分钟）" : "（未启用）")")
        onStateChanged?()
    }

    func stop() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        started = false
    }

    // MARK: 活动记录

    /// 主线程路径：记录活动；若当前处于休眠则自动恢复。
    /// 任何来源（HID 按键 / 媒体键 / 设备重新枚举 / 手动点击）都无条件恢复，
    /// 不再受 arrivalWakeSuppressedUntil 限制 —— 用户主动按键必须能唤醒。
    func noteActivity(source: String = "遥控器按键") {
        markActivity()
        if isSuspended { resume(trigger: source) }
        refreshRemainingText()
    }

    /// 触控板回调可能在后台线程高频触发，只更新时钟，不改状态。
    func noteTouchActivity() { markActivity() }

    /// 遥控器从深睡重新枚举时也当作唤醒信号。
    func wakeOnDeviceArrival() {
        guard isSuspended else { return }
        // 刚成功断开蓝牙时，系统会立刻自动重连；这段幽灵出现不算用户唤醒。
        guard Date() > arrivalWakeSuppressedUntil else { return }
        noteActivity(source: "遥控器重新连接")
    }

    private func markActivity() {
        lock.lock()
        let stamp = Date()
        lastActivityAt = stamp
        lock.unlock()
        // 触控板回调在后台线程，@Published 必须回到主线程再改
        let update = { [weak self] in
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let text = formatter.string(from: stamp)
            if self?.lastActivityText != text { self?.lastActivityText = text }
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async(execute: update) }
    }

    private func lastActivity() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return lastActivityAt
    }

    private func tick() {
        guard !isSuspended else { return }
        let now = Date()
        let last = lastActivity()
        if IdlePolicy.shouldSuspend(lastActivity: last, now: now,
                                    enabled: idleEnabled, minutes: idleMinutes) {
            PermissionPrimer.log("⏰ 闲置 \(idleMinutes) 分钟未操作 → 自动释放并休眠")
            suspend(.idle)
            return
        }
        let text = IdlePolicy.remainingText(
            IdlePolicy.remaining(lastActivity: last, now: now,
                                 enabled: idleEnabled, minutes: idleMinutes),
            enabled: idleEnabled, suspended: false)
        if text != remainingText { remainingText = text }
    }

    // MARK: 暂停 / 恢复

    func suspend(_ reason: SuspendReason) {
        guard !isSuspended else { return }
        isSuspended = true
        suspendReason = reason
        suspendedAt = Date()
        remainingText = IdlePolicy.remainingText(0, enabled: idleEnabled, suspended: true)
        VoiceInputController.shared.stop()
        releaseHardware?()
        let hw = hardwareStatus?() ?? ""
        PermissionPrimer.log("🌙 暂停接管（\(reason.rawValue)）：释放 HID 独占 + 停止触控板轮询\(hw.isEmpty ? "" : " | \(hw)")")
        onStateChanged?()
    }

    func resume(trigger: String = "手动") {
        guard isSuspended else { return }
        let previousReason = suspendReason
        let previous = previousReason?.rawValue ?? "暂停"
        isSuspended = false
        suspendReason = nil
        suspendedAt = nil
        arrivalWakeSuppressedUntil = .distantPast
        markActivity()
        restoreHardware?()
        let hw = hardwareStatus?() ?? ""
        PermissionPrimer.log("☀️ 恢复接管（触发：\(trigger)，原状态：\(previous)）\(hw.isEmpty ? "" : " | \(hw)")")
        if previousReason == .disconnect {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                let message = BluetoothRemoteController.reconnect()
                self?.lastBluetoothResult = message
                PermissionPrimer.log("🔌 \(message)")
                self?.onStateChanged?()
            }
        }
        refreshRemainingText()
        onStateChanged?()
    }

    func toggle() {
        isSuspended ? resume(trigger: "菜单栏") : suspend(.manual)
    }

    /// 设置页「立即测试」：不等 N 分钟，当场进入休眠并验证按任意键能恢复。
    func testIdleSuspend() {
        if isSuspended { resume(trigger: "测试按钮") }
        else { suspend(.test) }
    }

    // MARK: 设置

    func setIdleEnabled(_ value: Bool) {
        idleEnabled = value
        UserDefaults.standard.set(value, forKey: Key.idleEnabled)
        markActivity()
        refreshRemainingText()
        PermissionPrimer.log("🔋 闲置自动休眠：\(value ? "开启（\(idleMinutes) 分钟）" : "关闭")")
        onStateChanged?()
    }

    func setIdleMinutes(_ value: Int) {
        let clamped = IdlePolicy.clamp(value)
        idleMinutes = clamped
        UserDefaults.standard.set(clamped, forKey: Key.idleMinutes)
        markActivity()
        refreshRemainingText()
        PermissionPrimer.log("🔋 闲置阈值设为 \(clamped) 分钟")
        onStateChanged?()
    }

    /// 睡前一键：先释放硬件，再在后台尽力精确断开蓝牙。
    /// system_profiler 约 1 秒，放后台避免卡界面；结果回主线程更新 UI。
    func disconnectRemote() {
        let targetName = ConnectionMonitor.shared.deviceName
        suspend(.disconnect)
        lastBluetoothResult = "正在检查蓝牙连接…"
        onStateChanged?()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = BluetoothRemoteController.disconnect(preferredName: targetName)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if result.succeededNow {
                    // 只有真断开了才短暂抑制系统自动重连，且只抑制 3 秒
                    self.arrivalWakeSuppressedUntil = Date().addingTimeInterval(3)
                }
                self.lastBluetoothResult = result.message
                PermissionPrimer.log("🔌 \(result.message)")
                self.onStateChanged?()
            }
        }
    }

    private func refreshRemainingText() {
        if isSuspended {
            remainingText = IdlePolicy.remainingText(0, enabled: idleEnabled, suspended: true)
            return
        }
        remainingText = IdlePolicy.remainingText(
            IdlePolicy.remaining(lastActivity: lastActivity(), now: Date(),
                                 enabled: idleEnabled, minutes: idleMinutes),
            enabled: idleEnabled, suspended: false)
    }
}

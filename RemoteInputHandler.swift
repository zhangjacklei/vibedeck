//
//  RemoteInputHandler.swift
//  Remotastic
//
//  Processes HID input events from Siri Remote
//

import IOKit
import IOKit.hid
import Foundation
import Carbon.HIToolbox
import AppKit

class RemoteInputHandler {
    private let cursorController: CursorController
    private let mediaController: MediaController
    private weak var menuBarManager: MenuBarManager?
    private var devices: [IOHIDDevice] = []
    
    /// Called on any button activity; use to trigger trackpad re-scan after remote wake.
    var onButtonActivity: (() -> Void)?
    
    // First press after connection: do not perform action (sound already played at connect).
    private var isFirstPressAfterConnection = false
    
    // Click/drag state
    private var isSelectPressed = false
    private var selectPressTime: UInt64 = 0
    private var isDragging = false
    private let clickThreshold: Double = 0.25
    
    // Prevent double-processing with MediaKeyInterceptor
    static var lastProcessedButton: String?
    static var lastProcessedTime: UInt64 = 0
    /// 已记录过的未知按键（诊断用，避免刷屏）
    private static var loggedUnknowns: Set<String> = []
    /// 同一按键的去抖：A2540 会在多个 HID 接口上重复上报同一次按下
    private static var lastFireButton: String?
    private static var lastFireTime: TimeInterval = 0
    
    init(cursorController: CursorController, mediaController: MediaController, menuBarManager: MenuBarManager) {
        self.cursorController = cursorController
        self.mediaController = mediaController
        self.menuBarManager = menuBarManager
    }
    
    /// 省电休眠中：已释放 HID 独占，只保留被动监听用于「有按键再自动恢复」。
    private(set) var isSuspended = false

    func setRemoteDevice(_ device: IOHIDDevice?) {
        guard let device = device else {
            for d in devices { closeDevice(d) }
            devices.removeAll()
            isFirstPressAfterConnection = false
            return
        }

        guard !devices.contains(where: { $0 == device }) else { return }

        // 休眠期间新枚举出来的设备只被动监听，不重新独占
        if openDevice(device, seize: !isSuspended) {
            devices.append(device)
            if !isSuspended {
                isFirstPressAfterConnection = true
                CursorController.playKeyPressFeedback()
            }
        }
    }

    /// 暂停/恢复：把已打开的接口在「独占」与「被动」之间切换。
    /// 被动模式不发送任何数据给遥控器，只等按键上报，因此不会阻止它深睡。
    func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        let current = devices
        for d in current { closeDevice(d) }
        devices.removeAll()

        var reopened = 0
        for d in current where openDevice(d, seize: !suspended) {
            devices.append(d)
            reopened += 1
        }
        // 唤醒的那一下按键已经充当「连接后首次按键」，不要再吞掉下一次有效操作
        isFirstPressAfterConnection = false
        PermissionPrimer.log(suspended
            ? "🌙 HID 独占已释放，保留 \(reopened) 个被动按键监听"
            : "☀️ HID 独占已恢复（\(reopened) 个接口）")
    }

    private func closeDevice(_ device: IOHIDDevice) {
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func openDevice(_ device: IOHIDDevice, seize: Bool) -> Bool {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let primary = seize ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone
        if IOHIDDeviceOpen(device, IOOptionBits(primary)) == kIOReturnSuccess {
            registerCallbacks(device, context: context)
            return true
        }
        // 独占失败时退回被动监听，保证仍能收到按键
        if seize && IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
            registerCallbacks(device, context: context)
            return true
        }
        return false
    }

    private func registerCallbacks(_ device: IOHIDDevice, context: UnsafeMutableRawPointer) {
        IOHIDDeviceRegisterInputValueCallback(device, inputValueCallback, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }
    
    func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)
        
        guard let buttonName = RemoteInputHandler.classify(page: usagePage, usage: usage) else {
            // 未知按键：每个 (page, usage) 只记录一次，便于用真实设备补全映射
            if intValue == 1 {
                let key = String(format: "0x%02X:0x%03X", usagePage, usage)
                if !RemoteInputHandler.loggedUnknowns.contains(key) {
                    RemoteInputHandler.loggedUnknowns.insert(key)
                    PermissionPrimer.log("❓ 未知按键 page=\(key)")
                }
            }
            return
        }
        
        // 休眠中：只把「按下」当作唤醒信号，不执行任何绑定动作，也不重扫触控板。
        // 延迟到下一个 runloop 再恢复，避免在 HID 回调里重入 IOHIDDeviceOpen。
        if isSuspended {
            if intValue == 1 {
                PermissionPrimer.log("🌙 休眠中收到按键 \(buttonName) → 唤醒并恢复接管")
                DispatchQueue.main.async {
                    PowerManager.shared.noteActivity(source: "遥控器 \(buttonName) 键")
                }
            }
            return
        }

        // 只把「按下」算作使用，避免驱动周期性上报的松开帧让闲置计时永不超时
        if intValue == 1 { PowerManager.shared.noteActivity(source: "遥控器按键") }

        // Any button activity may cause the remote to re-enumerate; re-scan MT so trackpad can reconnect.
        onButtonActivity?()

        let earlyBinding = BindingStore.shared.binding(for: buttonName)

        // 按住说话优先处理，避免被“连接后首次按键静默”吞掉
        if earlyBinding.kind == .dictation {
            if intValue == 1 {
                isFirstPressAfterConnection = false
                PermissionPrimer.log("🔘 \(buttonName) down → dictation start")
                VoiceInputController.shared.start()
            } else {
                PermissionPrimer.log("🔘 \(buttonName) up → dictation stop")
                VoiceInputController.shared.stop()
            }
            return
        }

        // First key-down after connection: do not perform action (sound already played at connect).
        if intValue == 1 && isFirstPressAfterConnection {
            isFirstPressAfterConnection = false
            return
        }
        
        // Handle select button (trackpad click) - distinguish click vs drag
        if buttonName == "select" {
            handleSelectButton(pressed: intValue == 1)
            return
        }

        let binding = earlyBinding

        // Other buttons: only process on key down
        guard intValue == 1 else { return }
        
        // Mark this button as processed to prevent MediaKeyInterceptor from double-processing
        let currentTime = mach_absolute_time()
        RemoteInputHandler.lastProcessedButton = buttonName
        RemoteInputHandler.lastProcessedTime = currentTime

        // 去抖：150ms 内同一个键只执行一次
        let now = Date.timeIntervalSinceReferenceDate
        if RemoteInputHandler.lastFireButton == buttonName,
           now - RemoteInputHandler.lastFireTime < 0.15 {
            return
        }
        RemoteInputHandler.lastFireButton = buttonName
        RemoteInputHandler.lastFireTime = now

        PermissionPrimer.log(String(format: "🔘 Button pressed: %@ (0x%02X/0x%03X) → %@",
                                    buttonName, usagePage, usage, binding.summary))
        if binding.kind != .none {
            CursorController.playKeyPressFeedback()
        }
        execute(binding)
    }
    
    private func handleSelectButton(pressed: Bool) {
        if pressed && !isSelectPressed {
            isSelectPressed = true
            isDragging = false
            selectPressTime = mach_absolute_time()
            cursorController.isClickActive = true
            
            // Start drag after threshold
            DispatchQueue.main.asyncAfter(deadline: .now() + clickThreshold) { [weak self] in
                guard let self = self, self.isSelectPressed && !self.isDragging else { return }
                PermissionPrimer.log("🔘 Select button: Drag started")
                self.isDragging = true
                self.cursorController.isDragging = true
                self.cursorController.mouseDown()
            }
        } else if !pressed && isSelectPressed {
            isSelectPressed = false
            
            if isDragging {
                PermissionPrimer.log("🔘 Select button: Drag ended")
                cursorController.isDragging = false
                cursorController.mouseUp()
            } else {
                PermissionPrimer.log("🔘 Select button: Click")
                CursorController.playKeyPressFeedback()
                cursorController.performClick()
            }
            isDragging = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.cursorController.isClickActive = false
            }
        }
    }
    
    // MARK: - Button Identification
    
    /// 键识别逻辑抽成静态方法，便于自检直接断言（无需硬件）
    static func classify(page: UInt32, usage: UInt32) -> String? {
        switch (page, usage) {
        // Generic Desktop Page (0x01)
        case (0x01, 0x86): return "menu"          // System Menu Main
        case (0x01, 0x40): return "menu"          // Menu (alternative)
        
        // Consumer Page (0x0C)  
        case (0x0C, 0x04): return "siri"          // Siri button (actual)
        case (0x0C, 0x109): return "siri"         // A2540 语音键（本机实测）
        case (0x0C, 0x60): return "tv"            // TV button (actual)
        case (0x0C, 0x80): return "select"        // 触控板中心点按（本机实测）
        case (0x0C, 0x41): return "select"        // Menu Select (alternative)
        case (0x0C, 0xCD): return "playPause"     // Play/Pause
        case (0x0C, 0xE9): return "volumeUp"      // Volume Increment
        case (0x0C, 0xEA): return "volumeDown"    // Volume Decrement
        case (0x0C, 0xE2): return "mute"          // A2540 静音键（本机实测）
        case (0x0C, 0xB5): return "nextTrack"     // Scan Next Track
        case (0x0C, 0xB6): return "prevTrack"     // Scan Previous Track
        case (0x0C, 0x223): return "tv"           // AC Home (TV button alternative)
        case (0x0C, 0x224): return "menu"         // AC Back
        case (0x0C, 0x40): return "menu"          // Menu
        case (0x0C, 0x30): return "power"         // HID Consumer 0x30 = Power（A2540 电源键）
        case (0x0C, 0x20): return "mute"          // Mute (some remotes)

        // 圆环四向（A2540 实测 0x42–0x45，方向对应关系以实机测量为准）
        case (0x0C, 0x42): return RemoteButton.ringUp.rawValue
        case (0x0C, 0x43): return RemoteButton.ringDown.rawValue
        case (0x0C, 0x44): return RemoteButton.ringLeft.rawValue
        case (0x0C, 0x45): return RemoteButton.ringRight.rawValue
        
        // Button Page (0x09)
        case (0x09, 0x01): return "select"        // Button 1
        
        // Apple Vendor Page (0xFF00) - Siri button
        case (0xFF00, 0x01): return "siri"        // Siri button
        case (0xFF00, 0x02): return "siri"        // Siri button (alternative)
        case (0xFF00, 0x03): return "siri"        // Siri button (alternative)
        case (0xFF00, _): return "siri"           // Any Apple vendor usage = likely Siri
        
        // Telephony Page (0x0B) - sometimes used for Siri
        case (0x0B, 0x21): return "siri"          // Flash
        case (0x0B, 0x2F): return "siri"          // Phone Mute
        
        default: return nil
        }
    }
    
    // MARK: - Action Execution

    private func execute(_ binding: ButtonBinding) {
        switch binding.kind {
        case .none:
            break
        case .keystroke:
            KeySender.send(combo: binding.value)
        case .text:
            KeySender.type(text: binding.value)
        case .playPause:
            // .app 里遥控器同时会通过 AVRCP 发 Play/Pause；不重复发送，避免触发两次
            if !Bundle.main.bundlePath.hasSuffix(".app") {
                mediaController.sendMediaKey(.playPause)
            }
        case .nextTrack:
            mediaController.sendMediaKey(.next)
        case .previousTrack:
            mediaController.sendMediaKey(.previous)
        case .volumeUp:
            mediaController.sendMediaKey(.volumeUp)
        case .volumeDown:
            mediaController.sendMediaKey(.volumeDown)
        case .mute:
            mediaController.sendMediaKey(.mute)
        case .click:
            cursorController.performClick()
        case .rightClick:
            cursorController.performRightClick()
        case .scrollUp:
            cursorController.scroll(deltaX: 0, deltaY: 60)
        case .scrollDown:
            cursorController.scroll(deltaX: 0, deltaY: -60)
        case .missionControl:
            openMissionControl()
        case .dictation:
            // 由 handleInputValue 的按下/松开分支处理
            break
        case .launchApp:
            launchApp(named: binding.value)
        case .shell:
            runShell(binding.value)
        }
    }

    private func launchApp(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // 支持 bundle id、App 名称、完整路径
        if trimmed.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error = error { PermissionPrimer.log("🚀 打开失败：\(error.localizedDescription)") }
            }
            return
        }
        if FileManager.default.fileExists(atPath: trimmed) {
            NSWorkspace.shared.open(URL(fileURLWithPath: trimmed))
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", trimmed]
        try? process.run()
    }

    private func runShell(_ command: String) {
        guard !command.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        do {
            try process.run()
        } catch {
            PermissionPrimer.log("💻 shell 失败：\(error.localizedDescription)")
        }
    }
}

/// Opens Mission Control (one path for CLI and app).
func openMissionControl() {
    let bundleID = "com.apple.exposelauncher"
    if Bundle.main.bundlePath.hasSuffix(".app"),
       let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        return
    }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    proc.arguments = ["-b", bundleID]
    try? proc.run()
}

// C callback
private func inputValueCallback(context: UnsafeMutableRawPointer?, result: IOReturn, sender: UnsafeMutableRawPointer?, value: IOHIDValue) {
    guard let context = context else { return }
    Unmanaged<RemoteInputHandler>.fromOpaque(context).takeUnretainedValue().handleInputValue(value)
}

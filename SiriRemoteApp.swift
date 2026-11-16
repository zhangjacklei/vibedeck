//
//  SiriRemoteApp.swift
//  Remotastic
//
//  Menu bar application for controlling Mac with Siri Remote
//

import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Speech
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var statusItem: NSStatusItem!
    private var menuBarManager: MenuBarManager!
    private var remoteDetector: RemoteDetector?
    private var remoteInputHandler: RemoteInputHandler?
    private var mediaKeyInterceptor: MediaKeyInterceptor?
    private var touchHandler: TouchHandler?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 vibedeck \(BuildInfo.short) starting...")
        BuildInfo.logStartup()

        // 主动登记到 TCC 并弹系统授权框（辅助功能 + 输入监控）
        PermissionPrimer.promptIfNeeded()

        // 语音相关授权状态（Speech=0 未决 1 受限 2 拒绝 3 已授权；Mic 同理）
        let speechStatus = SFSpeechRecognizer.authorizationStatus().rawValue
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
        PermissionPrimer.log("🎙️ startup: speech=\(speechStatus) mic=\(micStatus) mics=\(AudioInputDevices.list().map { $0.name })")
        
        // 界面按浅色设计：强制整个 App 使用浅色外观，
        // 否则系统深色模式下会出现"白卡片 + 白字"看不清
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.setActivationPolicy(.accessory)
        
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let statusItem = statusItem else {
            NSApp.terminate(nil)
            return
        }
        statusItem.isVisible = true
        
        // Initialize menu bar manager
        menuBarManager = MenuBarManager(statusItem: statusItem)
        
        // Check accessibility permissions
        checkAccessibilityPermissions()
        
        // Initialize controllers
        let cursorController = CursorController()
        let mediaController = MediaController()
        menuBarManager.mediaController = mediaController
        
        remoteInputHandler = RemoteInputHandler(
            cursorController: cursorController,
            mediaController: mediaController,
            menuBarManager: menuBarManager
        )
        
        // Start touch handler for trackpad (before remote detection so we can wire the callback)
        touchHandler = TouchHandler(cursorController: cursorController)
        touchHandler?.scrollScale = menuBarManager.scrollSpeed.scale
        touchHandler?.start()
        remoteInputHandler?.onButtonActivity = { [weak self] in
            guard !PowerManager.shared.isSuspended else { return }
            self?.touchHandler?.tryReconnectTrackpad()
        }
        
        // Start remote detection
        remoteDetector = RemoteDetector { [weak self] device in
            DispatchQueue.main.async {
                // 休眠中遥控器重新枚举 = 用户按了键唤醒它；先恢复状态，
                // 让下面的 setRemoteDevice 直接以独占方式重新接管。
                if device != nil { PowerManager.shared.wakeOnDeviceArrival() }
                self?.remoteInputHandler?.setRemoteDevice(device)
                self?.menuBarManager.updateConnectionStatus(connected: device != nil)
                let name = device.flatMap {
                    IOHIDDeviceGetProperty($0, kIOHIDProductKey as CFString) as? String
                }
                ConnectionMonitor.shared.update(connected: device != nil, name: name)
            }
        }
        remoteDetector?.startDetection()
        ConnectionMonitor.refreshHID = { [weak self] in self?.remoteDetector?.refreshDevices() }

        // 省电管理：闲置自动释放 HID 独占 + 停止触控板轮询，按任意键自动唤醒
        let power = PowerManager.shared
        power.releaseHardware = { [weak self] in
            self?.remoteInputHandler?.setSuspended(true)
            self?.touchHandler?.pause()
        }
        power.restoreHardware = { [weak self] in
            self?.remoteInputHandler?.setSuspended(false)
            self?.touchHandler?.resume()
            self?.remoteDetector?.refreshDevices()
        }
        power.hardwareStatus = { [weak self] in
            let hid = (self?.remoteInputHandler?.isSuspended ?? false) ? "HID 被动" : "HID 独占"
            let mt = (self?.touchHandler?.paused ?? false) ? "触控板已停" : "触控板运行中"
            return "\(hid) / \(mt)"
        }
        power.onStateChanged = { [weak self] in
            self?.menuBarManager.updatePowerState()
        }
        power.start()

        // 启动后展示可视化设置面板（菜单栏图标可随时重新打开）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            SettingsWindowController.shared.show()
        }
        
        // 输入监控只在 PermissionPrimer.promptIfNeeded() 里请求一次，
        // 这里不再重复调用 CGRequestListenEventAccess（重复弹窗且会扰乱 TCC 状态）。
        
        // Start media key interceptor
        mediaKeyInterceptor = MediaKeyInterceptor()
        mediaKeyInterceptor?.onMediaKey = { [weak self] keyType in
            guard let self = self else { return false }
            return self.handleInterceptedMediaKey(keyType)
        }
        mediaKeyInterceptor?.start()

        // `--power-test`：在真实 app 进程里验证暂停/恢复确实作用到 HID 与触控板，
        // 而不是只改了状态位。无需物理遥控器，可直接从日志读到 PASS/FAIL。
        if CommandLine.arguments.contains("--power-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let power = PowerManager.shared
                power.suspend(.test)
                let suspendedHW = power.hardwareStatus?() ?? "无硬件状态回调"
                PermissionPrimer.log("🧪 暂停后硬件：\(suspendedHW)")

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    power.noteActivity(source: "自动化唤醒测试")
                    let restoredHW = power.hardwareStatus?() ?? "无硬件状态回调"
                    PermissionPrimer.log("🧪 恢复后硬件：\(restoredHW)")
                    let hardwareOK = suspendedHW.contains("被动") && suspendedHW.contains("已停")
                        && restoredHW.contains("独占") && restoredHW.contains("运行中")
                        && !power.isSuspended

                    power.disconnectRemote()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        let bluetoothOK = power.lastBluetoothResult.contains("不允许第三方")
                            || power.lastBluetoothResult.contains("已断开")
                            || power.lastBluetoothResult.contains("没有已连接")
                        PermissionPrimer.log("🧪 蓝牙结果：\(power.lastBluetoothResult)")
                        let ok = hardwareOK && bluetoothOK
                        PermissionPrimer.log(ok ? "🧪 POWER-TEST PASS：硬件释放/恢复链路 + 蓝牙反馈均正常"
                                                : "🧪 POWER-TEST FAIL：hardwareOK=\(hardwareOK) bluetoothOK=\(bluetoothOK)")
                        exit(ok ? 0 : 1)
                    }
                }
            }
        }

        // Wire up settings changes
    }

    /// 授权状态镜像：用于「刚授权就自动重连」，避免用户以为授权没生效
    private var lastInputMonitoringGranted = false

    func applicationDidBecomeActive(_ notification: Notification) {
        // 每次回到前台都刷新：TCC 状态可能在系统设置里刚被改动
        PermissionCenter.shared.refresh()
        ConnectionMonitor.shared.probeBluetooth()
        let granted = PermissionCenter.shared.inputMonitoringGranted
        if granted && !lastInputMonitoringGranted && !ConnectionMonitor.shared.isConnected {
            PermissionPrimer.log("🔐 输入监控刚被授权，自动重新接管遥控器")
            remoteDetector?.stopDetection()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.remoteDetector?.startDetection()
            }
        }
        lastInputMonitoringGranted = granted
        PermissionPrimer.log("🔐 回到前台：输入监控=\(granted ? "已授权" : "未授权") 辅助功能=\(AXIsProcessTrusted() ? "已授权" : "未授权")")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        cleanup()
        return .terminateNow
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        cleanup()
    }
    
    private func cleanup() {
        PowerManager.shared.stop()
        touchHandler?.stop()
        remoteDetector?.stopDetection()
        mediaKeyInterceptor?.stop()
    }
    
    // MARK: - Media Key Handling

    /// Convert mach_absolute_time() delta to seconds (machine ticks vary; use timebase).
    private static let machTimebase: (numer: UInt32, denom: UInt32) = {
        var info = mach_timebase_info_data_t(numer: 0, denom: 0)
        guard mach_timebase_info(&info) == 0 else { return (1, 1) }
        return (info.numer, info.denom)
    }()

    private static func machDeltaToSeconds(from start: UInt64) -> Double {
        guard start > 0 else { return .infinity }
        let now = mach_absolute_time()
        let delta = now >= start ? (now - start) : 0
        let nanos = delta * UInt64(Self.machTimebase.numer) / UInt64(Self.machTimebase.denom)
        return Double(nanos) / 1_000_000_000.0
    }
    
    private func handleInterceptedMediaKey(_ keyType: MediaKeyInterceptor.MediaKeyType) -> Bool {
        // 休眠期间被动监听会同时把媒体键交给系统；这里吞掉，
        // 避免「唤醒的第一下按键」意外改音量 / 唤起音乐 App。
        // 同时把它当作第三条唤醒路径：HID 被动监听在遥控器深睡后可能收不到按键，
        // 但系统级媒体键事件仍会到达（只要 event tap 有效）。
        if PowerManager.shared.isSuspended {
            DispatchQueue.main.async { PowerManager.shared.noteActivity(source: "媒体键唤醒") }
            return true
        }

        let buttonName: String
        let defaultAction: String
        
        switch keyType {
        case .playPause:
            buttonName = "playPause"
            defaultAction = "Play/Pause"
        case .next:
            buttonName = "nextTrack"
            defaultAction = "Next Track"
        case .previous:
            buttonName = "prevTrack"
            defaultAction = "Previous Track"
        case .volumeUp:
            buttonName = "volumeUp"
            defaultAction = "Volume Up"
        case .volumeDown:
            buttonName = "volumeDown"
            defaultAction = "Volume Down"
        case .mute:
            return false
        }
        
        // Check if RemoteInputHandler just processed this button (prevent double-processing)
        if RemoteInputHandler.lastProcessedButton == buttonName {
            let timeSinceLastProcess = Self.machDeltaToSeconds(from: RemoteInputHandler.lastProcessedTime)
            if timeSinceLastProcess < 0.2 { // Within 200ms debounce window
                // RemoteInputHandler already handled this, consume the event but don't process again
                return true
            }
        }
        
        let action = menuBarManager.getMapping(for: buttonName)
        
        if action == .none {
            return true // Consume but do nothing
        }
        
        if action.rawValue == defaultAction {
            // In .app, Play/Pause is also sent over AVRCP; we don't send from HID there. Let system handle once.
            if keyType == .playPause && Bundle.main.bundlePath.hasSuffix(".app") {
                return false // Let system handle (AVRCP); we don't send from HID in .app
            }
            return true // Consume; HID path is the single source (CLI or non–play/pause)
        }
        
        menuBarManager.executeAction(action.rawValue)
        return true
    }
    
    // MARK: - Permissions
    
    private func checkAccessibilityPermissions() {
        // macOS will show its own prompt when needed
        // No need for redundant custom alert
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

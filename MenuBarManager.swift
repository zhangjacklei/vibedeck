//
//  MenuBarManager.swift
//  Remotastic
//
//  Manages the menu bar icon and menu
//

import AppKit
import Carbon.HIToolbox

// Button actions that can be assigned
enum ButtonAction: String, CaseIterable {
    case none = "None"
    case playPause = "Play/Pause"
    case nextTrack = "Next Track"
    case previousTrack = "Previous Track"
    case volumeUp = "Volume Up"
    case volumeDown = "Volume Down"
    case mute = "Mute"
    case click = "Mouse Click"
    case rightClick = "Right Click"
    case escape = "Escape"
    case space = "Space"
    case enter = "Enter"
    case missionControl = "Mission Control"
}

// Scroll speed options
enum ScrollSpeed: String, CaseIterable {
    case slow = "Slow"
    case medium = "Medium"
    case fast = "Fast"
    
    var scale: CGFloat {
        switch self {
        case .slow: return 150.0
        case .medium: return 300.0
        case .fast: return 500.0
        }
    }
}

class MenuBarManager {
    
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let statusMenuItem: NSMenuItem
    private var lastConnected = false
    
    // Button mappings (stored in UserDefaults)
    private var buttonMappings: [String: ButtonAction] = [:]
    
    // Scroll speed (used for trackpad scroll scale; no menu, native multitouch)
    private(set) var scrollSpeed: ScrollSpeed = .medium
    
    // Callback for when mappings change
    var onMappingsChanged: (([String: ButtonAction]) -> Void)?
    
    /// Set by app delegate so menu bar can delegate media actions to MediaController (one path for CLI and app).
    var mediaController: MediaController?
    
    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        self.menu = NSMenu()
        self.statusMenuItem = NSMenuItem(title: "Status: Disconnected", action: nil, keyEquivalent: "")
        
        loadMappings()
        setupMenuBar()
    }
    
    private func loadMappings() {
        // Default mappings (only used on first launch)
        // Vibe-coding oriented defaults (local fork):
        // Play/Pause submits (Enter), Back/Menu interrupts (Esc), TV switches apps.
        let defaultMappings: [String: ButtonAction] = [
            "playPause": .enter,
            "menu": .escape,
            "select": .click,
            "volumeUp": .volumeUp,
            "volumeDown": .volumeDown,
            "siri": .space,
            "tv": .missionControl
        ]
        
        // Load saved mappings from UserDefaults
        if let saved = UserDefaults.standard.dictionary(forKey: "buttonMappings") as? [String: String] {
            // User has saved mappings - use those (migrate old "Toggle Trackpad Mode" to .escape)
            for (button, actionRaw) in saved {
                if let action = ButtonAction(rawValue: actionRaw) {
                    buttonMappings[button] = action
                } else if actionRaw == "Toggle Trackpad Mode" {
                    buttonMappings[button] = .escape
                }
            }
            // Fill in any missing buttons with defaults
            for (button, action) in defaultMappings {
                if buttonMappings[button] == nil {
                    buttonMappings[button] = action
                }
            }
            // Local fork: keep Menu = Escape (interrupt / cancel in coding agents).
        } else {
            // First launch - use defaults
            buttonMappings = defaultMappings
            saveMappings() // Save defaults immediately
        }
    }
    
    private func saveMappings() {
        var toSave: [String: String] = [:]
        for (button, action) in buttonMappings {
            toSave[button] = action.rawValue
        }
        UserDefaults.standard.set(toSave, forKey: "buttonMappings")
        onMappingsChanged?(buttonMappings)
    }
    
    private func setupMenuBar() {
        // Configure the button (the visible icon in menu bar)
        guard let button = statusItem.button else {
            return
        }
        
        button.title = "SR"
        
        // Try SF Symbol if available
        if #available(macOS 11.0, *) {
            let symbolNames = ["appletvremote.gen4", "tv.and.mediabox", "remote"]
            for name in symbolNames {
                if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Siri Remote") {
                    image.isTemplate = true
                    button.image = image
                    button.title = ""
                    break
                }
            }
        }
        
        rebuildMenu()
        statusItem.menu = menu
    }
    
    private func rebuildMenu() {
        menu.removeAllItems()
        
        // Title
        let titleItem = NSMenuItem(title: "vibedeck  \(BuildInfo.short)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Status
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        refreshStatus()

        menu.addItem(NSMenuItem.separator())

        // 省电 / 休眠：睡前不用手动退出 App
        let power = PowerManager.shared
        let pauseItem = NSMenuItem(
            title: power.isSuspended ? "恢复接管（或按遥控器任意键）" : "暂停接管（省电）",
            action: #selector(toggleSuspend), keyEquivalent: "p")
        pauseItem.target = self
        pauseItem.state = power.isSuspended ? .on : .off
        menu.addItem(pauseItem)

        let disconnectItem = NSMenuItem(title: "睡前一键释放（省电）…",
                                        action: #selector(disconnectRemote), keyEquivalent: "")
        disconnectItem.target = self
        menu.addItem(disconnectItem)

        let testItem = NSMenuItem(title: power.isSuspended ? "结束休眠测试并恢复" : "立即测试休眠",
                                  action: #selector(testIdleSuspend), keyEquivalent: "")
        testItem.target = self
        menu.addItem(testItem)

        let idleSubmenu = NSMenu()
        let offItem = NSMenuItem(title: "关闭自动休眠", action: #selector(disableIdleSleep), keyEquivalent: "")
        offItem.target = self
        offItem.state = power.idleEnabled ? .off : .on
        idleSubmenu.addItem(offItem)
        idleSubmenu.addItem(NSMenuItem.separator())
        for minutes in IdlePolicy.allowedMinutes {
            let item = NSMenuItem(title: "\(minutes) 分钟",
                                  action: #selector(chooseIdleMinutes(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = minutes
            item.state = (power.idleEnabled && power.idleMinutes == minutes) ? .on : .off
            idleSubmenu.addItem(item)
        }
        let idleItem = NSMenuItem(
            title: "闲置自动休眠：\(power.idleEnabled ? "\(power.idleMinutes) 分钟" : "关")",
            action: nil, keyEquivalent: "")
        idleItem.submenu = idleSubmenu
        menu.addItem(idleItem)

        menu.addItem(NSMenuItem.separator())

        // 打开可视化设置面板（按键配置 / 语音输入都在里面）
        let settingsItem = NSMenuItem(title: "打开设置面板…",
                                      action: #selector(openSettingsPanel),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let permissionItem = NSMenuItem(title: "打开权限设置（输入监控）…",
                                        action: #selector(openInputMonitoringPane),
                                        keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        let summaryItem = NSMenuItem(title: mappingSummary(), action: nil, keyEquivalent: "")
        summaryItem.isEnabled = false
        menu.addItem(summaryItem)

        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc private func changeMapping(_ sender: NSMenuItem) {
        guard let (buttonKey, action) = sender.representedObject as? (String, ButtonAction) else {
            return
        }
        buttonMappings[buttonKey] = action
        saveMappings()
        rebuildMenu()
    }
    
    @objc private func openInputMonitoringPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSettingsPanel() {
        SettingsWindowController.shared.show()
    }

    private func mappingSummary() -> String {
        let store = BindingStore.shared
        return "语音键：\(store.binding(for: RemoteButton.siri.rawValue).summary)　返回键：\(store.binding(for: RemoteButton.menu.rawValue).summary)"
    }

    func updateConnectionStatus(connected: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastConnected = connected
            self.refreshStatus()
        }
    }

    /// 省电状态 / 设置变化后由 PowerManager 回调，重建菜单并刷新状态行
    func updatePowerState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.rebuildMenu()
            self.refreshStatus()
        }
    }

    private func refreshStatus() {
        if PowerManager.shared.isSuspended {
            statusMenuItem.title = "Status: 已暂停（省电）"
        } else {
            statusMenuItem.title = lastConnected ? "Status: Connected ✓" : "Status: Disconnected"
        }
        statusItem.button?.appearsDisabled = !lastConnected || PowerManager.shared.isSuspended
    }

    @objc private func toggleSuspend() {
        PowerManager.shared.toggle()
    }

    @objc private func disconnectRemote() {
        PowerManager.shared.disconnectRemote()
    }

    @objc private func testIdleSuspend() {
        PowerManager.shared.testIdleSuspend()
    }

    @objc private func disableIdleSleep() {
        PowerManager.shared.setIdleEnabled(false)
    }

    @objc private func chooseIdleMinutes(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        PowerManager.shared.setIdleEnabled(true)
        PowerManager.shared.setIdleMinutes(minutes)
    }
    
    func getMapping(for button: String) -> ButtonAction {
        return buttonMappings[button] ?? .none
    }
    
    // Map HID codes to button names
    private let hidCodeToButton: [String: String] = [
        "0x000C:0x00CD": "playPause",    // Play/Pause
        "0x000C:0x00B5": "nextTrack",    // Next (not a physical button but for mapping)
        "0x000C:0x00B6": "prevTrack",    // Previous (not a physical button but for mapping)
        "0x000C:0x00E9": "volumeUp",     // Volume Up
        "0x000C:0x00EA": "volumeDown",   // Volume Down
        "0x0001:0x0086": "menu",         // Menu button (System Menu Main)
        "0x000C:0x0080": "select",       // Select button
        "0x000C:0x0040": "menu",         // Menu (alternate)
        "0x000C:0x0223": "menu",         // Home
        "0x000C:0x0224": "back",         // Back
    ]
    
    /// Get the action name for a given HID code (for event interception)
    func getMappingForHIDCode(_ hidCode: String) -> String? {
        guard let buttonName = hidCodeToButton[hidCode],
              let action = buttonMappings[buttonName] else {
            return nil
        }
        return action.rawValue
    }
    
    /// Execute an action by name
    func executeAction(_ actionName: String) {
        guard let action = ButtonAction(rawValue: actionName) else { return }
        
        switch action {
        case .none:
            break
        case .playPause:
            mediaController?.sendMediaKey(.playPause)
        case .nextTrack:
            mediaController?.sendMediaKey(.next)
        case .previousTrack:
            mediaController?.sendMediaKey(.previous)
        case .volumeUp:
            mediaController?.sendMediaKey(.volumeUp)
        case .volumeDown:
            mediaController?.sendMediaKey(.volumeDown)
        case .mute:
            mediaController?.sendMediaKey(.mute)
        case .click:
            performClick()
        case .rightClick:
            performRightClick()
        case .escape:
            sendKey(kVK_Escape)
        case .space:
            sendKey(kVK_Space)
        case .enter:
            sendKey(kVK_Return)
        case .missionControl:
            sendMissionControlKey()
        }
    }
    
    private func sendMissionControlKey() {
        openMissionControl()
    }
    
    private func performClick() {
        let pos = NSEvent.mouseLocation
        let screenH = NSScreen.main?.frame.height ?? 0
        let cgPos = CGPoint(x: pos.x, y: screenH - pos.y)
        
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: cgPos, mouseButton: .left)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: cgPos, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        usleep(10000)
        up?.post(tap: .cghidEventTap)
    }
    
    private func performRightClick() {
        let pos = NSEvent.mouseLocation
        let screenH = NSScreen.main?.frame.height ?? 0
        let cgPos = CGPoint(x: pos.x, y: screenH - pos.y)
        
        let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: cgPos, mouseButton: .right)
        let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: cgPos, mouseButton: .right)
        down?.post(tap: .cghidEventTap)
        usleep(10000)
        up?.post(tap: .cghidEventTap)
    }
    
    private func sendKey(_ keyCode: Int) {
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: true)?.post(tap: .cghidEventTap)
        usleep(10000)
        CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: false)?.post(tap: .cghidEventTap)
    }
    
    @objc private func quitApp() {
        NSStatusBar.system.removeStatusItem(statusItem)
        NSApp.terminate(nil)
    }
}

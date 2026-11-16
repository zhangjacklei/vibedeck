//
//  SettingsWindow.swift
//  Remotastic (local fork)
//
//  主窗口：CleanMyMac X 风格的侧边栏 + 卡片式内容区。
//

import SwiftUI
import AppKit

// MARK: - 窗口

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingView(rootView: SettingsRootView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "vibedeck"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            // 界面按浅色设计（固定白色卡片），强制浅色外观，
            // 避免系统切到深色模式后出现"白底白字"看不清的问题
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = hosting
            window.minSize = NSSize(width: 900, height: 620)
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        }
        guard let window = window else { return }
        // LSUIElement(.accessory) 应用无法靠 NSApp.activate 抢到前台，
        // 窗口会被其它 App 完全盖住 → 看起来像"没启动 / 还是旧界面"。
        // 临时提升窗口层级并强制 order front，随后恢复普通层级。
        window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak window] in
            window?.level = .normal
        }
    }
}

// MARK: - 配色

enum Palette {
    static let windowBackground = LinearGradient(
        colors: [Color(red: 0.965, green: 0.972, blue: 0.985),
                 Color(red: 0.930, green: 0.940, blue: 0.960)],
        startPoint: .top, endPoint: .bottom)
    static let card = Color.white
    static let textSecondary = Color(white: 0.42)
    static let accent = Color(red: 0.38, green: 0.40, blue: 0.92)
    static let accentSoft = Color(red: 0.38, green: 0.40, blue: 0.92).opacity(0.10)
    static let separator = Color(white: 0.90)
}

// MARK: - 通用卡片

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Palette.card)
                    .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
            )
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.textSecondary)
            .textCase(.uppercase)
    }
}

// MARK: - 根视图

/// 启动参数：直接执行 `vibedeck.app/Contents/MacOS/vibedeck --select siri`
/// 可打开指定按键的配置页（`open --args` 对 LSUIElement 应用可能不传参）
enum LaunchOptions {
    static var selectedButton: RemoteButton? {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--select"), index + 1 < args.count,
           let button = RemoteButton(rawValue: args[index + 1]) { return button }
        return .playPause
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case overview
    case buttons
    case voice
    case power
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .buttons: return "按键映射"
        case .voice: return "语音输入"
        case .power: return "省电与休眠"
        case .about: return "关于"
        }
    }

    /// 支持 `--page voice` 之类的启动参数，方便直接打开某一页
    static var initial: SettingsPage {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--page"), index + 1 < args.count,
           let page = SettingsPage(rawValue: args[index + 1]) {
            return page
        }
        return .buttons
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .buttons: return "appletvremote.gen4.fill"
        case .voice: return "waveform"
        case .power: return "moon.fill"
        case .about: return "info.circle.fill"
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject private var store = BindingStore.shared
    @ObservedObject private var voice = VoiceInputController.shared
    @ObservedObject private var monitor = ConnectionMonitor.shared
    @State private var page: SettingsPage = SettingsPage.initial

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(Palette.windowBackground)
        .environment(\.colorScheme, .light)
        // popover / sheet 是独立窗口，需要显式声明浅色，否则深色系统下会白底白字
        .preferredColorScheme(.light)
        .onAppear {
            voice.refreshDevices()
            PermissionCenter.shared.refresh()
            monitor.probeBluetooth()
        }
    }

    // MARK: 侧边栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.accent, Palette.accent.opacity(0.75)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 38, height: 38)
                    .overlay(Image(systemName: "appletvremote.gen4.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white))
                    .shadow(color: Palette.accent.opacity(0.35), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("vibedeck").font(.system(size: 13, weight: .semibold))
                    Text("遥控器控制台").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 18)

            ForEach(SettingsPage.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { page = item }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                        Text(item.title).font(.system(size: 13, weight: page == item ? .semibold : .regular))
                        Spacer()
                    }
                    .foregroundStyle(page == item ? Palette.accent : Color(white: 0.25))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(page == item ? Color.white : Color.clear)
                            .shadow(color: .black.opacity(page == item ? 0.08 : 0), radius: 4, y: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(monitor.isConnected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(monitor.statusText)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .help(monitor.connectionLine)
                }
                Text(BuildInfo.short)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary)
                    .help("构建于 \(BuildInfo.binaryStamp)\n\(BuildInfo.bundlePath)")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 214)
        .background(.ultraThinMaterial)
    }

    // MARK: 内容

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                switch page {
                case .overview: OverviewPage()
                case .buttons: ButtonsPage()
                case .voice: VoicePage()
                case .power: PowerPage()
                case .about: AboutPage()
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 30)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(page.title).font(.system(size: 26, weight: .bold))
            Spacer()
        }
        .padding(.bottom, 2)
    }
}

// MARK: - 连接状态（轻量全局镜像）

final class ConnectionMonitor: ObservableObject {
    static let shared = ConnectionMonitor()

    private static let waitingName = "等待遥控器…"
    private static let unnamedRemote = "Siri Remote"

    @Published var isConnected = false
    @Published var deviceName = waitingName
    /// system_profiler 里可见的遥控器（BLE 已配对但未产生 HID 时用它给出下一步）
    @Published var bluetoothNames: [String] = []

    /// HID 重新枚举钩子，由 AppDelegate 注入，供界面「重新检测」调用
    static var refreshHID: (() -> Void)?

    /// 概览页与省电页共用的主状态文案：两页必须逐字一致
    var statusText: String { isConnected ? "遥控器已连接" : "等待遥控器连接" }

    /// 共用状态图标
    var statusSymbol: String {
        isConnected ? "appletvremote.gen4.fill" : "dot.radiowaves.left.and.right"
    }

    /// 未连接时区分「系统蓝牙里能看到」与「完全没看到」，避免用户无从下手
    static func detail(connected: Bool, deviceName: String, bluetoothNames: [String]) -> String {
        guard !connected else { return deviceName }
        if let visible = bluetoothNames.first, !visible.isEmpty {
            return "系统蓝牙可见 \(visible)，但 HID 尚未接管：请按遥控器任意键唤醒"
        }
        return "请按遥控器任意键，或检查系统蓝牙"
    }

    /// 共用副文案：未连接时给出明确下一步，不残留"已连接"暗示
    var statusDetail: String {
        Self.detail(connected: isConnected, deviceName: deviceName, bluetoothNames: bluetoothNames)
    }

    var bluetoothLine: String {
        bluetoothNames.isEmpty ? "系统蓝牙中未发现遥控器" : "系统蓝牙可见：\(bluetoothNames.joined(separator: "、"))"
    }

    /// 后台探测蓝牙可见性；system_profiler 会阻塞，不能放主线程
    func probeBluetooth() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let names = BluetoothRemoteController.connectedRemotes().map { $0.name }
            DispatchQueue.main.async { self?.bluetoothNames = names }
        }
    }

    /// 界面「重新检测」：权限、HID、蓝牙、语音一次性全部刷新
    func recheckAll() {
        PermissionProbe.invalidateCachedStatuses()
        PermissionCenter.shared.refresh()
        VoiceInputController.shared.checkAuthorization()
        Self.refreshHID?()
        probeBluetooth()
    }

    /// 省电页底部的一行式状态，与 statusText 同源，禁止各页自行拼装
    var connectionLine: String {
        "\(deviceName) · \(isConnected ? "已连接" : "未连接")"
    }

    func update(connected: Bool, name: String? = nil) {
        DispatchQueue.main.async { self.apply(connected: connected, name: name) }
    }

    /// 同步应用，供 CLI 自检使用（命令行没有 runloop 等待 async）
    func apply(connected: Bool, name: String? = nil) {
        isConnected = connected
        if connected {
            // 已连接但产品名读不到时，绝不能保留"等待遥控器…"这种自相矛盾的文案
            deviceName = (name?.isEmpty == false) ? name! : Self.unnamedRemote
        } else {
            deviceName = Self.waitingName
        }
    }
}

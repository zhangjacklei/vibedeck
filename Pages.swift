//
//  Pages.swift
//  Remotastic (local fork)
//
//  五个页面：概览 / 按键映射 / 语音输入 / 省电与休眠 / 关于
//

import SwiftUI
import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - 权限帮助

enum PermissionHelp {
    static func inputMonitoringGranted() -> Bool {
        CGPreflightListenEventAccess()
    }

    static func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    static func openInputMonitoring() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    static func openAccessibility() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openMicrophone() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func openSpeechRecognition() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
    }

    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - 概览

struct OverviewPage: View {
    @ObservedObject private var monitor = ConnectionMonitor.shared
    @ObservedObject private var store = BindingStore.shared
    @ObservedObject private var voice = VoiceInputController.shared
    @ObservedObject private var permissions = PermissionCenter.shared
    @State private var tick = 0

    var body: some View {
        VStack(spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(monitor.isConnected ? Color.green.opacity(0.14) : Color.orange.opacity(0.14))
                                .frame(width: 44, height: 44)
                            Image(systemName: monitor.statusSymbol)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(monitor.isConnected ? .green : .orange)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(monitor.statusText)
                                .font(.system(size: 16, weight: .semibold))
                            Text(monitor.statusDetail)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                    }
                    Divider().overlay(Palette.separator)
                    HStack(spacing: 22) {
                        stat(title: "触控板", value: "驱动鼠标指针", symbol: "cursorarrow.rays")
                        stat(title: "语音键", value: voice.autoPaste ? "按住说话 · 自动粘贴" : "按住说话", symbol: "mic.fill")
                        stat(title: "已配置按键", value: "\(configuredCount) 个", symbol: "keyboard")
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "系统权限")
                    permissionRow(title: "输入监控",
                                  detail: permissions.inputMonitoringDetail,
                                  granted: permissions.inputMonitoringGranted,
                                  status: PermissionCenter.shared.snapshot.inputStatusLabel,
                                  action: PermissionHelp.openInputMonitoring)
                    Divider().overlay(Palette.separator)
                    permissionRow(title: "辅助功能",
                                  detail: "移动指针、注入按键与语音文字",
                                  granted: permissions.accessibilityGranted,
                                  action: PermissionHelp.openAccessibility)
                    Divider().overlay(Palette.separator)
                    permissionRow(title: "麦克风 + 语音识别",
                                  detail: permissions.voiceDetail,
                                  granted: voice.authorized,
                                  action: PermissionHelp.openMicrophone)
                    if !permissions.inputMonitoringGranted || !permissions.accessibilityGranted || !voice.authorized {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("提示：授权变更后无需重启，回到本窗口点「重新检测」。")
                            Text("若系统设置里开关已是打开状态：把 vibedeck 的开关关掉再打开一次（必要时移除后重新添加），用于刷新旧签名残留的记录。")
                            Text("本应用标识：\(Bundle.main.bundleIdentifier ?? "?") · \(BuildInfo.short)")
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(monitor.bluetoothLine)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                    Button {
                        tick += 1
                        monitor.recheckAll()
                    } label: {
                        Label("重新检测", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: "当前按键")
                    ForEach(RemoteButton.allCases.filter { $0 != .power }) { button in
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: button))
                                .font(.system(size: 12))
                                .frame(width: 18)
                                .foregroundStyle(Palette.accent)
                            Text(button.title).font(.system(size: 12))
                            Spacer()
                            Text(displaySummary(for: button))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            }
        }
        .id(tick)
    }

    private var configuredCount: Int {
        RemoteButton.allCases.filter { store.binding(for: $0.rawValue).kind != .none }.count
    }

    private func stat(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
                Text(value).font(.system(size: 12, weight: .medium))
            }
        }
    }

    private func permissionRow(title: String, detail: String, granted: Bool,
                               status: String? = nil, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            if !granted {
                if let status = status {
                    Text(status).font(.system(size: 10)).foregroundStyle(.orange)
                }
                Button("去开启", action: action).buttonStyle(.bordered).controlSize(.small)
            } else {
                Text("已授权").font(.system(size: 11)).foregroundStyle(.green)
            }
        }
    }

    private func displaySummary(for button: RemoteButton) -> String {
        let binding = store.binding(for: button.rawValue)
        if binding.kind == .launchApp, let app = AppCatalog.shared.app(matching: binding.value) {
            return app.name
        }
        return binding.summary
    }

    private func icon(for button: RemoteButton) -> String {
        switch button {
        case .power: return "power"
        case .mute: return "speaker.slash.fill"
        case .volumeUp: return "speaker.plus.fill"
        case .volumeDown: return "speaker.minus.fill"
        case .playPause: return "playpause.fill"
        case .menu: return "chevron.backward"
        case .tv: return "tv.fill"
        case .siri: return "mic.fill"
        case .ringUp: return "chevron.up"
        case .ringDown: return "chevron.down"
        case .ringLeft: return "chevron.left"
        case .ringRight: return "chevron.right"
        case .select: return "cursorarrow.click"
        }
    }
}

// MARK: - 按键映射

struct ButtonsPage: View {
    @ObservedObject private var store = BindingStore.shared
    @ObservedObject private var recorder = ShortcutRecorder.shared
    @State private var selected: RemoteButton? = LaunchOptions.selectedButton
    @State private var showAppPicker = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Card(padding: 8) {
                RemoteCanvas(selected: $selected, store: store)
                    .frame(width: 316, height: 540)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.93)],
                                                 startPoint: .top, endPoint: .bottom))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(white: 0.90), lineWidth: 1))
                    )
            }
            .frame(width: 336)

            Card {
                VStack(alignment: .leading, spacing: 16) {
                    if let button = selected {
                        editor(for: button)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("点左侧遥控器上的任意按键").font(.system(size: 15, weight: .semibold))
                            Text("选中后即可在这里指定它要执行的操作。")
                                .font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func editor(for button: RemoteButton) -> some View {
        let binding = store.binding(for: button.rawValue)

        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.accentSoft)
                    .frame(width: 38, height: 38)
                Image(systemName: binding.kind.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(button.title).font(.system(size: 15, weight: .semibold))
                Text(button.hint).font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
            }
            Spacer()
        }

        SectionTitle(text: "执行操作")

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], spacing: 8) {
            ForEach(BindingKind.allCases.filter { $0 != .scrollUp && $0 != .scrollDown }) { kind in
                actionTile(kind, selected: binding.kind == kind) {
                    var next = binding
                    if next.kind != kind {
                        // 值域不同则清空，避免 "return" 这类旧值跟到「打开 App」上
                        if next.kind.valueGroup != kind.valueGroup { next.value = "" }
                        next.kind = kind
                    }
                    if !kind.needsValue { next.value = "" }
                    store.set(next, for: button.rawValue)
                }
            }
        }

        if binding.kind == .launchApp {
            VStack(alignment: .leading, spacing: 8) {
                Text("要打开的 App")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                HStack(spacing: 8) {
                    if let app = AppCatalog.shared.app(matching: binding.value) {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        }
                        Text(app.name)
                            .font(.system(size: 12, weight: .medium))
                        Text(app.id)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text("未选择 App")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                    Button {
                        showAppPicker = true
                    } label: {
                        Label("选择 App…", systemImage: "square.grid.2x2")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .popover(isPresented: $showAppPicker, arrowEdge: .bottom) {
                        AppPickerView(selection: Binding(
                            get: { store.binding(for: button.rawValue).value },
                            set: { value in
                                var next = store.binding(for: button.rawValue)
                                next.value = value
                                store.set(next, for: button.rawValue)
                            }
                        ))
                        .padding(12)
                        .frame(width: 330)
                    }
                }
            }
        } else if binding.kind.needsValue {
            VStack(alignment: .leading, spacing: 6) {
                Text(binding.kind == .keystroke ? "快捷键" : "内容")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                TextField(binding.kind.valuePlaceholder, text: Binding(
                    get: { store.binding(for: button.rawValue).value },
                    set: { value in
                        var next = store.binding(for: button.rawValue)
                        next.value = value
                        store.set(next, for: button.rawValue)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

                if binding.kind == .keystroke {
                    HStack(spacing: 8) {
                        if recorder.isRecording {
                            Button {
                                recorder.stop()
                            } label: {
                                Label("请按下组合键…（点此取消）", systemImage: "record.circle")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            Button {
                                recorder.start { captured in
                                    var next = store.binding(for: button.rawValue)
                                    next.value = captured
                                    store.set(next, for: button.rawValue)
                                }
                            } label: {
                                Label("录制按键", systemImage: "keyboard")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if !binding.value.isEmpty {
                            if let problem = KeySender.validate(binding.value) {
                                Label(problem, systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                            } else {
                                Text("识别为 \(KeySender.prettyCombo(binding.value))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(red: 0.10, green: 0.55, blue: 0.28))
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    Text("任意按键或组合：j / esc / f5 / space、cmd+shift+p、ctrl+alt+→、⌘⇧P；多组用逗号分隔（cmd+c, cmd+v）。下面是常用预设，点「录制按键」可直接按实体键盘。")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text("常用")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textSecondary)
                        ForEach(["return", "escape", "tab", "cmd+return", "cmd+shift+p", "ctrl+c", "ctrl+l"], id: \.self) { preset in
                            Button(KeySender.prettyCombo(preset)) {
                                var next = binding
                                next.value = preset
                                store.set(next, for: button.rawValue)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
            }
        }

        Divider().overlay(Palette.separator)

        HStack {
            Text("当前：\(binding.summary)")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Button("恢复默认") {
                if let fallback = BindingStore.defaults[button] {
                    store.set(fallback, for: button.rawValue)
                } else {
                    store.set(.none, for: button.rawValue)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }

        if button == .siri {
            Text("选「按住语音输入」后：按住 Siri 键说话，松手自动把文字粘贴到当前光标处。麦克风可在「语音输入」页切换。")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if button == .power {
            Text("电源键由 macOS 的 loginwindow 直接接管，应用层通常收不到事件，因此这里只作为展示。")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionTile(_ kind: BindingKind, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: kind.symbol).font(.system(size: 12, weight: .medium))
                Text(kind.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Palette.accent : Color(white: 0.25))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Palette.accentSoft : Color(white: 0.97))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? Palette.accent.opacity(0.55) : Color(white: 0.90), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 语音输入

struct VoicePage: View {
    @ObservedObject private var voice = VoiceInputController.shared
    @ObservedObject private var permissions = PermissionCenter.shared
    @State private var testMode = false

    var body: some View {
        VStack(spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: "权限")
                    HStack(spacing: 10) {
                        Image(systemName: voice.authorized ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(voice.authorized ? .green : .orange)
                        Text(permissions.voiceDetail)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        if !voice.authorized {
                            Button("请求授权") {
                                if AppIdentity.isAppBundle {
                                    voice.requestAuthorization { permissions.refresh() }
                                } else {
                                    voice.checkAuthorization()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    // 两项 TCC 权限必须分开显示，否则用户不知道该去哪个设置页
                    HStack(spacing: 12) {
                        permissionChip(title: "麦克风",
                                       value: PermissionProbe.statusLabel(permissions.microphoneRaw),
                                       granted: permissions.microphoneGranted,
                                       action: PermissionHelp.openMicrophone)
                        permissionChip(title: "语音识别",
                                       value: PermissionProbe.statusLabel(permissions.speechRaw),
                                       granted: permissions.speechGranted,
                                       action: PermissionHelp.openSpeechRecognition)
                        Spacer()
                        Button("重新检测") {
                            PermissionProbe.invalidateCachedStatuses()
                            voice.checkAuthorization()
                            permissions.refresh()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if let reason = AppIdentity.voiceBlockReason() {
                        Text(reason).font(.system(size: 10)).foregroundStyle(.orange)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "麦克风来源")

                    HStack(spacing: 10) {
                        micTile(title: "Mac 麦克风",
                                subtitle: voice.selectedDeviceUID == VoiceInputController.remoteMicTag
                                          ? "（当前实际在用这个）"
                                          : currentMacMicName,
                                symbol: "laptopcomputer",
                                selected: true) {
                            voice.selectedDeviceUID = ""
                        }
                        micTile(title: "遥控器麦克风",
                                subtitle: voice.remoteMicAvailable ? "已检测到，可选" : "macOS 未开放，暂不可用",
                                symbol: "appletvremote.gen4",
                                selected: false,
                                enabled: voice.remoteMicAvailable) {
                            voice.selectedDeviceUID = VoiceInputController.remoteMicTag
                        }
                    }

                    if !voice.remoteMicAvailable {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textSecondary)
                            Text("A2540 的麦克风不是标准蓝牙麦克风，只在按住 Siri 时经私有 BLE 通道送给系统 Siri，macOS 不把它暴露给任何 App。因此这里固定使用 Mac 麦克风录音，遥控器只负责触发。")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if voice.selectedDeviceUID == VoiceInputController.remoteMicTag && !voice.remoteMicAvailable {
                        HStack(spacing: 8) {
                            Text("已回退到 Mac 麦克风（遥控器麦克风不可用）")
                                .font(.system(size: 11))
                                .foregroundStyle(.orange)
                            Button("改用 Mac 麦克风") { voice.selectedDeviceUID = "" }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                        }
                    }

                    if voice.selectedDeviceUID != VoiceInputController.remoteMicTag {
                        HStack(spacing: 8) {
                            Picker("", selection: $voice.selectedDeviceUID) {
                                Text("系统默认输入设备").tag("")
                                ForEach(voice.micDevices) { device in
                                    Text(device.name).tag(device.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 260)
                            Button {
                                voice.refreshDevices()
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            Spacer()
                        }
                    }

                    Text(voice.selectedDeviceUID == VoiceInputController.remoteMicTag
                         ? "遥控器麦克风录音更贴近嘴部；若系统未暴露该设备，会自动回退到 Mac 麦克风，识别不受影响。"
                         : "使用 Mac 内置或外接麦克风录音；用 Siri 键唤醒时，声音仍会从遥控器送入 Mac。")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "识别")
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("识别语言").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                            Picker("", selection: $voice.locale) {
                                Text("中文（普通话）").tag("zh-CN")
                                Text("中文（台湾）").tag("zh-TW")
                                Text("English (US)").tag("en-US")
                                Text("日本語").tag("ja-JP")
                            }
                            .labelsHidden()
                            .frame(width: 170)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("结束后").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                            Toggle("自动粘贴到当前输入框", isOn: $voice.autoPaste)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("浮窗").font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                            Toggle("显示实时转写浮窗", isOn: $voice.showHUD)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                        Spacer()
                    }

                    Divider().overlay(Palette.separator)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Button {
                                if voice.isListening { voice.stop() } else { voice.start() }
                            } label: {
                                Label(voice.isListening ? "停止并粘贴" : "开始测试识别",
                                      systemImage: voice.isListening ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(minWidth: 120)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)

                            levelMeter
                            Spacer()
                        }
                        Text(voice.transcript.isEmpty ? "说话内容会实时显示在这里…" : voice.transcript)
                            .font(.system(size: 13))
                            .foregroundStyle(voice.transcript.isEmpty ? Palette.textSecondary : .primary)
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(white: 0.97)))
                    }

                    if case let .failed(message) = voice.state {
                        Text(message).font(.system(size: 11)).foregroundStyle(.red)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(text: "用法")
                    Text("① 在「按键映射」里把 Siri 键设为「按住语音输入」\n② 按住遥控器 Siri 键说话，屏幕上方出现实时转写\n③ 松手即结束，文字自动粘贴到当前光标位置")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func permissionChip(title: String, value: String, granted: Bool,
                                action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(granted ? .green : .orange)
            Text("\(title)：\(value)").font(.system(size: 11))
            if !granted {
                Button("设置") { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(white: 0.97)))
    }

    private var currentMacMicName: String {
        let devices = voice.micDevices
        if voice.selectedDeviceUID.isEmpty || voice.selectedDeviceUID == VoiceInputController.remoteMicTag {
            return devices.first?.name ?? "系统默认"
        }
        return devices.first { $0.id == voice.selectedDeviceUID }?.name ?? "系统默认"
    }

    private func micTile(title: String, subtitle: String, symbol: String,
                         selected: Bool, enabled: Bool = true,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Palette.accentSoft : Color(white: 0.96))
                        .frame(width: 30, height: 30)
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? Palette.accent : Color(white: 0.45))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Palette.accent : Color(white: 0.22))
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? Palette.accent : Color(white: 0.80))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Palette.accentSoft : Color(white: 0.975))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Palette.accent.opacity(0.5) : Color(white: 0.90), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.55)
        .disabled(!enabled)
    }

    private var levelMeter: some View {
        HStack(spacing: 3) {
            ForEach(0..<14, id: \.self) { index in
                Capsule()
                    .fill(CGFloat(index) / 14.0 < CGFloat(voice.level) ? Palette.accent : Color(white: 0.88))
                    .frame(width: 4, height: CGFloat(6 + index % 5 * 3))
            }
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.12), value: voice.level)
    }
}

// MARK: - 省电与休眠

struct PowerPage: View {
    @ObservedObject private var power = PowerManager.shared
    @ObservedObject private var monitor = ConnectionMonitor.shared

    var body: some View {
        VStack(spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill((monitor.isConnected ? Color.green : Color.orange).opacity(0.14))
                                .frame(width: 44, height: 44)
                            Image(systemName: monitor.statusSymbol)
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(monitor.isConnected ? .green : .orange)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            // 主标题与概览页共用 monitor.statusText，保证两页连接状态逐字一致；
                            // 接管/省电状态放在副标题，避免被误读为连接状态
                            Text(monitor.statusText)
                                .font(.system(size: 16, weight: .semibold))
                            Text(statusDetail)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                    }

                    Divider().overlay(Palette.separator)

                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.accent)
                        Text(power.remainingText)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        if !power.lastActivityText.isEmpty && !power.isSuspended {
                            Text("最近操作 \(power.lastActivityText)")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            if power.isSuspended {
                                power.resume(trigger: "设置面板")
                            } else {
                                power.suspend(.manual)
                            }
                        } label: {
                            Label(power.isSuspended ? "立即恢复接管" : "立即暂停接管",
                                  systemImage: power.isSuspended ? "play.circle" : "pause.circle")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            power.disconnectRemote()
                        } label: {
                            Label("睡前一键释放", systemImage: "xmark.circle")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            BluetoothRemoteController.openSettings()
                        } label: {
                            Label("蓝牙设置", systemImage: "gearshape")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if !power.lastBluetoothResult.isEmpty {
                        Text(power.lastBluetoothResult)
                            .font(.system(size: 11))
                            .foregroundStyle(power.lastBluetoothResult.contains("不允许") ? .orange : Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "闲置自动休眠")

                    HStack(spacing: 10) {
                        Toggle("闲置达到设定时长后，自动释放遥控器", isOn: Binding(
                            get: { power.idleEnabled },
                            set: { power.setIdleEnabled($0) }
                        ))
                        .font(.system(size: 12))
                        .toggleStyle(.switch)
                        .tint(Palette.accent)
                        .controlSize(.small)
                        Text(power.idleEnabled ? "已开启" : "已关闭")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(power.idleEnabled ? .green : Palette.textSecondary)
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Text("闲置时长").font(.system(size: 12))
                        Picker("", selection: Binding(
                            get: { power.idleMinutes },
                            set: { power.setIdleMinutes($0) }
                        )) {
                            ForEach(IdlePolicy.allowedMinutes, id: \.self) { minutes in
                                Text("\(minutes) 分钟").tag(minutes)
                            }
                        }
                        .frame(width: 130)
                        .disabled(!power.idleEnabled)
                        Spacer()
                    }

                    Text("只要按键或触摸触控板就重新计时。休眠后按遥控器任意键会自动恢复接管，唤醒的那一下按键不执行映射动作。")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button {
                            power.testIdleSuspend()
                        } label: {
                            Label(power.isSuspended ? "结束测试并恢复" : "立即测试休眠",
                                  systemImage: "testtube.2")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Text("不必等 \(power.idleMinutes) 分钟：点这里立刻进入休眠，再按遥控器任意键验证是否自动恢复。")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Group {
                        SectionTitle(text: "为什么一晚上会没电")
                        bullet("A2540 没有电源开关，静置几分钟才会自行深睡；顶部电源键只控制 Apple TV。")
                        bullet("原版逻辑每 2 秒枚举一次触控板设备、每 15 秒重启一次触控板，会不断把遥控器从深睡里唤醒。")
                        bullet("Mac 开着 Power Nap / 有防睡眠断言时，屏幕黑了系统并没睡，耗电会持续一整夜。")
                    }
                    Divider().overlay(Palette.separator)
                    Group {
                        SectionTitle(text: "暂停时做了什么")
                        bullet("释放 HID 独占（kIOHIDOptionsTypeSeizeDevice），改为不主动发数据的被动按键监听。")
                        bullet("完全停掉 MultitouchSupport 扫描与重连定时器，遥控器得以进入深睡。")
                        bullet("唤醒有三条冗余路径：HID 按键、系统媒体键、设备重新枚举；任意一条命中都会自动恢复接管。")
                    }
                    Divider().overlay(Palette.separator)
                    Group {
                        SectionTitle(text: "关于「一键断开」")
                        bullet("本机实测：A2540 是 BLE HID，macOS 不把它的连接交给第三方 App，无法用代码精确断开。")
                        bullet("这个按钮的实际作用是立即释放全部资源让遥控器自行深睡；要彻底断开请点「蓝牙设置」手动断开。")
                        bullet("按钮结果会如实显示在这里，不会伪装成已断开。")
                    }
                    Divider().overlay(Palette.separator)
                    Group {
                        SectionTitle(text: "仍然建议")
                        bullet("睡前合盖让 Mac 真正睡眠，或顺手在系统设置里关一下蓝牙；遥控器面朝上放，别压住触控板。")
                        bullet("如果按任意键没恢复（例如遥控器已彻底断电），直接点「立即恢复接管」即可，不会卡在暂停状态。")
                        bullet("连接状态：\(monitor.connectionLine)（与概览页同源）")
                    }
                }
            }
        }
    }

    /// 副标题只描述「接管/省电状态」，连接状态一律交给 monitor.statusText，
    /// 避免两页对同一事实给出不同说法
    private var statusDetail: String {
        let mode = power.isSuspended ? "已暂停接管 · 省电中" : "正在接管遥控器"
        // 未连接时副文案也复用 monitor 的提示，与概览页逐字同源
        guard monitor.isConnected else {
            return "\(monitor.statusDetail) · \(power.isSuspended ? "已暂停接管" : "接管已就绪")"
        }
        if power.isSuspended, let at = power.suspendedAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return "\(mode) · 始于 \(formatter.string(from: at))"
        }
        return "\(mode) · HID 独占 + 触控板轮询运行"
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Palette.accent).frame(width: 4, height: 4)
                .padding(.top, 5)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 关于

struct AboutPage: View {
    var body: some View {
        VStack(spacing: 16) {
            Card {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [Palette.accent, Palette.accent.opacity(0.7)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 54, height: 54)
                        .overlay(Image(systemName: "appletvremote.gen4.fill")
                            .font(.system(size: 24, weight: .semibold)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("vibedeck").font(.system(size: 16, weight: .bold))
                        Text("基于 Remotastic 的本地改造版 · 支持二代 Siri Remote (A2540, 0x0314)")
                            .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        Text("\(BuildInfo.short) · 构建于 \(BuildInfo.binaryStamp)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer()
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: "本项目改动")
                    ForEach([
                        "补充 A2540 / A2854 的产品 ID，使二代遥控器可被识别",
                        "按键映射升级为任意快捷键、文本、App、命令，并支持按住语音输入",
                        "新增可视化遥控器界面，点按键即可配置",
                        "固定本地自签身份签名，系统授权在重新编译后依然有效",
                        "界面固定浅色外观，深色系统下不会再出现白底白字",
                        "实时转写浮窗默认关闭，需要时在「语音输入」页打开",
                        "侧边栏 / 菜单栏 / 关于页显示唯一构建号，便于核对版本",
                        "快捷键支持任意单键与组合、符号写法、多组连续动作，并可录制实体键盘按键",
                        "新增省电与休眠：闲置自动释放 HID 独占 + 停止触控板轮询，按键自动唤醒",
                        "菜单栏可暂停接管、睡前一键释放、立即测试休眠、调整闲置时长"
                    ], id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11)).foregroundStyle(.green)
                            Text(line).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(text: "上游与许可")
                    Text("Remotastic（MIT）: github.com/lauschue/Remotastic")
                        .font(.system(size: 12, design: .monospaced))
                    Text("触控板读取使用私有 MultitouchSupport 框架，macOS 大版本升级后可能需要适配。")
                        .font(.system(size: 11)).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

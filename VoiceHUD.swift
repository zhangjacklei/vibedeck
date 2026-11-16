//
//  VoiceHUD.swift
//  vibedeck
//
//  按住语音键时的轻量转写提示条。
//  设计约束（修 "严重影响输入"）：
//   - 永不成为 key / main 窗口 → 绝不抢键盘焦点
//   - 鼠标事件穿透 → 不挡点击
//   - 停靠在屏幕右上角，避开底部输入框
//   - 识别结束即自动淡出，并有看门狗兜底
//   - 可在「语音输入」页关闭
//

import AppKit
import SwiftUI
import Combine

/// 只显示、不参与焦点管理的面板
final class VoiceHUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class VoiceHUDController {
    static let shared = VoiceHUDController()

    private var panel: VoiceHUDPanel?
    private var watchdog: Timer?

    private let panelSize = NSSize(width: 320, height: 64)

    func show() {
        guard VoiceInputController.shared.showHUD else { return }

        if panel == nil {
            let panel = VoiceHUDPanel(contentRect: NSRect(origin: .zero, size: panelSize),
                                      styleMask: [.nonactivatingPanel, .borderless],
                                      backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.hidesOnDeactivate = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.contentView = NSHostingView(rootView: VoiceHUDView())
            self.panel = panel
        }

        guard let panel = panel else { return }
        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        startWatchdog()
    }

    func hide(animated: Bool = true) {
        watchdog?.invalidate()
        watchdog = nil
        guard let panel = panel, panel.isVisible else { return }
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        } else {
            panel.alphaValue = 0
            panel.orderOut(nil)
        }
    }

    /// 右上角停靠：远离常见输入框位置
    private func position(_ panel: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - panelSize.width - 22,
                                     y: visible.maxY - panelSize.height - 22))
    }

    /// 兜底：只要不在识别中（空闲/失败），0.4s 内自动收起
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            switch VoiceInputController.shared.state {
            case .idle, .failed:
                self.hide()
            case .listening, .finishing:
                break
            }
        }
    }
}

private struct VoiceHUDView: View {
    @ObservedObject private var voice = VoiceInputController.shared

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.44, blue: 0.95),
                                                  Color(red: 0.56, green: 0.42, blue: 0.96)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                Image(systemName: voice.isListening ? "waveform" : "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(voice.transcript.isEmpty ? "正在聆听…" : voice.transcript)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.head)
                levelBars
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.14).opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        )
        .padding(4)
        // HUD 是深色卡片，固定深色语义色，避免跟随系统外观导致白底白字
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }

    private var levelBars: some View {
        HStack(spacing: 2) {
            ForEach(0..<18, id: \.self) { index in
                Capsule()
                    .fill(CGFloat(index) / 18.0 < CGFloat(voice.level * 1.8)
                          ? Color(red: 0.60, green: 0.66, blue: 1.0)
                          : Color.white.opacity(0.15))
                    .frame(width: 2.5, height: CGFloat(3 + index % 4 * 2))
            }
        }
        .frame(height: 12)
        .animation(.easeOut(duration: 0.12), value: voice.level)
    }
}

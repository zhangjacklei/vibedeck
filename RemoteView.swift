//
//  RemoteView.swift
//  vibedeck
//
//  严格按真机照片比例绘制 A2540。
//  以下坐标全部来自对参考照片的像素测量（机身 219×852 px，宽高比 0.257）：
//    圆盘   直径 0.890×机身宽，中心 (0.498, 0.209)，四向点在 0.90R
//    返回/播放/静音  直径 0.092×机身高，中心 x=0.285，y=0.377 / 0.487 / 0.594
//    TV     0.356×0.092，中心 (0.715, 0.377)
//    音量   0.342×0.200，中心 (0.712, 0.540)
//    电源   中心 (0.804, 0.050)，直径 0.205×机身宽
//    麦克风孔 中心 (0.500, 0.050)
//  语音键在真机上是右侧边框上的侧键，这里画成侧边凸起。
//

import SwiftUI

struct RemoteCanvas: View {
    @Binding var selected: RemoteButton?
    @ObservedObject var store: BindingStore

    // 设计画布（机身比例固定 0.257，不改动）
    private let bodyWidth: CGFloat = 156
    private let bodyHeight: CGFloat = 594          // 156 × 3.805（真机产品图 369×1404）
    private let canvasSize = CGSize(width: 200, height: 628)
    private let bodyOrigin = CGPoint(x: 22, y: 16)

    // 真机测量值（相对机身宽/高的归一化坐标）
    private let padCenterN = CGPoint(x: 0.493, y: 0.211)
    private let padDiameterN: CGFloat = 0.875      // 相对机身宽
    private let keyDiameterN: CGFloat = 0.090      // 相对机身高
    private let leftColumnN: CGFloat = 0.285
    private let rightColumnN: CGFloat = 0.701
    private let rowBackN: CGFloat = 0.380
    private let rowPlayN: CGFloat = 0.486
    private let rowMuteN: CGFloat = 0.593
    private let volumeSizeN = CGSize(width: 0.336, height: 0.198)
    private let volumeCenterN = CGPoint(x: 0.701, y: 0.540)
    private let powerCenterN = CGPoint(x: 0.804, y: 0.050)
    private let powerDiameterN: CGFloat = 0.205
    private let micHoleN = CGPoint(x: 0.500, y: 0.050)

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / canvasSize.width,
                            proxy.size.height / canvasSize.height)
            canvas
                .frame(width: canvasSize.width, height: canvasSize.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: canvasSize.width * scale, height: canvasSize.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: 坐标换算

    private func px(_ nx: CGFloat) -> CGFloat { bodyOrigin.x + nx * bodyWidth }
    private func py(_ ny: CGFloat) -> CGFloat { bodyOrigin.y + ny * bodyHeight }

    private var padDiameter: CGFloat { padDiameterN * bodyWidth }
    private var keyDiameter: CGFloat { keyDiameterN * bodyHeight }
    private var padCenter: CGPoint { CGPoint(x: px(padCenterN.x), y: py(padCenterN.y)) }

    private var canvas: some View {
        ZStack {
            deviceBody
            sideSiriButton
            micHole
            powerButton
            clickpad
            controlCluster
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    // MARK: 机身

    private var deviceBody: some View {
        RoundedRectangle(cornerRadius: 25, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.95, green: 0.95, blue: 0.96),
                         Color(red: 0.86, green: 0.86, blue: 0.88),
                         Color(red: 0.79, green: 0.79, blue: 0.81),
                         Color(red: 0.88, green: 0.88, blue: 0.90)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .strokeBorder(Color(white: 0.72), lineWidth: 0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.9), Color.clear, Color.white.opacity(0.25)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.2))
            .frame(width: bodyWidth, height: bodyHeight)
            .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 14)
            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 2)
            .position(x: bodyOrigin.x + bodyWidth / 2, y: bodyOrigin.y + bodyHeight / 2)
    }

    // MARK: 侧边语音键（真机在右侧边框，画成细长凸起）

    private var sideSiriButton: some View {
        let height = bodyHeight * 0.108
        let isSelected = selected == .siri
        return Button {
            selected = .siri
        } label: {
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.93), Color(white: 0.70)],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(Capsule().strokeBorder(Color(white: 0.64), lineWidth: 0.8))
                .overlay(Capsule().strokeBorder(isSelected ? Palette.accent : Color.clear, lineWidth: 2))
                .frame(width: 9, height: height)
                .shadow(color: .black.opacity(0.18), radius: 2, x: 1, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("语音键（机身右侧）— \(store.binding(for: RemoteButton.siri.rawValue).summary)")
        .position(x: bodyOrigin.x + bodyWidth - 2, y: py(0.211))
    }

    // MARK: 顶部麦克风孔 / 电源

    private var micHole: some View {
        Capsule()
            .fill(Color(white: 0.15))
            .frame(width: 10, height: 4.4)
            .position(x: px(micHoleN.x), y: py(micHoleN.y))
    }

    private var powerButton: some View {
        let d = powerDiameterN * bodyWidth
        return hotspot(.power) {
            ZStack {
                Circle().fill(Color(white: 0.90))
                Circle().strokeBorder(selected == .power ? Palette.accent : Color(white: 0.60), lineWidth: 1.2)
                Image(systemName: "power")
                    .font(.system(size: d * 0.46, weight: .regular))
                    .foregroundStyle(Color(white: 0.30))
            }
            .contentShape(Circle())
        }
        .frame(width: d, height: d)
        .position(x: px(powerCenterN.x), y: py(powerCenterN.y))
    }

    // MARK: 圆盘

    private var clickpad: some View {
        let d = padDiameter
        let dotRadius = d * 0.45            // 0.90R
        return ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [Color(white: 0.22), Color(white: 0.11), Color(white: 0.17)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .frame(width: d, height: d)

            // 内圈（实测约 0.55 直径）
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.09)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1.4))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5))
                .frame(width: d * 0.55, height: d * 0.55)

            // 四向点（0.90R）
            directionDot(.ringUp).position(x: d / 2, y: d / 2 - dotRadius)
            directionDot(.ringDown).position(x: d / 2, y: d / 2 + dotRadius)
            directionDot(.ringLeft).position(x: d / 2 - dotRadius, y: d / 2)
            directionDot(.ringRight).position(x: d / 2 + dotRadius, y: d / 2)

            // 中心点按热区
            hotspot(.select) {
                Circle()
                    .fill(Color.white.opacity(0.001))
                    .contentShape(Circle())
                    .overlay(Circle().strokeBorder(selected == .select ? Palette.accent : Color.clear, lineWidth: 2))
            }
            .frame(width: d * 0.5, height: d * 0.5)
            .position(x: d / 2, y: d / 2)
        }
        .frame(width: d, height: d)
        .position(padCenter)
    }

    private func directionDot(_ button: RemoteButton) -> some View {
        let isSelected = selected == button
        return Button {
            selected = button
        } label: {
            ZStack {
                Circle()
                    .fill(isSelected ? Palette.accent : Color(white: 0.42))
                    .frame(width: isSelected ? 8 : 4.6, height: isSelected ? 8 : 4.6)
                    .shadow(color: isSelected ? Palette.accent.opacity(0.9) : .clear, radius: 4)
                Circle().fill(Color.white.opacity(0.001)).frame(width: 24, height: 24)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("\(button.title) — \(store.binding(for: button.rawValue).summary)")
    }

    // MARK: 按键组

    private var controlCluster: some View {
        ZStack {
            roundKey(.menu, symbol: "chevron.backward")
                .position(x: px(leftColumnN), y: py(rowBackN))

            // TV 键与左列按键同样为圆形（真机测量外接框宽高相等）
            hotspot(.tv) {
                Circle()
                    .fill(controlFill)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
                    .overlay(tvGlyph)
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
                    .overlay(Circle().strokeBorder(selected == .tv ? Palette.accent : Color.clear, lineWidth: 2))
                    .contentShape(Circle())
            }
            .frame(width: keyDiameter, height: keyDiameter)
            .position(x: px(rightColumnN), y: py(rowBackN))

            roundKey(.playPause, symbol: "playpause.fill")
                .position(x: px(leftColumnN), y: py(rowPlayN))

            volumeRocker
                .position(x: px(volumeCenterN.x), y: py(volumeCenterN.y))

            roundKey(.mute, symbol: "speaker.slash.fill")
                .position(x: px(leftColumnN), y: py(rowMuteN))
        }
    }

    private var controlFill: LinearGradient {
        LinearGradient(colors: [Color(white: 0.22), Color(white: 0.11)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var tvGlyph: some View {
        // 真机 TV 键图标：圆角屏幕轮廓 + 底部小底座
        let w = keyDiameter * 0.44
        let h = keyDiameter * 0.30
        return ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 1.5)
                .frame(width: w, height: h)
            Rectangle()
                .fill(Color.white)
                .frame(width: w * 0.34, height: 1.6)
                .offset(y: h * 0.5 + 3)
        }
    }

    private func roundKey(_ button: RemoteButton, symbol: String) -> some View {
        let d = keyDiameter
        return hotspot(button) {
            Circle()
                .fill(controlFill)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
                .overlay(Image(systemName: symbol)
                    .font(.system(size: d * 0.34, weight: .regular))
                    .foregroundStyle(.white))
                .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
                .overlay(Circle().strokeBorder(selected == button ? Palette.accent : Color.clear, lineWidth: 2))
                .contentShape(Circle())
        }
        .frame(width: d, height: d)
    }

    private var volumeRocker: some View {
        let w = volumeSizeN.width * bodyWidth
        let h = volumeSizeN.height * bodyHeight
        return VStack(spacing: 0) {
            volumeHalf(.volumeUp, symbol: "plus")
            Rectangle().fill(Color.white.opacity(0.14)).frame(height: 1)
            volumeHalf(.volumeDown, symbol: "minus")
        }
        .frame(width: w, height: h)
        .background(
            Capsule()
                .fill(controlFill)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
        )
    }

    private func volumeHalf(_ button: RemoteButton, symbol: String) -> some View {
        hotspot(button) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(Capsule().strokeBorder(selected == button ? Palette.accent : Color.clear, lineWidth: 2))
                .contentShape(Rectangle())
        }
    }

    // MARK: 通用热区

    private func hotspot<Content: View>(_ button: RemoteButton,
                                        @ViewBuilder content: () -> Content) -> some View {
        Button {
            selected = button
        } label: {
            content()
        }
        .buttonStyle(.plain)
        .help("\(button.title) — \(store.binding(for: button.rawValue).summary)")
    }
}

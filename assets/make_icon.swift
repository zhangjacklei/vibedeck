//
//  make_icon.swift
//  vibedeck 应用图标生成器
//
//  纯 AppKit/CoreGraphics 绘制，不依赖任何第三方素材。
//  运行：swift assets/make_icon.swift
//  产物：assets/icon_base.png + assets/vibedeck.icns
//

import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let baseURL = URL(fileURLWithPath: root + "/icon_base.png")

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}

let px = 1024
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                 pixelsWide: px, pixelsHigh: px,
                                 bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else {
    fatalError("无法创建位图")
}
NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else {
    fatalError("无法创建绘图上下文")
}
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// 背景：紫蓝渐变圆角方块
let bg = CGPath(roundedRect: CGRect(x: 0, y: 0, width: px, height: px),
                cornerWidth: 232, cornerHeight: 232, transform: nil)
context.addPath(bg)
context.clip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [rgb(0.31, 0.34, 0.90), rgb(0.62, 0.40, 0.96)] as CFArray,
                          locations: [0, 1])!
context.drawLinearGradient(gradient,
                           start: CGPoint(x: 60, y: px),
                           end: CGPoint(x: px - 40, y: 0),
                           options: [])

// 遥控器主体：白色圆角长条
let body = CGRect(x: 362, y: 120, width: 300, height: 784)
context.addPath(CGPath(roundedRect: body, cornerWidth: 140, cornerHeight: 140, transform: nil))
context.setFillColor(rgb(1, 1, 1, 0.97))
context.fillPath()

// 触控板区域：浅灰圆角矩形（A2540 的圆环触控面）
let pad = CGRect(x: 414, y: 500, width: 196, height: 292)
context.addPath(CGPath(roundedRect: pad, cornerWidth: 78, cornerHeight: 78, transform: nil))
context.setFillColor(rgb(0.93, 0.94, 0.97, 1))
context.fillPath()

// Siri 键：顶部小圆点
func dot(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat, _ color: CGColor) {
    context.addArc(center: CGPoint(x: cx, y: cy), radius: radius,
                   startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.setFillColor(color)
    context.fillPath()
}
dot(512, 812, 30, rgb(0.38, 0.40, 0.92, 1))

// 播放/菜单键
dot(512, 656, 24, rgb(0.55, 0.57, 0.66, 1))
dot(512, 424, 20, rgb(0.55, 0.57, 0.66, 1))

// 底部四向键：上下左右
dot(512, 320, 17, rgb(0.55, 0.57, 0.66, 1))
dot(512, 236, 17, rgb(0.55, 0.57, 0.66, 1))
dot(470, 278, 17, rgb(0.55, 0.57, 0.66, 1))
dot(554, 278, 17, rgb(0.55, 0.57, 0.66, 1))

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("无法生成 PNG")
}
try png.write(to: baseURL)
print("生成 \(baseURL.path)")

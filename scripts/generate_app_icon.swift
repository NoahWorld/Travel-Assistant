import AppKit
import Foundation

let size: CGFloat = 1024
let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let resourcesURL = rootURL.appendingPathComponent("Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let pngURL = resourcesURL.appendingPathComponent("AppIcon.png")
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")

try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func rectTL(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
    CGRect(x: x, y: size - y - height, width: width, height: height)
}

func pointTL(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x, y: size - y)
}

func drawRoundedRect(_ rect: CGRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func drawEllipse(_ rect: CGRect, fill: NSColor) {
    fill.setFill()
    NSBezierPath(ovalIn: rect).fill()
}

func handPath(offsetX: CGFloat = 0, offsetY: CGFloat = 0) -> NSBezierPath {
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        pointTL(x + offsetX, y + offsetY)
    }

    let path = NSBezierPath()
    path.move(to: p(118, 668))
    path.line(to: p(318, 633))
    path.curve(to: p(388, 632), controlPoint1: p(345, 628), controlPoint2: p(368, 627))
    path.line(to: p(532, 672))
    path.line(to: p(632, 666))
    path.curve(to: p(692, 694), controlPoint1: p(660, 664), controlPoint2: p(684, 673))
    path.line(to: p(849, 623))
    path.curve(to: p(932, 663), controlPoint1: p(888, 607), controlPoint2: p(922, 623))
    path.curve(to: p(894, 723), controlPoint1: p(940, 696), controlPoint2: p(924, 719))
    path.line(to: p(618, 879))
    path.curve(to: p(514, 886), controlPoint1: p(583, 899), controlPoint2: p(548, 901))
    path.line(to: p(305, 808))
    path.line(to: p(118, 839))
    path.close()
    return path
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let purple = color(0x403a73)
let lightGreen = color(0x99c463)
let darkGreen = color(0x3b7742)
let peach = color(0xffb886)
let shadow = color(0x8a8a8a, alpha: 0.72)
let white = color(0xf3f3f3)

drawRoundedRect(rectTL(90, 80, 870, 725).offsetBy(dx: 34, dy: -35), radius: 72, fill: shadow)
handPath(offsetX: 35, offsetY: 39).fill()

drawRoundedRect(rectTL(62, 75, 890, 830), radius: 82, fill: white)

drawRoundedRect(rectTL(116, 126, 812, 452), radius: 15, fill: purple)
drawRoundedRect(rectTL(146, 158, 752, 386), radius: 1, fill: lightGreen)
drawRoundedRect(rectTL(188, 201, 668, 252), radius: 1, fill: darkGreen)

drawEllipse(rectTL(136, 200, 126, 126), fill: lightGreen)
drawEllipse(rectTL(806, 200, 126, 126), fill: lightGreen)
drawEllipse(rectTL(136, 448, 126, 126), fill: lightGreen)
drawEllipse(rectTL(806, 448, 126, 126), fill: lightGreen)
drawEllipse(rectTL(438, 241, 188, 221), fill: lightGreen)
drawEllipse(rectTL(240, 315, 63, 63), fill: lightGreen)
drawEllipse(rectTL(761, 315, 63, 63), fill: lightGreen)

let hand = handPath()
peach.setFill()
purple.setStroke()
hand.lineJoinStyle = .round
hand.lineCapStyle = .round
hand.lineWidth = 32
hand.fill()
hand.stroke()

let palmShadow = NSBezierPath()
palmShadow.move(to: pointTL(418, 789))
palmShadow.curve(to: pointTL(664, 769), controlPoint1: pointTL(504, 793), controlPoint2: pointTL(602, 795))
palmShadow.curve(to: pointTL(694, 733), controlPoint1: pointTL(684, 760), controlPoint2: pointTL(697, 748))
palmShadow.curve(to: pointTL(632, 789), controlPoint1: pointTL(665, 777), controlPoint2: pointTL(568, 786))
color(0x9e6755, alpha: 0.52).setFill()
palmShadow.fill()

drawEllipse(rectTL(605, 715, 35, 46), fill: color(0xffdecf, alpha: 0.92))

image.unlockFocus()

func pngData(from image: NSImage, pixels: Int) throws -> Data {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: .alphaFirst,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    else {
        throw CocoaError(.fileWriteUnknown)
    }

    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

try pngData(from: image, pixels: Int(size)).write(to: pngURL)

let iconEntries: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for entry in iconEntries {
    try pngData(from: image, pixels: entry.pixels)
        .write(to: iconsetURL.appendingPathComponent(entry.name))
}

try? fileManager.removeItem(at: icnsURL)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw CocoaError(.fileWriteUnknown)
}

print(icnsURL.path)

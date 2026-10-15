import AppKit
// 生成 QuickMD 图标：圆角蓝底 + 白色 "M↓" 极简风
let size = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let path = NSBezierPath(roundedRect: rect, xRadius: 230, yRadius: 230)
// 渐变蓝
let grad = NSGradient(starting: NSColor(red: 0.10, green: 0.42, blue: 1.0, alpha: 1),
                      ending: NSColor(red: 0.02, green: 0.25, blue: 0.85, alpha: 1))!
grad.draw(in: path, angle: 135)
// 白色 M
let style = NSMutableParagraphStyle()
style.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 560, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: style
]
let s = "M"
let strSize = s.size(withAttributes: attrs)
s.draw(at: NSPoint(x: (CGFloat(size) - strSize.width) / 2, y: (CGFloat(size) - strSize.height) / 2 + 60), withAttributes: attrs)
// 底部三条横线（文档感）
NSColor.white.withAlphaComponent(0.85).setFill()
for i in 0..<3 {
    let w: CGFloat = i == 2 ? 300 : 460
    let r = NSRect(x: (CGFloat(size) - w) / 2, y: 150 - CGFloat(i) * 62, width: w, height: 30)
    NSBezierPath(roundedRect: r, xRadius: 15, yRadius: 15).fill()
}
img.unlockFocus()

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/QuickMD.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try! fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let specs = [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),(128,"128x128"),(256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")]
for (px, name) in specs {
    let target = NSImage(size: NSSize(width: px, height: px))
    target.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px),
             from: NSRect(x: 0, y: 0, width: size, height: size),
             operation: .copy, fraction: 1.0)
    target.unlockFocus()
    guard let tiff = target.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { fatalError("png fail \(name)") }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
}
print("iconset ok: \(outDir)")

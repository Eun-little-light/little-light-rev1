// 앱 아이콘 생성: swift make_icon.swift <out.png>
import Cocoa

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let c = CGPoint(x: size / 2, y: size / 2)

// 배경 스쿼클
let inset: CGFloat = 100
let bg = CGPath(roundedRect: CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2),
                cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.addPath(bg); ctx.setFillColor(CGColor(red: 0.035, green: 0.039, blue: 0.045, alpha: 1)); ctx.fillPath()
ctx.addPath(bg); ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.08)); ctx.setLineWidth(3); ctx.strokePath()

let ice = CGColor(red: 0.655, green: 0.925, blue: 1, alpha: 1)

// 분절 링 (6조각)
ctx.setStrokeColor(ice.copy(alpha: 0.6)!); ctx.setLineWidth(6)
for i in 0..<6 {
    let a = CGFloat(i) * .pi / 3
    ctx.addArc(center: c, radius: 300, startAngle: a, endAngle: a + .pi / 3 * 0.8, clockwise: false)
    ctx.strokePath()
}
// 셸
ctx.setFillColor(CGColor(red: 0.09, green: 0.1, blue: 0.11, alpha: 1))
ctx.fillEllipse(in: CGRect(x: c.x - 240, y: c.y - 240, width: 480, height: 480))
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.12)); ctx.setLineWidth(3)
ctx.strokeEllipse(in: CGRect(x: c.x - 240, y: c.y - 240, width: 480, height: 480))
// 렌즈
ctx.setFillColor(CGColor(red: 0.02, green: 0.024, blue: 0.028, alpha: 1))
ctx.fillEllipse(in: CGRect(x: c.x - 135, y: c.y - 135, width: 270, height: 270))
// 광점
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 1), ice, ice.copy(alpha: 0)!] as CFArray,
                      locations: [0, 0.25, 1])!
ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: 120, options: [])
// 궤도 파편
ctx.setFillColor(CGColor(red: 0.91, green: 0.9, blue: 0.87, alpha: 0.85))
for i in 0..<3 {
    let a = CGFloat(i) * 2 * .pi / 3 + .pi / 2
    let p = CGPoint(x: c.x + cos(a) * 365, y: c.y + sin(a) * 365)
    ctx.saveGState(); ctx.translateBy(x: p.x, y: p.y); ctx.rotate(by: a - .pi / 2)
    ctx.move(to: CGPoint(x: 0, y: 34)); ctx.addLine(to: CGPoint(x: 16, y: -20)); ctx.addLine(to: CGPoint(x: -16, y: -20))
    ctx.closePath(); ctx.fillPath(); ctx.restoreGState()
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))

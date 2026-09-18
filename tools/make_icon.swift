// swift tools/make_icon.swift <out.png> — draws the 1024px app icon: a resume sheet on ink blue
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let c = NSGraphicsContext.current!.cgContext
func rgb(_ h: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
// ground: ink blue with a soft vertical falloff
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgb(0x2a6cc0), rgb(0x173f78)] as CFArray, locations: [0, 1])!
c.drawLinearGradient(grad, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 0), options: [])
// the sheet (Letter proportions), with a shadow
let sheet = CGRect(x: 262, y: 170, width: 500, height: 647)
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: rgb(0x07162e, 0.45))
c.setFillColor(rgb(0xffffff)); c.fill(sheet)
c.restoreGState()
// name line, contact line, then heading + text rows like the resume
let left = sheet.minX + 58, right = sheet.maxX - 58
func bar(_ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: CGColor) {
    c.setFillColor(color); c.fill(CGRect(x: left, y: y, width: w, height: h))
}
var y = sheet.maxY - 100
bar(y, 250, 34, rgb(0x14181f)); y -= 34
bar(y, right - left, 10, rgb(0xb8c0cc)); y -= 58
for section in 0..<3 {
    bar(y, 150, 18, rgb(0x1f5fae)); y -= 36
    for row in 0..<(section == 0 ? 3 : 4) {
        let w = (right - left - 24) * (row % 3 == 2 ? 0.62 : 0.94)
        c.setFillColor(rgb(0x14181f)); c.fillEllipse(in: CGRect(x: left, y: y + 1, width: 9, height: 9))
        c.setFillColor(rgb(0xc9d0da)); c.fill(CGRect(x: left + 24, y: y, width: w, height: 11))
        y -= 26
    }
    y -= 22
}
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

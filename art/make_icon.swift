import AppKit
import CoreGraphics

// Render the Sotto app icon at a given pixel size: a flat indigo squircle with a
// white sound-wave equalizer (bars rising then settling = noise cleaned to clean voice).
func render(_ size: Int, to path: String) {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // Rounded-square background (macOS squircle-ish), flat indigo.
    let inset = s * 0.045
    let rect = CGRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
    let radius = (s - 2*inset) * 0.225
    let bg = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bg)
    ctx.setFillColor(CGColor(red: 0.30, green: 0.26, blue: 0.72, alpha: 1.0)) // indigo
    ctx.fillPath()

    // Equalizer bars (white), heights shaped like a smooth hump — "clean voice".
    let heights: [CGFloat] = [0.18, 0.34, 0.56, 0.80, 0.56, 0.34, 0.18]
    let n = heights.count
    let region = rect.insetBy(dx: rect.width * 0.20, dy: rect.height * 0.20)
    let gap = region.width / CGFloat(n) * 0.42
    let barW = (region.width - gap * CGFloat(n - 1)) / CGFloat(n)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    for i in 0..<n {
        let h = region.height * heights[i]
        let x = region.minX + CGFloat(i) * (barW + gap)
        let y = region.midY - h/2
        let br = barW/2
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: barW, height: h),
                           cornerWidth: br, cornerHeight: br, transform: nil))
    }
    ctx.fillPath()

    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let outDir = CommandLine.arguments[1]
render(1024, to: "\(outDir)/icon_1024.png")
print("rendered \(outDir)/icon_1024.png")

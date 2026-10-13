import AppKit
import CoreGraphics

// Sotto app icon: a flat teal squircle with a white waveform that starts jagged
// (noise) on the left and smooths into a calm wave on the right — noise cancelled.
func render(_ size: Int, to path: String) {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    let inset = s * 0.045
    let rect = CGRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
    let radius = (s - 2*inset) * 0.225
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(CGColor(red: 0.07, green: 0.63, blue: 0.53, alpha: 1.0)) // teal
    ctx.fillPath()

    // Waveform path: noisy left -> calm right.
    let region = rect.insetBy(dx: rect.width * 0.17, dy: rect.height * 0.30)
    let steps = 480
    let maxAmp = region.height * 0.46
    // A single smooth voice wave whose amplitude settles from loud (left) to calm
    // (right): the sound after noise is removed. No grain — clean at every size.
    let wave = CGMutablePath()
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let x = region.minX + region.width * t
        let env = 0.30 + 0.70 * (1.0 - t)               // amplitude eases down l->r
        let y = region.midY + maxAmp * env * sin(t * .pi * 2 * 3.2)
        if i == 0 { wave.move(to: CGPoint(x: x, y: y)) } else { wave.addLine(to: CGPoint(x: x, y: y)) }
    }
    ctx.addPath(wave)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(s * 0.045)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    let img = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
render(1024, to: "\(CommandLine.arguments[1])/icon_1024.png")
print("rendered")

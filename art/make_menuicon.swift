import AppKit
import CoreGraphics

// Monochrome menu-bar template: the Sotto settling wave in black on transparent.
// macOS tints it for light/dark automatically (isTemplate).
func render(_ w: Int, _ h: Int, to path: String) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
    let W = CGFloat(w), H = CGFloat(h)
    let region = CGRect(x: W*0.08, y: H*0.20, width: W*0.84, height: H*0.60)
    let steps = 240
    let maxAmp = region.height * 0.5
    let wave = CGMutablePath()
    for i in 0...steps {
        let t = CGFloat(i)/CGFloat(steps)
        let x = region.minX + region.width * t
        let env = 0.30 + 0.70 * (1.0 - t)
        let y = region.midY + maxAmp * env * sin(t * .pi * 2 * 3.2)
        if i == 0 { wave.move(to: CGPoint(x: x, y: y)) } else { wave.addLine(to: CGPoint(x: x, y: y)) }
    }
    ctx.addPath(wave)
    ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    ctx.setLineWidth(H * 0.11)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.strokePath()
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
let d = CommandLine.arguments[1]
render(72, 44, to: "\(d)/MenuIcon.png")     // 1x (36x22 pt)
render(144, 88, to: "\(d)/MenuIcon@2x.png") // 2x
print("rendered menu icons")

// HoldQ's icon: the letter Q made of the app's own ring. The bowl is the ring of the sign HoldQ shows while ⌘Q is held:
// its track at 18 % and the filled arc from twelve o'clock, clockwise. The arc stops where the tail of the Q crosses the
// ring, at half past four, and the tail carries on in full ink: the moment the hold turns into a quit.
// An Icon Composer icon (macOS 26+ switches it with the theme): this draws only the picture, light.png and dark.png,
// 1024 px, transparent; the plate is the system's own fill (./build writes icon.json and runs actool).
// Grid from STT's icon, so the family matches: drawn on the old 824 px plate (100..924) scaled to the canvas; the mark
// is 576 tall like STT's tallest bar, the line 64 (two of STT's 32 px bars). Ink #1C1C1E on light (STT's), white on dark.
// Usage: icon <dir> writes <dir>/light.png and <dir>/dark.png.

import AppKit

func draw(_ light: Bool) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let c = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    c.scaleBy(x: 1024 / 824, y: 1024 / 824); c.translateBy(x: -100, y: -100)
    func ink(_ a: CGFloat) -> CGColor {
        light ? CGColor(srgbRed: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: a) : CGColor(gray: 1, alpha: a)
    }
    let center = CGPoint(x: 512, y: 512), w: CGFloat = 64, r = (576 - w) / 2
    c.setLineWidth(w); c.setLineCap(.round)
    c.setStrokeColor(ink(0.18))
    c.addArc(center: center, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: false); c.strokePath()
    let tail = -CGFloat.pi / 4   // half past four
    c.setStrokeColor(ink(1))
    c.addArc(center: center, radius: r, startAngle: .pi / 2, endAngle: tail, clockwise: true); c.strokePath()
    // The tail from half way into the bowl to 96 px (three bars) outside the ring.
    c.move(to: CGPoint(x: center.x + cos(tail) * r / 2, y: center.y + sin(tail) * r / 2))
    c.addLine(to: CGPoint(x: center.x + cos(tail) * (r + 96), y: center.y + sin(tail) * (r + 96)))
    c.strokePath()
    return rep
}

let out = CommandLine.arguments[1]
for (name, light) in [("light", true), ("dark", false)] {
    try! draw(light).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}

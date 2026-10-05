import AppKit

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let tile = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 212, yRadius: 212)
NSColor(srgbRed: 0.08, green: 0.13, blue: 0.21, alpha: 1).setFill()
tile.fill()
let inset = NSBezierPath(roundedRect: NSRect(x: 68, y: 68, width: 888, height: 888), xRadius: 188, yRadius: 188)
NSColor(srgbRed: 0.13, green: 0.20, blue: 0.30, alpha: 1).setStroke()
inset.lineWidth = 3
inset.stroke()
NSColor(srgbRed: 1, green: 0.73, blue: 0.31, alpha: 1).setStroke()
func ridge(_ start: NSPoint, _ segments: [(NSPoint, NSPoint, NSPoint)]) {
    let path = NSBezierPath()
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = 27
    path.move(to: start)
    for (end, first, second) in segments { path.curve(to: end, controlPoint1: first, controlPoint2: second) }
    path.stroke()
}
ridge(NSPoint(x: 263, y: 411), [
    (NSPoint(x: 512, y: 799), NSPoint(x: 242, y: 669), NSPoint(x: 327, y: 799)),
    (NSPoint(x: 761, y: 531), NSPoint(x: 683, y: 799), NSPoint(x: 767, y: 679))
])
ridge(NSPoint(x: 334, y: 311), [
    (NSPoint(x: 330, y: 548), NSPoint(x: 367, y: 388), NSPoint(x: 331, y: 459)),
    (NSPoint(x: 512, y: 730), NSPoint(x: 330, y: 648), NSPoint(x: 411, y: 730)),
    (NSPoint(x: 695, y: 541), NSPoint(x: 615, y: 730), NSPoint(x: 695, y: 650)),
    (NSPoint(x: 749, y: 309), NSPoint(x: 695, y: 455), NSPoint(x: 713, y: 369))
])
ridge(NSPoint(x: 416, y: 245), [
    (NSPoint(x: 400, y: 546), NSPoint(x: 459, y: 365), NSPoint(x: 401, y: 452)),
    (NSPoint(x: 512, y: 660), NSPoint(x: 400, y: 608), NSPoint(x: 449, y: 660)),
    (NSPoint(x: 625, y: 545), NSPoint(x: 577, y: 660), NSPoint(x: 625, y: 609)),
    (NSPoint(x: 698, y: 251), NSPoint(x: 625, y: 438), NSPoint(x: 639, y: 331))
])
ridge(NSPoint(x: 512, y: 221), [
    (NSPoint(x: 469, y: 544), NSPoint(x: 546, y: 369), NSPoint(x: 471, y: 454)),
    (NSPoint(x: 512, y: 590), NSPoint(x: 469, y: 569), NSPoint(x: 487, y: 590)),
    (NSPoint(x: 555, y: 544), NSPoint(x: 539, y: 590), NSPoint(x: 555, y: 570)),
    (NSPoint(x: 603, y: 280), NSPoint(x: 555, y: 436), NSPoint(x: 574, y: 330))
])
image.unlockFocus()
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon rendering failed") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

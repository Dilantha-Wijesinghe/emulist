// Draws the Emulist app icon: a film frame with sprocket holes over a warm, halated light.
//   swift scripts/make-icon.swift <out.png>
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let context = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

// Squircle body.
let body = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
context.addPath(body)
context.clip()
let background = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 0.13, green: 0.12, blue: 0.12, alpha: 1), CGColor(red: 0.05, green: 0.05, blue: 0.055, alpha: 1),
] as CFArray, locations: [0, 1])!
context.drawLinearGradient(background, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])

// Warm light with a halation ring.
let glow = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1.0, green: 0.93, blue: 0.80, alpha: 1), CGColor(red: 1.0, green: 0.62, blue: 0.28, alpha: 0.95),
    CGColor(red: 0.85, green: 0.22, blue: 0.10, alpha: 0.45), CGColor(red: 0.5, green: 0.08, blue: 0.05, alpha: 0),
] as CFArray, locations: [0, 0.22, 0.5, 1])!
context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 540), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 540), endRadius: 330, options: [])

// Film strip edges with sprocket holes.
context.setFillColor(CGColor(red: 0.03, green: 0.03, blue: 0.035, alpha: 0.92))
context.fill(CGRect(x: 100, y: 100, width: 824, height: 150))
context.fill(CGRect(x: 100, y: 774, width: 824, height: 150))
context.setFillColor(CGColor(red: 0.96, green: 0.63, blue: 0.29, alpha: 0.9))
for i in 0..<6 {
    let x = 168.0 + Double(i) * 128
    for y in [150.0, 824.0] {
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: 56, height: 50), cornerWidth: 10, cornerHeight: 10, transform: nil))
    }
}
context.fillPath()
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

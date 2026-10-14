// Generates a placeholder 1536x1872 atlas (8 cols x 9 rows of 192x208) so the app runs before real art exists.
// Usage: swift Scripts/make-placeholder-pet.swift App/Squai/Resources/Pets/squai-default/spritesheet.png
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "spritesheet.png")
let cols = 8, rows = 9, cw = 192, ch = 208
let hues: [CGFloat] = [0.55, 0.10, 0.10, 0.30, 0.80, 0.00, 0.15, 0.60, 0.45] // one per state row

let ctx = CGContext(data: nil, width: cols * cw, height: rows * ch, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
for row in 0..<rows {
    for col in 0..<cols {
        let t = CGFloat(col) / CGFloat(cols)
        let bounce = abs(sin(t * .pi * 2)) * 24
        let cx = CGFloat(col * cw) + CGFloat(cw) / 2
        // CGContext is bottom-left origin; row 0 must be the TOP row of the PNG.
        let cy = CGFloat((rows - 1 - row) * ch) + 70 + bounce
        let body = CGRect(x: cx - 48, y: cy - 40, width: 96, height: 80 + bounce * 0.3)
        ctx.setFillColor(NSColor(hue: hues[row], saturation: 0.7, brightness: 0.9, alpha: 1).cgColor)
        ctx.fillEllipse(in: body)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - 22, y: cy + 4, width: 12, height: 14))
        ctx.fillEllipse(in: CGRect(x: cx + 10, y: cy + 4, width: 12, height: 14))
    }
}
let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path) \(img.width)x\(img.height)")

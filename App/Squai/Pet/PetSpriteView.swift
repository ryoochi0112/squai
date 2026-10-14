import AppKit

/// Draws the current frame, hit-tests only opaque pixels, and drags the window.
final class PetSpriteView: NSView {
    var frameImage: CGImage? { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    var onDragEnd: ((NSPoint) -> Void)?
    private var dragStart: NSPoint?
    private var moved = false

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let img = frameImage, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none // keep pixel art crisp
        ctx.draw(img, in: bounds)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let img = frameImage else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return alpha(of: img, at: local) > 16 ? self : nil
    }

    private func alpha(of img: CGImage, at p: NSPoint) -> UInt8 {
        let sx = CGFloat(img.width) / bounds.width, sy = CGFloat(img.height) / bounds.height
        let x = Int(p.x * sx), y = Int((bounds.height - p.y) * sy)
        guard x >= 0, y >= 0, x < img.width, y < img.height else { return 0 }
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        ctx.draw(img, in: CGRect(x: -x, y: -(img.height - 1 - y), width: img.width, height: img.height))
        return pixel[3]
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        moved = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = dragStart else { return }
        let now = event.locationInWindow
        let dx = now.x - start.x, dy = now.y - start.y
        if abs(dx) + abs(dy) > 2 { moved = true }
        var o = window.frame.origin
        o.x += dx; o.y += dy
        window.setFrameOrigin(o)
    }

    override func mouseUp(with event: NSEvent) {
        if moved, let window { onDragEnd?(window.frame.origin) } else { onClick?() }
        dragStart = nil
    }
}

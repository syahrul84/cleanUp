// Converts artwork on a dark background into a menu-bar template icon:
// pixel brightness becomes opacity (white shape -> solid, black bg -> clear),
// cropped to the shape and scaled onto a square canvas.
// Usage: swift make_menubar_icon.swift <input.png> <output.png> [canvasPx]
import AppKit

let args = CommandLine.arguments
guard args.count >= 3,
      let source = NSImage(contentsOfFile: args[1]),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("usage: swift make_menubar_icon.swift <input.png> <output.png> [canvasPx]\n", stderr)
    exit(1)
}
let canvasSize = args.count > 3 ? Int(args[3])! : 36

let w = cg.width, h = cg.height
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let readCtx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: w * 4, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
readCtx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
let pixels = readCtx.data!.assumingMemoryBound(to: UInt8.self)

// Luminance -> alpha, with a floor to drop the dark background cleanly.
var mask = [UInt8](repeating: 0, count: w * h * 4)
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        let luma = (0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1])
                    + 0.114 * Double(pixels[i + 2])) / 255.0 * (Double(pixels[i + 3]) / 255.0)
        let alpha = luma < 0.32 ? 0.0 : min(1.0, (luma - 0.32) / 0.45)
        mask[i + 3] = UInt8(alpha * 255) // premultiplied black: rgb stay 0
        if alpha > 0.05 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
guard minX < maxX, minY < maxY else { fputs("no shape found\n", stderr); exit(1) }

let maskCtx = CGContext(data: &mask, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: w * 4, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let shape = maskCtx.makeImage()!.cropping(
    to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!

// Fit the shape into the canvas with a small margin, centered.
let out = CGContext(data: nil, width: canvasSize, height: canvasSize, bitsPerComponent: 8,
                    bytesPerRow: 0, space: srgb,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let margin = Double(canvasSize) * 0.05
let avail = Double(canvasSize) - margin * 2
let sw = Double(shape.width), sh = Double(shape.height)
let scale = min(avail / sw, avail / sh)
let dw = sw * scale, dh = sh * scale
out.interpolationQuality = .high
out.draw(shape, in: CGRect(x: (Double(canvasSize) - dw) / 2,
                           y: (Double(canvasSize) - dh) / 2, width: dw, height: dh))

let rep = NSBitmapImageRep(cgImage: out.makeImage()!)
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]) (\(canvasSize)x\(canvasSize))")

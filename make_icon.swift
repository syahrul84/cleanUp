// Generates AppIcon_1024.png from a square source image:
// rounds the corners with real transparency and centers the artwork on
// Apple's Big Sur icon grid (824 pt content inside a 1024 pt canvas).
// Usage: swift make_icon.swift <input.png> <output.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3,
      let source = NSImage(contentsOfFile: args[1]),
      let sourceCG = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("usage: swift make_icon.swift <input.png> <output.png>\n", stderr)
    exit(1)
}

let canvas = 1024.0, content = 824.0
let inset = (canvas - content) / 2
let radius = content * 0.225 // Apple squircle corner radius approximation

let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas),
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

let contentRect = CGRect(x: inset, y: inset, width: content, height: content)
ctx.addPath(CGPath(roundedRect: contentRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()

// Crop 2% off each edge of the source first, so the mockup's darker
// corner pixels never reach the rounded mask.
let w = CGFloat(sourceCG.width), h = CGFloat(sourceCG.height)
let trim = min(w, h) * 0.02
let cropped = sourceCG.cropping(to: CGRect(x: trim, y: trim, width: w - 2 * trim, height: h - 2 * trim))!
ctx.interpolationQuality = .high
ctx.draw(cropped, in: contentRect)

let output = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: output)
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")

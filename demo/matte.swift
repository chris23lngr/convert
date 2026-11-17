// Difference matting: matte white.png black.png out.png
// alpha = 1 - (W - B), colour = B / alpha (straight alpha, sRGB).
import AppKit
func load(_ p: String) -> (CGImage, [UInt8]) {
  let img = NSImage(contentsOfFile: p)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
  var buf = [UInt8](repeating: 0, count: img.width * img.height * 4)
  let ctx = CGContext(data: &buf, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
  ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
  return (img, buf)
}
let a = CommandLine.arguments
let (wi, W) = load(a[1]); let (_, B) = load(a[2])
let n = wi.width * wi.height
var out = [UInt8](repeating: 0, count: n * 4)
for i in 0..<n {
  var d = 0.0
  for c in 0..<3 { d += Double(W[i*4+c]) - Double(B[i*4+c]) }
  let alpha = max(0, min(1, 1 - d / (3 * 255)))
  out[i*4+3] = UInt8((alpha * 255).rounded())
  for c in 0..<3 {
    // premultiplied output: colour * alpha == B
    out[i*4+c] = UInt8(max(0, min(255, Double(B[i*4+c]).rounded())))
  }
}
let ctx = CGContext(data: &out, width: wi.width, height: wi.height, bitsPerComponent: 8, bytesPerRow: wi.width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[3]))
print("wrote", a[3])

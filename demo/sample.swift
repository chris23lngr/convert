import AppKit
// usage: sample file.png x y [x y ...]  (pixel coords) -> hex colours
let a = CommandLine.arguments
let img = NSImage(contentsOfFile: a[1])!
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
var i = 2
while i + 1 < a.count {
  let c = rep.colorAt(x: Int(a[i])!, y: Int(a[i+1])!)!.usingColorSpace(.sRGB)!
  print(a[i], a[i+1], String(format: "#%02x%02x%02x", Int(c.redComponent*255), Int(c.greenComponent*255), Int(c.blueComponent*255)))
  i += 2
}

// Full-screen solid backdrop behind Finder, for difference matting of translucent menus.
// Starts white; `kill -USR1 <pid>` toggles white/black without taking focus.
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let frame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
w.backgroundColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
w.isOpaque = true
w.hasShadow = false
w.level = .normal
w.ignoresMouseEvents = true
w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
w.orderFrontRegardless()
signal(SIGUSR1, SIG_IGN)
var white = true
let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
src.setEventHandler {
  white.toggle()
  w.backgroundColor = white ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1) : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
  w.display()
}
src.resume()
app.run()

// Prints on-screen windows: id owner layer x y w h name
import CoreGraphics
let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in l {
  let owner = w["kCGWindowOwnerName"] as? String ?? ""
  let filter = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
  if !filter.isEmpty && owner != filter { continue }
  let b = w["kCGWindowBounds"] as! [String: Any]
  print(w["kCGWindowNumber"]!, owner, w["kCGWindowLayer"]!, b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!, w["kCGWindowName"] as? String ?? "")
}

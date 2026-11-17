// Renders the app icon with SwiftUI: `swift tools/make_icon.swift out.png [size]`
// A sky-blue squircle on Apple's macOS icon grid (824pt body in a 1024 canvas),
// two file cards and the convert arrows.
import AppKit
import SwiftUI

let sky = Color(red: 0.18, green: 0.66, blue: 1.0)        // #2EA8FF, the brand sky
let skyLight = Color(red: 0.45, green: 0.80, blue: 1.0)
let skyDeep = Color(red: 0.07, green: 0.45, blue: 0.96)

struct Card: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 46, style: .continuous)
            .fill(.white)
            .frame(width: 360, height: 452)
    }
}

struct Icon: View {
    var body: some View {
        ZStack {
            // Body
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [skyLight, sky, skyDeep], startPoint: .top, endPoint: .bottom))
                .overlay(
                    // Soft top sheen
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0)],
                                             startPoint: .top, endPoint: .center))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 3)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 12)

            // Back card: the original file
            Card()
                .opacity(0.5)
                .rotationEffect(.degrees(-9))
                .offset(x: -62, y: -30)

            // Front card: the converted file, carrying the arrows
            Card()
                .overlay(
                    VStack(spacing: 30) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 190, weight: .bold))
                            .foregroundStyle(LinearGradient(colors: [skyLight, skyDeep],
                                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        VStack(spacing: 18) {
                            Capsule().fill(sky.opacity(0.22)).frame(width: 200, height: 22)
                            Capsule().fill(sky.opacity(0.22)).frame(width: 140, height: 22)
                        }
                    }
                )
                .rotationEffect(.degrees(6))
                .offset(x: 56, y: 34)
                .shadow(color: Color(red: 0.0, green: 0.2, blue: 0.5).opacity(0.35), radius: 26, y: 16)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func render() {
    let args = CommandLine.arguments
    let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "icon.png")
    let size = args.count > 2 ? Double(args[2]) ?? 1024 : 1024
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = size / 1024
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: out)
    print("wrote \(out.path) (\(cg.width)px)")
}

MainActor.assumeIsolated { render() }

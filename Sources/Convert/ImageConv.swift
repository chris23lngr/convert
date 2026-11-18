import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageConv {
    static func utType(_ id: String) -> UTType? {
        switch id {
        case "jpg", "pdf-jpg": .jpeg
        case "png", "pdf-png": .png
        case "heic": .heic
        case "avif": UTType("public.avif")
        case "tiff": .tiff
        case "gif-img": .gif
        case "bmp": .bmp
        case "pdf-img": .pdf
        default: nil
        }
    }

    static func convert(_ input: URL, _ t: Target, _ s: ConvSettings) throws -> URL {
        guard let src = CGImageSourceCreateWithURL(input as CFURL, nil), CGImageSourceGetCount(src) > 0 else {
            throw ConvertError("Couldn't read this image")
        }
        let opaque = ["jpg", "bmp"].contains(t.id)
        let image = try render(src, maxSize: s.maxSize, flatten: opaque)
        let out = uniqueOutput(for: input, ext: t.ext)

        if t.id == "webp" {
            try writeWebP(image, to: out, quality: s.imageQuality)
            return out
        }
        var props: [CFString: Any] = [:]
        if t.isLossyImage { props[kCGImageDestinationLossyCompressionQuality] = s.imageQuality }
        if t.id != "pdf-img", let meta = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyGPSDictionary] {
                if let v = meta[key] { props[key] = v }
            }
        }
        try write(image, to: out, type: utType(t.id), label: t.label, props: props)
        return out
    }

    static func write(_ image: CGImage, to out: URL, type: UTType?, label: String, props: [CFString: Any]) throws {
        guard let type, let dest = CGImageDestinationCreateWithURL(out as CFURL, type.identifier as CFString, 1, nil)
        else {
            throw ConvertError("This Mac can't write \(label)")
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: out)
            throw ConvertError("Couldn't write \(label)")
        }
    }

    /// Decodes the first frame with orientation applied, optionally downscaled and flattened onto white.
    static func render(_ src: CGImageSource, maxSize: Int, flatten: Bool) throws -> CGImage {
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let full = max(w, h)
        var opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if full > 0 { opts[kCGImageSourceThumbnailMaxPixelSize] = maxSize > 0 ? min(maxSize, full) : full }
        guard var img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw ConvertError("Couldn't decode this image")
        }
        if flatten, hasAlpha(img) { img = try flattenOnWhite(img) }
        return img
    }

    static func hasAlpha(_ img: CGImage) -> Bool {
        switch img.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: false
        default: true
        }
    }

    static func flattenOnWhite(_ img: CGImage) throws -> CGImage {
        let space = img.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let ctx = CGContext(
                data: nil, width: img.width, height: img.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw ConvertError("Couldn't flatten transparency") }
        let rect = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.draw(img, in: rect)
        guard let out = ctx.makeImage() else { throw ConvertError("Couldn't flatten transparency") }
        return out
    }

    static func writeWebP(_ image: CGImage, to out: URL, quality: Double) throws {
        guard let cwebp = Tools.cwebp else { throw ConvertError("WebP needs cwebp: brew install webp") }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try write(image, to: tmp, type: .png, label: "PNG", props: [:])
        try runSync(cwebp, ["-quiet", "-q", "\(Int(quality * 100))", "-metadata", "icc", tmp.path, "-o", out.path])
    }
}

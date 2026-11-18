import CoreGraphics
import CoreText
import Foundation
import Testing

@testable import Convert

/// A fresh instance (and temporary folder) is made for every test; `deinit` cleans it up.
final class PDFTextTests {
    private let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
    }

    deinit {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makePDF(text: String? = nil) throws -> URL {
        let url = dir.appendingPathComponent("sample.pdf")
        var bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let context = try #require(CGContext(url as CFURL, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        context.fill(CGRect(x: 10, y: 10, width: 20, height: 20))
        if let text {
            context.textPosition = CGPoint(x: 20, y: 100)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text)), context)
        }
        context.endPDFPage()
        context.closePDF()
        return url
    }

    @Test func graphicsOnlyPDFDoesNotCreateTextFile() throws {
        let input = try makePDF()
        let target = try #require(Targets.byID("pdf-txt"))
        let error = #expect(throws: (any Error).self) {
            try PDFConv.convert(input, target, ConvSettings()) { _ in }
        }
        #expect(error?.localizedDescription == "This PDF contains no extractable text")
        let output = input.deletingPathExtension().appendingPathExtension("txt")
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func exportsSelectableText() throws {
        let input = try makePDF(text: "Sample text")
        let target = try #require(Targets.byID("pdf-txt"))
        let outputs = try PDFConv.convert(input, target, ConvSettings()) { _ in }
        let text = try String(contentsOf: #require(outputs.first), encoding: .utf8)
        #expect(text.trimmingCharacters(in: .whitespacesAndNewlines) == "Sample text")
    }
}

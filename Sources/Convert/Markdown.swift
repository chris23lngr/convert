import Foundation

/// A small Markdown → HTML renderer, enough for notes, READMEs and docs:
/// headings, paragraphs, **bold**, *italic*, ~~strike~~, `code`, fenced code blocks,
/// links, images (as their alt text), block quotes, nested lists, task lists, tables and rules.
/// The HTML then goes through the same pipeline as any HTML file (textutil / AppKit → PDF).
enum Markdown {
    static func isMarkdown(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "mkd"].contains(url.pathExtension.lowercased())
    }

    /// Renders the file to a styled standalone HTML file in a temp folder and returns its URL.
    static func renderToTempHTML(_ input: URL) throws -> URL {
        let text = try String(contentsOf: input, encoding: .utf8)
        let title = input.deletingPathExtension().lastPathComponent
        let html = document(body: toHTML(text), title: title)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent(title).appendingPathExtension("html")
        try html.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    static func document(body: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(escape(title))</title>
        <style>
        body { font-family: -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif; font-size: 11pt; line-height: 1.5; color: #1d1d1f; }
        h1 { font-size: 22pt; margin: 0 0 10pt; }
        h2 { font-size: 16pt; margin: 18pt 0 8pt; }
        h3 { font-size: 13pt; margin: 14pt 0 6pt; }
        h4, h5, h6 { font-size: 11pt; margin: 12pt 0 4pt; }
        p, ul, ol, blockquote, pre, table { margin: 0 0 9pt; }
        code { font-family: Menlo, monospace; font-size: 9.5pt; background: #f2f2f4; }
        pre { font-family: Menlo, monospace; font-size: 9.5pt; background: #f2f2f4; padding: 8pt; }
        blockquote { color: #555; margin-left: 12pt; padding-left: 10pt; border-left: 3pt solid #d0d0d6; }
        table.quote, table.code { width: 100%; }
        table.code td { border: 0; background: #f2f2f4; padding: 8pt 10pt; }
        table.code pre { margin: 0; padding: 0; }
        table.quote td { border: 0; border-left: 3pt solid #d0d0d6; background: #f7f7f9; color: #555; padding: 6pt 10pt; }
        ul, ol { margin-top: 0; margin-bottom: 9pt; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #d0d0d6; padding: 4pt 8pt; text-align: left; }
        th { background: #f2f2f4; }
        a { color: #0a66d8; }
        hr { border: 0; border-top: 1px solid #d0d0d6; margin: 14pt 0; }
        </style></head><body>
        \(body)
        </body></html>
        """
    }

    // MARK: - Blocks

    static func toHTML(_ source: String) -> String {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var out: [String] = []
        var i = 0
        var paragraph: [String] = []
        var listStack: [(tag: String, indent: Int)] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            out.append("<p>" + paragraph.map(inline).joined(separator: "<br>\n") + "</p>")
            paragraph = []
        }
        func closeLists(to depth: Int = 0) {
            while listStack.count > depth { out.append("</li></\(listStack.removeLast().tag)>") }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }

            // Fenced code block
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph(); closeLists()
                let fence = String(trimmed.prefix(3))
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(escape(lines[i])); i += 1
                }
                out.append("<table class=\"code\"><tr><td><pre><code>" + code.joined(separator: "\n") + "</code></pre></td></tr></table>")
                i += 1
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                // A blank line ends a list unless the next line continues it.
                if !listStack.isEmpty {
                    let next = lines[(i + 1)...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    if next.map({ listItem($0) == nil }) ?? true { closeLists() }
                }
                i += 1
                continue
            }

            // Heading
            if let m = match(#"^(#{1,6})\s+(.*?)\s*#*\s*$"#, trimmed) {
                flushParagraph(); closeLists()
                let level = m[1].count
                out.append("<h\(level)>\(inline(m[2]))</h\(level)>")
                i += 1
                continue
            }

            // Horizontal rule
            if match(#"^([-*_])(\s*\1){2,}$"#, trimmed) != nil {
                flushParagraph(); closeLists()
                out.append("<hr>")
                i += 1
                continue
            }

            // Table: header row, then a |---|---| separator
            if trimmed.contains("|"), i + 1 < lines.count,
               match(#"^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$"#, lines[i + 1].trimmingCharacters(in: .whitespaces)) != nil {
                flushParagraph(); closeLists()
                var rows = ["<tr>" + cells(trimmed).map { "<th>\(inline($0))</th>" }.joined() + "</tr>"]
                i += 2
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append("<tr>" + cells(lines[i]).map { "<td>\(inline($0))</td>" }.joined() + "</tr>")
                    i += 1
                }
                out.append("<table>" + rows.joined() + "</table>")
                continue
            }

            // Block quote (consecutive "> " lines, rendered recursively)
            if trimmed.hasPrefix(">") {
                flushParagraph(); closeLists()
                var quoted: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    var rest = t.dropFirst()
                    if rest.hasPrefix(" ") { rest = rest.dropFirst() }
                    quoted.append(String(rest)); i += 1
                }
                // A one-cell table: the AppKit HTML importer ignores block-quote indents but draws table cells.
                out.append("<table class=\"quote\"><tr><td>" + toHTML(quoted.joined(separator: "\n")) + "</td></tr></table>")
                continue
            }

            // List item
            if let item = listItem(line) {
                flushParagraph()
                if listStack.isEmpty || indent > listStack.last!.indent {
                    out.append(item.open)
                    listStack.append((item.tag, indent))
                } else {
                    while listStack.count > 1, indent < listStack.last!.indent {
                        out.append("</li></\(listStack.removeLast().tag)>")
                    }
                    if listStack.last!.tag != item.tag {
                        out.append("</li></\(listStack.removeLast().tag)>" + item.open)
                        listStack.append((item.tag, indent))
                    } else {
                        out.append("</li>")
                    }
                }
                var content = item.text
                if let task = match(#"^\[([ xX])\]\s+(.*)$"#, content) {
                    content = (task[1] == " " ? "☐ " : "☑ ") + task[2]
                }
                out.append("<li>" + inline(content))
                i += 1
                continue
            }

            // Continuation of a list item's text
            if !listStack.isEmpty, indent > 0 {
                out.append(" " + inline(trimmed))
                i += 1
                continue
            }

            closeLists()
            paragraph.append(trimmed)
            i += 1
        }
        flushParagraph()
        closeLists()
        return out.joined(separator: "\n")
    }

    /// A list item line: its list's tag, the opening tag for a list that starts with it, and its text.
    /// Like CommonMark, an ordered list counts from its first item's number; later numbers are ignored.
    private static func listItem(_ line: String) -> (tag: String, open: String, text: String)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        if let m = match(#"^[-*+]\s+(.*)$"#, t) { return ("ul", "<ul>", m[1]) }
        if let m = match(#"^(\d{1,9})[.)]\s+(.*)$"#, t) {
            let start = Int(m[1]) ?? 1
            return ("ol", start == 1 ? "<ol>" : "<ol start=\"\(start)\">", m[2])
        }
        return nil
    }

    private static func cells(_ row: String) -> [String] {
        var t = row.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Inline

    static func inline(_ text: String) -> String {
        // Pull code spans out first so nothing inside them is formatted.
        var codes: [String] = []
        var s = replace(#"`([^`]+)`"#, in: text) { m in
            codes.append("<code>\(escape(m[1]))</code>")
            return "\u{E000}\(codes.count - 1)\u{E000}"
        }
        s = escape(s)
        s = replace(#"!\[([^\]]*)\]\(([^)\s]+)(?:\s+&quot;[^&]*&quot;)?\)"#, in: s) { m in m[1] }
        s = replace(#"\[([^\]]+)\]\(([^)\s]+)(?:\s+&quot;[^&]*&quot;)?\)"#, in: s) { m in "<a href=\"\(m[2])\">\(m[1])</a>" }
        s = replace(#"&lt;(https?://[^\s&]+)&gt;"#, in: s) { m in "<a href=\"\(m[1])\">\(m[1])</a>" }
        s = replace(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#, in: s) { m in "<strong>\(m[2])</strong>" }
        s = replace(#"(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])"#, in: s) { m in "<em>\(m[1])</em>" }
        s = replace(#"(?<![\w_])_(?=\S)(.+?)(?<=\S)_(?![\w_])"#, in: s) { m in "<em>\(m[1])</em>" }
        s = replace(#"~~(?=\S)(.+?)(?<=\S)~~"#, in: s) { m in "<del>\(m[1])</del>" }
        s = replace("\u{E000}(\\d+)\u{E000}", in: s) { m in codes[Int(m[1])!] }
        return s
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Regex helpers

    private static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { idx in
            Range(m.range(at: idx), in: s).map { String(s[$0]) } ?? ""
        }
    }

    private static func replace(_ pattern: String, in s: String, _ transform: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        var result = ""
        var last = s.startIndex
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let whole = Range(m.range, in: s) else { continue }
            result += s[last..<whole.lowerBound]
            let groups = (0..<m.numberOfRanges).map { idx in
                Range(m.range(at: idx), in: s).map { String(s[$0]) } ?? ""
            }
            result += transform(groups)
            last = whole.upperBound
        }
        result += s[last...]
        return result
    }
}

import XCTest
@testable import Convert

/// The Markdown → HTML renderer. Its output is exact and stable, so these compare whole snippets.
final class MarkdownTests: XCTestCase {
    private func html(_ lines: String...) -> String {
        Markdown.toHTML(lines.joined(separator: "\n"))
    }

    // MARK: Inline

    func testNestedEmphasis() {
        XCTAssertEqual(html("**bold *nested* bold**"), "<p><strong>bold <em>nested</em> bold</strong></p>")
    }

    func testUnderscoresInsideWordsAreNotItalic() {
        XCTAssertEqual(html("snake_case_word and _real italic_"),
                       "<p>snake_case_word and <em>real italic</em></p>")
    }

    func testCodeSpansProtectTheirContents() {
        XCTAssertEqual(html("`a*b*c` and *x*"), "<p><code>a*b*c</code> and <em>x</em></p>")
    }

    func testRawHTMLIsEscaped() {
        XCTAssertEqual(html(#"<b>raw</b> & "quotes""#),
                       "<p>&lt;b&gt;raw&lt;/b&gt; &amp; &quot;quotes&quot;</p>")
    }

    // MARK: Lists

    func testOrderedListFromOneHasNoStart() {
        XCTAssertEqual(html("1. one", "2. two"), "<ol>\n<li>one\n</li>\n<li>two\n</li></ol>")
    }

    func testOrderedListKeepsItsStartNumber() {
        // Like CommonMark, only the first number counts.
        XCTAssertEqual(html("3. three", "4. four", "9. nine"),
                       "<ol start=\"3\">\n<li>three\n</li>\n<li>four\n</li>\n<li>nine\n</li></ol>")
    }

    func testOrderedListCanStartAtZero() {
        XCTAssertEqual(html("0. zero"), "<ol start=\"0\">\n<li>zero\n</li></ol>")
    }

    func testNestedOrderedListKeepsItsStartNumber() {
        XCTAssertEqual(html("- outer", "  2. inner two", "  3. inner three", "- back"),
                       """
                       <ul>
                       <li>outer
                       <ol start="2">
                       <li>inner two
                       </li>
                       <li>inner three
                       </li></ol>
                       </li>
                       <li>back
                       </li></ul>
                       """)
    }

    func testOrderedListAfterBulletsKeepsItsStartNumber() {
        XCTAssertEqual(html("- bullet", "5) five", "6) six"),
                       "<ul>\n<li>bullet\n</li></ul><ol start=\"5\">\n<li>five\n</li>\n<li>six\n</li></ol>")
    }

    func testListBetweenParagraphs() {
        XCTAssertEqual(html("Para", "", "1. one", "", "After"),
                       "<p>Para</p>\n<ol>\n<li>one\n</li></ol>\n<p>After</p>")
    }
}

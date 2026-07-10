import Foundation

struct SummaryShareContent {
    let html: String
    let markdown: String
}

enum SummaryShareRenderer {
    static func render(document: SummaryDocument, actionItemsHeading: String) -> SummaryShareContent {
        SummaryShareContent(
            html: renderHTML(document: document, actionItemsHeading: actionItemsHeading),
            markdown: renderMarkdown(document: document, actionItemsHeading: actionItemsHeading)
        )
    }

    private static func renderMarkdown(document: SummaryDocument, actionItemsHeading: String) -> String {
        var chunks: [String] = []

        if let title = normalizedInlineMarkdown(document.title).nilIfBlank {
            chunks.append("# \(title)")
        }

        chunks.append(contentsOf: document.sections.compactMap(renderMarkdownSection))

        if let actionItems = renderMarkdownActionItems(document.actionItems, heading: actionItemsHeading) {
            chunks.append(actionItems)
        }

        return joinedChunks(chunks)
    }

    private static func renderMarkdownSection(_ section: SummarySection) -> String? {
        var chunks: [String] = []

        if let heading = normalizedInlineMarkdown(section.heading).nilIfBlank {
            chunks.append("## \(heading)")
        }

        chunks.append(contentsOf: section.blocks.compactMap(renderMarkdownBlock))
        return joinedChunks(chunks).nilIfBlank
    }

    private static func renderMarkdownBlock(_ block: SummaryBlock) -> String? {
        switch block.content {
        case let .paragraph(text):
            normalizedInlineMarkdown(text.text).nilIfBlank
        case let .bulletedList(items):
            renderMarkdownBulletList(items.map(\.text))
        case let .numberedList(items):
            items.enumerated()
                .compactMap { index, item in
                    normalizedInlineMarkdown(item.text).nilIfBlank.map { "\(index + 1). \($0)" }
                }
                .joined(separator: "\n")
                .nilIfBlank
        case let .checklist(items):
            items.compactMap { item in
                normalizedInlineMarkdown(item.text.text).nilIfBlank.map { "- [\(item.checked ? "x" : " ")] \($0)" }
            }
            .joined(separator: "\n")
            .nilIfBlank
        case let .quote(text):
            normalizedInlineMarkdown(text.text)
                .components(separatedBy: .newlines)
                .compactMap(\.nilIfBlank)
                .map { "> \($0)" }
                .joined(separator: "\n")
                .nilIfBlank
        case let .code(language, content):
            content.text.nilIfBlank.map { "```\(language)\n\($0)\n```" }
        case let .image(_, caption):
            normalizedInlineMarkdown(caption.text).nilIfBlank
        case let .heading(level, content):
            normalizedInlineMarkdown(content.text).nilIfBlank.map {
                "\(String(repeating: "#", count: clampedHeadingLevel(level))) \($0)"
            }
        case let .table(headers, rows):
            renderMarkdownTable(headers: headers, rows: rows)
        }
    }

    private static func renderMarkdownBulletList(_ items: [String]) -> String? {
        items.compactMap { item in
            normalizedInlineMarkdown(item).nilIfBlank.map { "- \($0)" }
        }
        .joined(separator: "\n")
        .nilIfBlank
    }

    private static func renderMarkdownTable(headers: [SummaryText], rows: [[SummaryText]]) -> String? {
        guard !headers.isEmpty else { return nil }

        let header = markdownTableRow(headers)
        let separator = "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |"
        let rowLines = rows.map(markdownTableRow)
        return ([header, separator] + rowLines).joined(separator: "\n")
    }

    private static func markdownTableRow(_ cells: [SummaryText]) -> String {
        let renderedCells = cells.map { text in
            normalizedInlineMarkdown(text.text)
                .replacing("|", with: "\\|")
                .replacing("\n", with: "<br>")
        }
        return "| " + renderedCells.joined(separator: " | ") + " |"
    }

    private static func renderMarkdownActionItems(_ actionItems: [SummaryActionItem], heading: String) -> String? {
        let items = actionItems.compactMap(normalizedActionItem)

        guard !items.isEmpty else { return nil }
        let lines = items.map { item in
            let assignee = item.assignee.map { " (\($0))" } ?? ""
            return "- [ ] \(item.title)\(assignee)"
        }
        return (["## \(normalizedInlineMarkdown(heading))"] + lines).joined(separator: "\n")
    }

    private static func renderHTML(document: SummaryDocument, actionItemsHeading: String) -> String {
        var chunks: [String] = []

        if let title = normalizedInlineMarkdown(document.title).nilIfBlank {
            chunks.append("<h1>\(renderInlineHTML(title))</h1>")
        }

        chunks.append(contentsOf: document.sections.compactMap(renderHTMLSection))

        if let actionItems = renderHTMLActionItems(document.actionItems, heading: actionItemsHeading) {
            chunks.append(actionItems)
        }

        let body = chunks.joined(separator: "\n")
        return """
        <!doctype html>
        <html>
        <head><meta charset="utf-8"></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func renderHTMLSection(_ section: SummarySection) -> String? {
        var chunks: [String] = []

        if let heading = normalizedInlineMarkdown(section.heading).nilIfBlank {
            chunks.append("<h2>\(renderInlineHTML(heading))</h2>")
        }

        chunks.append(contentsOf: section.blocks.compactMap(renderHTMLBlock))
        guard !chunks.isEmpty else { return nil }
        return "<section>\n\(chunks.joined(separator: "\n"))\n</section>"
    }

    private static func renderHTMLBlock(_ block: SummaryBlock) -> String? {
        switch block.content {
        case let .paragraph(text):
            return htmlParagraph(text.text)
        case let .bulletedList(items):
            return htmlList(items.map(\.text), element: "ul")
        case let .numberedList(items):
            return htmlList(items.map(\.text), element: "ol")
        case let .checklist(items):
            let renderedItems = items.compactMap { item -> String? in
                guard let text = normalizedInlineMarkdown(item.text.text).nilIfBlank else { return nil }
                let marker = item.checked ? "☑" : "☐"
                return "<li>\(marker) \(renderInlineHTML(text))</li>"
            }
            return htmlList(renderedItems: renderedItems, element: "ul")
        case let .quote(text):
            return htmlParagraph(text.text).map { "<blockquote>\($0)</blockquote>" }
        case let .code(_, content):
            return content.text.nilIfBlank.map { "<pre><code>\(escapeHTML($0))</code></pre>" }
        case let .image(_, caption):
            return normalizedInlineMarkdown(caption.text).nilIfBlank.map {
                "<p><em>\(renderInlineHTML($0))</em></p>"
            }
        case let .heading(level, content):
            return normalizedInlineMarkdown(content.text).nilIfBlank.map {
                let element = "h\(clampedHeadingLevel(level))"
                return "<\(element)>\(renderInlineHTML($0))</\(element)>"
            }
        case let .table(headers, rows):
            return renderHTMLTable(headers: headers, rows: rows)
        }
    }

    private static func htmlParagraph(_ text: String) -> String? {
        normalizedInlineMarkdown(text).nilIfBlank.map { "<p>\(renderInlineHTML($0))</p>" }
    }

    private static func htmlList(_ items: [String], element: String) -> String? {
        let renderedItems = items.compactMap { item in
            normalizedInlineMarkdown(item).nilIfBlank.map { "<li>\(renderInlineHTML($0))</li>" }
        }
        return htmlList(renderedItems: renderedItems, element: element)
    }

    private static func htmlList(renderedItems: [String], element: String) -> String? {
        guard !renderedItems.isEmpty else { return nil }
        return "<\(element)>\n\(renderedItems.joined(separator: "\n"))\n</\(element)>"
    }

    private static func renderHTMLTable(headers: [SummaryText], rows: [[SummaryText]]) -> String? {
        guard !headers.isEmpty else { return nil }

        let headerCells = headers.map { "<th>\(renderInlineHTML(normalizedInlineMarkdown($0.text)))</th>" }
        let rowHTML = rows.map { row in
            let cells = row.map { "<td>\(renderInlineHTML(normalizedInlineMarkdown($0.text)))</td>" }
            return "<tr>\(cells.joined())</tr>"
        }

        return """
        <table>
        <thead><tr>\(headerCells.joined())</tr></thead>
        <tbody>
        \(rowHTML.joined(separator: "\n"))
        </tbody>
        </table>
        """
    }

    private static func renderHTMLActionItems(_ actionItems: [SummaryActionItem], heading: String) -> String? {
        let renderedItems = actionItems.compactMap(normalizedActionItem).map { item in
            let assignee = item.assignee.map { " (\(renderInlineHTML($0)))" } ?? ""
            return "<li>☐ \(renderInlineHTML(item.title))\(assignee)</li>"
        }

        guard let list = htmlList(renderedItems: renderedItems, element: "ul") else { return nil }
        return "<section>\n<h2>\(renderInlineHTML(normalizedInlineMarkdown(heading)))</h2>\n\(list)\n</section>"
    }

    private static func normalizedActionItem(_ item: SummaryActionItem) -> (title: String, assignee: String?)? {
        guard let title = normalizedInlineMarkdown(item.title).nilIfBlank else { return nil }
        return (title, normalizedInlineMarkdown(item.assignee).nilIfBlank)
    }

    private static func renderInlineHTML(_ markdown: String) -> String {
        guard let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return escapedInlineHTML(markdown)
        }

        return attributed.runs.map { run in
            var html = escapedInlineHTML(String(attributed[run.range].characters))

            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    html = "<code>\(html)</code>"
                }
                if intent.contains(.stronglyEmphasized) {
                    html = "<strong>\(html)</strong>"
                }
                if intent.contains(.emphasized) {
                    html = "<em>\(html)</em>"
                }
                if intent.contains(.strikethrough) {
                    html = "<del>\(html)</del>"
                }
            }

            if let link = run.link, isSafeHTMLLink(link) {
                html = "<a href=\"\(escapeHTMLAttribute(link.absoluteString))\">\(html)</a>"
            }
            return html
        }
        .joined()
    }

    private static func normalizedInlineMarkdown(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(#/!\[([^\]]*)\]\([^)]+\)/#) { match in
                String(match.1)
            }
    }

    private static func joinedChunks(_ chunks: [String]) -> String {
        chunks
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clampedHeadingLevel(_ level: Int) -> Int {
        min(max(level, 3), 6)
    }

    private static func isSafeHTMLLink(_ link: URL) -> Bool {
        guard let scheme = link.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    private static func escapedInlineHTML(_ text: String) -> String {
        escapeHTML(text).replacing("\n", with: "<br>")
    }

    private static func escapeHTMLAttribute(_ text: String) -> String {
        escapeHTML(text).replacing("\"", with: "&quot;")
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacing("&", with: "&amp;")
            .replacing("<", with: "&lt;")
            .replacing(">", with: "&gt;")
    }
}

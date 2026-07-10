import AppKit
import Foundation
@testable import Dahlia

#if canImport(Testing)
    import Testing

    struct SummaryShareRendererTests {
        @Test
        func rendersRichHTMLAndMarkdownWhileOmittingStructuredTranscriptReferences() {
            let document = SummaryDocument(
                title: "Weekly Sync",
                sections: [
                    SummarySection(
                        id: UUID.v7(),
                        heading: "Summary",
                        blocks: [
                            .paragraph(SummaryText(
                                "Ship **alpha** based on decision. See [docs](https://example.com?a=1&b=2).",
                                transcriptRef: TranscriptReference(time: "00:10:00")
                            )),
                            .bulletedList(items: [
                                SummaryText("Confirm rollout", transcriptRef: TranscriptReference(time: "00:11:00")),
                            ]),
                            .numberedList(items: [
                                SummaryText("Prepare notes"),
                            ]),
                            .checklist(items: [
                                SummaryBlock.ChecklistItem(text: SummaryText("Follow up"), checked: false),
                            ]),
                            .quote(SummaryText("Keep launch small")),
                            .code(language: "swift", content: SummaryText("let enabled = true")),
                        ]
                    ),
                ]
            )

            let content = SummaryShareRenderer.render(document: document, actionItemsHeading: "Action Items")

            #expect(content.markdown.contains("# Weekly Sync"))
            #expect(content.markdown.contains("## Summary"))
            #expect(content.markdown.contains("Ship **alpha** based on decision."))
            #expect(content.markdown.contains("[docs](https://example.com?a=1&b=2)"))
            #expect(content.markdown.contains("- Confirm rollout"))
            #expect(content.markdown.contains("1. Prepare notes"))
            #expect(content.markdown.contains("- [ ] Follow up"))
            #expect(content.markdown.contains("> Keep launch small"))
            #expect(content.markdown.contains("```swift\nlet enabled = true\n```"))

            #expect(content.html.contains("<h1>Weekly Sync</h1>"))
            #expect(content.html.contains("<h2>Summary</h2>"))
            #expect(content.html.contains("Ship <strong>alpha</strong> based on decision."))
            #expect(content.html.contains("<a href=\"https://example.com?a=1&amp;b=2\">docs</a>"))
            #expect(content.html.contains("<ul>"))
            #expect(content.html.contains("<ol>"))
            #expect(content.html.contains("<li>☐ Follow up</li>"))
            #expect(content.html.contains("<blockquote><p>Keep launch small</p></blockquote>"))
            #expect(content.html.contains("<pre><code>let enabled = true</code></pre>"))

            #expect(!content.markdown.contains("00:10:00"))
            #expect(!content.markdown.contains("00:11:00"))
            #expect(!content.html.contains("00:10:00"))
            #expect(!content.html.contains("00:11:00"))
        }

        @Test
        func rendersStructuredActionItemsAndEscapesHTML() {
            let document = SummaryDocument(
                title: "Review <Draft>",
                sections: [],
                actionItems: [
                    SummaryActionItem(title: "Send **proposal**", assignee: "Aki & Ren"),
                    SummaryActionItem(title: "Schedule review", assignee: ""),
                ]
            )

            let content = SummaryShareRenderer.render(document: document, actionItemsHeading: "Action Items")

            #expect(content.markdown == """
            # Review <Draft>

            ## Action Items
            - [ ] Send **proposal** (Aki & Ren)
            - [ ] Schedule review
            """)
            #expect(content.html.contains("<h1>Review &lt;Draft&gt;</h1>"))
            #expect(content.html.contains("<h2>Action Items</h2>"))
            #expect(content.html.contains("<li>☐ Send <strong>proposal</strong> (Aki &amp; Ren)</li>"))
            #expect(content.html.contains("<li>☐ Schedule review</li>"))
        }

        @MainActor
        @Test
        func writesHTMLAndPlainTextAsRepresentationsOfOnePasteboardItem() throws {
            let pasteboard = NSPasteboard(name: .init("SummaryShareRendererTests-\(UUID().uuidString)"))
            defer { pasteboard.releaseGlobally() }
            let content = SummaryShareContent(html: "<strong>Summary</strong>", markdown: "**Summary**")

            #expect(SummaryPasteboardWriter.write(content, to: pasteboard))

            let items = try #require(pasteboard.pasteboardItems)
            let item = try #require(items.first)
            #expect(items.count == 1)
            #expect(item.string(forType: .html) == content.html)
            #expect(item.string(forType: .string) == content.markdown)
        }
    }
#endif

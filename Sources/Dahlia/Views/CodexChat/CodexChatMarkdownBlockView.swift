import SwiftUI

struct CodexChatMarkdownBlockView: View {
    let block: CodexChatMarkdownBlock

    var body: some View {
        switch block {
        case let .paragraph(text):
            markdownText(text)
        case let .heading(level, text):
            markdownText(text)
                .font(headingFont(for: level))
                .fontWeight(.semibold)
        case let .unorderedList(items):
            list(items: items, ordered: false)
        case let .orderedList(items):
            list(items: items, ordered: true)
        case let .blockquote(text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.tertiary)
                    .frame(width: 3)
                markdownText(text)
                    .foregroundStyle(.secondary)
            }
        case let .code(language, text):
            VStack(alignment: .leading, spacing: 6) {
                if let language {
                    Text(language)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                }
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        case .divider:
            Divider()
        }
    }

    private func list(items: [String], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .frame(minWidth: 14, alignment: .trailing)
                    markdownText(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func markdownText(_ value: String) -> some View {
        Text(attributedMarkdown(value))
            .textSelection(.enabled)
    }

    private func attributedMarkdown(_ value: String) -> AttributedString {
        (try? AttributedString(
            markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(value)
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        default: .headline
        }
    }
}

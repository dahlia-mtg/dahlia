import SwiftUI

struct CodexChatMarkdownProjectionView: View {
    let blocks: [CodexChatMarkdownRenderedBlock]
    let pendingSuffix: String?

    init(
        blocks: [CodexChatMarkdownRenderedBlock],
        pendingSuffix: String? = nil
    ) {
        self.blocks = blocks
        self.pendingSuffix = pendingSuffix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks.indices, id: \.self) { index in
                CodexChatMarkdownBlockView(block: block(at: index))
            }
        }
    }

    private func block(at index: Int) -> CodexChatMarkdownRenderedBlock {
        guard index == blocks.indices.last,
              let pendingSuffix
        else { return blocks[index] }

        return blocks[index].appendingPendingSuffix(pendingSuffix) ?? blocks[index]
    }
}

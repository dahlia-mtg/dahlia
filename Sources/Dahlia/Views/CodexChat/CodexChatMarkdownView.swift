import SwiftUI

struct CodexChatMarkdownView: View {
    let markdown: String
    let isStreaming: Bool

    @State private var projectionModel: CodexChatMarkdownProjectionModel

    init(markdown: String, isStreaming: Bool = false) {
        self.markdown = markdown
        self.isStreaming = isStreaming
        _projectionModel = State(initialValue: CodexChatMarkdownProjectionModel())
    }

    var body: some View {
        Group {
            if let projection = projectionModel.projection,
               projectionModel.canDisplayProjection,
               projectionModel.canDisplayPendingSuffix {
                CodexChatMarkdownProjectionView(
                    blocks: projection.blocks,
                    pendingSuffix: projectionModel.pendingSuffix
                )
            } else {
                Text(markdown)
                    .textSelection(.enabled)
            }
        }
        .onChange(
            of: CodexChatMarkdownInput(markdown: markdown, isStreaming: isStreaming),
            initial: true
        ) { _, input in
            projectionModel.submit(input)
        }
        .onDisappear(perform: projectionModel.cancel)
    }
}

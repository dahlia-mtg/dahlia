import SwiftUI

/// 設定画面「AI 要約」タブ。要約生成に使うモデルと出力上限を管理する。
struct AISummarySettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                Picker(selection: $settings.llmModel) {
                    ForEach(LLMModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                } label: {
                    Text(L10n.model)
                    Text(L10n.modelDescription)
                }
                .pickerStyle(.menu)

                LabeledContent {
                    TextField("", value: $settings.llmMaxTokens, format: .number)
                        .textFieldStyle(.roundedBorder)
                } label: {
                    Text(L10n.maxTokens)
                    Text(L10n.maxTokensDescription)
                }
            } header: {
                Text(L10n.aiSummary)
            } footer: {
                Text(L10n.aiSummaryModelSettingsDescription)
            }
        }
        .formStyle(.grouped)
    }
}

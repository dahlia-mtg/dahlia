import SwiftUI

/// 設定画面「Model Provider」タブ。LLM プロバイダーの認証と接続設定を管理する。
struct AccountSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var apiToken = ""
    @State private var isTestingConnection = false
    @State private var isLoadingDatabricksProfiles = false
    @State private var databricksProfiles: [DatabricksCLIClient.Profile] = []
    @State private var connectionTestResult: ConnectionTestResult?
    @State private var databricksProfileLoadError: String?

    private enum ConnectionTestResult {
        case success
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                Picker(selection: $settings.llmProvider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                } label: {
                    Text(L10n.modelProvider)
                    Text(L10n.modelProviderDescription)
                }
                .pickerStyle(.menu)

                providerConfigurationRows

                if shouldShowAPITokenField {
                    LabeledContent {
                        SecureField("", text: $apiToken)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { settings.llmAPIToken = apiToken }
                    } label: {
                        Text(apiTokenLabel)
                        Text(L10n.apiTokenStoredInKeychain)
                    }
                }
            } footer: {
                Text(L10n.modelProviderSettingsDescription)
            }

            Section {
                connectionTestControl
                connectionTestStatus
            } header: {
                Text(L10n.testConnection)
            } footer: {
                Text(L10n.connectionDiagnosticsDescription)
            }
        }
        .formStyle(.grouped)
        .task {
            await loadInitialState()
        }
        .onDisappear(perform: saveAPIToken)
        .onChange(of: settings.llmProviderRawValue) { _, _ in
            providerConfigurationDidChange()
        }
        .onChange(of: settings.llmModelRawValue) { _, _ in
            connectionTestResult = nil
        }
        .onChange(of: settings.llmDatabricksWorkspaceURL) { _, _ in
            connectionTestResult = nil
        }
        .onChange(of: settings.llmDatabricksProfile) { _, _ in
            connectionTestResult = nil
        }
        .onChange(of: settings.llmDatabricksAuthenticationTypeRawValue) { _, _ in
            providerConfigurationDidChange()
        }
    }

    // MARK: - Private

    private var selectedDatabricksProfile: DatabricksCLIClient.Profile? {
        databricksProfiles.first { $0.name == settings.llmDatabricksProfile }
    }

    private var endpoint: String {
        switch (settings.llmProvider, settings.llmDatabricksAuthenticationType) {
        case (.openAI, _):
            AppSettings.openAIEndpointURL
        case (.databricks, .personalAccessToken):
            settings.resolvedLLMEndpointURL
        case (.databricks, .oauthCLI):
            selectedDatabricksProfile?.endpointURL ?? ""
        }
    }

    private var endpointPlaceholder: String {
        if shouldLoadDatabricksProfiles {
            L10n.workspaceHostUnavailableFromProfile
        } else {
            L10n.endpointGeneratedFromWorkspaceURL
        }
    }

    private var isConnectionConfigurationComplete: Bool {
        endpoint.nilIfBlank != nil
            && (!shouldShowAPITokenField || apiToken.nilIfBlank != nil)
    }

    private var shouldShowAPITokenField: Bool {
        settings.llmProvider == .openAI
            || settings.llmDatabricksAuthenticationType == .personalAccessToken
    }

    private var shouldLoadDatabricksProfiles: Bool {
        settings.llmProvider == .databricks
            && settings.llmDatabricksAuthenticationType == .oauthCLI
    }

    private var apiTokenLabel: String {
        settings.llmProvider == .databricks ? L10n.personalAccessToken : L10n.apiToken
    }

    @ViewBuilder
    private var connectionTestControl: some View {
        if isTestingConnection {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(L10n.testing)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button(L10n.testConnection, action: testConnection)
                .disabled(!isConnectionConfigurationComplete)
        }
    }

    @ViewBuilder
    private var connectionTestStatus: some View {
        if let result = connectionTestResult {
            switch result {
            case .success:
                SettingsStatusMessage(
                    text: L10n.connectionSuccess,
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                )
            case let .failure(message):
                SettingsStatusMessage(
                    text: message,
                    systemImage: "xmark.circle.fill",
                    tint: .red
                )
            }
        } else if !isConnectionConfigurationComplete {
            Text(L10n.llmConfigIncomplete)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var providerConfigurationRows: some View {
        switch settings.llmProvider {
        case .openAI:
            LabeledContent {
                endpointPreview(AppSettings.openAIEndpointURL)
            } label: {
                Text(L10n.endpointURL)
                Text(L10n.openAIEndpointDescription)
            }
        case .databricks:
            Picker(selection: $settings.llmDatabricksAuthenticationType) {
                ForEach(DatabricksAuthenticationType.allCases) { authenticationType in
                    Text(authenticationType.displayName).tag(authenticationType)
                }
            } label: {
                Text(L10n.authenticationType)
                Text(L10n.databricksAuthenticationTypeDescription)
            }
            .pickerStyle(.menu)

            databricksConfigurationRows
        }
    }

    @ViewBuilder
    private var databricksConfigurationRows: some View {
        switch settings.llmDatabricksAuthenticationType {
        case .personalAccessToken:
            LabeledContent {
                TextField(
                    "",
                    text: $settings.llmDatabricksWorkspaceURL,
                    prompt: Text("https://e2-demo-tokyo.cloud.databricks.com")
                )
                .textFieldStyle(.roundedBorder)
            } label: {
                Text(L10n.databricksWorkspaceURL)
                Text(L10n.databricksWorkspaceURLDescription)
            }
        case .oauthCLI:
            DatabricksOAuthSettingsRows(
                selectedProfile: $settings.llmDatabricksProfile,
                profiles: databricksProfiles,
                isLoading: isLoadingDatabricksProfiles,
                loadError: databricksProfileLoadError,
                refreshProfiles: refreshDatabricksProfiles
            )
        }

        LabeledContent(L10n.endpointURL) {
            endpointPreview(endpoint)
        }
    }

    private func endpointPreview(_ endpoint: String) -> some View {
        let endpoint = endpoint.nilIfBlank
        return Text(endpoint ?? endpointPlaceholder)
            .font(.callout.monospaced())
            .foregroundStyle(endpoint == nil ? Color.secondary : Color.primary)
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func loadInitialState() async {
        apiToken = settings.llmAPIToken
        if shouldLoadDatabricksProfiles {
            await loadDatabricksProfiles()
        }
    }

    private func saveAPIToken() {
        settings.llmAPIToken = apiToken
    }

    private func providerConfigurationDidChange() {
        connectionTestResult = nil
        if shouldLoadDatabricksProfiles {
            refreshDatabricksProfiles()
        } else {
            databricksProfileLoadError = nil
        }
    }

    private func refreshDatabricksProfiles() {
        Task { await loadDatabricksProfiles() }
    }

    private func testConnection() {
        if shouldShowAPITokenField {
            settings.llmAPIToken = apiToken
        }
        connectionTestResult = nil
        isTestingConnection = true
        Task {
            defer { isTestingConnection = false }
            do {
                let endpoint = try await LLMEndpointResolver().endpoint(
                    provider: settings.llmProvider,
                    databricksAuthenticationType: settings.llmDatabricksAuthenticationType,
                    databricksWorkspaceURL: settings.llmDatabricksWorkspaceURL,
                    databricksProfile: settings.llmDatabricksProfile
                )
                let token = try await LLMCredentialResolver().accessToken(
                    provider: settings.llmProvider,
                    apiToken: apiToken,
                    databricksAuthenticationType: settings.llmDatabricksAuthenticationType,
                    databricksProfile: settings.llmDatabricksProfile
                )
                try await LLMService.testConnection(
                    endpoint: endpoint,
                    model: settings.resolvedLLMModelName,
                    token: token
                )
                connectionTestResult = .success
            } catch {
                connectionTestResult = .failure(error.localizedDescription)
            }
        }
    }

    private func loadDatabricksProfiles() async {
        isLoadingDatabricksProfiles = true
        databricksProfileLoadError = nil
        defer { isLoadingDatabricksProfiles = false }

        do {
            let profiles = try await DatabricksCLIClient().profiles()
            databricksProfiles = profiles
            let selectedProfile = AppSettings.resolvedDatabricksProfileSelection(
                current: settings.llmDatabricksProfile,
                availableProfiles: profiles.map(\.name)
            )
            if selectedProfile != settings.llmDatabricksProfile {
                settings.llmDatabricksProfile = selectedProfile
            }
        } catch {
            databricksProfiles = []
            databricksProfileLoadError = error.localizedDescription
        }
    }
}

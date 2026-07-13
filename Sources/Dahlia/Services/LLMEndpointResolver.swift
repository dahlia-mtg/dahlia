import Foundation

/// LLM プロバイダーの認証設定から、リクエスト先の endpoint を解決する。
struct LLMEndpointResolver {
    private let databricksClient: DatabricksCLIClient

    init(databricksClient: DatabricksCLIClient = DatabricksCLIClient()) {
        self.databricksClient = databricksClient
    }

    func endpoint(
        provider: LLMProvider,
        databricksAuthenticationType: DatabricksAuthenticationType,
        databricksWorkspaceURL: String,
        databricksProfile: String
    ) async throws -> String {
        switch (provider, databricksAuthenticationType) {
        case (.openAI, _):
            return AppSettings.openAIEndpointURL
        case (.databricks, .personalAccessToken):
            guard let endpoint = AppSettings.databricksEndpointURL(workspaceURL: databricksWorkspaceURL) else {
                throw LLMEndpointError.workspaceURLInvalid
            }
            return endpoint
        case (.databricks, .oauthCLI):
            let profiles = try await databricksClient.profiles()
            guard let profile = profiles.first(where: { $0.name == databricksProfile }) else {
                throw LLMEndpointError.profileNotFound
            }
            guard let endpoint = profile.endpointURL else {
                throw LLMEndpointError.profileWorkspaceHostUnavailable
            }
            return endpoint
        }
    }
}

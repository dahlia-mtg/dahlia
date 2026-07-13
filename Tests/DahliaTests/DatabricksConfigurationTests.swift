@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    struct DatabricksConfigurationTests {
        @Test
        func profileSelectionUsesOnlyRegisteredCLIProfiles() {
            #expect(AppSettings.resolvedDatabricksProfileSelection(current: "", availableProfiles: []).isEmpty)
            #expect(AppSettings.resolvedDatabricksProfileSelection(current: "CUSTOM", availableProfiles: []).isEmpty)
            #expect(
                AppSettings.resolvedDatabricksProfileSelection(
                    current: "MISSING",
                    availableProfiles: ["DEV", "WORK"]
                ) == "DEV"
            )
            #expect(
                AppSettings.resolvedDatabricksProfileSelection(
                    current: " WORK ",
                    availableProfiles: ["DEV", "WORK"]
                ) == "WORK"
            )
        }

        @Test
        func oauthConfigurationRequiresOnlyCLIProfile() {
            let settings = AppSettings.shared
            let previousProviderRawValue = settings.llmProviderRawValue
            let previousWorkspaceURL = settings.llmDatabricksWorkspaceURL
            let previousAuthenticationTypeRawValue = settings.llmDatabricksAuthenticationTypeRawValue
            let previousProfile = settings.llmDatabricksProfile
            defer {
                settings.llmProviderRawValue = previousProviderRawValue
                settings.llmDatabricksWorkspaceURL = previousWorkspaceURL
                settings.llmDatabricksAuthenticationTypeRawValue = previousAuthenticationTypeRawValue
                settings.llmDatabricksProfile = previousProfile
            }

            settings.llmProvider = .databricks
            settings.llmDatabricksWorkspaceURL = ""
            settings.llmDatabricksAuthenticationType = .oauthCLI
            settings.llmDatabricksProfile = "WORK"
            #expect(settings.isLLMConfigComplete)
            #expect(settings.resolvedLLMEndpointURL.isEmpty)

            settings.llmDatabricksProfile = "  "
            #expect(!settings.isLLMConfigComplete)
        }
    }
#endif

@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    struct DatabricksConfigurationTests {
        @Test
        func profileSelectionSupportsFirstTimeSignInAndExistingProfiles() {
            #expect(AppSettings.resolvedDatabricksProfileSelection(current: "", availableProfiles: []) == "DAHLIA")
            #expect(AppSettings.resolvedDatabricksProfileSelection(current: "CUSTOM", availableProfiles: []) == "CUSTOM")
            #expect(
                AppSettings.resolvedDatabricksProfileSelection(
                    current: "MISSING",
                    availableProfiles: ["DEV", "WORK"]
                ) == "DEV"
            )
            #expect(
                AppSettings.resolvedDatabricksProfileSelection(
                    current: "WORK",
                    availableProfiles: ["DEV", "WORK"]
                ) == "WORK"
            )
        }

        @Test
        func configurationRequiresWorkspaceAndCLIProfileInsteadOfPAT() {
            let settings = AppSettings.shared
            let previousProviderRawValue = settings.llmProviderRawValue
            let previousWorkspaceID = settings.llmDatabricksWorkspaceID
            let previousProfile = settings.llmDatabricksProfile
            defer {
                settings.llmProviderRawValue = previousProviderRawValue
                settings.llmDatabricksWorkspaceID = previousWorkspaceID
                settings.llmDatabricksProfile = previousProfile
            }

            settings.llmProvider = .databricks
            settings.llmDatabricksWorkspaceID = "1234567890123456"
            settings.llmDatabricksProfile = "DAHLIA"
            #expect(settings.isLLMConfigComplete)

            settings.llmDatabricksProfile = "  "
            #expect(!settings.isLLMConfigComplete)
        }
    }
#endif

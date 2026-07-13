@testable import Dahlia

#if canImport(Testing)
    import Testing

    struct SettingsCategoryTests {
        @Test
        func modelProviderAndAISummarySettingsAreSeparateCategories() throws {
            #expect(SettingsCategory.modelProvider.label == L10n.modelProvider)
            #expect(SettingsCategory.modelProvider.rawValue == "accounts")
            #expect(SettingsCategory.aiSummary.label == L10n.aiSummary)
            let modelProviderIndex = try #require(SettingsCategory.allCases.firstIndex(of: .modelProvider))
            let aiSummaryIndex = try #require(SettingsCategory.allCases.firstIndex(of: .aiSummary))
            #expect(modelProviderIndex < aiSummaryIndex)
        }

        @Test
        func debugCategoryIsLastAndUsesDebugPresentation() {
            #expect(SettingsCategory.allCases.last == .audioDiagnostics)
            #expect(SettingsCategory.audioDiagnostics.label == L10n.debug)
            #expect(SettingsCategory.audioDiagnostics.systemImage == "ladybug")
        }
    }
#endif

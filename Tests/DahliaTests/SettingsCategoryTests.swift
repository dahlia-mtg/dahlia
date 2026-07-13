@testable import Dahlia

#if canImport(Testing)
    import Testing

    struct SettingsCategoryTests {
        @Test
        func accountAndAISummarySettingsAreSeparateCategories() throws {
            #expect(SettingsCategory.accounts.label == L10n.accountManagement)
            #expect(SettingsCategory.aiSummary.label == L10n.aiSummary)
            let accountsIndex = try #require(SettingsCategory.allCases.firstIndex(of: .accounts))
            let aiSummaryIndex = try #require(SettingsCategory.allCases.firstIndex(of: .aiSummary))
            #expect(accountsIndex < aiSummaryIndex)
        }

        @Test
        func debugCategoryIsLastAndUsesDebugPresentation() {
            #expect(SettingsCategory.allCases.last == .audioDiagnostics)
            #expect(SettingsCategory.audioDiagnostics.label == L10n.debug)
            #expect(SettingsCategory.audioDiagnostics.systemImage == "ladybug")
        }
    }
#endif

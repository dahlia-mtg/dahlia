@testable import Dahlia

#if canImport(Testing)
    import Testing

    struct SettingsCategoryTests {
        @Test
        func categoriesAreOrderedByUserWorkflow() {
            #expect(SettingsCategory.allCases == [
                .general,
                .transcription,
                .screenshots,
                .calendar,
                .cloudStorage,
                .modelProvider,
                .aiSummary,
                .mcp,
                .instructions,
                .developer,
                .audioDiagnostics,
            ])
        }

        @Test
        func groupsContainEveryCategoryOnce() {
            let groupedCategories = SettingsGroup.allCases.flatMap(\.categories)
            #expect(groupedCategories == SettingsCategory.allCases)
        }

        @Test
        func technicalCategoriesUseUserFacingLabelsAndIdentifiers() {
            #expect(SettingsCategory.modelProvider.rawValue == "accounts")
            #expect(SettingsCategory.modelProvider.label == L10n.aiConnection)
            #expect(SettingsCategory.cloudStorage.rawValue == "cloudStorage")
            #expect(SettingsCategory.cloudStorage.label == L10n.export)
            #expect(SettingsCategory.mcp.rawValue == "mcp")
            #expect(SettingsCategory.mcp.label == "MCP")
            #expect(SettingsCategory.mcp.systemImage == "network")
            #expect(SettingsCategory.audioDiagnostics.rawValue == "audioDiagnostics")
            #expect(SettingsCategory.audioDiagnostics.label == L10n.diagnostics)
        }

        @Test
        func advancedSettingsRemainAtTheEnd() {
            #expect(SettingsGroup.allCases.last == .advanced)
            #expect(SettingsGroup.advanced.categories == [.developer, .audioDiagnostics])
        }
    }
#endif

import Foundation
@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    @Suite(.serialized)
    struct AppSettingsBatchLanguageTests {
        @Test
        func remembersTheLastConfirmedBatchLanguagePair() {
            let settings = AppSettings.shared
            let originalPrimary = settings.batchPrimaryLocaleIdentifier
            let originalSecondary = settings.batchSecondaryLocaleIdentifier
            defer {
                settings.batchPrimaryLocaleIdentifier = originalPrimary
                settings.batchSecondaryLocaleIdentifier = originalSecondary
            }
            let selection = BatchTranscriptionLanguageSelection(
                primaryLocaleIdentifier: "ja_JP",
                secondaryLocaleIdentifier: "en_US"
            )

            settings.rememberBatchLanguageSelection(selection)

            #expect(settings.preferredBatchLanguageSelection(
                fallbackPrimaryLocaleIdentifier: "fr_FR"
            ) == selection)

            let singleLanguage = BatchTranscriptionLanguageSelection(primaryLocaleIdentifier: "de_DE")
            settings.rememberBatchLanguageSelection(singleLanguage)

            #expect(settings.batchSecondaryLocaleIdentifier.isEmpty)
            #expect(settings.preferredBatchLanguageSelection(
                fallbackPrimaryLocaleIdentifier: "fr_FR"
            ) == singleLanguage)
        }

        @Test
        func invalidStoredPairFallsBackToTheCurrentPrimaryLanguage() {
            let settings = AppSettings.shared
            let originalPrimary = settings.batchPrimaryLocaleIdentifier
            let originalSecondary = settings.batchSecondaryLocaleIdentifier
            defer {
                settings.batchPrimaryLocaleIdentifier = originalPrimary
                settings.batchSecondaryLocaleIdentifier = originalSecondary
            }
            settings.batchPrimaryLocaleIdentifier = "en_US"
            settings.batchSecondaryLocaleIdentifier = "en_GB"

            let selection = settings.preferredBatchLanguageSelection(
                fallbackPrimaryLocaleIdentifier: "ja_JP"
            )

            #expect(selection == BatchTranscriptionLanguageSelection(primaryLocaleIdentifier: "ja_JP"))
        }
    }
#endif

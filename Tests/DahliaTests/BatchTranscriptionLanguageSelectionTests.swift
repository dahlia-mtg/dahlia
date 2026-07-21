import Foundation
@testable import Dahlia

#if canImport(Testing)
    import Testing

    struct BatchTranscriptionLanguageSelectionTests {
        @Test
        func acceptsDistinctLanguagesAndNormalizesBlankSecondaryLanguage() {
            let mixed = BatchTranscriptionLanguageSelection(
                primaryLocaleIdentifier: " ja_JP ",
                secondaryLocaleIdentifier: " en_US "
            )
            let single = BatchTranscriptionLanguageSelection(
                primaryLocaleIdentifier: "ja_JP",
                secondaryLocaleIdentifier: "   "
            )

            #expect(mixed.isValid)
            #expect(mixed.localeIdentifiers == ["ja_JP", "en_US"])
            #expect(single.isValid)
            #expect(single.secondaryLocaleIdentifier == nil)
        }

        @Test
        func rejectsEmptyPrimaryAndRegionalVariantsOfOneLanguage() {
            #expect(!BatchTranscriptionLanguageSelection(primaryLocaleIdentifier: "").isValid)
            #expect(!BatchTranscriptionLanguageSelection(
                primaryLocaleIdentifier: "en_US",
                secondaryLocaleIdentifier: "en_GB"
            ).isValid)
        }
    }
#endif

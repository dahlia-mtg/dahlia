import AppKit
import Foundation
@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    struct CaptionViewModelBatchLanguageTests {
        @Test
        func localeOptionsIncludeRememberedLanguagesHiddenByTheDisplayFilter() {
            let viewModel = CaptionViewModel()
            viewModel.supportedLocales = [
                Locale(identifier: "ja_JP"),
                Locale(identifier: "en_US"),
                Locale(identifier: "fr_FR"),
            ]
            viewModel.filteredLocales = [Locale(identifier: "ja_JP")]

            let options = viewModel.batchTranscriptionLocaleOptions(
                preferredIdentifiers: ["ja_JP", "en_US"]
            )

            #expect(Set(options.map(\.identifier)) == ["ja_JP", "en_US"])
        }

        @Test
        func confirmationFailureRestoresTheAttemptedLanguagePair() async throws {
            _ = NSApplication.shared
            let fixture = try BatchAudioTestFixture(name: "FailedLanguageConfirmation")
            defer { fixture.removeFiles() }
            let selection = BatchTranscriptionLanguageSelection(
                primaryLocaleIdentifier: "ja_JP",
                secondaryLocaleIdentifier: "en_US"
            )
            let viewModel = CaptionViewModel()
            viewModel.configureBatchTranscription(
                dbQueue: fixture.database.dbQueue,
                managedRootURL: fixture.managedRootURL,
                recoverExistingSessions: false
            )
            viewModel.pendingBatchTranscriptionConfirmation = BatchTranscriptionConfirmation(
                sessionId: fixture.session.id,
                meetingId: fixture.meeting.id,
                suggestedLanguageSelection: selection,
                retainAudioAfterBatch: true
            )

            viewModel.confirmBatchTranscription(
                languageSelection: selection,
                retainAudioAfterBatch: true
            )

            #expect(await waitUntil {
                viewModel.pendingBatchTranscriptionConfirmation?.suggestedLanguageSelection == selection
            })
        }

        private func waitUntil(_ predicate: () -> Bool) async -> Bool {
            for _ in 0 ..< 100 {
                if predicate() { return true }
                await Task.yield()
            }
            return predicate()
        }
    }
#endif

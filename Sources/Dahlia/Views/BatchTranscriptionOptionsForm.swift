import SwiftUI

struct BatchTranscriptionOptionsForm: View {
    let locales: [Locale]
    @Binding var selectedPrimaryLocaleIdentifier: String
    @Binding var selectedSecondaryLocaleIdentifier: String
    @Binding var deleteAudioAfterTranscription: Bool

    @AppStorage(AppSettings.generateSummaryAfterBatchTranscriptionUserDefaultsKey)
    private var generateSummaryAfterBatchTranscription = false
    @AppStorage(AppSettings.exportBatchSummaryToVaultUserDefaultsKey)
    private var exportBatchSummaryToVault = true
    @AppStorage(AppSettings.exportBatchSummaryToGoogleDocsUserDefaultsKey)
    private var exportBatchSummaryToGoogleDocs = false
    @AppStorage(AppSettings.summaryPreviousMeetingCountUserDefaultsKey)
    private var previousMeetingCount = AppSettings.defaultSummaryPreviousMeetingCount

    var body: some View {
        Form {
            Section(L10n.transcription) {
                Picker(L10n.primaryLanguage, selection: $selectedPrimaryLocaleIdentifier) {
                    ForEach(locales, id: \.identifier) { locale in
                        Text(displayName(for: locale)).tag(locale.identifier)
                    }
                }
                .pickerStyle(.menu)

                Picker(L10n.secondaryLanguage, selection: $selectedSecondaryLocaleIdentifier) {
                    Text(L10n.none).tag("")
                    ForEach(secondaryLocales, id: \.identifier) { locale in
                        Text(displayName(for: locale)).tag(locale.identifier)
                    }
                }
                .pickerStyle(.menu)

                Text(L10n.secondaryLanguageDescription)
                    .foregroundStyle(.secondary)

                Toggle(isOn: $deleteAudioAfterTranscription) {
                    Text(L10n.deleteBatchAudioAfterTranscription)
                    Text(L10n.deleteBatchAudioAfterTranscriptionDescription)
                }
                .toggleStyle(.checkbox)
            }

            Section(L10n.summaryAndExport) {
                Toggle(isOn: $generateSummaryAfterBatchTranscription) {
                    Text(L10n.generateSummaryAfterBatchTranscription)
                    Text(L10n.generateSummaryAfterBatchTranscriptionDescription)
                }
                .toggleStyle(.checkbox)

                SummaryGenerationOptionsControls(
                    previousMeetingCount: normalizedPreviousMeetingCount,
                    exportsToVault: $exportBatchSummaryToVault,
                    exportsToGoogleDocs: $exportBatchSummaryToGoogleDocs,
                    isEnabled: generateSummaryAfterBatchTranscription
                )
            }
        }
        .formStyle(.grouped)
        .onChange(of: selectedPrimaryLocaleIdentifier, resetInvalidSecondaryLocale)
    }

    private func displayName(for locale: Locale) -> String {
        locale.localizedString(forIdentifier: locale.identifier)
            ?? Locale.current.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier
    }

    private var secondaryLocales: [Locale] {
        let primaryLanguageCode = BatchTranscriptionLanguageSelection.languageCode(for: selectedPrimaryLocaleIdentifier)
        return locales.filter { locale in
            BatchTranscriptionLanguageSelection.languageCode(for: locale.identifier) != primaryLanguageCode
        }
    }

    private func resetInvalidSecondaryLocale() {
        guard !selectedSecondaryLocaleIdentifier.isEmpty,
              !secondaryLocales.contains(where: { $0.identifier == selectedSecondaryLocaleIdentifier }) else { return }
        selectedSecondaryLocaleIdentifier = ""
    }

    private var normalizedPreviousMeetingCount: Binding<Int> {
        Binding(
            get: { AppSettings.normalizedSummaryPreviousMeetingCount(previousMeetingCount) },
            set: { previousMeetingCount = AppSettings.normalizedSummaryPreviousMeetingCount($0) }
        )
    }
}

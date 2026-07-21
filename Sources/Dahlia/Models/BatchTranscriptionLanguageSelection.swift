import Foundation

/// 録音後の文字起こしに使う、順序付きの最大2言語。
struct BatchTranscriptionLanguageSelection: Equatable, Sendable {
    let primaryLocaleIdentifier: String
    let secondaryLocaleIdentifier: String?

    init(primaryLocaleIdentifier: String, secondaryLocaleIdentifier: String? = nil) {
        self.primaryLocaleIdentifier = primaryLocaleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secondaryLocaleIdentifier = secondaryLocaleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }

    var isValid: Bool {
        guard !primaryLocaleIdentifier.isEmpty else { return false }
        guard let secondaryLocaleIdentifier else { return true }
        return Self.languageCode(for: primaryLocaleIdentifier) != Self.languageCode(for: secondaryLocaleIdentifier)
    }

    var localeIdentifiers: [String] {
        [primaryLocaleIdentifier, secondaryLocaleIdentifier].compactMap(\.self)
    }

    static func languageCode(for localeIdentifier: String) -> String? {
        Locale(identifier: localeIdentifier).language.languageCode?.identifier
    }
}

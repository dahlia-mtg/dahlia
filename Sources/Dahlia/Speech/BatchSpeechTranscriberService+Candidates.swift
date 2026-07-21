@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import NaturalLanguage
import Speech

extension BatchSpeechTranscriberService {
    static func timeAlignedCandidates(
        from observations: [AttributedString],
        locale: Locale,
        utteranceRanges: [BatchSpeechDetectionRange]
    ) -> [BatchTranscriptionCandidate] {
        utteranceRanges.flatMap { utteranceRange in
            let audioTimeRange = CMTimeRange(
                start: CMTime(seconds: utteranceRange.startSeconds, preferredTimescale: 600),
                end: CMTime(seconds: utteranceRange.endSeconds, preferredTimescale: 600)
            )
            return observations.compactMap { observation -> BatchTranscriptionCandidate? in
                guard let attributedRange = observation.rangeOfAudioTimeRangeAttributes(
                    intersecting: audioTimeRange
                ) else { return nil }
                return candidate(
                    from: AttributedString(observation[attributedRange]),
                    locale: locale,
                    range: utteranceRange
                )
            }
        }
    }

    static func wholeRangeCandidates(
        from observations: [AttributedString],
        locale: Locale,
        range: BatchSpeechDetectionRange
    ) -> [BatchTranscriptionCandidate] {
        observations.compactMap { observation in
            candidate(from: observation, locale: locale, range: range)
        }
    }

    static func naturalLanguage(for locale: Locale) -> NLLanguage? {
        guard let languageCode = locale.language.languageCode?.identifier else { return nil }
        guard languageCode == "zh", let script = locale.language.script?.identifier else {
            return NLLanguage(rawValue: languageCode)
        }
        return NLLanguage(rawValue: "\(languageCode)-\(script)")
    }

    static func audioRange(for audioURL: URL) throws -> BatchSpeechDetectionRange {
        let audioFile = try AVAudioFile(forReading: audioURL)
        let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        return BatchSpeechDetectionRange(startSeconds: 0, endSeconds: duration)
    }

    private static func candidate(
        from attributedText: AttributedString,
        locale: Locale,
        range: BatchSpeechDetectionRange
    ) -> BatchTranscriptionCandidate? {
        guard let text = SpeechTranscriberService.normalizedTranscriptText(String(attributedText.characters)) else {
            return nil
        }
        return BatchTranscriptionCandidate(
            localeIdentifier: locale.identifier,
            startSeconds: range.startSeconds,
            endSeconds: range.endSeconds,
            text: text,
            confidence: transcriptionConfidence(in: attributedText),
            languageProbability: languageProbability(for: text, locale: locale)
        )
    }

    private static func transcriptionConfidence(in text: AttributedString) -> Double {
        var weightedConfidence = 0.0
        var characterCount = 0
        for run in text.runs {
            let runCharacterCount = max(1, text[run.range].characters.count)
            let confidence = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] ?? 0.5
            weightedConfidence += min(1, max(0, confidence)) * Double(runCharacterCount)
            characterCount += runCharacterCount
        }
        guard characterCount > 0 else { return 0.5 }
        return weightedConfidence / Double(characterCount)
    }

    private static func languageProbability(for text: String, locale: Locale) -> Double {
        guard let language = naturalLanguage(for: locale) else { return 0 }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.languageHypotheses(withMaximum: 20)[language] ?? 0
    }
}

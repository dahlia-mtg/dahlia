import CoreMedia
import Foundation
import NaturalLanguage
import Speech
@testable import Dahlia

#if canImport(Testing)
    import Testing

    struct BatchTranscriptionCandidateResolverTests {
        private struct TimedFragment {
            let text: String
            let start: TimeInterval
            let end: TimeInterval
            let confidence: Double
        }

        @Test
        func selectsTheBestLanguageForEachUtterance() {
            let resolved = BatchTranscriptionCandidateResolver.resolve(
                candidates: [
                    candidate("ja_JP", 0, 1, "こんにちは", confidence: 0.95, languageProbability: 0.99),
                    candidate("en_US", 0, 1, "Hello", confidence: 0.35, languageProbability: 0.99),
                    candidate("ja_JP", 2, 3, "次です", confidence: 0.40, languageProbability: 0.99),
                    candidate("en_US", 2, 3, "Next item", confidence: 0.94, languageProbability: 0.99),
                ],
                detectionRanges: [
                    BatchSpeechDetectionRange(startSeconds: 0, endSeconds: 1),
                    BatchSpeechDetectionRange(startSeconds: 2, endSeconds: 3),
                ],
                primaryLocaleIdentifier: "ja_JP"
            )

            #expect(resolved.map(\.localeIdentifier) == ["ja_JP", "en_US"])
            #expect(resolved.map(\.text) == ["こんにちは", "Next item"])
        }

        @Test
        func splitsOneTranscriptionResultAcrossTimedUtterances() {
            let utterances = [
                BatchSpeechDetectionRange(startSeconds: 0, endSeconds: 1),
                BatchSpeechDetectionRange(startSeconds: 2, endSeconds: 3),
            ]
            let japanese = BatchSpeechTranscriberService.timeAlignedCandidates(
                from: [
                    timedText([
                        TimedFragment(text: "こんにちは ", start: 0, end: 1, confidence: 0.95),
                        TimedFragment(text: "次です", start: 2, end: 3, confidence: 0.35),
                    ]),
                ],
                locale: Locale(identifier: "ja_JP"),
                utteranceRanges: utterances
            )
            let english = BatchSpeechTranscriberService.timeAlignedCandidates(
                from: [
                    timedText([
                        TimedFragment(text: "Hello ", start: 0, end: 1, confidence: 0.35),
                        TimedFragment(text: "Next item", start: 2, end: 3, confidence: 0.95),
                    ]),
                ],
                locale: Locale(identifier: "en_US"),
                utteranceRanges: utterances
            )

            let resolved = BatchTranscriptionCandidateResolver.resolve(
                candidates: japanese + english,
                detectionRanges: utterances,
                primaryLocaleIdentifier: "ja_JP"
            )

            #expect(resolved.map(\.localeIdentifier) == ["ja_JP", "en_US"])
            #expect(resolved.map(\.text) == ["こんにちは", "Next item"])
        }

        @Test
        func keepsThePreviousLanguageWhenScoresAreNearlyTied() {
            let resolved = BatchTranscriptionCandidateResolver.resolve(
                candidates: [
                    candidate("en_US", 0, 1, "First", confidence: 0.95, languageProbability: 0.9),
                    candidate("ja_JP", 0, 1, "最初", confidence: 0.50, languageProbability: 0.9),
                    candidate("en_US", 2, 3, "AI", confidence: 0.80, languageProbability: 0.5),
                    candidate("ja_JP", 2, 3, "AI", confidence: 0.82, languageProbability: 0.5),
                ],
                detectionRanges: [
                    BatchSpeechDetectionRange(startSeconds: 0, endSeconds: 1),
                    BatchSpeechDetectionRange(startSeconds: 2, endSeconds: 3),
                ],
                primaryLocaleIdentifier: "ja_JP"
            )

            #expect(resolved.map(\.localeIdentifier) == ["en_US", "en_US"])
        }

        @Test
        func fallsBackToTheBestWholeRangeCandidateWithoutSpeechRanges() {
            let resolved = BatchTranscriptionCandidateResolver.resolve(
                candidates: [
                    candidate("ja_JP", 0, 20, "日本語の候補", confidence: 0.55, languageProbability: 0.95),
                    candidate("en_US", 0, 20, "English candidate", confidence: 0.88, languageProbability: 0.95),
                ],
                detectionRanges: [],
                primaryLocaleIdentifier: "ja_JP",
                fallbackRange: BatchSpeechDetectionRange(startSeconds: 0, endSeconds: 60)
            )

            #expect(resolved.count == 1)
            #expect(resolved.first?.localeIdentifier == "en_US")
            #expect(resolved.first?.startSeconds == 0)
            #expect(resolved.first?.endSeconds == 60)
        }

        @Test
        func mergesSpeechRangesSeparatedByAtMostThreeHundredMilliseconds() {
            let resolved = BatchTranscriptionCandidateResolver.resolve(
                candidates: [
                    candidate("ja_JP", 0, 2, "ひとつの発話", confidence: 0.9, languageProbability: 1),
                    candidate("en_US", 0, 2, "One utterance", confidence: 0.4, languageProbability: 1),
                ],
                detectionRanges: [
                    BatchSpeechDetectionRange(startSeconds: 0, endSeconds: 1),
                    BatchSpeechDetectionRange(startSeconds: 1.3, endSeconds: 2),
                ],
                primaryLocaleIdentifier: "ja_JP"
            )

            #expect(resolved.count == 1)
            #expect(resolved.first?.startSeconds == 0)
            #expect(resolved.first?.endSeconds == 2)
        }

        @Test
        func fallsBackWhenCandidateTimingIsMissing() {
            let resolved = BatchTranscriptionCandidateResolver.resolve(
                candidates: [
                    candidate("ja_JP", 0, 0, "日本語", confidence: 0.4, languageProbability: 0.8),
                    candidate("en_US", 0, 0, "English", confidence: 0.9, languageProbability: 0.8),
                ],
                detectionRanges: [BatchSpeechDetectionRange(startSeconds: 0, endSeconds: 1)],
                primaryLocaleIdentifier: "ja_JP",
                fallbackRange: BatchSpeechDetectionRange(startSeconds: 0, endSeconds: 60)
            )

            #expect(resolved.map(\.localeIdentifier) == ["en_US"])
            #expect(resolved.first?.startSeconds == 0)
            #expect(resolved.first?.endSeconds == 60)
        }

        @Test
        func fallsBackWhenOneLocaleCannotBeAssignedToEveryUtterance() {
            let fallbackCandidates = [
                candidate("ja_JP", 0, 4, "日本語の全体候補", confidence: 0.9, languageProbability: 0.9),
                candidate("en_US", 0, 4, "English whole-range candidate", confidence: 0.6, languageProbability: 0.9),
            ]
            let resolved = BatchTranscriptionCandidateResolver.resolve(
                candidates: [
                    candidate("ja_JP", 0, 1, "最初", confidence: 0.9, languageProbability: 0.9),
                    candidate("en_US", 0, 1, "First", confidence: 0.6, languageProbability: 0.9),
                    candidate("ja_JP", 3, 4, "次", confidence: 0.9, languageProbability: 0.9),
                ],
                detectionRanges: [
                    BatchSpeechDetectionRange(startSeconds: 0, endSeconds: 1),
                    BatchSpeechDetectionRange(startSeconds: 3, endSeconds: 4),
                ],
                primaryLocaleIdentifier: "ja_JP",
                fallbackCandidates: fallbackCandidates,
                fallbackRange: BatchSpeechDetectionRange(startSeconds: 0, endSeconds: 4)
            )

            #expect(resolved.map(\.localeIdentifier) == ["ja_JP"])
            #expect(resolved.map(\.text) == ["日本語の全体候補"])
        }

        @Test
        func languageProbabilityCanSelectAnArbitraryLanguagePair() {
            let resolved = BatchTranscriptionCandidateResolver.resolve(
                candidates: [
                    candidate("fr_FR", 0, 1, "Bonjour", confidence: 0.8, languageProbability: 0.1),
                    candidate("de_DE", 0, 1, "Guten Tag", confidence: 0.8, languageProbability: 0.9),
                ],
                detectionRanges: [BatchSpeechDetectionRange(startSeconds: 0, endSeconds: 1)],
                primaryLocaleIdentifier: "fr_FR"
            )

            #expect(resolved.map(\.localeIdentifier) == ["de_DE"])
        }

        @Test
        func exactInitialTieUsesThePrimaryLanguage() {
            let resolved = BatchTranscriptionCandidateResolver.resolve(
                candidates: [
                    candidate("ja_JP", 0, 1, "同点", confidence: 0.8, languageProbability: 0.5),
                    candidate("en_US", 0, 1, "Tie", confidence: 0.8, languageProbability: 0.5),
                ],
                detectionRanges: [BatchSpeechDetectionRange(startSeconds: 0, endSeconds: 1)],
                primaryLocaleIdentifier: "ja_JP"
            )

            #expect(resolved.map(\.localeIdentifier) == ["ja_JP"])
        }

        @Test
        func doesNotMergeSpeechRangesSeparatedByMoreThanThreeHundredMilliseconds() {
            let resolved = BatchTranscriptionCandidateResolver.resolve(
                candidates: [
                    candidate("ja_JP", 0, 1, "一", confidence: 0.9, languageProbability: 0.9),
                    candidate("en_US", 0, 1, "One", confidence: 0.4, languageProbability: 0.9),
                    candidate("ja_JP", 1.31, 2, "二", confidence: 0.4, languageProbability: 0.9),
                    candidate("en_US", 1.31, 2, "Two", confidence: 0.9, languageProbability: 0.9),
                ],
                detectionRanges: [
                    BatchSpeechDetectionRange(startSeconds: 0, endSeconds: 1),
                    BatchSpeechDetectionRange(startSeconds: 1.31, endSeconds: 2),
                ],
                primaryLocaleIdentifier: "ja_JP"
            )

            #expect(resolved.map(\.localeIdentifier) == ["ja_JP", "en_US"])
        }

        @Test
        func emptyAndBlankCandidatesProduceNoTranscript() {
            #expect(BatchTranscriptionCandidateResolver.resolve(
                candidates: [],
                detectionRanges: [],
                primaryLocaleIdentifier: "ja_JP"
            ).isEmpty)
            #expect(BatchTranscriptionCandidateResolver.resolve(
                candidates: [candidate("ja_JP", 0, 1, "   ", confidence: 1, languageProbability: 1)],
                detectionRanges: [BatchSpeechDetectionRange(startSeconds: 0, endSeconds: 1)],
                primaryLocaleIdentifier: "ja_JP"
            ).isEmpty)
        }

        @Test
        func mapsChineseLocalesToScriptQualifiedNaturalLanguages() {
            #expect(BatchSpeechTranscriberService.naturalLanguage(
                for: Locale(identifier: "zh_CN")
            ) == NLLanguage.simplifiedChinese)
            #expect(BatchSpeechTranscriberService.naturalLanguage(
                for: Locale(identifier: "zh_TW")
            ) == NLLanguage.traditionalChinese)
            #expect(BatchSpeechTranscriberService.naturalLanguage(
                for: Locale(identifier: "fr_FR")
            ) == NLLanguage.french)
        }

        private func candidate(
            _ localeIdentifier: String,
            _ startSeconds: TimeInterval,
            _ endSeconds: TimeInterval,
            _ text: String,
            confidence: Double,
            languageProbability: Double
        ) -> BatchTranscriptionCandidate {
            BatchTranscriptionCandidate(
                localeIdentifier: localeIdentifier,
                startSeconds: startSeconds,
                endSeconds: endSeconds,
                text: text,
                confidence: confidence,
                languageProbability: languageProbability
            )
        }

        private func timedText(
            _ fragments: [TimedFragment]
        ) -> AttributedString {
            var result = AttributedString()
            for fragment in fragments {
                var attributedFragment = AttributedString(fragment.text)
                let range = attributedFragment.startIndex ..< attributedFragment.endIndex
                attributedFragment[range][AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] = CMTimeRange(
                    start: CMTime(seconds: fragment.start, preferredTimescale: 600),
                    end: CMTime(seconds: fragment.end, preferredTimescale: 600)
                )
                attributedFragment[range][AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] = fragment.confidence
                result.append(attributedFragment)
            }
            return result
        }
    }
#endif

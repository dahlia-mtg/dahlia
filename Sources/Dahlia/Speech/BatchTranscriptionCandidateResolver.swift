import Foundation

enum BatchTranscriptionCandidateResolver {
    private struct ScoredCandidate {
        let candidate: BatchTranscriptionCandidate
        let score: Double
    }

    private static let maximumUtteranceGap: TimeInterval = 0.3
    private static let confidenceWeight = 0.8
    private static let languageProbabilityWeight = 0.2
    private static let tieThreshold = 0.03

    static func resolve(
        candidates: [BatchTranscriptionCandidate],
        detectionRanges: [BatchSpeechDetectionRange],
        primaryLocaleIdentifier: String,
        fallbackCandidates: [BatchTranscriptionCandidate]? = nil,
        fallbackRange: BatchSpeechDetectionRange? = nil
    ) -> [ResolvedBatchTranscriptionCandidate] {
        let usableFallbackCandidates = (fallbackCandidates ?? candidates).filter { candidate in
            candidate.text.nilIfBlank != nil
        }
        guard !usableFallbackCandidates.isEmpty else { return [] }

        let timedCandidates = candidates.filter { candidate in
            candidate.endSeconds > candidate.startSeconds && candidate.text.nilIfBlank != nil
        }

        let utterances = utteranceRanges(from: detectionRanges)
        guard !utterances.isEmpty, !timedCandidates.isEmpty else {
            return resolveWholeRange(
                usableFallbackCandidates,
                primaryLocaleIdentifier: primaryLocaleIdentifier,
                fallbackRange: fallbackRange
            )
        }

        var assignments: [Int: [BatchTranscriptionCandidate]] = [:]
        for candidate in timedCandidates {
            guard let utteranceIndex = utterances.indices.max(by: { lhs, rhs in
                overlap(candidate, utterances[lhs]) < overlap(candidate, utterances[rhs])
            }), overlap(candidate, utterances[utteranceIndex]) > 0 else { continue }
            assignments[utteranceIndex, default: []].append(candidate)
        }

        let expectedLocaleIdentifiers = Set(usableFallbackCandidates.map(\.localeIdentifier))
        var previousLocaleIdentifier: String?
        var resolved: [ResolvedBatchTranscriptionCandidate] = []
        for utteranceIndex in utterances.indices {
            guard let assigned = assignments[utteranceIndex],
                  Set(assigned.map(\.localeIdentifier)) == expectedLocaleIdentifiers else {
                return resolveWholeRange(
                    usableFallbackCandidates,
                    primaryLocaleIdentifier: primaryLocaleIdentifier,
                    fallbackRange: fallbackRange
                )
            }
            let aggregated = aggregateByLocale(assigned)
            guard let selected = select(
                aggregated,
                primaryLocaleIdentifier: primaryLocaleIdentifier,
                previousLocaleIdentifier: previousLocaleIdentifier
            ) else { continue }
            let utterance = utterances[utteranceIndex]
            resolved.append(
                ResolvedBatchTranscriptionCandidate(
                    localeIdentifier: selected.localeIdentifier,
                    startSeconds: utterance.startSeconds,
                    endSeconds: utterance.endSeconds,
                    text: selected.text
                )
            )
            previousLocaleIdentifier = selected.localeIdentifier
        }
        return resolved
    }

    private static func resolveWholeRange(
        _ candidates: [BatchTranscriptionCandidate],
        primaryLocaleIdentifier: String,
        fallbackRange: BatchSpeechDetectionRange?
    ) -> [ResolvedBatchTranscriptionCandidate] {
        let aggregated = aggregateByLocale(candidates)
        guard let selected = select(
            aggregated,
            primaryLocaleIdentifier: primaryLocaleIdentifier,
            previousLocaleIdentifier: nil
        ) else { return [] }
        return [
            ResolvedBatchTranscriptionCandidate(
                localeIdentifier: selected.localeIdentifier,
                startSeconds: fallbackRange?.startSeconds ?? selected.startSeconds,
                endSeconds: fallbackRange?.endSeconds ?? selected.endSeconds,
                text: selected.text
            ),
        ]
    }

    private static func aggregateByLocale(_ candidates: [BatchTranscriptionCandidate]) -> [BatchTranscriptionCandidate] {
        Dictionary(grouping: candidates, by: \.localeIdentifier).map { localeIdentifier, localizedCandidates in
            let ordered = localizedCandidates.sorted { $0.startSeconds < $1.startSeconds }
            let weightedCharacterCount = ordered.reduce(0) { $0 + max(1, $1.text.count) }
            let confidence = ordered.reduce(0.0) { partial, candidate in
                partial + candidate.confidence * Double(max(1, candidate.text.count))
            } / Double(weightedCharacterCount)
            let languageProbability = ordered.reduce(0.0) { partial, candidate in
                partial + candidate.languageProbability * Double(max(1, candidate.text.count))
            } / Double(weightedCharacterCount)
            return BatchTranscriptionCandidate(
                localeIdentifier: localeIdentifier,
                startSeconds: ordered.map(\.startSeconds).min() ?? 0,
                endSeconds: ordered.map(\.endSeconds).max() ?? 0,
                text: ordered.map(\.text).joined(separator: " "),
                confidence: confidence,
                languageProbability: languageProbability
            )
        }
    }

    private static func select(
        _ candidates: [BatchTranscriptionCandidate],
        primaryLocaleIdentifier: String,
        previousLocaleIdentifier: String?
    ) -> BatchTranscriptionCandidate? {
        let scored = candidates.map { candidate in
            ScoredCandidate(
                candidate: candidate,
                score: confidenceWeight * candidate.confidence
                    + languageProbabilityWeight * candidate.languageProbability
            )
        }.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.candidate.localeIdentifier < rhs.candidate.localeIdentifier
            }
            return lhs.score > rhs.score
        }
        guard let first = scored.first else { return nil }
        guard scored.count > 1, first.score - scored[1].score <= tieThreshold else {
            return first.candidate
        }
        if let previousLocaleIdentifier,
           let previous = scored.first(where: { $0.candidate.localeIdentifier == previousLocaleIdentifier }) {
            return previous.candidate
        }
        return scored.first(where: { $0.candidate.localeIdentifier == primaryLocaleIdentifier })?.candidate
            ?? first.candidate
    }

    static func utteranceRanges(from ranges: [BatchSpeechDetectionRange]) -> [BatchSpeechDetectionRange] {
        let ordered = ranges
            .filter { $0.endSeconds > $0.startSeconds }
            .sorted { $0.startSeconds < $1.startSeconds }
        guard var current = ordered.first else { return [] }
        var result: [BatchSpeechDetectionRange] = []
        for range in ordered.dropFirst() {
            if range.startSeconds - current.endSeconds <= maximumUtteranceGap + TimeInterval.ulpOfOne {
                current = BatchSpeechDetectionRange(
                    startSeconds: current.startSeconds,
                    endSeconds: max(current.endSeconds, range.endSeconds)
                )
            } else {
                result.append(current)
                current = range
            }
        }
        result.append(current)
        return result
    }

    private static func overlap(
        _ candidate: BatchTranscriptionCandidate,
        _ detectionRange: BatchSpeechDetectionRange
    ) -> TimeInterval {
        max(0, min(candidate.endSeconds, detectionRange.endSeconds) - max(candidate.startSeconds, detectionRange.startSeconds))
    }
}

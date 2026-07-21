@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import Speech

/// CAFの指定rangeを精度優先のSpeechTranscriberで文字起こしする。
enum BatchSpeechTranscriberService {
    private struct TranscriptionAnalysis {
        let observations: [AttributedString]
        let detectionRanges: [BatchSpeechDetectionRange]
    }

    static func transcribe(_ request: BatchSpeechTranscriptionRequest) async throws -> [BatchRecognizedTranscriptSegment] {
        guard request.startFrame >= 0, request.frameCount > 0 else { return [] }
        let rangeURL = try extractRange(
            from: request.audioURL,
            startFrame: request.startFrame,
            frameCount: request.frameCount
        )
        defer { try? FileManager.default.removeItem(at: rangeURL) }

        guard let secondaryLocale = request.secondaryLocale else {
            return try await transcribeSingle(rangeURL: rangeURL, request: request)
        }

        let fallbackRange = try audioRange(for: rangeURL)
        let primary = try await analyzeTranscriptions(
            rangeURL: rangeURL,
            locale: request.locale,
            detectsSpeech: true
        )
        let secondary = try await analyzeTranscriptions(
            rangeURL: rangeURL,
            locale: secondaryLocale,
            detectsSpeech: false
        )
        let utteranceRanges = BatchTranscriptionCandidateResolver.utteranceRanges(from: primary.detectionRanges)
        let timedCandidates = timeAlignedCandidates(
            from: primary.observations,
            locale: request.locale,
            utteranceRanges: utteranceRanges
        ) + timeAlignedCandidates(
            from: secondary.observations,
            locale: secondaryLocale,
            utteranceRanges: utteranceRanges
        )
        let fallbackCandidates = wholeRangeCandidates(
            from: primary.observations,
            locale: request.locale,
            range: fallbackRange
        ) + wholeRangeCandidates(
            from: secondary.observations,
            locale: secondaryLocale,
            range: fallbackRange
        )
        let resolved = BatchTranscriptionCandidateResolver.resolve(
            candidates: timedCandidates,
            detectionRanges: primary.detectionRanges,
            primaryLocaleIdentifier: request.locale.identifier,
            fallbackCandidates: fallbackCandidates,
            fallbackRange: fallbackRange
        )
        return resolved.map { candidate in
            recognizedSegment(
                text: candidate.text,
                localeIdentifier: candidate.localeIdentifier,
                startSeconds: candidate.startSeconds,
                endSeconds: candidate.endSeconds,
                request: request
            )
        }
    }

    private static func transcribeSingle(
        rangeURL: URL,
        request: BatchSpeechTranscriptionRequest
    ) async throws -> [BatchRecognizedTranscriptSegment] {
        let transcriber = SpeechTranscriber(locale: request.locale, preset: .transcription)
        try await installAssetsIfNeeded(for: transcriber)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: rangeURL)
        let resultTask = Task<[BatchRecognizedTranscriptSegment], Error> {
            var segments: [BatchRecognizedTranscriptSegment] = []
            for try await result in transcriber.results where result.isFinal {
                guard let text = SpeechTranscriberService.normalizedTranscriptText(String(result.text.characters)) else {
                    continue
                }
                segments.append(
                    recognizedSegment(
                        text: text,
                        localeIdentifier: request.locale.identifier,
                        startSeconds: finiteSeconds(result.range.start.seconds),
                        endSeconds: finiteSeconds(result.range.end.seconds),
                        request: request
                    )
                )
            }
            return segments
        }

        do {
            try await analyze(audioFile: audioFile, with: analyzer)
            return try await resultTask.value
        } catch {
            await analyzer.cancelAndFinishNow()
            resultTask.cancel()
            throw error
        }
    }

    private static func analyzeTranscriptions(
        rangeURL: URL,
        locale: Locale,
        detectsSpeech: Bool
    ) async throws -> TranscriptionAnalysis {
        let transcriber = attributedTranscriber(locale: locale)
        try await installAssetsIfNeeded(for: transcriber)
        let detector = detectsSpeech
            ? SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium), reportResults: true)
            : nil
        let modules: [any SpeechModule] = if let detector {
            [transcriber, detector]
        } else {
            [transcriber]
        }
        let analyzer = SpeechAnalyzer(modules: modules)
        let audioFile = try AVAudioFile(forReading: rangeURL)

        let resultTask = Task<[AttributedString], Error> {
            var observations: [AttributedString] = []
            for try await result in transcriber.results where result.isFinal {
                observations.append(result.text)
            }
            return observations
        }
        let detectionTask = detector.map { detector in
            Task<[BatchSpeechDetectionRange], Error> {
                var ranges: [BatchSpeechDetectionRange] = []
                for try await result in detector.results where result.isFinal && result.speechDetected {
                    ranges.append(
                        BatchSpeechDetectionRange(
                            startSeconds: finiteSeconds(result.range.start.seconds),
                            endSeconds: finiteSeconds(result.range.end.seconds)
                        )
                    )
                }
                return ranges
            }
        }

        do {
            try await analyze(audioFile: audioFile, with: analyzer)
            let observations = try await resultTask.value
            let detectionRanges = try await detectionTask?.value ?? []
            return TranscriptionAnalysis(observations: observations, detectionRanges: detectionRanges)
        } catch {
            await analyzer.cancelAndFinishNow()
            resultTask.cancel()
            detectionTask?.cancel()
            throw error
        }
    }

    private static func attributedTranscriber(locale: Locale) -> SpeechTranscriber {
        let preset = SpeechTranscriber.Preset.transcription
        return SpeechTranscriber(
            locale: locale,
            transcriptionOptions: preset.transcriptionOptions,
            reportingOptions: preset.reportingOptions,
            attributeOptions: preset.attributeOptions.union([.audioTimeRange, .transcriptionConfidence])
        )
    }

    private static func analyze(audioFile: AVAudioFile, with analyzer: SpeechAnalyzer) async throws {
        guard let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile) else {
            throw BatchSpeechTranscriberError.analysisDidNotAdvance
        }
        try await analyzer.finalizeAndFinish(through: lastSampleTime)
    }

    private static func recognizedSegment(
        text: String,
        localeIdentifier: String,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        request: BatchSpeechTranscriptionRequest
    ) -> BatchRecognizedTranscriptSegment {
        let absoluteStart = request.recordingStartTime.addingTimeInterval(
            request.sessionOffsetSeconds + startSeconds
        )
        let absoluteEnd = request.recordingStartTime.addingTimeInterval(
            request.sessionOffsetSeconds + endSeconds
        )
        return BatchRecognizedTranscriptSegment(
            segment: TranscriptSegment(
                sessionId: request.recordingSessionId,
                startTime: absoluteStart,
                endTime: absoluteEnd,
                text: text,
                isConfirmed: true,
                speakerLabel: request.source.speakerLabel
            ),
            localeIdentifier: localeIdentifier
        )
    }

    private static func finiteSeconds(_ seconds: TimeInterval) -> TimeInterval {
        seconds.isFinite ? seconds : 0
    }

    private static func installAssetsIfNeeded(for transcriber: SpeechTranscriber) async throws {
        let status = await AssetInventory.status(forModules: [transcriber])
        if status < .installed,
           let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    private static func extractRange(from sourceURL: URL, startFrame: Int64, frameCount: Int64) throws -> URL {
        let source = try AVAudioFile(forReading: sourceURL)
        guard startFrame < source.length else {
            throw BatchSpeechTranscriberError.invalidAudioRange
        }
        let availableFrames = min(frameCount, source.length - startFrame)
        guard availableFrames > 0 else {
            throw BatchSpeechTranscriberError.invalidAudioRange
        }

        let destinationURL = FileManager.default.temporaryDirectory
            .appending(path: "dahlia-batch-\(UUID.v7().uuidString).caf")
        source.framePosition = startFrame

        do {
            let destination = try AVAudioFile(
                forWriting: destinationURL,
                settings: source.processingFormat.settings,
                commonFormat: source.processingFormat.commonFormat,
                interleaved: source.processingFormat.isInterleaved
            )
            let capacity: AVAudioFrameCount = 16384
            guard let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: capacity) else {
                throw BatchSpeechTranscriberError.audioFormatUnavailable
            }

            var remaining = availableFrames
            while remaining > 0 {
                let requested = AVAudioFrameCount(min(Int64(capacity), remaining))
                try source.read(into: buffer, frameCount: requested)
                guard buffer.frameLength > 0 else {
                    throw BatchSpeechTranscriberError.invalidAudioRange
                }
                try destination.write(from: buffer)
                remaining -= Int64(buffer.frameLength)
            }
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }

        return destinationURL
    }
}

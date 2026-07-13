@preconcurrency import AVFoundation
import CoreAudio
import CoreMedia
import os

actor MicrophoneRecognitionTestSession {
    typealias EventHandler = @MainActor @Sendable (MicrophoneRecognitionTestEvent) -> Void

    private static let logger = Logger(subsystem: "com.dahlia", category: "MicrophoneRecognitionTest")

    private var manager: AudioCaptureManager?
    private var service: SpeechTranscriberService?
    private var bridge: AudioBufferBridge?
    private var eventHandler: EventHandler?

    func start(
        deviceID: AudioDeviceID?,
        locale: Locale,
        onEvent: @escaping EventHandler
    ) async throws -> AudioCaptureStartInfo {
        guard manager == nil else {
            throw AudioCaptureError.microphoneDeviceUnavailable
        }
        guard await AudioCaptureManager.requestMicrophonePermission() else {
            throw AudioCaptureError.microphonePermissionDenied
        }

        let (service, bridge, targetFormat) = try await prepareRecognition(locale: locale, onEvent: onEvent)
        let manager = makeManager(targetFormat: targetFormat, bridge: bridge, onEvent: onEvent)
        manager.onUnexpectedStop = { [weak self] in
            Task {
                await self?.captureStoppedUnexpectedly()
            }
        }

        do {
            let startInfo = try manager.startCapture(
                targetFormat: targetFormat,
                selectedDeviceID: deviceID
            )
            self.manager = manager
            self.service = service
            self.bridge = bridge
            eventHandler = onEvent
            return startInfo
        } catch {
            bridge.finish()
            await service.cancel()
            throw error
        }
    }

    private func prepareRecognition(
        locale: Locale,
        onEvent: @escaping EventHandler
    ) async throws -> (SpeechTranscriberService, AudioBufferBridge, AVAudioFormat) {
        let service = SpeechTranscriberService(locale: locale, speakerLabel: RecordingAudioSource.microphone.speakerLabel)
        try await service.prepare()
        guard let targetFormat = await service.targetAudioFormat() else {
            throw AudioCaptureError.converterCreationFailed
        }

        let bridge = try AudioBufferBridge(sourceFormat: targetFormat, analyzerFormat: targetFormat)
        try await service.startStreaming(
            bridge: bridge,
            recordingStartTime: .now,
            recordingSessionId: .v7()
        ) { event in
            Self.forward(event, to: onEvent)
        }
        return (service, bridge, targetFormat)
    }

    private func makeManager(
        targetFormat: AVAudioFormat,
        bridge: AudioBufferBridge,
        onEvent: @escaping EventHandler
    ) -> AudioCaptureManager {
        let manager = AudioCaptureManager()
        let frameOffset = OSAllocatedUnfairLock(initialState: Int64(0))
        let bufferCount = OSAllocatedUnfairLock(initialState: 0)
        let timescale = CMTimeScale(targetFormat.sampleRate.rounded())
        manager.onAudioBuffer = { buffer in
            let frameLength = Int64(buffer.frameLength)
            let startFrame = frameOffset.withLock { offset in
                let startFrame = offset
                offset += frameLength
                return startFrame
            }
            let count = bufferCount.withLock { count in
                count += 1
                return count
            }
            let chunk = CapturedAudioChunk(
                source: .microphone,
                buffer: buffer,
                sessionRelativeStartTime: CMTime(value: startFrame, timescale: timescale)
            )
            if !bridge.append(chunk) {
                Self.logger.error("Speech analyzer rejected microphone buffer \(count)")
            }
            let level = AudioLevelCalculator.normalizedLevel(in: buffer)
            Task { @MainActor in
                onEvent(.inputLevel(level, bufferCount: count))
            }
        }
        manager.onInputLevels = { levels in
            Task { @MainActor in
                onEvent(.inputChannelLevels(levels))
            }
        }
        return manager
    }

    @MainActor
    private static func forward(_ event: TranscriptionEvent, to onEvent: EventHandler) {
        switch event {
        case let .preview(segment):
            onEvent(.transcript(segment.text, isFinal: false))
        case let .finalized(segment):
            onEvent(.transcript(segment.text, isFinal: true))
        case let .failure(_, _, _, message):
            onEvent(.failure(message))
        case .clearPreview, .translation:
            break
        }
    }

    func stop() async {
        manager?.stopCapture()
        bridge?.finish()
        do {
            try await service?.stopStreaming()
        } catch {
            await eventHandler?(.failure(error.localizedDescription))
        }
        await service?.reset()
        clear()
    }

    private func captureStoppedUnexpectedly() async {
        await eventHandler?(.captureStopped)
    }

    private func clear() {
        manager = nil
        service = nil
        bridge = nil
        eventHandler = nil
    }
}

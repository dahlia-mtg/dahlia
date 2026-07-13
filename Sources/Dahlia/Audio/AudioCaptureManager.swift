import AudioToolbox
@preconcurrency import AVFoundation
import CoreAudio
import os

enum AudioCaptureError: Error, LocalizedError {
    case invalidHardwareFormat
    case converterCreationFailed
    case microphonePermissionDenied
    case microphoneDeviceUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidHardwareFormat:
            L10n.invalidHardwareFormat
        case .converterCreationFailed:
            L10n.converterCreationFailed
        case .microphonePermissionDenied:
            L10n.microphoneDenied
        case .microphoneDeviceUnavailable:
            L10n.microphoneUnavailable
        }
    }
}

/// AVAudioEngine を使用してマイクからオーディオをキャプチャし、
/// 指定されたターゲットフォーマットに変換して AVAudioPCMBuffer で出力する。
final class AudioCaptureManager: NSObject {
    private static let logger = Logger(subsystem: "com.dahlia", category: "MicrophoneCapture")

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var captureFormat: AVAudioFormat?
    private var didReportUnexpectedStop = false
    private var hasInputTap = false
    private var didLogFirstBuffer = false
    private var didLogConversionFailure = false

    /// 変換済み AVAudioPCMBuffer のコールバック（オーディオスレッドから呼ばれる）
    var onAudioBuffer: ((AVAudioPCMBuffer) -> Void)?
    var onInputLevels: (([Double]) -> Void)?
    var onUnexpectedStop: (() -> Void)?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(engineConfigurationDidChange),
            name: .AVAudioEngineConfigurationChange,
            object: engine
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// マイクのパーミッションを確認・要求する。
    static func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// マイクキャプチャを開始する。
    @discardableResult
    func startCapture(
        targetFormat: AVAudioFormat,
        selectedDeviceID: AudioDeviceID? = nil,
        bufferSize: AVAudioFrameCount = 4096,
        prefersVoiceProcessing: Bool = true
    ) throws -> AudioCaptureStartInfo {
        didReportUnexpectedStop = false
        var lastError: (any Error)?
        let selectedDeviceDescription = selectedDeviceID.map(String.init) ?? "system-default"

        Self.logger.info(
            "Starting microphone capture; device=\(selectedDeviceDescription, privacy: .public), voiceProcessing=\(prefersVoiceProcessing)"
        )

        for enablesVoiceProcessing in Self.voiceProcessingAttemptOrder(prefersVoiceProcessing: prefersVoiceProcessing) {
            do {
                return try startCaptureAttempt(
                    targetFormat: targetFormat,
                    selectedDeviceID: selectedDeviceID,
                    bufferSize: bufferSize,
                    enablesVoiceProcessing: enablesVoiceProcessing
                )
            } catch {
                lastError = error
                Self.logger.error(
                    "Microphone capture attempt failed; voiceProcessing=\(enablesVoiceProcessing), error=\(error.localizedDescription, privacy: .public)"
                )
                resetCaptureAttempt()
            }
        }

        throw lastError ?? AudioCaptureError.invalidHardwareFormat
    }

    private func startCaptureAttempt(
        targetFormat: AVAudioFormat,
        selectedDeviceID: AudioDeviceID?,
        bufferSize: AVAudioFrameCount,
        enablesVoiceProcessing: Bool
    ) throws -> AudioCaptureStartInfo {
        let inputNode = engine.inputNode
        if inputNode.isVoiceProcessingEnabled {
            try inputNode.setVoiceProcessingEnabled(false)
        }

        let defaultDeviceID = Self.defaultInputDeviceID()
        if let selectedDeviceID,
           Self.shouldConfigureInputDevice(
               selectedDeviceID,
               defaultDeviceID: defaultDeviceID,
               enablesVoiceProcessing: enablesVoiceProcessing
           ) {
            try Self.configureInputDevice(selectedDeviceID, for: inputNode)
        }

        let voiceProcessingFormat = try configureVoiceProcessing(
            enablesVoiceProcessing,
            inputNode: inputNode
        )

        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw AudioCaptureError.invalidHardwareFormat
        }

        let sourceFormat = Self.captureSourceFormat(
            hardwareFormat: hardwareFormat,
            voiceProcessingFormat: voiceProcessingFormat,
            enablesVoiceProcessing: enablesVoiceProcessing
        )
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw AudioCaptureError.invalidHardwareFormat
        }

        Self.logger.info("Microphone hardware format: \(hardwareFormat.diagnosticDescription, privacy: .public)")
        Self.logger.info("Microphone source format: \(sourceFormat.diagnosticDescription, privacy: .public)")
        Self.logger.info("Microphone target format: \(targetFormat.diagnosticDescription, privacy: .public)")

        guard let audioConverter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioCaptureError.converterCreationFailed
        }
        audioConverter.sampleRateConverterQuality = AVAudioQuality.medium.rawValue
        converter = audioConverter
        captureFormat = targetFormat

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: sourceFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        hasInputTap = true

        engine.prepare()
        try engine.start()
        Self.logger.info("Microphone engine started; voiceProcessing=\(enablesVoiceProcessing)")
        Self.logger.info(
            "Microphone modes; preferred=\(AVCaptureDevice.preferredMicrophoneMode.rawValue), active=\(AVCaptureDevice.activeMicrophoneMode.rawValue)"
        )

        return AudioCaptureStartInfo(
            hardwareFormatDescription: hardwareFormat.diagnosticDescription,
            sourceFormatDescription: sourceFormat.diagnosticDescription,
            targetFormatDescription: targetFormat.diagnosticDescription
        )
    }

    private func configureVoiceProcessing(
        _ enabled: Bool,
        inputNode: AVAudioInputNode
    ) throws -> AVAudioFormat? {
        guard enabled else { return nil }
        let outputNode = engine.outputNode
        try inputNode.setVoiceProcessingEnabled(true)
        // Let the macOS microphone mode be the single source of truth. Standard
        // mode stays unprocessed, while Voice Isolation and Wide Spectrum take
        // priority over this bypass inside the system Voice Processing unit.
        inputNode.isVoiceProcessingBypassed = true
        inputNode.isVoiceProcessingInputMuted = false
        inputNode.isVoiceProcessingAGCEnabled = true
        inputNode.voiceProcessingOtherAudioDuckingConfiguration = .init(
            enableAdvancedDucking: false,
            duckingLevel: .min
        )
        let voiceProcessingFormat = outputNode.inputFormat(forBus: 0)
        guard voiceProcessingFormat.sampleRate > 0,
              voiceProcessingFormat.channelCount > 0 else {
            throw AudioCaptureError.invalidHardwareFormat
        }

        // Voice Processing requires the input node's output format and output
        // node's input format to match. Use the output device's accepted format
        // for both sides instead of the built-in microphone's multi-channel
        // hardware format.
        engine.connect(engine.mainMixerNode, to: outputNode, format: voiceProcessingFormat)
        return voiceProcessingFormat
    }

    /// キャプチャを停止する。
    func stopCapture() {
        resetCaptureAttempt()
    }

    @objc private func engineConfigurationDidChange() {
        guard captureFormat != nil,
              !engine.isRunning,
              !didReportUnexpectedStop else { return }
        didReportUnexpectedStop = true
        Self.logger.error("Microphone engine stopped after a configuration change")
        onUnexpectedStop?()
    }

    private func processAudioBuffer(_ inputBuffer: AVAudioPCMBuffer) {
        guard let targetFormat = captureFormat else { return }
        onInputLevels?(AudioLevelCalculator.normalizedLevels(in: inputBuffer))
        if !didLogFirstBuffer {
            didLogFirstBuffer = true
            let formatDescription = inputBuffer.format.diagnosticDescription
            Self.logger.info(
                "Received first microphone buffer; frames=\(inputBuffer.frameLength), format=\(formatDescription, privacy: .public)"
            )
        }

        updateConverterIfNeeded(from: inputBuffer.format, to: targetFormat)

        guard let converter,
              let outputBuffer = AudioConverter.convert(inputBuffer, to: targetFormat, using: converter) else {
            if !didLogConversionFailure {
                didLogConversionFailure = true
                let inputDescription = inputBuffer.format.diagnosticDescription
                let targetDescription = targetFormat.diagnosticDescription
                Self.logger.error(
                    "Failed to convert microphone buffer; input=\(inputDescription, privacy: .public), target=\(targetDescription, privacy: .public)"
                )
            }
            return
        }
        onAudioBuffer?(outputBuffer)
    }

    private func updateConverterIfNeeded(from inputFormat: AVAudioFormat, to targetFormat: AVAudioFormat) {
        guard converter?.inputFormat != inputFormat else { return }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        converter?.sampleRateConverterQuality = AVAudioQuality.medium.rawValue
        Self.logger.notice("Recreated microphone converter for input format: \(inputFormat.diagnosticDescription, privacy: .public)")
    }

    private static func configureInputDevice(_ deviceID: AudioDeviceID, for inputNode: AVAudioInputNode) throws {
        guard let audioUnit = inputNode.audioUnit else {
            throw AudioCaptureError.microphoneDeviceUnavailable
        }

        var selectedDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &selectedDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard status == noErr else {
            throw AudioCaptureError.microphoneDeviceUnavailable
        }
    }

    private func resetCaptureAttempt() {
        captureFormat = nil
        converter = nil
        if hasInputTap {
            engine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        engine.stop()
        if engine.inputNode.isVoiceProcessingEnabled {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
        didLogFirstBuffer = false
        didLogConversionFailure = false
    }

}

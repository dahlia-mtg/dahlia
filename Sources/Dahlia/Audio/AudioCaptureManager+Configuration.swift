@preconcurrency import AVFoundation
import CoreAudio

extension AudioCaptureManager {
    static func voiceProcessingAttemptOrder(prefersVoiceProcessing: Bool) -> [Bool] {
        prefersVoiceProcessing ? [true, false] : [false]
    }

    static func shouldConfigureInputDevice(
        _ selectedDeviceID: AudioDeviceID,
        defaultDeviceID: AudioDeviceID?,
        enablesVoiceProcessing: Bool
    ) -> Bool {
        !enablesVoiceProcessing || selectedDeviceID != defaultDeviceID
    }

    static func captureSourceFormat(
        hardwareFormat: AVAudioFormat,
        voiceProcessingFormat: AVAudioFormat?,
        enablesVoiceProcessing: Bool
    ) -> AVAudioFormat {
        if enablesVoiceProcessing, let voiceProcessingFormat {
            voiceProcessingFormat
        } else {
            hardwareFormat
        }
    }
}

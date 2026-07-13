import AVFoundation
import CoreAudio
@testable import Dahlia

#if canImport(Testing)
    import Testing

    struct AudioCaptureManagerTests {
        @Test
        func voiceProcessingFallsBackToRawInput() {
            #expect(AudioCaptureManager.voiceProcessingAttemptOrder(prefersVoiceProcessing: true) == [true, false])
        }

        @Test
        func rawInputDoesNotAttemptVoiceProcessing() {
            #expect(AudioCaptureManager.voiceProcessingAttemptOrder(prefersVoiceProcessing: false) == [false])
        }

        @Test
        func defaultDeviceIsNotExplicitlyConfiguredForVoiceProcessing() {
            let deviceID = AudioDeviceID(42)

            #expect(!AudioCaptureManager.shouldConfigureInputDevice(
                deviceID,
                defaultDeviceID: deviceID,
                enablesVoiceProcessing: true
            ))
        }

        @Test
        func defaultDeviceIsExplicitlyConfiguredForRawInput() {
            let deviceID = AudioDeviceID(42)

            #expect(AudioCaptureManager.shouldConfigureInputDevice(
                deviceID,
                defaultDeviceID: deviceID,
                enablesVoiceProcessing: false
            ))
        }

        @Test
        func nondefaultDeviceIsExplicitlyConfiguredForVoiceProcessing() {
            #expect(AudioCaptureManager.shouldConfigureInputDevice(
                AudioDeviceID(42),
                defaultDeviceID: AudioDeviceID(7),
                enablesVoiceProcessing: true
            ))
        }

        @Test
        func voiceProcessingUsesNegotiatedOutputFormat() throws {
            let hardwareFormat = try #require(AVAudioFormat(
                standardFormatWithSampleRate: 48000,
                channels: 2
            ))
            let voiceProcessingFormat = try #require(AVAudioFormat(
                standardFormatWithSampleRate: 48000,
                channels: 1
            ))

            let result = AudioCaptureManager.captureSourceFormat(
                hardwareFormat: hardwareFormat,
                voiceProcessingFormat: voiceProcessingFormat,
                enablesVoiceProcessing: true
            )

            #expect(result === voiceProcessingFormat)
        }

        @Test
        func rawInputUsesHardwareFormat() throws {
            let hardwareFormat = try #require(AVAudioFormat(
                standardFormatWithSampleRate: 48000,
                channels: 2
            ))
            let voiceProcessingFormat = try #require(AVAudioFormat(
                standardFormatWithSampleRate: 48000,
                channels: 1
            ))

            let result = AudioCaptureManager.captureSourceFormat(
                hardwareFormat: hardwareFormat,
                voiceProcessingFormat: voiceProcessingFormat,
                enablesVoiceProcessing: false
            )

            #expect(result === hardwareFormat)
        }
    }
#endif

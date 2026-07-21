import Foundation

struct BatchRecognizedTranscriptSegment: Equatable {
    var segment: TranscriptSegment
    let localeIdentifier: String
}

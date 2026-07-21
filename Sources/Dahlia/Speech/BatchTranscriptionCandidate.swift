import Foundation

struct BatchTranscriptionCandidate: Equatable {
    let localeIdentifier: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let text: String
    let confidence: Double
    let languageProbability: Double
}

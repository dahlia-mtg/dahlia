import Foundation

struct ResolvedBatchTranscriptionCandidate: Equatable {
    let localeIdentifier: String
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval
    let text: String
}

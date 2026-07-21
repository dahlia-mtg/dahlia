import Foundation

struct BatchTranscriptionConfirmation: Identifiable, Equatable {
    let sessionId: UUID
    let meetingId: UUID
    let suggestedLanguageSelection: BatchTranscriptionLanguageSelection
    let retainAudioAfterBatch: Bool

    var id: UUID { sessionId }
}

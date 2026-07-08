import Foundation
import GRDB

/// ひとつづきの録音セッションを表す GRDB レコード。
struct RecordingSessionRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "recording_sessions"

    var id: UUID
    var meetingId: UUID
    var startedAt: Date
    var endedAt: Date?
    var duration: TimeInterval?
    var offsetSeconds: TimeInterval
    var createdAt: Date
    var updatedAt: Date
}

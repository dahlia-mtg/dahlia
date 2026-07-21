import Foundation
import GRDB
@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    struct BatchSecondaryLocaleMigrationTests {
        private struct MigrationFixture {
            let now: Date
            let vault: VaultRecord
            let meeting: MeetingRecord
            let sessionId: UUID
            let segmentId: UUID
        }

        @Test
        func existingV22SessionsGainNullableSecondaryLocaleWithoutDataLoss() throws {
            let databaseURL = URL.temporaryDirectory
                .appending(path: UUID.v7().uuidString)
                .appendingPathExtension("sqlite")
            defer { try? FileManager.default.removeItem(at: databaseURL) }
            let fixture = makeFixture()
            let legacyQueue = try DatabaseQueue(path: databaseURL.path)
            try AppDatabaseManager.migrator.migrate(legacyQueue, upTo: "v22_transcriptPagingIndex")
            try legacyQueue.write { db in
                try insertV22Fixture(fixture, db: db)
                #expect(try AppDatabaseManager.migrator.completedMigrations(db).last == "v22_transcriptPagingIndex")
            }

            let migrated = try AppDatabaseManager(path: databaseURL.path)
            let result = try migrated.dbQueue.read { db in
                try migratedValues(fixture: fixture, db: db)
            }
            let session = try #require(result.session)
            #expect(session.meetingId == fixture.meeting.id)
            #expect(session.startedAt == fixture.now)
            #expect(session.duration == 60)
            #expect(session.transcriptionMode == .batch)
            #expect(session.retainAudioAfterBatch)
            #expect(session.batchAttemptCount == 2)
            #expect(session.batchSecondaryLocaleIdentifier == nil)
            #expect(result.localeIdentifier == "ja_JP")
            #expect(result.foreignKeyViolations.isEmpty)
        }

        private func makeFixture() -> MigrationFixture {
            let now = Date(timeIntervalSince1970: 1_776_384_000)
            let vault = VaultRecord(
                id: .v7(),
                path: "/tmp/migration-vault",
                name: "Preserved vault",
                createdAt: now,
                lastOpenedAt: now
            )
            let meeting = MeetingRecord(
                id: .v7(),
                vaultId: vault.id,
                projectId: nil,
                name: "Preserved meeting",
                description: "Preserved description",
                status: .ready,
                duration: 60,
                createdAt: now,
                updatedAt: now
            )
            return MigrationFixture(
                now: now,
                vault: vault,
                meeting: meeting,
                sessionId: .v7(),
                segmentId: .v7()
            )
        }

        private nonisolated func insertV22Fixture(_ fixture: MigrationFixture, db: Database) throws {
            try fixture.vault.insert(db)
            try fixture.meeting.insert(db)
            try insertSession(fixture: fixture, db: db)
            try insertAudio(fixture: fixture, db: db)
        }

        private nonisolated func insertSession(fixture: MigrationFixture, db: Database) throws {
            try db.execute(
                sql: """
                INSERT INTO recording_sessions (
                    id, meetingId, startedAt, endedAt, duration, offsetSeconds,
                    createdAt, updatedAt, transcriptionMode, retainAudioAfterBatch, batchAttemptCount
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    fixture.sessionId, fixture.meeting.id, fixture.now,
                    fixture.now.addingTimeInterval(60), 60, 0, fixture.now, fixture.now,
                    TranscriptionMode.batch.rawValue, true, 2,
                ]
            )
        }

        private nonisolated func insertAudio(fixture: MigrationFixture, db: Database) throws {
            try RecordingAudioSegmentRecord(
                id: fixture.segmentId,
                recordingSessionId: fixture.sessionId,
                source: .microphone,
                segmentIndex: 0,
                generationId: .v7(),
                state: .ready,
                partialRelativePath: "migration.partial.caf",
                finalRelativePath: "migration.caf",
                sampleRate: 16000,
                channelCount: 1,
                sealedFrameCount: 160,
                sessionStartOffsetSeconds: 0,
                sessionEndOffsetSeconds: 0.01,
                byteCount: 320,
                sha256: Data(repeating: 1, count: 32),
                finalizationStartedAt: fixture.now,
                integrityVerifiedAt: fixture.now,
                finalizedAt: fixture.now,
                purgeRequestedAt: nil,
                purgedAt: nil,
                failureStage: nil,
                failureCode: nil,
                createdAt: fixture.now,
                updatedAt: fixture.now
            ).insert(db)
            try RecordingAudioSegmentRangeRecord(
                id: .v7(),
                audioSegmentId: fixture.segmentId,
                startFrame: 0,
                frameCount: 160,
                sessionOffsetSeconds: 0,
                localeIdentifier: "ja_JP",
                createdAt: fixture.now,
                updatedAt: fixture.now
            ).insert(db)
        }

        private nonisolated func migratedValues(
            fixture: MigrationFixture,
            db: Database
        ) throws -> (
            session: RecordingSessionRecord?,
            localeIdentifier: String?,
            foreignKeyViolations: [Row]
        ) {
            try (
                RecordingSessionRecord.fetchOne(db, key: fixture.sessionId),
                String.fetchOne(
                    db,
                    sql: """
                    SELECT recording_audio_segment_ranges.localeIdentifier
                    FROM recording_audio_segment_ranges
                    JOIN recording_audio_segments
                      ON recording_audio_segments.id = recording_audio_segment_ranges.audioSegmentId
                    JOIN recording_sessions
                      ON recording_sessions.id = recording_audio_segments.recordingSessionId
                    JOIN meetings ON meetings.id = recording_sessions.meetingId
                    WHERE meetings.id = ? AND recording_sessions.id = ?
                    """,
                    arguments: [fixture.meeting.id, fixture.sessionId]
                ),
                Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            )
        }
    }
#endif

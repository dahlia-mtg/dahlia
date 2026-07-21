@preconcurrency import AVFoundation
import Foundation
import GRDB
@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    struct BatchTranscriptionConfirmationServiceTests {
        @Test(arguments: [
            (retainsAudio: true, policy: RecordingAudioRetentionPolicy.keepInApp),
            (retainsAudio: false, policy: RecordingAudioRetentionPolicy.deleteAfterTranscription),
        ])
        func confirmsSegmentedRangesAndPersistsRetentionPolicy(
            retainsAudio: Bool,
            policy: RecordingAudioRetentionPolicy
        ) async throws {
            let fixture = try BatchAudioTestFixture(
                name: "SegmentedConfirmation-\(retainsAudio)",
                endedAt: Date(timeIntervalSince1970: 1_776_384_060),
                duration: 60
            )
            defer { fixture.removeFiles() }
            let recorder = try BatchAudioRecordingSession(
                dbQueue: fixture.database.dbQueue,
                managedRootURL: fixture.managedRootURL,
                meetingId: fixture.meeting.id,
                recordingSessionId: fixture.session.id,
                recordingStartTime: fixture.now,
                sampleRate: 16000,
                configuration: RecordingAudioStore.Configuration(
                    targetSegmentDuration: .seconds(60),
                    maximumFinalizingSegmentCountPerSource: 2,
                    maximumActiveSegmentDuration: .seconds(600),
                    maximumActiveSegmentByteCount: 64 * 1_024 * 1_024,
                    minimumAvailableCapacity: 0,
                    capacityCheckInterval: .seconds(5)
                )
            )
            let writer = try await recorder.beginRange(
                source: .microphone,
                locale: Locale(identifier: "ja_JP"),
                at: fixture.now
            )
            let buffer = try #require(AVAudioPCMBuffer(
                pcmFormat: recorder.targetFormat,
                frameCapacity: 160
            ))
            buffer.frameLength = 160
            writer.appendBuffer(buffer)
            try await recorder.finish()

            let confirmation = try await BatchTranscriptionConfirmationService.confirm(
                sessionId: fixture.session.id,
                languageSelection: BatchTranscriptionLanguageSelection(primaryLocaleIdentifier: "en_US"),
                retainAudioAfterBatch: retainsAudio,
                dbQueue: fixture.database.dbQueue
            )
            let result = try await fixture.database.dbQueue.read { db in
                try (
                    RecordingSessionRecord.fetchOne(db, key: fixture.session.id),
                    RecordingAudioSegmentRangeRecord.fetchAll(db)
                )
            }
            #expect(confirmation.sessionIds == [fixture.session.id])
            #expect(result.0?.retainAudioAfterBatch == retainsAudio)
            #expect(result.0?.audioRetentionPolicy == policy)
            #expect(result.0?.batchLastAttemptAt != nil)
            #expect(result.0?.batchSecondaryLocaleIdentifier == nil)
            #expect(result.1.map(\.localeIdentifier) == ["en_US"])
        }

        @Test
        func persistsSecondaryLocaleAndUsesPrimaryForAllRanges() async throws {
            let fixture = try BatchAudioTestFixture(
                name: "MixedLanguageConfirmation",
                endedAt: Date(timeIntervalSince1970: 1_776_384_060),
                duration: 60
            )
            defer { fixture.removeFiles() }
            let recorder = try BatchAudioRecordingSession(
                dbQueue: fixture.database.dbQueue,
                managedRootURL: fixture.managedRootURL,
                meetingId: fixture.meeting.id,
                recordingSessionId: fixture.session.id,
                recordingStartTime: fixture.now,
                sampleRate: 16000
            )
            let writer = try await recorder.beginRange(
                source: .microphone,
                locale: Locale(identifier: "fr_FR"),
                at: fixture.now
            )
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: recorder.targetFormat, frameCapacity: 160))
            buffer.frameLength = 160
            writer.appendBuffer(buffer)
            try await recorder.finish()

            _ = try await BatchTranscriptionConfirmationService.confirm(
                sessionId: fixture.session.id,
                languageSelection: BatchTranscriptionLanguageSelection(
                    primaryLocaleIdentifier: "ja_JP",
                    secondaryLocaleIdentifier: "en_US"
                ),
                retainAudioAfterBatch: true,
                dbQueue: fixture.database.dbQueue
            )

            let result = try await fixture.database.dbQueue.read { db in
                try (
                    RecordingSessionRecord.fetchOne(db, key: fixture.session.id),
                    RecordingAudioSegmentRangeRecord.fetchAll(db)
                )
            }
            #expect(result.0?.batchSecondaryLocaleIdentifier == "en_US")
            #expect(result.1.allSatisfy { $0.localeIdentifier == "ja_JP" })
        }

        @Test
        func rejectsRegionalVariantsOfTheSameLanguage() async throws {
            let fixture = try BatchAudioTestFixture(name: "InvalidMixedLanguages")
            defer { fixture.removeFiles() }

            await #expect(throws: CocoaError.self) {
                try await BatchTranscriptionConfirmationService.confirm(
                    sessionId: fixture.session.id,
                    languageSelection: BatchTranscriptionLanguageSelection(
                        primaryLocaleIdentifier: "en_US",
                        secondaryLocaleIdentifier: "en_GB"
                    ),
                    retainAudioAfterBatch: false,
                    dbQueue: fixture.database.dbQueue
                )
            }
        }

        @Test
        func appliesMixedLanguagesToEveryUnconfirmedSessionInTheMeeting() async throws {
            let fixture = try BatchAudioTestFixture(
                name: "MultipleMixedLanguageSessions",
                endedAt: Date(timeIntervalSince1970: 1_776_384_060),
                duration: 60
            )
            defer { fixture.removeFiles() }
            let secondSession = RecordingSessionRecord(
                id: .v7(),
                meetingId: fixture.meeting.id,
                startedAt: fixture.now.addingTimeInterval(60),
                endedAt: fixture.now.addingTimeInterval(120),
                duration: 60,
                offsetSeconds: 60,
                createdAt: fixture.now,
                updatedAt: fixture.now,
                transcriptionMode: .batch
            )
            try await fixture.database.dbQueue.write { db in
                try secondSession.insert(db)
                try insertAudioRanges(sessionId: fixture.session.id, locales: ["fr_FR"], now: fixture.now, db: db)
                try insertAudioRanges(sessionId: secondSession.id, locales: ["de_DE", "it_IT"], now: fixture.now, db: db)
            }

            let result = try await BatchTranscriptionConfirmationService.confirm(
                sessionId: fixture.session.id,
                languageSelection: BatchTranscriptionLanguageSelection(
                    primaryLocaleIdentifier: "ja_JP",
                    secondaryLocaleIdentifier: "en_US"
                ),
                retainAudioAfterBatch: true,
                dbQueue: fixture.database.dbQueue
            )

            let persisted = try await fixture.database.dbQueue.read { db in
                try (
                    RecordingSessionRecord.order(Column("startedAt").asc).fetchAll(db),
                    RecordingAudioSegmentRangeRecord.fetchAll(db)
                )
            }
            #expect(result.sessionIds == [fixture.session.id, secondSession.id])
            #expect(persisted.0.allSatisfy { $0.batchSecondaryLocaleIdentifier == "en_US" })
            #expect(persisted.1.allSatisfy { $0.localeIdentifier == "ja_JP" })
        }

        @Test
        func singleLanguagePreservesExplicitRangeLocalesAndClearsSecondaryLanguage() async throws {
            let fixture = try BatchAudioTestFixture(
                name: "PreservedExplicitLocales",
                endedAt: Date(timeIntervalSince1970: 1_776_384_060),
                duration: 60
            )
            defer { fixture.removeFiles() }
            try await fixture.database.dbQueue.write { db in
                try insertAudioRanges(
                    sessionId: fixture.session.id,
                    locales: ["ja_JP", "en_US"],
                    now: fixture.now,
                    db: db
                )
                try db.execute(
                    sql: "UPDATE recording_sessions SET batchSecondaryLocaleIdentifier = ? WHERE id = ?",
                    arguments: ["fr_FR", fixture.session.id]
                )
            }

            _ = try await BatchTranscriptionConfirmationService.confirm(
                sessionId: fixture.session.id,
                languageSelection: BatchTranscriptionLanguageSelection(primaryLocaleIdentifier: "de_DE"),
                retainAudioAfterBatch: false,
                dbQueue: fixture.database.dbQueue
            )

            let persisted = try await fixture.database.dbQueue.read { db in
                try (
                    RecordingSessionRecord.fetchOne(db, key: fixture.session.id),
                    RecordingAudioSegmentRangeRecord.order(Column("startFrame").asc).fetchAll(db)
                )
            }
            #expect(persisted.0?.batchSecondaryLocaleIdentifier == nil)
            #expect(persisted.1.map(\.localeIdentifier) == ["ja_JP", "en_US"])
        }

        @Test
        func rollsBackEverySessionWhenOneSessionHasNoAudioRange() async throws {
            let fixture = try BatchAudioTestFixture(
                name: "ConfirmationRollback",
                endedAt: Date(timeIntervalSince1970: 1_776_384_060),
                duration: 60
            )
            defer { fixture.removeFiles() }
            let secondSession = RecordingSessionRecord(
                id: .v7(),
                meetingId: fixture.meeting.id,
                startedAt: fixture.now.addingTimeInterval(60),
                endedAt: fixture.now.addingTimeInterval(120),
                duration: 60,
                offsetSeconds: 60,
                createdAt: fixture.now,
                updatedAt: fixture.now,
                transcriptionMode: .batch
            )
            try await fixture.database.dbQueue.write { db in
                try secondSession.insert(db)
                try insertAudioRanges(sessionId: fixture.session.id, locales: ["fr_FR"], now: fixture.now, db: db)
                try insertAudioRanges(sessionId: secondSession.id, locales: [], now: fixture.now, db: db)
            }

            await #expect(throws: CocoaError.self) {
                try await BatchTranscriptionConfirmationService.confirm(
                    sessionId: fixture.session.id,
                    languageSelection: BatchTranscriptionLanguageSelection(
                        primaryLocaleIdentifier: "ja_JP",
                        secondaryLocaleIdentifier: "en_US"
                    ),
                    retainAudioAfterBatch: true,
                    dbQueue: fixture.database.dbQueue
                )
            }

            let persisted = try await fixture.database.dbQueue.read { db in
                try (
                    RecordingSessionRecord.order(Column("startedAt").asc).fetchAll(db),
                    RecordingAudioSegmentRangeRecord.fetchAll(db)
                )
            }
            #expect(persisted.0.allSatisfy {
                $0.batchSecondaryLocaleIdentifier == nil && $0.batchLastAttemptAt == nil
            })
            #expect(persisted.1.map(\.localeIdentifier) == ["fr_FR"])
        }

        private nonisolated func insertAudioRanges(
            sessionId: UUID,
            locales: [String],
            now: Date,
            db: Database
        ) throws {
            let segmentId = UUID.v7()
            let segment = RecordingAudioSegmentRecord(
                id: segmentId,
                recordingSessionId: sessionId,
                source: .microphone,
                segmentIndex: 0,
                generationId: .v7(),
                state: .ready,
                partialRelativePath: "\(segmentId.uuidString).partial.caf",
                finalRelativePath: "\(segmentId.uuidString).caf",
                sampleRate: 16000,
                channelCount: 1,
                sealedFrameCount: Int64(max(1, locales.count) * 160),
                sessionStartOffsetSeconds: 0,
                sessionEndOffsetSeconds: Double(max(1, locales.count)) * 0.01,
                byteCount: nil,
                sha256: nil,
                finalizationStartedAt: nil,
                integrityVerifiedAt: nil,
                finalizedAt: nil,
                purgeRequestedAt: nil,
                purgedAt: nil,
                failureStage: nil,
                failureCode: nil,
                createdAt: now,
                updatedAt: now
            )
            try segment.insert(db)
            for (index, localeIdentifier) in locales.enumerated() {
                try RecordingAudioSegmentRangeRecord(
                    id: .v7(),
                    audioSegmentId: segmentId,
                    startFrame: Int64(index * 160),
                    frameCount: 160,
                    sessionOffsetSeconds: Double(index) * 0.01,
                    localeIdentifier: localeIdentifier,
                    createdAt: now,
                    updatedAt: now
                ).insert(db)
            }
        }
    }
#endif

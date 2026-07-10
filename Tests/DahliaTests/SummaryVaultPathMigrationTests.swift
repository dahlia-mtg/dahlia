import Foundation
import GRDB
@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    struct SummaryVaultPathMigrationTests {
        @Test
        func initializesDatabaseWithSummaryVaultRelativePathColumn() throws {
            let database = try AppDatabaseManager(path: ":memory:")

            let columns = try database.dbQueue.read { db in
                try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('summaries')")
            }

            #expect(columns.contains("vaultRelativePath"))
        }

        @Test
        func existingV12DatabaseAddsColumnWithoutDataLoss() throws {
            let databaseURL = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
                .appendingPathExtension("sqlite")
            let meetingId = UUID.v7()
            let createdAt = Date.now
            defer { try? FileManager.default.removeItem(at: databaseURL) }

            let legacyQueue = try DatabaseQueue(path: databaseURL.path)
            try createV12SummaryDatabase(
                in: legacyQueue,
                meetingId: meetingId,
                createdAt: createdAt
            )

            let migrated = try AppDatabaseManager(path: databaseURL.path)
            let result = try migrated.dbQueue.read { db in
                let columns = try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('summaries')")
                let row = try Row.fetchOne(db, sql: "SELECT * FROM summaries WHERE meetingId = ?", arguments: [meetingId])
                return try (columns, #require(row))
            }
            let vaultRelativePath: String? = result.1["vaultRelativePath"]

            #expect(result.0.contains("vaultRelativePath"))
            #expect(result.1["title"] == "Legacy")
            #expect(result.1["summary"] == "Body")
            #expect(result.1["googleFileId"] == "drive-id")
            #expect(vaultRelativePath == nil)
        }

        private func createV12SummaryDatabase(
            in dbQueue: DatabaseQueue,
            meetingId: UUID,
            createdAt: Date
        ) throws {
            try dbQueue.write { db in
                try db.execute(
                    sql: """
                    CREATE TABLE summaries (
                        meetingId BLOB PRIMARY KEY,
                        title TEXT NOT NULL DEFAULT '',
                        summary TEXT NOT NULL,
                        document TEXT,
                        googleFileId TEXT,
                        createdAt DATETIME NOT NULL
                    )
                    """
                )
                try db.create(table: "grdb_migrations") { table in
                    table.column("identifier", .text).primaryKey()
                }
                for migration in Self.v12MigrationIdentifiers {
                    try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)", arguments: [migration])
                }
                try db.execute(
                    sql: """
                    INSERT INTO summaries (meetingId, title, summary, document, googleFileId, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [meetingId, "Legacy", "Body", "{\"title\":\"Legacy\"}", "drive-id", createdAt]
                )
            }
        }

        private static let v12MigrationIdentifiers = [
            "v3_googleDriveFolderSchema",
            "v4_instructionsSchema",
            "v5_summaryGoogleFileId",
            "v6_transcriptSegmentTranslation",
            "v7_normalizeLegacyMeetingStatus",
            "v8_recordingSessions",
            "v9_summaryDocument",
            "v10_batchTranscription",
            "v11_batchAudioStorageLocation",
            "v12_batchTranscriptionDiscard",
        ]
    }
#endif

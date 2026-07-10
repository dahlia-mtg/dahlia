import Foundation
@testable import Dahlia

#if canImport(Testing)
    import Testing

    struct VaultSummaryFileLocatorTests {
        @Test
        func storedPathResolvesWithoutCurrentProjectContext() throws {
            let vaultURL = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let summaryURL = vaultURL.appending(path: "Projects/Alpha/summary.md")
            let meetingId = UUID.v7()
            defer { try? FileManager.default.removeItem(at: vaultURL) }

            try FileManager.default.createDirectory(at: summaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writeSummary(meetingId: meetingId, to: summaryURL)

            let resolved = SummaryService.findSummaryFile(
                storedRelativePath: "Projects/Alpha/summary.md",
                projectURL: nil,
                vaultURL: vaultURL,
                meetingId: meetingId
            )

            #expect(resolved == summaryURL.standardizedFileURL)
        }

        @Test
        func staleStoredPathFallsBackToMovedSummaryFrontmatter() throws {
            let vaultURL = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let movedURL = vaultURL.appending(path: "Archive/Renamed.md")
            let meetingId = UUID.v7()
            defer { try? FileManager.default.removeItem(at: vaultURL) }

            try FileManager.default.createDirectory(at: movedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writeSummary(meetingId: meetingId, to: movedURL)

            let resolved = SummaryService.findSummaryFile(
                storedRelativePath: "Projects/Alpha/Old.md",
                projectURL: vaultURL.appending(path: "Projects/Alpha", directoryHint: .isDirectory),
                vaultURL: vaultURL,
                meetingId: meetingId
            )

            #expect(resolved?.resolvingSymlinksInPath() == movedURL.resolvingSymlinksInPath())
        }

        private func writeSummary(meetingId: UUID, to url: URL) throws {
            try Data(
                """
                ---
                meeting_id: "\(meetingId.uuidString)"
                ---

                Summary
                """.utf8
            ).write(to: url, options: .atomic)
        }
    }
#endif

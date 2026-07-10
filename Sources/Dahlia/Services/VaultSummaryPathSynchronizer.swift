import Foundation
import GRDB

struct VaultSummaryPathSynchronizer {
    let vaultURL: URL
    let dbQueue: DatabaseQueue
    let vaultId: UUID

    func filesForInitialReconciliation() -> [LocatedVaultSummaryFile] {
        guard pathsNeedReconciliation() else { return [] }
        return VaultSummaryFileLocator.locatedSummaryFiles(in: vaultURL)
    }

    func reconcile(_ summaryFiles: [LocatedVaultSummaryFile], in db: Database) throws {
        let pathsByMeetingId = Dictionary(grouping: summaryFiles, by: \LocatedVaultSummaryFile.meetingId)
            .mapValues { $0.map(\.relativePath) }
        let summaries = try SummaryRecord.fetchAll(vaultId: vaultId, in: db)

        for var summary in summaries {
            guard let candidates = pathsByMeetingId[summary.meetingId],
                  let relativePath = candidates.first
            else { continue }
            if let storedRelativePath = summary.vaultRelativePath,
               candidates.contains(storedRelativePath) {
                continue
            }
            summary.vaultRelativePath = relativePath
            try summary.update(db)
        }
    }

    func renamePathsByPrefix(oldPrefix: String, newPrefix: String, in db: Database) throws {
        try SummaryRecord.renameVaultRelativePathsByPrefix(
            oldPrefix: oldPrefix,
            newPrefix: newPrefix,
            vaultId: vaultId,
            in: db
        )
    }

    func syncFiles(at relativePaths: [String]) {
        let summaryFiles = relativePaths.compactMap { relativePath -> LocatedVaultSummaryFile? in
            guard let fileURL = VaultSummaryFileLocator.fileURL(for: relativePath, vaultURL: vaultURL) else { return nil }
            return VaultSummaryFileLocator.locatedSummaryFile(at: fileURL, vaultURL: vaultURL)
        }
        guard !summaryFiles.isEmpty else { return }

        try? dbQueue.write { db in
            for summaryFile in summaryFiles {
                if storedSummaryFileExists(for: summaryFile.meetingId, in: db) {
                    continue
                }
                try SummaryRecord.updateVaultRelativePath(
                    summaryFile.relativePath,
                    meetingId: summaryFile.meetingId,
                    vaultId: vaultId,
                    in: db
                )
            }
        }
    }

    func clearRemovedPaths(_ relativePaths: [String]) {
        guard !relativePaths.isEmpty else { return }
        try? dbQueue.write { db in
            for relativePath in relativePaths {
                try SummaryRecord.clearVaultRelativePath(relativePath, vaultId: vaultId, in: db)
            }
        }
    }

    private func pathsNeedReconciliation() -> Bool {
        (try? dbQueue.read { db in
            let summaries = try SummaryRecord.fetchAll(vaultId: vaultId, in: db)
            return summaries.contains { summary in
                guard let relativePath = summary.vaultRelativePath,
                      let fileURL = VaultSummaryFileLocator.fileURL(for: relativePath, vaultURL: vaultURL)
                else { return true }
                return !FileManager.default.fileExists(atPath: fileURL.path)
            }
        }) ?? false
    }

    private func storedSummaryFileExists(for meetingId: UUID, in db: Database) -> Bool {
        guard let summary = try? SummaryRecord.fetchOne(db, key: meetingId),
              let storedRelativePath = summary.vaultRelativePath,
              let storedURL = VaultSummaryFileLocator.fileURL(for: storedRelativePath, vaultURL: vaultURL)
        else { return false }
        return FileManager.default.fileExists(atPath: storedURL.path)
    }
}

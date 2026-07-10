import CoreServices
import Foundation

struct VaultFileSystemEventBatch {
    let directoryRenames: [(oldPath: String, newPath: String)]
    let newDirectories: [String]
    let removedDirectories: [String]
    let changedSummaryPaths: [String]
    let removedSummaryPaths: [String]

    init(paths: [String], flags: [UInt32], vaultURL: URL, fileManager: FileManager = .default) {
        let vaultPath = vaultURL.path + "/"
        var pendingRenames: [(path: String, exists: Bool)] = []
        var newDirectories: [String] = []
        var removedDirectories: [String] = []
        var changedSummaryPaths: [String] = []
        var removedSummaryPaths: [String] = []

        for (path, flag) in zip(paths, flags) {
            guard let event = Self.classify(path: path, flag: flag, vaultPath: vaultPath, fileManager: fileManager) else { continue }
            switch event {
            case let .directoryRename(path, exists):
                pendingRenames.append((path, exists))
            case let .directoryCreated(path):
                newDirectories.append(path)
            case let .directoryRemoved(path):
                removedDirectories.append(path)
            case let .summaryChanged(path):
                changedSummaryPaths.append(path)
            case let .summaryRemoved(path):
                removedSummaryPaths.append(path)
            }
        }

        let resolvedRenames = Self.resolveDirectoryRenames(pendingRenames)
        directoryRenames = resolvedRenames.renames
        self.newDirectories = newDirectories + resolvedRenames.created
        self.removedDirectories = removedDirectories + resolvedRenames.removed
        self.changedSummaryPaths = changedSummaryPaths
        self.removedSummaryPaths = removedSummaryPaths
    }

    private static func classify(
        path: String,
        flag: UInt32,
        vaultPath: String,
        fileManager: FileManager
    ) -> Event? {
        guard path.hasPrefix(vaultPath) else { return nil }
        let relativePath = String(path.dropFirst(vaultPath.count))
        guard !relativePath.isEmpty else { return nil }

        let isDirectory = flag & UInt32(kFSEventStreamEventFlagItemIsDir) != 0
        if isDirectory {
            return classifyDirectory(path: path, relativePath: relativePath, flag: flag, fileManager: fileManager)
        }
        return classifyFile(path: path, relativePath: relativePath, flag: flag, fileManager: fileManager)
    }

    private static func classifyDirectory(
        path: String,
        relativePath: String,
        flag: UInt32,
        fileManager: FileManager
    ) -> Event? {
        let components = relativePath.split(separator: "/")
        guard !components.contains(where: { $0.hasPrefix(".") || $0.hasPrefix("_") }) else { return nil }

        let exists = fileManager.fileExists(atPath: path)
        if flag & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
            return .directoryRename(relativePath, exists: exists)
        }
        if flag & UInt32(kFSEventStreamEventFlagItemRemoved) != 0, !exists {
            return .directoryRemoved(relativePath)
        }
        if flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0, exists {
            return .directoryCreated(relativePath)
        }
        return nil
    }

    private static func classifyFile(
        path: String,
        relativePath: String,
        flag: UInt32,
        fileManager: FileManager
    ) -> Event? {
        let components = relativePath.split(separator: "/")
        guard !components.contains(where: { $0.hasPrefix(".") }),
              !components.contains("_dahlia"),
              URL(fileURLWithPath: relativePath).pathExtension.lowercased() == "md"
        else { return nil }

        let exists = fileManager.fileExists(atPath: path)
        let isRenamed = flag & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
        let isCreated = flag & UInt32(kFSEventStreamEventFlagItemCreated) != 0
        let isRemoved = flag & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
        if exists, isRenamed || isCreated {
            return .summaryChanged(relativePath)
        }
        if !exists, isRenamed || isRemoved {
            return .summaryRemoved(relativePath)
        }
        return nil
    }

    private static func resolveDirectoryRenames(
        _ pendingRenames: [(path: String, exists: Bool)]
    ) -> (renames: [(oldPath: String, newPath: String)], created: [String], removed: [String]) {
        var renames: [(oldPath: String, newPath: String)] = []
        var created: [String] = []
        var removed: [String] = []
        var index = 0

        while index + 1 < pendingRenames.count {
            let first = pendingRenames[index]
            let second = pendingRenames[index + 1]
            if first.exists != second.exists {
                let oldPath = first.exists ? second.path : first.path
                let newPath = first.exists ? first.path : second.path
                renames.append((oldPath, newPath))
                index += 2
            } else {
                appendUnpairedRename(first, created: &created, removed: &removed)
                index += 1
            }
        }

        if index < pendingRenames.count {
            appendUnpairedRename(pendingRenames[index], created: &created, removed: &removed)
        }
        return (renames, created, removed)
    }

    private static func appendUnpairedRename(
        _ rename: (path: String, exists: Bool),
        created: inout [String],
        removed: inout [String]
    ) {
        if rename.exists {
            created.append(rename.path)
        } else {
            removed.append(rename.path)
        }
    }

    private enum Event {
        case directoryRename(String, exists: Bool)
        case directoryCreated(String)
        case directoryRemoved(String)
        case summaryChanged(String)
        case summaryRemoved(String)
    }
}

import Foundation

struct DatabricksCLIClient {
    struct CommandOutput {
        let standardOutput: Data
        let standardError: Data
        let terminationStatus: Int32
    }

    struct Profile: Decodable, Hashable, Identifiable {
        let name: String
        let host: String?
        let workspaceID: String?
        private let authenticationType: String

        var id: String { name }

        fileprivate var usesOAuthU2M: Bool {
            authenticationType == "databricks-cli"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            host = try container.decodeIfPresent(String.self, forKey: .host)
            authenticationType = try container.decode(String.self, forKey: .authenticationType)
            if let stringValue = try? container.decode(String.self, forKey: .workspaceID) {
                workspaceID = stringValue
            } else if let integerValue = try? container.decode(Int64.self, forKey: .workspaceID) {
                workspaceID = String(integerValue)
            } else {
                workspaceID = nil
            }
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case host
            case authenticationType = "auth_type"
            case workspaceID = "workspace_id"
        }
    }

    typealias CommandRunner = @Sendable ([String]) async throws -> CommandOutput

    private let runCommand: CommandRunner

    init(executableURL: URL? = Self.locateExecutable()) {
        runCommand = { arguments in
            guard let executableURL else {
                throw DatabricksCLIError.cliNotInstalled
            }

            return try await Task.detached(priority: .userInitiated) {
                let process = Process()
                let standardOutput = Pipe()
                let standardError = Pipe()
                process.executableURL = executableURL
                process.arguments = arguments
                process.standardOutput = standardOutput
                process.standardError = standardError

                try process.run()
                let standardOutputTask = Task.detached {
                    standardOutput.fileHandleForReading.readDataToEndOfFile()
                }
                let standardErrorTask = Task.detached {
                    standardError.fileHandleForReading.readDataToEndOfFile()
                }
                process.waitUntilExit()

                return await CommandOutput(
                    standardOutput: standardOutputTask.value,
                    standardError: standardErrorTask.value,
                    terminationStatus: process.terminationStatus
                )
            }.value
        }
    }

    init(runCommand: @escaping CommandRunner) {
        self.runCommand = runCommand
    }

    func profiles() async throws -> [Profile] {
        let output = try await runCommand([
            "auth",
            "profiles",
            "--skip-validate",
            "--output",
            "json",
        ])
        try validate(output)

        guard let response = try? JSONDecoder().decode(ProfilesResponse.self, from: output.standardOutput) else {
            throw DatabricksCLIError.invalidProfilesResponse
        }
        return response.profiles
            .filter(\.usesOAuthU2M)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func locateExecutable(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var candidatePaths = environment["PATH"]?
            .split(separator: ":")
            .map { String($0) + "/databricks" } ?? []
        candidatePaths.append(contentsOf: [
            "/opt/homebrew/bin/databricks",
            "/usr/local/bin/databricks",
        ])

        return candidatePaths.lazy
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func validate(_ output: CommandOutput) throws {
        guard output.terminationStatus == 0 else {
            let detail = String(data: output.standardError, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw DatabricksCLIError.commandFailed(detail: detail?.nilIfBlank)
        }
    }

    private struct ProfilesResponse: Decodable {
        let profiles: [Profile]
    }
}

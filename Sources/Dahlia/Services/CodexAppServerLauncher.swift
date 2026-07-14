import Foundation

protocol CodexAppServerLaunching: Sendable {
    func launch() throws -> any CodexAppServerTransport
}

struct BundledCodexAppServerLauncher: CodexAppServerLaunching {
    private let executableLocator: any CodexExecutableLocating
    private let homeLocator: any CodexHomeLocating

    init(
        executableLocator: any CodexExecutableLocating = BundleCodexExecutableLocator(),
        homeLocator: any CodexHomeLocating = ApplicationSupportCodexHomeLocator()
    ) {
        self.executableLocator = executableLocator
        self.homeLocator = homeLocator
    }

    func launch() throws -> any CodexAppServerTransport {
        let homeURL = try homeLocator.homeURL()
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = homeURL.path
        environment["PATH"] = executableSearchPath(environment: environment)
        return try CodexAppServerProcessTransport(
            executableURL: executableLocator.executableURL(),
            environment: environment
        )
    }

    private func executableSearchPath(environment: [String: String]) -> String {
        var paths = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        for path in ["/opt/homebrew/bin", "/usr/local/bin"] where !paths.contains(path) {
            paths.append(path)
        }
        return paths.joined(separator: ":")
    }
}

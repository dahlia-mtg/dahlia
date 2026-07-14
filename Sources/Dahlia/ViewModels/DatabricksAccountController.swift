import Foundation
import Observation

@MainActor
@Observable
final class DatabricksAccountController {
    private(set) var profiles: [DatabricksCLIClient.Profile] = []
    private(set) var isLoadingProfiles = false
    private(set) var isApplyingConfiguration = false
    private(set) var isConfigured = false
    private(set) var errorMessage: String?

    private let client: DatabricksCLIClient
    private let configurationManager: CodexConfigurationManager
    private let service: CodexAppServerService

    init(
        client: DatabricksCLIClient = DatabricksCLIClient(),
        configurationManager: CodexConfigurationManager = CodexConfigurationManager(),
        service: CodexAppServerService = .shared
    ) {
        self.client = client
        self.configurationManager = configurationManager
        self.service = service
    }

    var isBusy: Bool {
        isLoadingProfiles || isApplyingConfiguration
    }

    func prepare(profileName: String) async -> String? {
        await loadProfiles()
        guard errorMessage == nil else { return nil }

        let resolvedProfileName = resolvedProfileName(current: profileName)
        guard resolvedProfileName == profileName else { return resolvedProfileName }
        await apply(profileName: resolvedProfileName)
        return nil
    }

    func profile(named name: String) -> DatabricksCLIClient.Profile? {
        profiles.first { $0.name == name }
    }

    private func loadProfiles() async {
        isLoadingProfiles = true
        isConfigured = false
        errorMessage = nil
        defer { isLoadingProfiles = false }

        do {
            profiles = try await client.profiles()
            if profiles.isEmpty {
                errorMessage = L10n.noDatabricksProfiles
            }
        } catch is CancellationError {
            // SwiftUI cancels this operation when the settings screen disappears.
        } catch {
            profiles = []
            errorMessage = error.localizedDescription
        }
    }

    private func resolvedProfileName(current: String) -> String {
        profiles.contains { $0.name == current } ? current : profiles.first?.name ?? ""
    }

    private func apply(profileName: String) async {
        guard let profile = profile(named: profileName) else {
            errorMessage = L10n.databricksProfileRequired
            return
        }

        isApplyingConfiguration = true
        isConfigured = false
        errorMessage = nil
        defer { isApplyingConfiguration = false }

        do {
            if try configurationManager.configureDatabricks(profile: profile) {
                try await service.reloadConfiguration()
            }
            _ = try await service.models(forceRefresh: true)
            AppSettings.shared.codexConfiguredAccountProviderRawValue = AIAccountProvider.databricks.rawValue
            isConfigured = true
        } catch is CancellationError {
            // A newer profile selection superseded this configuration attempt.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

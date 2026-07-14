import Foundation
@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    struct DatabricksAccountControllerTests {
        @Test
        func validProfileConfiguresCodexAndLoadsModels() async {
            let rootURL = FileManager.default.temporaryDirectory
                .appending(path: "dahlia-databricks-account-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: rootURL) }
            let response = Data(
                #"{"profiles":[{"name":"DEFAULT","host":"https://dbc.example.com","auth_type":"databricks-cli"}]}"#.utf8
            )
            let client = DatabricksCLIClient { _ in
                .init(standardOutput: response, standardError: Data(), terminationStatus: 0)
            }
            let service = CodexAppServerService {
                TestCodexAppServerTransport(mode: .models)
            }
            let controller = DatabricksAccountController(
                client: client,
                configurationManager: CodexConfigurationManager(
                    homeLocator: ApplicationSupportCodexHomeLocator(applicationSupportURL: rootURL)
                ),
                service: service
            )
            let previousConfiguredProvider = AppSettings.shared.codexConfiguredAccountProviderRawValue
            defer { AppSettings.shared.codexConfiguredAccountProviderRawValue = previousConfiguredProvider }

            let resolvedProfile = await controller.prepare(profileName: "DEFAULT")

            #expect(resolvedProfile == nil)
            #expect(controller.isConfigured)
            #expect(controller.errorMessage == nil)
            #expect(AppSettings.shared.codexConfiguredAccountProviderRawValue == AIAccountProvider.databricks.rawValue)
            await service.shutdown()
        }
    }
#endif

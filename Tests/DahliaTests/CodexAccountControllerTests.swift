import Foundation
@testable import Dahlia

#if canImport(Testing)
    import Testing

    @MainActor
    struct CodexAccountControllerTests {
        @Test
        func explicitSignInOpensBrowserAndRefreshesAccount() async {
            let transport = TestCodexAppServerTransport(mode: .loginCompletes)
            let service = CodexAppServerService(transportFactory: { transport })
            let urlOpener = TestCodexLoginURLOpener()
            let controller = CodexAccountController(service: service, urlOpener: urlOpener)

            await controller.loadStatus()
            #expect(controller.accountStatus?.isAuthenticated == false)

            await controller.signIn()

            #expect(urlOpener.openedURLs == [URL(string: "https://chatgpt.com/auth/test")])
            #expect(controller.accountStatus?.isAuthenticated == true)
            #expect(controller.errorMessage == nil)
            await service.shutdown()
        }

        @Test
        func browserOpenFailureCancelsLoginAndShowsRetryableError() async {
            let transport = TestCodexAppServerTransport(mode: .loginBlocks)
            let service = CodexAppServerService(transportFactory: { transport })
            let urlOpener = TestCodexLoginURLOpener(result: false)
            let controller = CodexAccountController(service: service, urlOpener: urlOpener)

            await controller.loadStatus()
            await controller.signIn()

            #expect(controller.errorMessage == L10n.codexLoginPageCouldNotOpen)
            #expect(await transport.messages().contains {
                $0.objectValue?["method"]?.stringValue == "account/login/cancel"
            })
            #expect(await !(transport.isClosed))
            await service.shutdown()
        }

        @Test
        func activatingChatGPTRemovesDatabricksConfigurationAndReloadsStatus() async throws {
            let rootURL = FileManager.default.temporaryDirectory
                .appending(path: "dahlia-chatgpt-activation-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: rootURL) }
            let locator = ApplicationSupportCodexHomeLocator(applicationSupportURL: rootURL)
            let configURL = try locator.homeURL().appending(path: "config.toml")
            try Data("model_provider = \"Databricks\"\n".utf8).write(to: configURL)
            let service = CodexAppServerService {
                TestCodexAppServerTransport(mode: .models)
            }
            let controller = CodexAccountController(
                service: service,
                configurationManager: CodexConfigurationManager(homeLocator: locator)
            )

            await controller.activateChatGPTSubscription()

            #expect(controller.accountStatus?.isAuthenticated == true)
            #expect(controller.errorMessage == nil)
            #expect(!FileManager.default.fileExists(atPath: configURL.path))
            await service.shutdown()
        }
    }
#endif

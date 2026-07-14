import Foundation
@testable import Dahlia

#if canImport(Testing)
    import Testing

    struct DatabricksCLIClientTests {
        @Test
        func profilesLoadsOAuthCLIProfilesWithoutValidation() async throws {
            let recorder = CommandRecorder()
            let response = Data(
                """
                {"profiles":[
                    {"name":"WORK","host":"https://work.example.com","auth_type":"pat","workspace_id":"111"},
                    {"name":"DEV","host":"https://dev.example.com/","auth_type":"databricks-cli","workspace_id":222}
                ]}
                """.utf8
            )
            let client = DatabricksCLIClient { arguments in
                await recorder.record(arguments)
                return .init(standardOutput: response, standardError: Data(), terminationStatus: 0)
            }

            let profiles = try await client.profiles()

            #expect(profiles.map(\.name) == ["DEV"])
            #expect(profiles.map(\.workspaceID) == ["222"])
            #expect(await recorder.commands == [
                [
                    "auth",
                    "profiles",
                    "--skip-validate",
                    "--output",
                    "json",
                ],
            ])
        }

        @Test
        func profilesReportsCLIErrorOutput() async {
            let client = DatabricksCLIClient { _ in
                .init(
                    standardOutput: Data(),
                    standardError: Data("profile file is invalid".utf8),
                    terminationStatus: 1
                )
            }

            do {
                _ = try await client.profiles()
                Issue.record("Expected profile loading to fail")
            } catch {
                #expect(error.localizedDescription.contains("profile file is invalid"))
            }
        }

        private actor CommandRecorder {
            private(set) var commands: [[String]] = []

            func record(_ arguments: [String]) {
                commands.append(arguments)
            }
        }
    }
#endif

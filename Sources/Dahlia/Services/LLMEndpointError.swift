import Foundation

enum LLMEndpointError: LocalizedError {
    case workspaceURLInvalid
    case profileNotFound
    case profileWorkspaceHostUnavailable

    var errorDescription: String? {
        switch self {
        case .workspaceURLInvalid:
            L10n.databricksWorkspaceURLInvalid
        case .profileNotFound:
            L10n.databricksProfileNotFound
        case .profileWorkspaceHostUnavailable:
            L10n.workspaceHostUnavailableFromProfile
        }
    }
}

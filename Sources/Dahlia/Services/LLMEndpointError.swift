import Foundation

enum LLMEndpointError: LocalizedError {
    case workspaceIDRequired
    case profileNotFound
    case profileWorkspaceHostUnavailable

    var errorDescription: String? {
        switch self {
        case .workspaceIDRequired:
            L10n.databricksWorkspaceIDRequired
        case .profileNotFound:
            L10n.databricksProfileNotFound
        case .profileWorkspaceHostUnavailable:
            L10n.workspaceHostUnavailableFromProfile
        }
    }
}

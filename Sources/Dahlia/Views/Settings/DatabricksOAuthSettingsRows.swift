import SwiftUI

struct DatabricksOAuthSettingsRows: View {
    @Binding var selectedProfile: String
    let profiles: [DatabricksCLIClient.Profile]
    let isLoading: Bool
    let loadError: String?
    let refreshProfiles: () -> Void

    var body: some View {
        LabeledContent {
            HStack {
                profilePicker

                Button(
                    L10n.refreshDatabricksProfiles,
                    systemImage: "arrow.clockwise",
                    action: refreshProfiles
                )
                .labelStyle(.iconOnly)
                .disabled(isLoading)
            }
        } label: {
            Text(L10n.databricksProfile)
            Text(L10n.databricksProfileDescription)
        }

        LabeledContent(L10n.databricksWorkspaceID) {
            Text(workspaceID ?? L10n.workspaceIDUnavailableFromProfile)
                .foregroundStyle(workspaceID == nil ? Color.secondary : Color.primary)
                .textSelection(.enabled)
        }

        if let loadError {
            SettingsStatusMessage(
                text: loadError,
                systemImage: "xmark.circle.fill",
                tint: .red
            )
        }
    }

    @ViewBuilder
    private var profilePicker: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
        } else if profiles.isEmpty {
            Text(L10n.noDatabricksProfiles)
                .foregroundStyle(.secondary)
        } else {
            Picker("", selection: $selectedProfile) {
                ForEach(profiles) { profile in
                    Text(profile.name).tag(profile.name)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }

    private var workspaceID: String? {
        profiles.first { $0.name == selectedProfile }?.workspaceID?.nilIfBlank
    }
}

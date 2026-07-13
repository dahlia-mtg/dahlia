import SwiftUI

/// 設定画面（Cmd+, で表示）。
struct SettingsView: View {
    var sidebarViewModel: SidebarViewModel
    var onSelectVault: (VaultRecord) -> Void = { _ in }

    @AppStorage(SettingsNavigation.selectedCategoryDefaultsKey)
    private var selection: SettingsCategory = .general

    var body: some View {
        NavigationSplitView {
            SettingsSidebarView(selection: $selection)
        } detail: {
            SettingsDetailView(
                selection: selection,
                sidebarViewModel: sidebarViewModel,
                onSelectVault: onSelectVault
            )
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 860, minHeight: 560)
    }
}

import SwiftUI

/// 設定画面「スクリーンショット」タブ。自動スクリーンショット取得を管理する。
struct ScreenshotSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        SettingsPage {
            SettingsSection(
                title: L10n.automaticScreenshots,
                description: L10n.automaticScreenshotsDescription
            ) {
                SettingsCard {
                    VStack(spacing: 0) {
                        SettingsToggleRow(
                            title: L10n.automaticScreenshots,
                            description: L10n.automaticScreenshotsToggleDescription,
                            isOn: $settings.automaticScreenshotEnabled
                        )

                        Divider()

                        SettingsControlRow(
                            title: L10n.screenshotInterval,
                            description: L10n.screenshotIntervalDescription
                        ) {
                            Picker(L10n.screenshotInterval, selection: $settings.automaticScreenshotIntervalSeconds) {
                                ForEach(AppSettings.automaticScreenshotIntervalOptions, id: \.self) { interval in
                                    Text(L10n.seconds(interval)).tag(interval)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 120, alignment: .trailing)
                            .disabled(!settings.automaticScreenshotEnabled)
                        }

                        Divider()

                        SettingsControlRow(
                            title: L10n.screenshotChangeThreshold,
                            description: L10n.screenshotChangeThresholdDescription
                        ) {
                            Picker(L10n.screenshotChangeThreshold, selection: $settings.automaticScreenshotChangeThresholdPercent) {
                                ForEach(AppSettings.automaticScreenshotChangeThresholdPercentOptions, id: \.self) { threshold in
                                    Text(L10n.percent(threshold)).tag(threshold)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 120, alignment: .trailing)
                            .disabled(!settings.automaticScreenshotEnabled)
                        }
                    }
                }
            }
        }
    }
}

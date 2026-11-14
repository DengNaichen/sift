import AppKit
import SwiftUI
import MailroomCore

// MARK: - Tab 4: 阅读与外观

struct AppearanceSettingsTabView: View {
    let model: SettingsViewModel

    private var s: SettingsFormState { model.form }

    var body: some View {

        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionBlock(title: "主题") {
                HStack(spacing: 10) {
                    ThemePreviewCardView(
                        preference: .system,
                        title: "跟随系统",
                        selected: model.themePreference == .system
                    ) {
                        model.setThemePreference(.system)
                    }

                    ThemePreviewCardView(
                        preference: .light,
                        title: "浅色",
                        selected: model.themePreference == .light
                    ) {
                        model.setThemePreference(.light)
                    }

                    ThemePreviewCardView(
                        preference: .dark,
                        title: "深色",
                        selected: model.themePreference == .dark
                    ) {
                        model.setThemePreference(.dark)
                    }
                }
            }

            SettingsSectionBlock(title: "阅读与界面") {
                SunkenCardGroup {
                    SettingsRowView(title: "默认正文格式") {
                        MonochromeSegmentedControl(
                            options: [
                                (false, "富文本"),
                                (true, "纯文本")
                            ],
                            selection: model.preferPlainText
                        ) { plain in
                            model.setPreferPlainText(plain)
                        }
                    }

                    SunkenRowDivider()

                    SettingsRowView(title: "远程图片") {
                        MonochromeSegmentedControl(
                            options: RemoteImageChoice.allCases.map { ($0, $0.label) },
                            selection: s.remoteImageChoice
                        ) { picked in
                            s.remoteImageChoice = picked
                        }
                    }

                    SunkenRowDivider()

                    SettingsRowView(title: "底部快捷键提示条") {
                        MonochromeToggle(isOn: model.showKeyboardHUD)
                    }

                    SunkenRowDivider()

                    SettingsRowView(title: "默认展开 AI 判据条") {
                        MonochromeToggle(isOn: model.aiReasoningExpanded)
                    }
                }
            }
        }
    }
}

private struct ThemePreviewCardView: View {
    @Environment(\.palette) private var p
    let preference: ThemePreference
    let title: String
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                miniatureCanvas
                    .frame(height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.gray.opacity(0.16), lineWidth: 1)
                    )

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.ink)
                    .padding(.horizontal, 2)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? p.paper : p.sunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        selected ? p.ink.opacity(p.mode == .dark ? 0.42 : 0.48) : p.line,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var miniatureCanvas: some View {
        switch preference {
        case .system:
            HStack(spacing: 0) {
                miniHalf(canvas: Color(hex: 0xFAFBFD), paper: .white, bar: Color(hex: 0x0F1117), active: Color.black.opacity(0.07))
                miniHalf(canvas: Color(hex: 0x101114), paper: Color(hex: 0x16171B), bar: Color(hex: 0xECEDEF), active: Color.white.opacity(0.11))
            }
        case .light:
            miniFull(canvas: Color(hex: 0xFAFBFD), paper: .white, ink: Color(hex: 0x0F1117), active: Color.black.opacity(0.07))
        case .dark:
            miniFull(canvas: Color(hex: 0x101114), paper: Color(hex: 0x16171B), ink: Color(hex: 0xECEDEF), active: Color.white.opacity(0.11))
        }
    }

    private func miniHalf(canvas: Color, paper: Color, bar: Color, active: Color) -> some View {
        ZStack {
            canvas
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(paper)
                .overlay(
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(active)
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(bar.opacity(0.18))
                            .frame(width: 34, height: 3.5)
                        Spacer(minLength: 0)
                    }
                    .padding(5)
                )
                .padding(5)
        }
    }

    private func miniFull(canvas: Color, paper: Color, ink: Color, active: Color) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 1.5).fill(ink.opacity(0.2)).frame(width: 24, height: 3.5)
                RoundedRectangle(cornerRadius: 1.5).fill(ink.opacity(0.2)).frame(width: 32, height: 3.5)
                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(width: 44, alignment: .leading)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(paper)
                .overlay(
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(active)
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(ink.opacity(0.18))
                            .frame(width: 68, height: 3.5)
                        Spacer(minLength: 0)
                    }
                    .padding(7)
                )
                .padding(.vertical, 4)
                .padding(.trailing, 4)
        }
        .background(canvas)
    }
}

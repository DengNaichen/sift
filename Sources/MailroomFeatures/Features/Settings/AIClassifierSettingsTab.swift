import AppKit
import SwiftUI
import MailroomCore

// MARK: - Tab 3: AI 分类引擎

struct AIClassifierSettingsTabView: View {
    @Environment(\.palette) private var p
    let model: SettingsViewModel

    private var s: SettingsFormState { model.form }

    var body: some View {
        @Bindable var bindable = s

        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionBlock(title: "引擎模式") {
                HStack(spacing: 8) {
                    ForEach(ClassifierEngineChoice.allCases) { mode in
                        EngineModeCardView(
                            mode: mode,
                            selected: s.engineMode == mode
                        ) {
                            withAnimation(.snappy(duration: 0.16)) {
                                s.selectEngine(mode)
                            }
                        }
                    }
                }
            }

            if s.engineMode != .rules {
                SettingsSectionBlock(title: "模型连接") {
                    SunkenCardGroup {
                        if s.engineMode == .hybrid {
                            SettingsRowView(title: "服务商") {
                                MonochromeSegmentedControl(
                                    options: LLMProviderChoice.allCases.map { ($0, $0.label) },
                                    selection: s.provider
                                ) { picked in
                                    s.selectProvider(picked)
                                }
                            }

                            SunkenRowDivider()
                        }

                        SettingsRowView(title: "Endpoint") {
                            SettingsMonospaceInput(
                                text: $bindable.endpoint,
                                placeholder: "https://...",
                                width: 288
                            )
                        }

                        if s.engineMode == .hybrid {
                            SunkenRowDivider()

                            SettingsRowView(title: "API Key", badge: "钥匙串") {
                                HStack(spacing: 6) {
                                    SettingsSecretInput(
                                        text: $bindable.apiKey,
                                        revealed: s.apiKeyRevealed,
                                        placeholder: "输入密钥…",
                                        width: 224
                                    )
                                    QuietActionButton(title: s.apiKeyRevealed ? "隐藏" : "显示") {
                                        s.apiKeyRevealed.toggle()
                                    }
                                }
                            }
                        }

                        SunkenRowDivider()

                        SettingsRowView(title: "模型") {
                            HStack(spacing: 6) {
                                SettingsMonospaceInput(
                                    text: $bindable.modelName,
                                    placeholder: "model-id",
                                    width: 204
                                )
                                QuietActionButton(title: s.connectionTestStatus ?? "测试连接") {
                                    s.triggerConnectionPreview()
                                }
                            }
                        }
                    }
                }
            }

            SettingsSectionBlock(title: "判别门限与数据范围") {
                SunkenCardGroup {
                    SettingsRowView(
                        title: "自动分拣确信度门限",
                        subtitle: "低于门限的邮件留在待处理并以虚线标出"
                    ) {
                        HStack(spacing: 10) {
                            Text("\(Int(s.confidenceThreshold.rounded()))%")
                                .font(.system(size: 12.5, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(p.ink)
                                .frame(width: 36, alignment: .trailing)

                            Slider(value: $bindable.confidenceThreshold, in: 80...98, step: 1)
                                .tint(p.ink)
                                .frame(width: 146)
                        }
                    }

                    if s.engineMode != .rules {
                        SunkenRowDivider()

                        SettingsRowView(title: "送审内容范围") {
                            MonochromeSegmentedControl(
                                options: PayloadScopeChoice.allCases.map { ($0, $0.label) },
                                selection: s.payloadScope
                            ) { picked in
                                s.payloadScope = picked
                            }
                        }

                        SunkenRowDivider()

                        SettingsRowView(title: "本地缓存判别结果") {
                            MonochromeToggle(isOn: $bindable.cacheDecisions)
                        }
                    }
                }
            }
        }
    }
}

private struct EngineModeCardView: View {
    @Environment(\.palette) private var p
    let mode: ClassifierEngineChoice
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(mode.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(p.ink)
                    Spacer(minLength: 0)
                    if let badge = mode.badgeText {
                        QuietTagView(text: badge)
                    }
                }

                Text(mode.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.ink3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
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
}

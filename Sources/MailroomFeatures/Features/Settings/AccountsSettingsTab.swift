import AppKit
import SwiftUI
import MailroomCore

// MARK: - Tab 1: 邮箱与连接

struct AccountsSettingsTabView: View {
    @Environment(\.palette) private var p
    let model: SettingsViewModel

    private var s: SettingsFormState { model.form }
    private var isFDAReady: Bool { model.isFullDiskAccessReady }
    private var lockedPrimaryAddresses: [String] { model.lockedPrimaryAddresses }

    var body: some View {
        @Bindable var bindable = s

        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionBlock(title: "连接与权限") {
                SunkenCardGroup {
                    SettingsRowView(title: "数据源") {
                        MonochromeSegmentedControl(
                            options: [
                                ("appleMail", "Apple Mail"),
                                ("demo", "演示数据")
                            ],
                            selection: model.sourceModeKey
                        ) { picked in
                            model.selectSource(picked)
                        }
                    }

                    SunkenRowDivider()

                    SettingsRowView(
                        title: "完全磁盘访问",
                        subtitle: isFDAReady ? nil : "尚未授权读取 ~/Library/Mail"
                    ) {
                        HStack(spacing: 10) {
                            HStack(spacing: 5.5) {
                                Circle()
                                    .fill(isFDAReady ? p.sage : p.amber)
                                    .frame(width: 5.5, height: 5.5)
                                Text(isFDAReady ? "已就绪" : "待授权")
                                    .font(.system(size: 12))
                                    .foregroundStyle(p.ink3)
                            }

                            if !isFDAReady {
                                QuietActionButton(title: "系统设置") {
                                    model.perform(.openFullDiskAccessSettings)
                                }
                            }

                            QuietActionButton(title: isFDAReady ? "重新检测" : "重连", prominent: !isFDAReady) {
                                model.perform(.switchToLive)
                            }
                        }
                    }

                    SunkenRowDivider()

                    SettingsRowView(title: "自动化控制「邮件」") {
                        HStack(spacing: 10) {
                            HStack(spacing: 5.5) {
                                Circle()
                                    .fill(p.sage)
                                    .frame(width: 5.5, height: 5.5)
                                Text("已授权")
                                    .font(.system(size: 12))
                                    .foregroundStyle(p.ink3)
                            }

                            QuietActionButton(title: s.automationVerifyStatus ?? "验证") {
                                s.triggerAutomationPreview()
                            }
                        }
                    }

                    SunkenRowDivider()

                    SettingsRowView(title: "单次同步上限") {
                        MonochromeSegmentedControl(
                            options: [
                                (50, "50"),
                                (100, "100"),
                                (200, "200"),
                                (500, "500")
                            ],
                            selection: s.syncLimit
                        ) { limit in
                            s.syncLimit = limit
                        }
                    }
                }
            }

            SettingsSectionBlock(title: "邮箱账户") {
                SunkenCardGroup {
                    ForEach(Array(s.accountItems.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 {
                            SunkenRowDivider()
                        }
                        AccountShellRowView(item: $bindable.accountItems[idx])
                    }
                }
            }

            SettingsSectionBlock(
                title: "本人发件别名",
                footnote: "包含本人地址参与回复的线程受保护，不会自动移入废纸篓。"
            ) {
                SunkenCardGroup {
                    TagChipsEditorView(
                        lockedChips: lockedPrimaryAddresses,
                        customChips: s.customAliases,
                        draft: $bindable.aliasDraft,
                        placeholder: "添加别名后回车…",
                        onSubmit: { s.submitAliasDraft() },
                        onRemove: { idx in s.removeAlias(at: idx) }
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
            }
        }
    }
}

private struct AccountShellRowView: View {
    @Environment(\.palette) private var p
    @Binding var item: SettingsAccountShellItem

    var body: some View {
        HStack(spacing: 10) {
            MonochromeToggle(isOn: $item.enabled)

            Button {
                item.tone = item.tone.next
            } label: {
                Circle()
                    .fill(item.tone.color(in: p))
                    .frame(width: 7, height: 7)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("点击切换圆点色")

            TextField("名称", text: $item.label)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(p.ink)
                .padding(.horizontal, 6)
                .frame(width: 70, height: 24)
                .background(p.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(p.line, lineWidth: 1)
                )

            Text(item.address)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(p.ink3)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("\(item.archivePath) · \(item.trashPath)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(p.ink3)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .opacity(item.enabled ? 1.0 : 0.48)
    }
}

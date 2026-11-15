import AppKit
import SwiftUI
import MailroomCore

// MARK: - Tab 2: 分拣与护栏（Superhuman 7 类分拣与本地硬护栏）

struct TriageSettingsTabView: View {
    @Environment(\.palette) private var p
    let model: SettingsViewModel

    private var s: SettingsFormState { model.form }

    var body: some View {
        @Bindable var bindable = s

        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionBlock(
                title: "自动分拣去向",
                footnote: "需回复与待办来信（需处理）始终留在收件箱待处理。"
            ) {
                SunkenCardGroup {
                    SettingsRowView(title: "快捷预设") {
                        MonochromeSegmentedControl<SiftPreset?>(
                            options: SiftPreset.allCases.map { (Optional($0), $0.title) },
                            selection: s.activePreset
                        ) { picked in
                            if let picked {
                                s.applyPreset(picked)
                            }
                        }
                    }

                    ForEach(s.triageMatrix) { row in
                        SunkenRowDivider()

                        SettingsRowView(
                            title: row.title,
                            badge: row.category.allowsTrashPreference ? nil : "禁删"
                        ) {
                            MonochromeSegmentedControl(
                                options: row.allowedChoices.map { ($0, $0.label) },
                                selection: row.choice
                            ) { picked in
                                s.setDisposition(picked, for: row.category)
                            }
                        }
                    }
                }
            }

            SettingsSectionBlock(
                title: "护栏与黑白名单",
                footnote: "星标邮件、本人参与的对话线程，以及合同签署、账单异常与受保护主题始终受硬护栏保护，绝不自动删除。"
            ) {
                SunkenCardGroup {
                    SettingsRowView(title: "残缺或纯图片邮件留待人工核实") {
                        MonochromeToggle(isOn: $bindable.reviewIncompleteMails)
                    }

                    SunkenRowDivider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("受保护域名与发件人")
                            .font(.system(size: 13))
                            .foregroundStyle(p.ink)

                        TagChipsEditorView(
                            lockedChips: [".edu", ".edu.cn", ".gov"],
                            customChips: s.customProtectedEntries,
                            draft: $bindable.protectedDraft,
                            placeholder: "添加域名或邮箱后回车…",
                            onSubmit: { s.submitProtectedDraft() },
                            onRemove: { idx in s.removeProtectedEntry(at: idx) }
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    SunkenRowDivider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 7) {
                            Text("屏蔽发件人或域名")
                                .font(.system(size: 13))
                                .foregroundStyle(p.ink)
                            QuietTagView(text: "受护栏约束")
                        }

                        TagChipsEditorView(
                            lockedChips: [],
                            customChips: s.customBlockedEntries,
                            draft: $bindable.blockedDraft,
                            placeholder: "添加发件人或域名后回车…",
                            onSubmit: { s.submitBlockedDraft() },
                            onRemove: { idx in s.removeBlockedEntry(at: idx) }
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
            }
        }
    }
}

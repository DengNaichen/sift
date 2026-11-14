import AppKit
import SwiftUI
import MailroomCore

// MARK: - Tab 2: 分拣与护栏

struct TriageSettingsTabView: View {
    @Environment(\.palette) private var p
    let model: SettingsViewModel

    private var s: SettingsFormState { model.form }

    var body: some View {
        @Bindable var bindable = s

        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionBlock(title: "自动分拣去向") {
                SunkenCardGroup {
                    ForEach(Array(s.triageMatrix.enumerated()), id: \.element.id) { idx, row in
                        if idx > 0 {
                            SunkenRowDivider()
                        }
                        SettingsRowView(title: row.title) {
                            MonochromeSegmentedControl(
                                options: TriageDispositionChoice.allCases.map { ($0, $0.label) },
                                selection: row.choice
                            ) { picked in
                                s.triageMatrix[idx].choice = picked
                            }
                        }
                    }
                }
            }

            SettingsSectionBlock(
                title: "护栏与白名单",
                footnote: "星标邮件、本人参与的对话线程，以及合同签署与账单异常始终留在待处理。"
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
                }
            }
        }
    }
}

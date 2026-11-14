import AppKit
import SwiftUI
import MailroomCore

// MARK: - Tab 5: 快捷键与诊断

struct DiagnosticsSettingsTabView: View {
    @Environment(\.palette) private var p
    let model: SettingsViewModel

    private var s: SettingsFormState { model.form }

    private let leftShortcuts: [(String, [String])] = [
        ("上下移动焦点", ["J", "K"]),
        ("阅毕归档", ["Space"]),
        ("重要保留", ["⇧K"]),
        ("移入废纸篓", ["⌫"]),
        ("拉回待处理", ["R"]),
        ("撤销", ["Z"])
    ]

    private let rightShortcuts: [(String, [String])] = [
        ("切换分拣夹", ["1", "2", "3"]),
        ("在 Apple Mail 打开", ["↵"]),
        ("展开 / 收起判据", ["I"]),
        ("收起 / 展开侧栏", ["["]),
        ("搜索与命令", ["⌘K"]),
        ("打开 / 关闭设置", ["⌘,"])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionBlock(title: "快捷键") {
                HStack(alignment: .top, spacing: 10) {
                    shortcutColumn(items: leftShortcuts)
                    shortcutColumn(items: rightShortcuts)
                }
            }

            SettingsSectionBlock(title: "诊断与缓存") {
                VStack(spacing: 10) {
                    // 四宫格只读健康概览（同源 InboxZeroView 统计卡）
                    HStack(spacing: 0) {
                        diagnosticMetricCell(value: s.walStatusText, label: "Envelope Index", showReadyDot: true)
                        verticalCellDivider
                        diagnosticMetricCell(value: s.hitRateText, label: ".emlx 命中率", showReadyDot: false)
                        verticalCellDivider
                        diagnosticMetricCell(value: s.pendingLedgerText, label: "待结算变更", showReadyDot: false)
                        verticalCellDivider
                        diagnosticMetricCell(value: s.cacheSizeText, label: "本地缓存", showReadyDot: false)
                    }
                    .background(p.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(p.line, lineWidth: 1)
                    )

                    SunkenCardGroup {
                        SettingsRowView(title: "连接诊断") {
                            HStack(spacing: 6) {
                                QuietActionButton(title: "重新自检") {
                                    s.refreshDiagnostics()
                                }
                                QuietActionButton(title: "复制报告") {
                                    s.showTransientFeedback("复制报告将在接入诊断逻辑后启用")
                                }
                            }
                        }

                        SunkenRowDivider()

                        SettingsRowView(title: "本地解析缓存") {
                            if s.confirmingCacheRebuild {
                                HStack(spacing: 6) {
                                    QuietActionButton(title: "取消") {
                                        s.confirmingCacheRebuild = false
                                    }
                                    QuietActionButton(title: "确认重建", destructiveText: true) {
                                        s.confirmCacheRebuild()
                                    }
                                }
                            } else {
                                QuietActionButton(title: "重建缓存…") {
                                    s.confirmingCacheRebuild = true
                                }
                            }
                        }

                        SunkenRowDivider()

                        SettingsRowView(title: "离线评测样本") {
                            QuietActionButton(title: "导出 JSON…") {
                                s.showTransientFeedback("导出评测样本将在接入后端逻辑后启用")
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            s.refreshDiagnostics(silent: true)
        }
    }

    private var verticalCellDivider: some View {
        Rectangle().fill(p.line).frame(width: 1)
    }

    private func diagnosticMetricCell(value: String, label: String, showReadyDot: Bool) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                if showReadyDot {
                    Circle()
                        .fill(p.sage)
                        .frame(width: 5.5, height: 5.5)
                }
                Text(value)
                    .font(.system(size: 14.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(p.ink)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(p.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func shortcutColumn(items: [(String, [String])]) -> some View {
        SunkenCardGroup {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, pair in
                if idx > 0 {
                    SunkenRowDivider()
                }
                HStack {
                    Text(pair.0)
                        .font(.system(size: 12.5))
                        .foregroundStyle(p.ink2)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(pair.1, id: \.self) { key in
                            KbdView(text: key)
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8.5)
            }
        }
    }
}

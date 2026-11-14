import AppKit
import SwiftUI
import MailroomCore

struct SettingsWorkspaceView: View {
    @Environment(\.palette) private var p
    let model: SettingsViewModel

    private var s: SettingsFormState { model.form }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // 44pt 顶栏面包屑（与邮件列表/阅读区顶栏严格同高）
                HStack(spacing: 7) {
                    Text("设置")
                        .font(.system(size: 12.5))
                        .foregroundStyle(p.ink3)
                    Text("/")
                        .font(.system(size: 12.5))
                        .foregroundStyle(p.ink3.opacity(0.6))
                    Text(s.activeSection.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(p.ink)

                    Spacer()

                    KbdView(text: "⌘,")
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .frame(height: 44)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(p.line).frame(height: 1)
                }

                // 主体单栏居中滚动区
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 26) {
                            Color.clear
                                .frame(height: 0)
                                .id("settings-top")

                            Text(s.activeSection.title)
                                .font(.system(size: 17.5, weight: .semibold))
                                .foregroundStyle(p.ink)

                            switch s.activeSection {
                            case .accounts:
                                AccountsSettingsTabView(model: model)
                            case .triage:
                                TriageSettingsTabView(model: model)
                            case .ai:
                                AIClassifierSettingsTabView(model: model)
                            case .appearance:
                                AppearanceSettingsTabView(model: model)
                            case .diagnostics:
                                DiagnosticsSettingsTabView(model: model)
                            }
                        }
                        .frame(maxWidth: 620, alignment: .leading)
                        .padding(.horizontal, 36)
                        .padding(.top, 26)
                        .padding(.bottom, 48)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .borderlessScroller()
                    }
                    .onChange(of: s.activeSection) { _, _ in
                        proxy.scrollTo("settings-top", anchor: .top)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let banner = s.transientBannerText {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(p.ink2)
                    Text(banner)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.ink)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7.5)
                .deckGlassCapsule()
                .padding(.trailing, 22)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(p.paper)
        .onAppear {
            model.syncAccounts(model.liveAccounts)
        }
        .onChange(of: model.liveAccounts) { _, updated in
            model.syncAccounts(updated)
        }
    }
}

import AppKit
import SwiftUI
import MailroomCore

struct SettingsSidebarView: View {
    @Environment(\.palette) private var p
    let model: SettingsViewModel
    @State private var backHovered = false
    @State private var searchHovered = false

    private var connectionSections: [SettingsSection] {
        [.accounts, .triage, .ai]
    }

    private var workspaceSections: [SettingsSection] {
        [.appearance, .diagnostics]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. 返回收件箱顶栏（与 SidebarView 32pt 品牌栏等高对齐）
            Button {
                model.perform(.closeSettings)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(backHovered ? p.ink : p.ink2)
                    Text("返回收件箱")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(p.ink)
                    Spacer()
                    KbdView(text: "esc")
                }
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(backHovered ? p.ink.opacity(0.045) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { backHovered = $0 }
            .help("返回收件箱（Esc）")

            // 2. 搜索与命令入口（与收件箱侧栏一致的交互式 Liquid Glass 胶囊）
            Button {
                model.perform(.openPalette)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(searchHovered ? p.ink2 : p.ink3)
                    Text("搜索与命令")
                        .font(.system(size: 12))
                        .foregroundStyle(searchHovered ? p.ink2 : p.ink3)
                    Spacer()
                    KbdView(text: "⌘K")
                }
                .padding(.leading, 10)
                .padding(.trailing, 7)
                .frame(height: 29)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { searchHovered = $0 }
            .deckGlassCapsule(interactive: true)
            .padding(.top, 8)

            // 3. 五大设置分组
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionGroup(title: "连接与分拣", items: connectionSections)
                    sectionGroup(title: "工作台", items: workspaceSections)
                }
                .padding(.vertical, 14)
            }

            Spacer(minLength: 0)

            // 4. 底部控制按钮（与收件箱侧栏一致极简留白）
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                Button {
                    model.perform(.closeSettings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(p.ink)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .deckGlassCapsule(interactive: true)
                .help("关闭设置（⌘,）")
            }
            .frame(height: 30)
            .padding(.trailing, 1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(width: 206)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sectionGroup(title: String, items: [SettingsSection]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(p.ink3)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)

            ForEach(items) { sec in
                let active = (model.form.activeSection == sec)
                Button {
                    withAnimation(.snappy(duration: 0.16)) {
                        model.form.activeSection = sec
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: sec.iconName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(active ? p.ink : p.ink3)
                            .frame(width: 15)

                        Text(sec.title)
                            .font(.system(size: 12.5, weight: active ? .medium : .regular))
                            .foregroundStyle(active ? p.ink : p.ink2)
                            .lineLimit(1)

                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(active ? p.ink.opacity(0.065) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

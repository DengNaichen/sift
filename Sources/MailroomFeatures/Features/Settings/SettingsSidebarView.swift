import AppKit
import SwiftUI
import MailroomCore

struct SettingsSidebarView: View {
    @Environment(\.palette) private var p
    let model: SettingsViewModel

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
                        .foregroundStyle(p.ink2)
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
                        .fill(Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("返回收件箱（Esc）")

            // 2. 搜索与命令入口
            Button {
                model.perform(.openPalette)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(p.ink3)
                    Text("搜索与命令")
                        .font(.system(size: 12))
                        .foregroundStyle(p.ink3)
                    Spacer()
                    KbdView(text: "⌘K")
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(p.ink.opacity(0.048), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
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

            // 4. 底部状态栏
            HStack(spacing: 5.5) {
                Circle()
                    .fill(model.isLiveSource ? p.sage : p.amber)
                    .frame(width: 5.5, height: 5.5)
                Text("Mailroom")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(p.ink3)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Button {
                    model.perform(.closeSettings)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.ink)
                        .frame(width: 24, height: 24)
                        .background(p.ink.opacity(0.065), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("关闭设置（⌘,）")
            }
            .frame(height: 28)
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(width: 206)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(p.canvas)
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

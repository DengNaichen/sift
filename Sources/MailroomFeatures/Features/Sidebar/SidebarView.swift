import SwiftUI
import MailroomCore

struct SidebarView: View {
    @Environment(\.palette) private var p
    let model: SidebarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. 品牌栏
            HStack(spacing: 9) {
                FluidSilkLogoIcon()
                Text("Mailroom")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(p.ink)

                Spacer()

                Button {
                    model.perform(.toggleSidebar)
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(p.ink3)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("收起侧边栏（[）")
            }
            .frame(height: 32)
            .padding(.horizontal, 4)

            // 2. 多邮箱范围滤镜（支持 2–N 个真实邮箱横向自适应切换）
            if model.showsAccountTabs {
                VStack(alignment: .leading, spacing: 4) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            AccountScopeTab(
                                label: "全部",
                                dotColor: nil,
                                active: model.isAllAccountsActive
                            ) {
                                model.perform(.setAccountScope(.all))
                            }
                            ForEach(model.accounts) { acc in
                                AccountScopeTab(
                                    label: acc.label,
                                    dotColor: p.accountDotColor(acc.id),
                                    active: model.isActive(account: acc)
                                ) {
                                    model.perform(.setAccountScope(.account(acc.id)))
                                }
                                .help(acc.address)
                            }
                        }
                        .padding(2)
                    }
                    .background(p.ink.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                    if let activeAcc = model.activeAccount {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(p.accountDotColor(activeAcc.id))
                                .frame(width: 6, height: 6)
                            Text(activeAcc.address)
                                .font(.system(size: 11))
                                .foregroundStyle(p.ink3)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.top, 8)
            }

            // 3. 搜索与命令入口
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

            // 4. 分拣导航树
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("待你拍板")
                            .font(.system(size: 10.5, weight: .medium))
                            .tracking(0.4)
                            .foregroundStyle(p.ink3)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 2)

                        ForEach(model.triageFolders) { def in
                            SidebarFolderRow(
                                def: def,
                                count: model.count(of: def.id),
                                active: model.isActive(folder: def.id)
                            ) {
                                model.perform(.setFolder(def.id))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("已分拣")
                            .font(.system(size: 10.5, weight: .medium))
                            .tracking(0.4)
                            .foregroundStyle(p.ink3)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 2)

                        ForEach(model.processedFolders) { def in
                            SidebarFolderRow(
                                def: def,
                                count: model.count(of: def.id),
                                active: model.isActive(folder: def.id)
                            ) {
                                model.perform(.setFolder(def.id))
                            }
                        }
                    }
                }
                .padding(.vertical, 14)
            }

            Spacer(minLength: 0)

            // 5. 底部状态与控制栏
            HStack(spacing: 4) {
                Circle()
                    .fill(model.isLiveSource ? p.sage : p.amber)
                    .frame(width: 5.5, height: 5.5)
                Text(model.savedMinutesText)
                    .font(.system(size: 11))
                    .foregroundStyle(p.ink3)
                    .lineLimit(1)
                    .help(model.sourceHelpText)

                Spacer(minLength: 2)

                if model.isLiveSource {
                    IconFooterButton(
                        systemName: "arrow.clockwise",
                        help: "立即同步 Apple Mail（⌘R）"
                    ) {
                        model.perform(.syncNow)
                    }
                } else if model.showsDemoControls {
                    IconFooterButton(systemName: "envelope.badge", help: "模拟收到 3 封新邮件") {
                        model.perform(.simulateIncoming)
                    }
                    IconFooterButton(systemName: "arrow.counterclockwise", help: "重置演示数据") {
                        model.perform(.resetDemo)
                    }
                }

                IconFooterButton(
                    systemName: model.isDarkTheme ? "moon" : "sun.max",
                    help: model.isDarkTheme ? "切换到浅色模式" : "切换到深色模式"
                ) {
                    model.perform(.toggleTheme)
                }

                IconFooterButton(
                    systemName: "gearshape",
                    help: "设置（⌘,）"
                ) {
                    model.perform(.openSettings(nil))
                }
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
}

private struct AccountScopeTab: View {
    @Environment(\.palette) private var p
    let label: String
    let dotColor: Color?
    let active: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(size: 11.5, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? p.ink : p.ink3)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Group {
                    if active {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(p.paper)
                            .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarFolderRow: View {
    @Environment(\.palette) private var p
    let def: FolderDef
    let count: Int
    let active: Bool
    let onTap: () -> Void

    private var iconName: String {
        switch def.id {
        case .inbox: return "tray"
        case .inboxHuman: return "person"
        case .inboxStakes: return "doc.text"
        case .inboxUncertain: return "questionmark.circle"
        case .kept: return "flag"
        case .archived: return "archivebox"
        case .trashed: return "trash"
        }
    }

    private var iconColor: Color {
        if def.id == .kept && (count > 0 || active) {
            return p.amber
        }
        return active ? p.ink : p.ink3
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 15)

                Text(def.label)
                    .font(.system(size: 12.5, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? p.ink : p.ink2)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(count)")
                    .font(.system(size: 11, weight: (active || def.id == .inbox) ? .medium : .regular, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(count == 0 ? p.ink3.opacity(0.4) : (active || def.id == .inbox ? p.ink2 : p.ink3))
            }
            .padding(.leading, def.isSub ? 16 : 8)
            .padding(.trailing, 8)
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

private struct IconFooterButton: View {
    @Environment(\.palette) private var p
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(p.ink3)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

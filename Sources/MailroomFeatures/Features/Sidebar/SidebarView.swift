import SwiftUI
import MailroomCore

struct SidebarView: View {
    @Environment(\.palette) private var p
    let model: SidebarViewModel
    var isPeek: Bool = false
    var onDismissPeek: (() -> Void)? = nil

    @State private var searchHovered = false
    @State private var toggleHovered = false
    @Namespace private var accountScopeNS

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. 品牌栏
            HStack(spacing: 9) {
                FluidSilkLogoIcon()
                Text("Mailroom")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(p.ink)

                Spacer()

                sidebarToggleButton
            }
            .frame(height: 32)
            .padding(.horizontal, 4)

            // 2. 多邮箱范围滤镜（无框横向流 + 滑动液态玻璃选中胶囊 + 右缘柔和渐隐）
            if model.showsAccountTabs {
                VStack(alignment: .leading, spacing: 3) {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            DeckGlassCluster(spacing: 8) {
                                HStack(spacing: 2) {
                                    AccountScopeTab(
                                        label: "全部",
                                        dotColor: nil,
                                        active: model.isAllAccountsActive,
                                        useLiquidGlass: !isPeek,
                                        namespace: accountScopeNS
                                    ) {
                                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                            model.perform(.setAccountScope(.all))
                                            proxy.scrollTo("scope-all", anchor: .leading)
                                        }
                                    }
                                    .id("scope-all")

                                    ForEach(model.accounts) { acc in
                                        let scopeId = "scope-\(acc.id)"
                                        AccountScopeTab(
                                            label: acc.label,
                                            dotColor: p.accountDotColor(acc.id),
                                            active: model.isActive(account: acc),
                                            useLiquidGlass: !isPeek,
                                            namespace: accountScopeNS
                                        ) {
                                            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                                model.perform(.setAccountScope(.account(acc.id)))
                                                proxy.scrollTo(scopeId, anchor: .center)
                                            }
                                        }
                                        .id(scopeId)
                                        .help(acc.address)
                                    }
                                }
                            }
                            .padding(.leading, 1)
                            .padding(.trailing, 14)
                            .padding(.vertical, 3)
                        }
                        .mask(
                            HStack(spacing: 0) {
                                Color.black
                                LinearGradient(
                                    colors: [.black, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 16)
                            }
                        )
                    }

                    if let activeAcc = model.activeAccount {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(p.accountDotColor(activeAcc.id))
                                .frame(width: 5.5, height: 5.5)
                            Text(activeAcc.address)
                                .font(.system(size: 11))
                                .foregroundStyle(p.ink3)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.top, 5)
            }

            // 3. 搜索与命令入口（展开态为独立交互式 Liquid Glass 胶囊，呼应中央 ⌘K 命令面板）
            searchTriggerBar
                .padding(.top, 8)

            // 4. 分拣导航树（保持安静哑光，不做花哨玻璃行）
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

            // 5. 底部控制胶囊簇（极简无冗余统计文案）
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                footerControlsCluster
            }
            .frame(height: 30)
            .padding(.trailing, 1)
        }
        .padding(.horizontal, 10)
        .padding(.top, isPeek ? 8 : 4)
        .padding(.bottom, isPeek ? 10 : 8)
        .frame(width: 206)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var searchTriggerBar: some View {
        let button = Button {
            onDismissPeek?()
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

        if isPeek {
            button
                .background(
                    Capsule()
                        .fill(p.ink.opacity(searchHovered ? (p.mode == .dark ? 0.12 : 0.07) : (p.mode == .dark ? 0.08 : 0.048)))
                )
        } else {
            button
                .deckGlassCapsule(interactive: true)
        }
    }

    @ViewBuilder
    private var footerControlsCluster: some View {
        let cluster = HStack(spacing: 1) {
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
                onDismissPeek?()
                model.perform(.openSettings(nil))
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)

        if isPeek {
            cluster
                .background(Capsule().fill(p.ink.opacity(p.mode == .dark ? 0.08 : 0.048)))
        } else {
            cluster
                .deckGlassCapsule(interactive: true)
        }
    }

    @ViewBuilder
    private var sidebarToggleButton: some View {
        let btn = Button {
            onDismissPeek?()
            model.perform(.toggleSidebar)
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(toggleHovered ? p.ink : p.ink3)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.snappy(duration: 0.16)) {
                toggleHovered = hovering
            }
        }
        .help(isPeek ? "固定展开侧边栏（[）" : "收起侧边栏（[）")

        if isPeek {
            btn.background(
                Circle()
                    .fill(toggleHovered ? p.ink.opacity(p.mode == .dark ? 0.11 : 0.06) : .clear)
            )
        } else if toggleHovered {
            btn.deckGlassCapsule(interactive: true)
        } else {
            btn
        }
    }
}

private struct AccountScopeTab: View {
    @Environment(\.palette) private var p
    let label: String
    let dotColor: Color?
    let active: Bool
    let useLiquidGlass: Bool
    let namespace: Namespace.ID
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        let pill = Button(action: onTap) {
            HStack(spacing: 5) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(size: 11.5, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? p.ink : (hovered ? p.ink2 : p.ink3))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(height: 25)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }

        if active {
            if useLiquidGlass {
                pill
                    .deckGlassCapsule(interactive: true)
                    .deckGlassID("active-account-scope", in: namespace)
            } else {
                pill
                    .background(
                        Capsule()
                            .fill(p.ink.opacity(p.mode == .dark ? 0.14 : 0.08))
                            .matchedGeometryEffect(id: "peek-account-scope", in: namespace)
                    )
            }
        } else {
            pill
                .background(
                    Capsule()
                        .fill(hovered ? p.ink.opacity(p.mode == .dark ? 0.07 : 0.038) : .clear)
                )
        }
    }
}

private struct SidebarFolderRow: View {
    @Environment(\.palette) private var p
    let def: FolderDef
    let count: Int
    let active: Bool
    let onTap: () -> Void
    @State private var hovered = false

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
                    .fill(active ? p.ink.opacity(p.mode == .dark ? 0.11 : 0.068) : (hovered ? p.ink.opacity(0.036) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct IconFooterButton: View {
    @Environment(\.palette) private var p
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hovered ? p.ink : p.ink3)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(hovered ? p.ink.opacity(p.mode == .dark ? 0.12 : 0.065) : .clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

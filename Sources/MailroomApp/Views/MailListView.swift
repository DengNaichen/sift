import SwiftUI
import MailroomCore

struct MailListView: View {
    @Environment(\.palette) private var p
    let vm: DeckViewModel

    private var folderTitle: String {
        FolderDef.all.first(where: { $0.id == vm.state.folder })?.label ?? "邮件"
    }

    private var showAccountBadge: Bool {
        vm.accounts.count > 1 && vm.state.accountScope == .all
    }

    var body: some View {
        VStack(spacing: 0) {
            // 列表栏顶：44pt 与右侧阅读工具栏严格对齐
            HStack(spacing: 8) {
                if vm.sidebarCollapsed {
                    Button {
                        vm.toggleSidebar()
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(p.ink3)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("展开侧边栏（[）")
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                Text(folderTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(p.ink)
                    .lineLimit(1)

                Text("\(vm.visibleRows.count)")
                    .font(.system(size: 11.5, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(p.ink3)

                Spacer()

                if let acc = vm.activeAccount {
                    Button {
                        vm.setAccountScope(.all)
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(p.accountDotColor(acc.id))
                                .frame(width: 5.5, height: 5.5)
                            Text(acc.label)
                                .font(.system(size: 11))
                                .foregroundStyle(p.ink2)
                            Image(systemName: "xmark")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(p.ink3)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(p.sunken, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("点击恢复全部邮箱")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .frame(height: 44)

            if vm.visibleRows.isEmpty {
                VStack {
                    Spacer()
                    Text(vm.state.folder.isInboxFolder ? "队列已清空 ✨" : "当前列表为空")
                        .font(.system(size: 12.5))
                        .foregroundStyle(p.ink3)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.visibleRows) { row in
                                let selected = (row.id == vm.state.focusId)
                                let unread = row.isInboxOrKept && !vm.state.readIds.contains(row.id)
                                MailListRowView(
                                    row: row,
                                    selected: selected,
                                    unread: unread,
                                    showAccountBadge: showAccountBadge,
                                    onSelect: {
                                        vm.selectRow(row.id)
                                    },
                                    onQuickAction: { action in
                                        vm.actOnCard(action, id: row.id)
                                    },
                                    onQuickRescue: {
                                        vm.rescueRow(row.id)
                                    }
                                )
                                .id(row.id)
                            }
                        }
                        .padding(.vertical, 4)
                        .borderlessScroller()
                    }
                    .onChange(of: vm.state.focusId) { _, newId in
                        guard let newId else { return }
                        withAnimation(.snappy(duration: 0.16)) {
                            proxy.scrollTo(newId, anchor: nil)
                        }
                    }
                }
            }
        }
        .frame(width: 352)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(p.paper)
        .overlay(alignment: .trailing) {
            Rectangle().fill(p.line).frame(width: 1)
        }
    }
}

private struct MailListRowView: View {
    @Environment(\.palette) private var p
    let row: FolderRow
    let selected: Bool
    let unread: Bool
    let showAccountBadge: Bool
    let onSelect: () -> Void
    let onQuickAction: (CardAction) -> Void
    let onQuickRescue: () -> Void

    @State private var isHovered = false

    private var content: MailContent { row.content }

    private var evidence: String? {
        switch row {
        case .inbox(let mail), .kept(let mail):
            return Excerpt.evidenceOf(mail)
        case .handled:
            return nil
        }
    }

    private var previewText: String {
        let raw = evidence ?? Excerpt.openingLines(content.plainText, maxLength: 96)
        return raw.isEmpty ? "（无正文摘要）" : raw
    }

    private var timestamp: Date {
        switch row {
        case .handled(let item): return item.handledAt
        case .inbox, .kept: return content.receivedAt
        }
    }

    private var leadingDotColor: Color? {
        if unread {
            return p.cobalt
        }
        switch row {
        case .inbox(let mail), .kept(let mail):
            return p.kindDotColor(mail.meta.kind).opacity(0.45)
        case .handled:
            return nil
        }
    }

    private var showHoverActions: Bool {
        guard isHovered else { return false }
        switch row {
        case .inbox, .handled: return true
        case .kept: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 第 1 行：色相/未读点 + 发件人 + 极简账号名 + 悬停快捷操作/时间
            HStack(spacing: 5.5) {
                if let dot = leadingDotColor {
                    Circle()
                        .fill(dot)
                        .frame(width: 6, height: 6)
                }

                Text(content.from.name)
                    .font(.system(
                        size: 13,
                        weight: unread ? .semibold : (row.isInboxOrKept ? .medium : .regular)
                    ))
                    .foregroundStyle(row.isInboxOrKept ? p.ink : p.ink2)
                    .lineLimit(1)

                if showAccountBadge {
                    Text("· \(content.account.label)")
                        .font(.system(size: 11))
                        .foregroundStyle(p.ink3)
                        .lineLimit(1)
                }

                if case .kept = row {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(p.amber)
                }

                Spacer(minLength: 4)

                if showHoverActions {
                    HStack(spacing: 3) {
                        switch row {
                        case .inbox:
                            QuickRowIconButton(systemName: "checkmark", help: "阅毕归档（Space）") {
                                onQuickAction(.archive)
                            }
                            QuickRowIconButton(systemName: "flag", help: "重要保留（⇧K）") {
                                onQuickAction(.keep)
                            }
                            QuickRowIconButton(systemName: "trash", help: "判为推广（⌫）") {
                                onQuickAction(.trash)
                            }
                        case .handled:
                            QuickRowIconButton(systemName: "arrow.uturn.backward", help: "拉回待处理（R）") {
                                onQuickRescue()
                            }
                        case .kept:
                            EmptyView()
                        }
                    }
                } else {
                    if !content.attachments.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 10.5))
                            if content.attachments.count > 1 {
                                Text("\(content.attachments.count)")
                                    .font(.system(size: 10.5, design: .monospaced))
                            }
                        }
                        .foregroundStyle(p.ink3)
                    }

                    Text(MailFormatting.formatTime(timestamp))
                        .font(.system(size: 11, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(p.ink3)
                }
            }
            .frame(height: 18)

            // 第 2 行：整行完整留给邮件主题，不再被大徽标挤压
            Text(content.subject)
                .font(.system(
                    size: 12.5,
                    weight: unread ? .semibold : (row.isInboxOrKept ? .medium : .regular)
                ))
                .foregroundStyle(row.isInboxOrKept ? p.ink : p.ink2)
                .lineLimit(1)

            // 第 3 行：精炼单行摘要 + 右下角已处理分类微标
            HStack(spacing: 6) {
                Text(previewText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.ink3)
                    .lineLimit(1)

                Spacer(minLength: 0)

                trailingMicroPill
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if selected {
                FluidSilkRowBackground()
            } else if isHovered {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(p.hoverFill)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var trailingMicroPill: some View {
        switch row {
        case .inbox, .kept:
            EmptyView()
        case .handled(let item):
            Text(item.category)
                .font(.system(size: 10))
                .foregroundStyle(p.ink3)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(p.sunken, in: RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        }
    }
}

private struct QuickRowIconButton: View {
    @Environment(\.palette) private var p
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(hovered ? p.cobalt : p.ink2)
                .frame(width: 22, height: 19)
                .background(p.paper, in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .strokeBorder(hovered ? p.cobalt : p.lineStrong, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovered = $0 }
    }
}

import Foundation
import MailroomCore

/// 列表中一行的展示模型：选中 / 未读 / 账号角标 / 摘要 / 时间戳均已在此算好。
struct MailListRowModel: Identifiable, Equatable {
    let row: FolderRow
    let selected: Bool
    let unread: Bool
    let showAccountBadge: Bool

    var id: MessageId { row.id }
    var content: MailContent { row.content }

    /// 收件箱 / 保留邮件优先展示 AI 原句引证，否则取正文开头
    var previewText: String {
        let evidence: String?
        switch row {
        case .inbox(let mail), .kept(let mail):
            evidence = Excerpt.evidenceOf(mail)
        case .handled:
            evidence = nil
        }
        let raw = evidence ?? Excerpt.openingLines(content.plainText, maxLength: 96)
        return raw.isEmpty ? "（无正文摘要）" : raw
    }

    /// 已处理邮件显示处理时间，其余显示收信时间
    var timestamp: Date {
        switch row {
        case .handled(let item): return item.handledAt
        case .inbox, .kept: return content.receivedAt
        }
    }

    var timestampText: String { MailFormatting.formatTime(timestamp) }
}

/// 中栏邮件列表
@MainActor
struct MailListViewModel {
    let app: AppModel
    private var deck: DeckStore { app.deck }

    var sidebarCollapsed: Bool { app.shell.sidebarCollapsed }

    var folderTitle: String {
        FolderDef.all.first(where: { $0.id == deck.state.folder })?.label ?? "邮件"
    }

    var rowCount: Int { deck.visibleRows.count }
    var isEmpty: Bool { deck.visibleRows.isEmpty }
    var emptyText: String { deck.state.folder.isInboxFolder ? "队列已清空 ✨" : "当前列表为空" }
    var activeAccount: MailAccount? { deck.activeAccount }
    var focusId: MessageId? { deck.state.focusId }

    var rows: [MailListRowModel] {
        let state = deck.state
        let showAccountBadge = deck.accounts.count > 1 && state.accountScope == .all
        return deck.visibleRows.map { row in
            MailListRowModel(
                row: row,
                selected: row.id == state.focusId,
                unread: row.isInboxOrKept && !state.readIds.contains(row.id),
                showAccountBadge: showAccountBadge
            )
        }
    }

    func perform(_ command: DeckCommand) { app.perform(command) }
}

import Foundation

public enum CardAction: String, Equatable, Sendable {
    case archive
    case keep
    case trash
}

public enum FolderId: String, Equatable, Hashable, CaseIterable, Sendable, Identifiable {
    case inbox = "inbox"
    case inboxHuman = "inbox:human"
    case inboxStakes = "inbox:stakes"
    case inboxUncertain = "inbox:uncertain"
    case kept = "kept"
    case archived = "archived"
    case trashed = "trashed"

    public var id: String { rawValue }

    public var isInboxFolder: Bool {
        switch self {
        case .inbox, .inboxHuman, .inboxStakes, .inboxUncertain:
            return true
        case .kept, .archived, .trashed:
            return false
        }
    }
}

public enum FolderGroup: String, Equatable, Sendable {
    case triage
    case processed
}

public struct FolderDef: Equatable, Sendable, Identifiable {
    public let id: FolderId
    public let group: FolderGroup
    public let label: String
    public let shortcut: String?
    public let isSub: Bool

    public static let all: [FolderDef] = [
        FolderDef(id: .inbox, group: .triage, label: "全部待处理", shortcut: "1", isSub: false),
        FolderDef(id: .inboxHuman, group: .triage, label: "真人来信", shortcut: nil, isSub: true),
        FolderDef(id: .inboxStakes, group: .triage, label: "合同 · 账单 · 条款", shortcut: nil, isSub: true),
        FolderDef(id: .inboxUncertain, group: .triage, label: "待你拍板", shortcut: nil, isSub: true),
        FolderDef(id: .kept, group: .processed, label: "重要保留", shortcut: nil, isSub: false),
        FolderDef(id: .archived, group: .processed, label: "已自动归档", shortcut: "2", isSub: false),
        FolderDef(id: .trashed, group: .processed, label: "废纸篓", shortcut: "3", isSub: false),
    ]
}

public enum AccountScope: Equatable, Hashable, Sendable {
    case all
    case account(String)
}

public enum FolderRow: Equatable, Sendable, Identifiable {
    case inbox(MailItem)
    case kept(MailItem)
    case handled(HandledItem)

    public var id: MessageId { content.id }

    public var content: MailContent {
        switch self {
        case .inbox(let mail), .kept(let mail):
            return mail.content
        case .handled(let item):
            return item.content
        }
    }

    public var isInboxOrKept: Bool {
        switch self {
        case .inbox, .kept: return true
        case .handled: return false
        }
    }
}

public enum UndoEntry: Equatable, Sendable {
    case card(action: CardAction, mail: MailItem, index: Int, folder: FolderId)
    case rescue(item: HandledItem, mail: MailItem, folder: FolderId)

    public var descriptionText: String {
        switch self {
        case .rescue(_, let mail, _):
            return "已拉回待处理「\(mail.subject)」"
        case .card(let action, let mail, _, _):
            switch action {
            case .archive: return "已归档「\(mail.subject)」"
            case .keep: return "已标为重要保留「\(mail.subject)」"
            case .trash: return "已判为推广，移入废纸篓「\(mail.subject)」"
            }
        }
    }
}

public struct Tally: Equatable, Sendable {
    public var archived: Int = 0
    public var kept: Int = 0
    public var trashed: Int = 0
    public var rescued: Int = 0

    public init(archived: Int = 0, kept: Int = 0, trashed: Int = 0, rescued: Int = 0) {
        self.archived = archived
        self.kept = kept
        self.trashed = trashed
        self.rescued = rescued
    }
}

public enum ToastKind: Equatable, Sendable {
    case done
    case undone
}

public struct DeckToast: Equatable, Sendable {
    public let seq: Int
    public let kind: ToastKind
    public let entry: UndoEntry
}

public struct DeckState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case loading
        case ready
    }

    public var phase: Phase = .loading
    public var folder: FolderId = .inbox
    public var accountScope: AccountScope = .all
    public var queue: [MailItem] = []
    public var kept: [MailItem] = []
    public var handled: [HandledItem] = []
    public var readIds: Set<MessageId> = []
    public var focusId: MessageId? = nil
    public var undo: [UndoEntry] = []
    public var tally: Tally = Tally()
    public var toast: DeckToast? = nil
    public var seq: Int = 0

    public init() {}

    public static func orderHandled(_ list: [HandledItem]) -> [HandledItem] {
        list.sorted { a, b in
            let rankA = a.disposition == .archived ? 0 : 1
            let rankB = b.disposition == .archived ? 0 : 1
            if rankA != rankB { return rankA < rankB }
            return a.handledAt > b.handledAt
        }
    }

    public static func matchesAccount(_ content: MailContent, scope: AccountScope) -> Bool {
        switch scope {
        case .all: return true
        case .account(let id): return content.account.id == id
        }
    }

    public func rows(for targetFolder: FolderId, scope: AccountScope) -> [FolderRow] {
        switch targetFolder {
        case .inbox:
            return queue
                .filter { Self.matchesAccount($0.content, scope: scope) }
                .map { .inbox($0) }
        case .inboxHuman:
            return queue
                .filter { Self.matchesAccount($0.content, scope: scope) && $0.meta.kind == .human }
                .map { .inbox($0) }
        case .inboxStakes:
            return queue
                .filter {
                    Self.matchesAccount($0.content, scope: scope)
                    && [.policy, .contract, .billing].contains($0.meta.kind)
                }
                .map { .inbox($0) }
        case .inboxUncertain:
            return queue
                .filter {
                    Self.matchesAccount($0.content, scope: scope)
                    && ($0.meta.kind == .uncertain || $0.meta.kind == .rescued)
                }
                .map { .inbox($0) }
        case .kept:
            return kept
                .filter { Self.matchesAccount($0.content, scope: scope) }
                .map { .kept($0) }
        case .archived:
            return handled
                .filter { Self.matchesAccount($0.content, scope: scope) && $0.disposition == .archived }
                .map { .handled($0) }
        case .trashed:
            return handled
                .filter { Self.matchesAccount($0.content, scope: scope) && $0.disposition == .trashed }
                .map { .handled($0) }
        }
    }

    public var visibleRows: [FolderRow] {
        rows(for: folder, scope: accountScope)
    }

    public var folderCounts: [FolderId: Int] {
        var result: [FolderId: Int] = [:]
        for f in FolderId.allCases {
            result[f] = rows(for: f, scope: accountScope).count
        }
        return result
    }

    public var accounts: [MailAccount] {
        var seen = Set<String>()
        var ordered: [MailAccount] = []
        for m in queue where seen.insert(m.account.id).inserted { ordered.append(m.account) }
        for m in kept where seen.insert(m.account.id).inserted { ordered.append(m.account) }
        for h in handled where seen.insert(h.account.id).inserted { ordered.append(h.account) }
        return ordered
    }
}

public enum DeckEvent: Sendable {
    case loaded(DeckSnapshot)
    /// 外部同步（FSEvents 增量更新：保留会话内 kept / undo / tally，更新未读与进出项）
    case externalSynced(DeckSnapshot)
    case folder(FolderId)
    case accountScope(AccountScope)
    case card(id: MessageId, action: CardAction, now: Date)
    case rescued(MailItem)
    case undo
    case incoming([MailItem])
    case focus(MessageId)
    case moveFocus(Int)
    case toastExpired(Int)
    case hydrated(MailContent)
}

public enum DeckReducer {
    public static func reduce(_ state: DeckState, _ event: DeckEvent) -> DeckState {
        var s = state
        switch event {
        case .loaded(let snapshot):
            var next = DeckState()
            next.phase = .ready
            next.folder = s.folder
            next.accountScope = s.accountScope
            next.queue = snapshot.queue
            next.kept = []
            next.handled = DeckState.orderHandled(snapshot.handled)
            next.seq = s.seq
            // 继承 Apple Mail 中原本已读的邮件 ID
            for item in snapshot.queue where item.content.isReadInMail {
                next.readIds.insert(item.id)
            }
            return markFocusedRead(next, focusId: reconcileFocus(next))

        case .externalSynced(let snapshot):
            guard s.phase == .ready else {
                return reduce(s, .loaded(snapshot))
            }
            let keptIds = Set(s.kept.map(\.id))
            let manualTrashed = s.handled.filter { $0.manual }
            let manualTrashedIds = Set(manualTrashed.map(\.id))

            s.queue = snapshot.queue.filter { !keptIds.contains($0.id) && !manualTrashedIds.contains($0.id) }
            var mergedHandled = snapshot.handled.filter { !keptIds.contains($0.id) && !manualTrashedIds.contains($0.id) }
            mergedHandled.append(contentsOf: manualTrashed)
            s.handled = DeckState.orderHandled(mergedHandled)

            for item in s.queue where item.content.isReadInMail {
                s.readIds.insert(item.id)
            }
            return markFocusedRead(s, focusId: reconcileFocus(s))

        case .folder(let folder):
            guard s.folder != folder else { return s }
            s.folder = folder
            return markFocusedRead(s, focusId: reconcileFocus(s))

        case .accountScope(let scope):
            guard s.accountScope != scope else { return s }
            s.accountScope = scope
            return markFocusedRead(s, focusId: reconcileFocus(s))

        case .card(let id, let action, let now):
            guard let queueIndex = s.queue.firstIndex(where: { $0.id == id }) else { return s }
            let mail = s.queue[queueIndex]
            let beforeRows = s.visibleRows
            let visIndex = beforeRows.firstIndex(where: { $0.id == id }) ?? 0

            s.queue.remove(at: queueIndex)
            if action == .keep {
                s.kept.removeAll { $0.id == id }
                s.kept.insert(mail, at: 0)
            } else if action == .trash {
                var nextHandled = s.handled
                nextHandled.append(MailAdapterFunctions.toManualHandled(mail, handledAt: now))
                s.handled = DeckState.orderHandled(nextHandled)
            }

            pushUndo(&s, entry: .card(action: action, mail: mail, index: queueIndex, folder: s.folder))
            bumpTally(&s.tally, action: action, by: 1)

            let afterRows = s.visibleRows
            let nextFocus = (s.focusId == id) ? focusAfterRemoval(afterRows, prevIndex: visIndex) : reconcileFocus(s)
            return markFocusedRead(s, focusId: nextFocus)

        case .rescued(let mail):
            guard let itemIndex = s.handled.firstIndex(where: { $0.id == mail.id }) else { return s }
            let item = s.handled[itemIndex]
            let beforeRows = s.visibleRows
            let visIndex = beforeRows.firstIndex(where: { $0.id == item.id }) ?? 0

            s.handled.remove(at: itemIndex)
            s.queue.removeAll { $0.id == mail.id }
            s.queue.append(mail)
            s.readIds.remove(mail.id)

            pushUndo(&s, entry: .rescue(item: item, mail: mail, folder: s.folder))
            s.tally.rescued += 1

            let afterRows = s.visibleRows
            let nextFocus = (s.focusId == item.id) ? focusAfterRemoval(afterRows, prevIndex: visIndex) : reconcileFocus(s)
            return markFocusedRead(s, focusId: nextFocus)

        case .undo:
            guard let entry = s.undo.popLast() else { return s }
            s.seq += 1
            s.toast = DeckToast(seq: s.seq, kind: .undone, entry: entry)

            switch entry {
            case .card(let action, let mail, let index, let prevFolder):
                if !DeckState.matchesAccount(mail.content, scope: s.accountScope) {
                    s.accountScope = .all
                }
                s.folder = prevFolder.isInboxFolder ? prevFolder : .inbox
                let insertPos = min(max(0, index), s.queue.count)
                s.queue.insert(mail, at: insertPos)
                if action == .keep {
                    s.kept.removeAll { $0.id == mail.id }
                } else if action == .trash {
                    s.handled.removeAll { $0.id == mail.id }
                }
                bumpTally(&s.tally, action: action, by: -1)
                s.focusId = mail.id
                s.focusId = reconcileFocus(s)
                return s

            case .rescue(let item, let mail, _):
                if !DeckState.matchesAccount(item.content, scope: s.accountScope) {
                    s.accountScope = .all
                }
                s.folder = item.disposition == .archived ? .archived : .trashed
                s.queue.removeAll { $0.id == mail.id }
                var nextHandled = s.handled
                nextHandled.append(item)
                s.handled = DeckState.orderHandled(nextHandled)
                s.tally.rescued = max(0, s.tally.rescued - 1)
                s.focusId = item.id
                s.focusId = reconcileFocus(s)
                return s
            }

        case .incoming(let mails):
            s.queue.append(contentsOf: mails)
            return markFocusedRead(s, focusId: reconcileFocus(s))

        case .focus(let id):
            return markFocusedRead(s, focusId: id)

        case .moveFocus(let delta):
            let rows = s.visibleRows
            guard !rows.isEmpty else { return s }
            let cur = max(0, rows.firstIndex(where: { $0.id == s.focusId }) ?? 0)
            let targetIndex = min(rows.count - 1, max(0, cur + delta))
            return markFocusedRead(s, focusId: rows[targetIndex].id)

        case .toastExpired(let seq):
            if s.toast?.seq == seq {
                s.toast = nil
            }
            return s

        case .hydrated(let updatedContent):
            let targetId = updatedContent.id
            if let qIdx = s.queue.firstIndex(where: { $0.id == targetId }) {
                s.queue[qIdx].content = updatedContent
            }
            if let kIdx = s.kept.firstIndex(where: { $0.id == targetId }) {
                s.kept[kIdx].content = updatedContent
            }
            if let hIdx = s.handled.firstIndex(where: { $0.id == targetId }) {
                s.handled[hIdx].content = updatedContent
            }
            return s
        }
    }

    private static func pushUndo(_ s: inout DeckState, entry: UndoEntry) {
        s.seq += 1
        s.undo.append(entry)
        if s.undo.count > 50 {
            s.undo.removeFirst(s.undo.count - 50)
        }
        s.toast = DeckToast(seq: s.seq, kind: .done, entry: entry)
    }

    private static func bumpTally(_ tally: inout Tally, action: CardAction, by delta: Int) {
        switch action {
        case .archive: tally.archived = max(0, tally.archived + delta)
        case .keep: tally.kept = max(0, tally.kept + delta)
        case .trash: tally.trashed = max(0, tally.trashed + delta)
        }
    }

    private static func focusAfterRemoval(_ rows: [FolderRow], prevIndex: Int) -> MessageId? {
        guard !rows.isEmpty else { return nil }
        let idx = min(max(0, prevIndex), rows.count - 1)
        return rows[idx].id
    }

    private static func reconcileFocus(_ s: DeckState) -> MessageId? {
        let rows = s.visibleRows
        guard !rows.isEmpty else { return nil }
        if let f = s.focusId, rows.contains(where: { $0.id == f }) {
            return f
        }
        return rows[0].id
    }

    private static func markFocusedRead(_ state: DeckState, focusId: MessageId?) -> DeckState {
        var s = state
        s.focusId = focusId
        guard let focusId,
              s.folder.isInboxFolder || s.folder == .kept,
              !s.readIds.contains(focusId) else {
            return s
        }
        s.readIds.insert(focusId)
        return s
    }
}

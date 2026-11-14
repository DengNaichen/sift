import AppKit
import Foundation

public enum MailAccessStatus: Equatable, Sendable {
    case ready(mailDir: String)
    case fullDiskAccessRequired(expectedPath: String)
    case mailStoreNotFound
}

public enum MailStoreEnvironment {
    public static func locateMailVDirectory() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let mailRoot = home.appendingPathComponent("Library/Mail", isDirectory: true)
        if let items = try? FileManager.default.contentsOfDirectory(
            at: mailRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let vDirs = items
                .filter { $0.lastPathComponent.hasPrefix("V") }
                .sorted { lhs, rhs in
                    let lNum = Int(lhs.lastPathComponent.dropFirst()) ?? 0
                    let rNum = Int(rhs.lastPathComponent.dropFirst()) ?? 0
                    return lNum < rNum
                }
            if let highest = vDirs.last {
                return highest
            }
        }
        // 若 Library/Mail 被 TCC 拦截导致无法列目录，默认探测现代 macOS 常用的 V10
        let fallbackV10 = mailRoot.appendingPathComponent("V10", isDirectory: true)
        return fallbackV10
    }

    public static func checkAccess() -> MailAccessStatus {
        guard let vDir = locateMailVDirectory() else {
            return .mailStoreNotFound
        }
        let indexPath = vDir.appendingPathComponent("MailData/Envelope Index").path
        do {
            let conn = try SQLiteConnection(readOnlyPath: indexPath)
            _ = try conn.query("SELECT 1 FROM mailboxes LIMIT 1") { $0.int64(0) }
            return .ready(mailDir: vDir.path)
        } catch {
            return .fullDiskAccessRequired(expectedPath: indexPath)
        }
    }

    @MainActor
    public static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 真实接入 macOS Apple Mail 的双向适配器：
/// - 读路径：只读连接 `Envelope Index` (WAL) + `.emlx` 解析 + 本地增量 SQLite 缓存
/// - 同步路径：`FSEvents` 监听 `MailData` 变化 + 防回声窗口
/// - 写路径：按 `(accountUUID, mailboxPath, ROWID)` 精准驱动 Apple Mail
public actor AppleMailAdapter: MailAdapter {
    public nonisolated let sourceLabel: String = "Apple Mail"
    public nonisolated let supportsDemoControls: Bool = false

    private struct ResolvedAccount {
        let uuid: String
        let mailAccount: MailAccount
        let inboxMailboxes: [(rowId: Int64, asPath: String)]
        let primaryInboxPath: String
        let archivePath: String?
        let trashPath: String?
    }

    private struct MailboxRecord {
        let rowId: Int64
        let scheme: String
        let accountUUID: String
        let decodedPath: String
        let totalCount: Int64
    }

    private struct LocatedMessage {
        let rowId: Int64
        let accountUUID: String
        let physicalMailboxId: Int64
        let physicalMailboxPath: String
        let inboxPath: String
        let wasRead: Bool
        let wasFlagged: Bool
    }

    private let mailVDir: URL
    private let classifier: any MailClassifier
    private let scriptExecutor: any AppleMailExecutor
    private let mutationLedger: MutationLedger
    private let accountsDBPath: String?
    private let extraOwnerAddresses: Set<String>
    private let maxInboxFetch: Int

    private var cacheDB: SQLiteConnection?
    private var mboxDataRootCache: [Int64: URL] = [:]
    private var mailboxesById: [Int64: MailboxRecord] = [:]
    private var accountsByUUID: [String: ResolvedAccount] = [:]
    private var sentMailboxIds: Set<Int64> = []
    private var ownerAddresses: Set<String> = []
    private var liveLocations: [MessageId: LocatedMessage] = [:]
    private var liveContents: [MessageId: MailContent] = [:]
    private var handledItemsCache: [MessageId: HandledItem] = [:]
    private var rescuedToQueueIds: Set<MessageId> = []
    private var lastMutationAt: Date = .distantPast
    private var lastObservedDataVersion: Int64 = -1

    private var watcher: MailDirectoryWatcher?
    private var changeContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    public static func defaultAccountsDBPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Accounts/Accounts4.sqlite")
            .path
    }

    public init(
        mailVDir: URL? = MailStoreEnvironment.locateMailVDirectory(),
        classifier: any MailClassifier = RuleBasedClassifier(),
        maxInboxFetch: Int = 80,
        scriptExecutor: any AppleMailExecutor = AppleMailScriptRunner(),
        cacheDBPath: String? = nil,
        mutationLedgerDBPath: String? = nil,
        accountsDBPath: String? = AppleMailAdapter.defaultAccountsDBPath(),
        ownerAddresses: Set<String> = [],
        echoSuppressionWindow: TimeInterval = 15.0,
        inFlightTimeout: TimeInterval = 60.0
    ) throws {
        guard let dir = mailVDir else {
            throw SQLiteError.openFailed("未找到 ~/Library/Mail/V* 目录")
        }
        self.mailVDir = dir
        self.classifier = classifier
        self.scriptExecutor = scriptExecutor
        self.maxInboxFetch = maxInboxFetch
        self.accountsDBPath = accountsDBPath
        self.extraOwnerAddresses = Set(
            ownerAddresses
                .map(ConversationResolver.normalizeEmailAddress)
                .filter { !$0.isEmpty }
        )
        self.cacheDB = try Self.openOrCreateCacheDB(atPath: cacheDBPath)
        self.mutationLedger = try MutationLedger(
            dbPath: mutationLedgerDBPath ?? MutationLedger.defaultDatabasePath(),
            echoSuppressionWindow: echoSuppressionWindow,
            inFlightTimeout: inFlightTimeout
        )
    }

    private static func openOrCreateCacheDB(atPath customPath: String? = nil) throws -> SQLiteConnection {
        let dbPath: String
        if let customPath {
            dbPath = customPath
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            dbPath = appSupport
                .appendingPathComponent("MailroomDeck", isDirectory: true)
                .appendingPathComponent("bridge_cache_v1.sqlite")
                .path
        }
        let conn = try SQLiteConnection(readWritePath: dbPath)
        try? conn.execute("DROP TABLE IF EXISTS parsed_emlx_v2;")
        try conn.execute("""
            CREATE TABLE IF NOT EXISTS parsed_emlx_v3 (
                row_id INTEGER PRIMARY KEY,
                rfc_message_id TEXT NOT NULL,
                sender_name TEXT NOT NULL,
                sender_addr TEXT NOT NULL,
                to_json TEXT NOT NULL DEFAULT '[]',
                subject TEXT NOT NULL,
                date_header TEXT,
                plain_text TEXT NOT NULL,
                html_body TEXT,
                has_remote_images INTEGER NOT NULL DEFAULT 0,
                attachments_json TEXT NOT NULL,
                has_unsub INTEGER NOT NULL DEFAULT 0,
                has_list_id INTEGER NOT NULL DEFAULT 0,
                is_reply INTEGER NOT NULL DEFAULT 0,
                is_auto INTEGER NOT NULL DEFAULT 0,
                unloaded_html_images INTEGER NOT NULL DEFAULT 0,
                body_representation TEXT NOT NULL DEFAULT 'empty',
                is_boilerplate_stub INTEGER NOT NULL DEFAULT 0,
                body_is_image_only INTEGER NOT NULL DEFAULT 0,
                is_partial INTEGER NOT NULL DEFAULT 0,
                is_truncated INTEGER NOT NULL DEFAULT 0
            );
        """)
        try conn.execute("""
            CREATE TABLE IF NOT EXISTS triage_ledger (
                rfc_message_id TEXT PRIMARY KEY,
                state TEXT NOT NULL,
                updated_at REAL NOT NULL
            );
        """)
        return conn
    }

    // MARK: - Live Change Stream

    public nonisolated func externalChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let id = UUID()
            Task {
                await self.registerContinuation(id: id, continuation: continuation)
            }
            continuation.onTermination = { _ in
                Task {
                    await self.unregisterContinuation(id: id)
                }
            }
        }
    }

    private func registerContinuation(id: UUID, continuation: AsyncStream<Void>.Continuation) {
        changeContinuations[id] = continuation
        if watcher == nil {
            let mailDataPath = mailVDir.appendingPathComponent("MailData").path
            let w = MailDirectoryWatcher(watchedPath: mailDataPath) { [weak self] in
                guard let self else { return }
                Task {
                    await self.handleFilesystemNotification()
                }
            }
            watcher = w
            w.start()
        }
    }

    private func unregisterContinuation(id: UUID) {
        changeContinuations.removeValue(forKey: id)
        if changeContinuations.isEmpty {
            watcher?.stop()
            watcher = nil
        }
    }

    private func handleFilesystemNotification() {
        // 抑制由本进程刚发出的 AppleEvent 造成的回声刷新
        if Date().timeIntervalSince(lastMutationAt) < 2.2 {
            return
        }
        let indexPath = mailVDir.appendingPathComponent("MailData/Envelope Index").path
        if let conn = try? SQLiteConnection(readOnlyPath: indexPath),
           let ver = (try? conn.query("PRAGMA data_version;") { $0.int64(0) })?.first {
            // 注意：新建连接每次 data_version 恒为 1，因此改用 max(ROWID) + 未读总数指纹判断是否有实质变更
            let fingerprint = (try? conn.query(
                "SELECT COALESCE(MAX(ROWID), 0) * 100000 + COALESCE(SUM(unread_count), 0) FROM mailboxes;"
            ) { $0.int64(0) })?.first ?? ver
            let maxMsgId = (try? conn.query("SELECT COALESCE(MAX(ROWID), 0) FROM messages;") { $0.int64(0) })?.first ?? 0
            let combined = fingerprint &+ (maxMsgId &* 31)
            if lastObservedDataVersion == combined {
                return
            }
            lastObservedDataVersion = combined
        }
        for cont in changeContinuations.values {
            cont.yield(())
        }
    }

    // MARK: - Read Path: Envelope Index + .emlx

    public func fetchDeck() async throws -> DeckSnapshot {
        let indexPath = mailVDir.appendingPathComponent("MailData/Envelope Index").path
        let mailConn = try SQLiteConnection(readOnlyPath: indexPath)

        if accountsByUUID.isEmpty {
            try refreshAccountsAndMailboxes(using: mailConn)
        }

        let allInboxIds = accountsByUUID.values.flatMap { $0.inboxMailboxes.map(\.rowId) }
        guard !allInboxIds.isEmpty else {
            return DeckSnapshot(queue: [], handled: [])
        }

        let inClause = allInboxIds.map(String.init).joined(separator: ",")
        let inboxSet = Set(allInboxIds)

        struct RawRow {
            let rowId: Int64
            let physicalMailboxId: Int64
            let matchedInboxId: Int64?
            let conversationId: Int64
            let read: Bool
            let flagged: Bool
            let dateReceivedEpoch: Int64
            let sqlSubject: String
            let sqlSenderAddr: String
            let sqlSenderName: String
            let sqlSummary: String
            let hasListHash: Bool
            let hasUnsubType: Bool
            let sqlAutomated: Bool
        }

        let sql = """
        WITH inbox_candidates AS (
            SELECT ROWID AS rid, mailbox AS inbox_mb FROM messages WHERE mailbox IN (\(inClause)) AND deleted = 0
            UNION
            SELECT message_id AS rid, mailbox_id AS inbox_mb FROM labels WHERE mailbox_id IN (\(inClause))
        )
        SELECT m.ROWID,
               m.mailbox,
               ic.inbox_mb,
               COALESCE(m.conversation_id, 0),
               m.read,
               m.flagged,
               COALESCE(NULLIF(m.date_received, 0), m.date_sent, 0) AS recv_ts,
               COALESCE(s.subject, ''),
               COALESCE(a.address, ''),
               COALESCE(a.comment, ''),
               COALESCE(sm.summary, ''),
               m.list_id_hash,
               m.unsubscribe_type,
               COALESCE(m.automated_conversation, 0)
        FROM inbox_candidates ic
        JOIN messages m ON m.ROWID = ic.rid
        LEFT JOIN subjects s ON m.subject = s.ROWID
        LEFT JOIN addresses a ON m.sender = a.ROWID
        LEFT JOIN summaries sm ON m.summary = sm.ROWID
        WHERE m.deleted = 0
        ORDER BY recv_ts DESC
        LIMIT \(maxInboxFetch);
        """

        let rawRows = try mailConn.query(sql) { row in
            RawRow(
                rowId: row.int64(0),
                physicalMailboxId: row.int64(1),
                matchedInboxId: row.optionalInt64(2),
                conversationId: row.int64(3),
                read: row.int64(4) != 0,
                flagged: row.int64(5) != 0,
                dateReceivedEpoch: row.int64(6),
                sqlSubject: row.string(7) ?? "",
                sqlSenderAddr: row.string(8) ?? "",
                sqlSenderName: row.string(9) ?? "",
                sqlSummary: row.string(10) ?? "",
                hasListHash: row.optionalInt64(11) != nil,
                hasUnsubType: row.optionalInt64(12) != nil,
                sqlAutomated: row.int64(13) != 0
            )
        }

        struct ResolvedCandidate {
            let row: RawRow
            let inboxMb: MailboxRecord
            let physicalMbPath: String
            let resolvedAcc: ResolvedAccount
            let parsed: CachedMessagePayload
            let msgId: MessageId
        }

        var candidates: [ResolvedCandidate] = []
        candidates.reserveCapacity(rawRows.count)
        var observedStates: [ObservedInboxState] = []
        observedStates.reserveCapacity(rawRows.count)
        var seenMessageIds = Set<MessageId>()

        for r in rawRows {
            let effectiveInboxId = inboxSet.contains(r.physicalMailboxId)
                ? r.physicalMailboxId
                : (r.matchedInboxId ?? r.physicalMailboxId)

            guard let inboxMb = mailboxesById[effectiveInboxId],
                  let resolvedAcc = accountsByUUID[inboxMb.accountUUID] else {
                continue
            }
            let physicalMbPath = mailboxesById[r.physicalMailboxId]?.decodedPath ?? inboxMb.decodedPath

            let parsed = resolveMessageDetails(
                rowId: r.rowId,
                physicalMailboxId: r.physicalMailboxId,
                fallbackSubject: r.sqlSubject,
                fallbackSenderName: r.sqlSenderName,
                fallbackSenderAddr: r.sqlSenderAddr,
                fallbackSummary: r.sqlSummary,
                mailConn: mailConn
            )

            let msgId = MessageId(parsed.rfcMessageId)
            guard seenMessageIds.insert(msgId).inserted else { continue }

            observedStates.append(
                ObservedInboxState(
                    messageId: msgId.rawValue,
                    rowId: r.rowId,
                    mailboxPath: inboxMb.decodedPath,
                    isRead: r.read,
                    isFlagged: r.flagged,
                    isInInbox: true
                )
            )

            candidates.append(
                ResolvedCandidate(
                    row: r,
                    inboxMb: inboxMb,
                    physicalMbPath: physicalMbPath,
                    resolvedAcc: resolvedAcc,
                    parsed: parsed,
                    msgId: msgId
                )
            )
        }

        let reconciliation = try await mutationLedger.reconcile(observedInboxMessages: observedStates)
        for convergedId in reconciliation.convergedMessageIds {
            clearLedgerState(messageId: convergedId)
        }
        let ledgerStates = loadLedgerStates()

        var visibleCandidates: [ResolvedCandidate] = []
        visibleCandidates.reserveCapacity(candidates.count)
        for candidate in candidates {
            let r = candidate.row
            // 已标旗且已读的邮件代表「重要保留已处理」，不再进入待拍板队列
            if r.flagged && r.read {
                continue
            }
            if reconciliation.suppressedMessageIds.contains(candidate.msgId.rawValue) {
                continue
            }
            let ledger = ledgerStates[candidate.msgId.rawValue]
            if ledger == "archived" || ledger == "trashed" || ledger == "kept" {
                continue
            }
            visibleCandidates.append(candidate)
        }

        let convTargets = visibleCandidates.map {
            ConversationLookupTarget(
                rowId: $0.row.rowId,
                conversationId: $0.row.conversationId,
                receivedAtEpoch: $0.row.dateReceivedEpoch
            )
        }
        let convResolver = ConversationResolver(ownerAddresses: ownerAddresses)
        let convByRowId = (try? convResolver.resolve(targets: convTargets, using: mailConn) { rowId, mbId in
            self.cachedOrDiskPlainText(rowId: rowId, physicalMailboxId: mbId)
        }) ?? [:]

        var queue: [MailItem] = []
        var handled: [HandledItem] = []
        var emittedIds = Set<MessageId>()

        for candidate in visibleCandidates {
            let r = candidate.row
            let parsed = candidate.parsed
            let msgId = candidate.msgId
            let resolvedAcc = candidate.resolvedAcc
            let inboxMb = candidate.inboxMb
            let ledger = ledgerStates[msgId.rawValue]

            liveLocations[msgId] = LocatedMessage(
                rowId: r.rowId,
                accountUUID: resolvedAcc.uuid,
                physicalMailboxId: r.physicalMailboxId,
                physicalMailboxPath: candidate.physicalMbPath,
                inboxPath: inboxMb.decodedPath,
                wasRead: r.read,
                wasFlagged: r.flagged
            )

            let convCtx = convByRowId[r.rowId]
            let normalizedSender = ConversationResolver.normalizeEmailAddress(parsed.senderAddr)
            let isOwnerSender = !normalizedSender.isEmpty && ownerAddresses.contains(normalizedSender)
            let msgSentByOwner = sentMailboxIds.contains(r.physicalMailboxId) || isOwnerSender

            let receivedDate = r.dateReceivedEpoch > 0 ? Date(timeIntervalSince1970: TimeInterval(r.dateReceivedEpoch)) : Date()
            let content = MailContent(
                id: msgId,
                from: Sender(
                    name: parsed.senderName.isEmpty ? (parsed.senderAddr.components(separatedBy: "@").first ?? "未知发件人") : parsed.senderName,
                    address: parsed.senderAddr
                ),
                account: resolvedAcc.mailAccount,
                subject: parsed.subject.isEmpty ? "（无主题）" : parsed.subject,
                receivedAt: receivedDate,
                plainText: parsed.plainText.isEmpty ? "（该邮件正文尚未下载到本地，按 ↵ 可在 Apple Mail 中打开查看完整原信）" : parsed.plainText,
                attachments: parsed.attachments,
                isReadInMail: r.read,
                to: parsed.to,
                isFlaggedInMail: r.flagged,
                sentByOwner: msgSentByOwner,
                conversation: convCtx,
                bodyRepresentation: parsed.bodyRepresentation,
                isPartial: parsed.isPartial,
                isTruncated: parsed.isTruncated || (parsed.plainText.isEmpty && parsed.htmlBody == nil),
                unloadedHtmlImages: parsed.unloadedHtmlImages,
                bodyIsImageOnly: parsed.bodyIsImageOnly,
                htmlBody: parsed.htmlBody,
                hasRemoteImages: parsed.hasRemoteImages
            )
            liveContents[msgId] = content

            emittedIds.insert(msgId)

            if rescuedToQueueIds.contains(msgId) || ledger == "rescued" {
                let prevCat = handledItemsCache[msgId]?.category ?? "自动分拣"
                let prevProb = handledItemsCache[msgId]?.probability ?? 0.92
                queue.append(
                    MailItem(
                        content: content,
                        meta: DecisionMeta(
                            kind: .rescued,
                            badge: "你拉回的 · 原判\(prevCat)",
                            confidence: prevProb
                        )
                    )
                )
                continue
            }

            let outcome = classifier.classify(
                RawMailSignals(
                    content: content,
                    hasListUnsubscribe: parsed.hasUnsub || r.hasUnsubType,
                    hasListId: parsed.hasListId || r.hasListHash,
                    isReply: parsed.isReply,
                    isAutoSubmitted: parsed.isAuto,
                    sqlAutomatedFlag: r.sqlAutomated,
                    conversation: convCtx,
                    sentByOwner: msgSentByOwner,
                    isPartial: parsed.isPartial,
                    isTruncated: parsed.isTruncated || parsed.plainText.isEmpty,
                    unloadedHtmlImages: parsed.unloadedHtmlImages,
                    bodyIsImageOnly: parsed.bodyIsImageOnly,
                    isFlagged: r.flagged,
                    isBoilerplateStub: parsed.isBoilerplateStub
                )
            )

            switch outcome {
            case .triage(let meta):
                queue.append(MailItem(content: content, meta: meta))
            case .autoHandled(let disposition, let category, let probability):
                // Shadow Triage：自动判为通知/推广的收件箱邮件归入「已分拣」视图供检视或拉回，不擅自篡改真邮箱
                let item = HandledItem(
                    content: content,
                    disposition: disposition,
                    category: category,
                    probability: probability,
                    handledAt: receivedDate,
                    manual: false
                )
                handledItemsCache[msgId] = item
                handled.append(item)
            }
        }

        // 若刚刚拉回待处理的邮件正等待 Envelope Index 收敛，保留在队列中防止界面闪跳
        for awaitingIdRaw in reconciliation.awaitingInboxMessageIds {
            let awaitingId = MessageId(awaitingIdRaw)
            guard !emittedIds.contains(awaitingId),
                  let handledItem = handledItemsCache[awaitingId],
                  rescuedToQueueIds.contains(awaitingId) || ledgerStates[awaitingIdRaw] == "rescued" else {
                continue
            }
            queue.append(MailAdapterFunctions.rescuedCard(from: handledItem))
            emittedIds.insert(awaitingId)
        }

        return DeckSnapshot(queue: queue, handled: handled)
    }

    // MARK: - Write Path (AppleScript + Persistent MutationLedger + ROWID Re-Resolution)

    public func undoRecord(for id: MessageId) async -> UndoRecord? {
        try? await mutationLedger.undoRecord(for: id.rawValue)
    }

    public func archive(id: MessageId) async throws {
        guard let loc = liveLocations[id],
              let acc = accountsByUUID[loc.accountUUID] else {
            throw AppleMailScriptError.messageNotFound(id.rawValue)
        }
        let targetArchive = acc.archivePath ?? "Archive"
        let createIfMissing = (acc.archivePath == nil)
        let maxRowBefore = currentMaxRowId()

        let undo = UndoRecord(
            messageId: id.rawValue,
            action: .archived,
            accountUUID: acc.uuid,
            inboxPath: loc.inboxPath,
            targetMailboxPath: targetArchive,
            previousRead: loc.wasRead,
            previousFlagged: loc.wasFlagged,
            lastKnownRowId: loc.rowId,
            maxRowIdBeforeMove: maxRowBefore
        )

        lastMutationAt = Date()
        let pending = try await mutationLedger.beginMutation(
            rfcMessageId: id.rawValue,
            action: .archive,
            accountUUID: acc.uuid,
            sourceMailbox: loc.inboxPath,
            destinationMailbox: targetArchive,
            inboxPath: loc.inboxPath,
            expectedRead: true,
            expectedFlagged: nil,
            preMoveRowId: loc.rowId,
            maxRowIdBeforeMove: maxRowBefore,
            undoRecord: undo
        )
        saveLedgerState(messageId: id.rawValue, state: "archived")

        do {
            try await scriptExecutor.moveMessage(
                accountUUID: acc.uuid,
                sourceMailboxes: [loc.inboxPath, loc.physicalMailboxPath],
                destinationMailbox: targetArchive,
                createDestinationIfMissing: createIfMissing,
                rowId: loc.rowId,
                rfcMessageId: id.rawValue,
                markRead: true,
                markFlagged: nil
            )
        } catch {
            try? await mutationLedger.markFailed(
                mutationId: pending.mutationId,
                error: error.localizedDescription,
                rollbackUndoRecord: true
            )
            clearLedgerState(messageId: id.rawValue)
            throw error
        }

        let newRowId = findMovedRowId(
            rfcMessageId: id.rawValue,
            afterRowId: maxRowBefore,
            fallbackRowId: nil
        )
        try? await mutationLedger.markCommitted(
            mutationId: pending.mutationId,
            resolvedRowId: newRowId,
            resolvedMailbox: targetArchive
        )
        lastMutationAt = Date()
    }

    public func flagImportant(id: MessageId) async throws {
        guard let loc = liveLocations[id],
              let acc = accountsByUUID[loc.accountUUID] else {
            throw AppleMailScriptError.messageNotFound(id.rawValue)
        }
        let maxRowBefore = currentMaxRowId()
        let undo = UndoRecord(
            messageId: id.rawValue,
            action: .kept,
            accountUUID: acc.uuid,
            inboxPath: loc.inboxPath,
            targetMailboxPath: loc.inboxPath,
            previousRead: loc.wasRead,
            previousFlagged: loc.wasFlagged,
            lastKnownRowId: loc.rowId,
            maxRowIdBeforeMove: maxRowBefore
        )

        lastMutationAt = Date()
        let pending = try await mutationLedger.beginMutation(
            rfcMessageId: id.rawValue,
            action: .keep,
            accountUUID: acc.uuid,
            sourceMailbox: loc.inboxPath,
            destinationMailbox: loc.inboxPath,
            inboxPath: loc.inboxPath,
            expectedRead: true,
            expectedFlagged: true,
            preMoveRowId: loc.rowId,
            maxRowIdBeforeMove: maxRowBefore,
            undoRecord: undo
        )
        saveLedgerState(messageId: id.rawValue, state: "kept")

        do {
            try await scriptExecutor.updateFlags(
                accountUUID: acc.uuid,
                mailboxes: [loc.inboxPath, loc.physicalMailboxPath],
                rowId: loc.rowId,
                rfcMessageId: id.rawValue,
                markRead: true,
                markFlagged: true
            )
        } catch {
            try? await mutationLedger.markFailed(
                mutationId: pending.mutationId,
                error: error.localizedDescription,
                rollbackUndoRecord: true
            )
            clearLedgerState(messageId: id.rawValue)
            throw error
        }

        try? await mutationLedger.markCommitted(
            mutationId: pending.mutationId,
            resolvedRowId: loc.rowId,
            resolvedMailbox: loc.inboxPath
        )
        lastMutationAt = Date()
    }

    public func moveToTrash(id: MessageId, reason: TrashReason) async throws {
        guard let loc = liveLocations[id],
              let acc = accountsByUUID[loc.accountUUID] else {
            throw AppleMailScriptError.messageNotFound(id.rawValue)
        }
        let targetTrash = acc.trashPath ?? "Deleted Messages"
        let maxRowBefore = currentMaxRowId()

        let undo = UndoRecord(
            messageId: id.rawValue,
            action: .trashed,
            accountUUID: acc.uuid,
            inboxPath: loc.inboxPath,
            targetMailboxPath: targetTrash,
            previousRead: loc.wasRead,
            previousFlagged: loc.wasFlagged,
            lastKnownRowId: loc.rowId,
            maxRowIdBeforeMove: maxRowBefore
        )

        lastMutationAt = Date()
        let pending = try await mutationLedger.beginMutation(
            rfcMessageId: id.rawValue,
            action: .trash,
            accountUUID: acc.uuid,
            sourceMailbox: loc.inboxPath,
            destinationMailbox: targetTrash,
            inboxPath: loc.inboxPath,
            expectedRead: true,
            expectedFlagged: nil,
            preMoveRowId: loc.rowId,
            maxRowIdBeforeMove: maxRowBefore,
            undoRecord: undo
        )
        saveLedgerState(messageId: id.rawValue, state: "trashed")

        do {
            try await scriptExecutor.moveMessage(
                accountUUID: acc.uuid,
                sourceMailboxes: [loc.inboxPath, loc.physicalMailboxPath],
                destinationMailbox: targetTrash,
                createDestinationIfMissing: false,
                rowId: loc.rowId,
                rfcMessageId: id.rawValue,
                markRead: true,
                markFlagged: nil
            )
        } catch {
            try? await mutationLedger.markFailed(
                mutationId: pending.mutationId,
                error: error.localizedDescription,
                rollbackUndoRecord: true
            )
            clearLedgerState(messageId: id.rawValue)
            throw error
        }

        let newRowId = findMovedRowId(
            rfcMessageId: id.rawValue,
            afterRowId: maxRowBefore,
            fallbackRowId: nil
        )
        try? await mutationLedger.markCommitted(
            mutationId: pending.mutationId,
            resolvedRowId: newRowId,
            resolvedMailbox: targetTrash
        )
        lastMutationAt = Date()
    }

    public func restore(id: MessageId) async throws {
        guard let undo = try await mutationLedger.undoRecord(for: id.rawValue) else {
            clearLedgerState(messageId: id.rawValue)
            rescuedToQueueIds.remove(id)
            return
        }

        lastMutationAt = Date()
        let previousLedgerState = loadLedgerStates()[id.rawValue]
        rescuedToQueueIds.remove(id)

        switch undo.action {
        case .shadowRescued:
            clearLedgerState(messageId: id.rawValue)
            try? await mutationLedger.removeUndoRecord(for: id.rawValue)
            return

        case .kept:
            let pending = try await mutationLedger.beginMutation(
                rfcMessageId: id.rawValue,
                action: .restore,
                accountUUID: undo.accountUUID,
                sourceMailbox: undo.targetMailboxPath,
                destinationMailbox: undo.inboxPath,
                inboxPath: undo.inboxPath,
                expectedRead: undo.previousRead,
                expectedFlagged: undo.previousFlagged,
                preMoveRowId: undo.resolvedRowId ?? undo.lastKnownRowId,
                maxRowIdBeforeMove: undo.maxRowIdBeforeMove
            )
            clearLedgerState(messageId: id.rawValue)
            do {
                try await scriptExecutor.updateFlags(
                    accountUUID: undo.accountUUID,
                    mailboxes: [undo.targetMailboxPath, undo.inboxPath],
                    rowId: undo.resolvedRowId ?? undo.lastKnownRowId,
                    rfcMessageId: id.rawValue,
                    markRead: undo.previousRead,
                    markFlagged: undo.previousFlagged
                )
            } catch {
                if let previousLedgerState {
                    saveLedgerState(messageId: id.rawValue, state: previousLedgerState)
                }
                try? await mutationLedger.markFailed(
                    mutationId: pending.mutationId,
                    error: error.localizedDescription,
                    rollbackUndoRecord: false
                )
                throw error
            }
            try? await mutationLedger.markCommitted(
                mutationId: pending.mutationId,
                resolvedRowId: undo.resolvedRowId ?? undo.lastKnownRowId,
                resolvedMailbox: undo.inboxPath
            )

        case .archived, .trashed:
            // 先查 Envelope Index 是否已为移动后的邮件分配了新 ROWID（O(1) 避免大邮箱扫描）
            let resolvedNewRowId = findMovedRowId(
                rfcMessageId: id.rawValue,
                afterRowId: undo.maxRowIdBeforeMove,
                fallbackRowId: undo.resolvedRowId ?? undo.lastKnownRowId
            )
            let maxRowBeforeRestore = currentMaxRowId()
            let sourceMailboxes = [undo.resolvedMailboxPath, undo.targetMailboxPath].compactMap { $0 }
            let pending = try await mutationLedger.beginMutation(
                rfcMessageId: id.rawValue,
                action: .restore,
                accountUUID: undo.accountUUID,
                sourceMailbox: undo.targetMailboxPath,
                destinationMailbox: undo.inboxPath,
                inboxPath: undo.inboxPath,
                expectedRead: undo.previousRead,
                expectedFlagged: undo.previousFlagged,
                preMoveRowId: resolvedNewRowId ?? undo.lastKnownRowId,
                maxRowIdBeforeMove: maxRowBeforeRestore
            )
            clearLedgerState(messageId: id.rawValue)

            do {
                try await scriptExecutor.moveMessage(
                    accountUUID: undo.accountUUID,
                    sourceMailboxes: sourceMailboxes,
                    destinationMailbox: undo.inboxPath,
                    createDestinationIfMissing: false,
                    rowId: resolvedNewRowId,
                    rfcMessageId: id.rawValue,
                    markRead: undo.previousRead,
                    markFlagged: undo.previousFlagged
                )
            } catch {
                if let previousLedgerState {
                    saveLedgerState(messageId: id.rawValue, state: previousLedgerState)
                }
                try? await mutationLedger.markFailed(
                    mutationId: pending.mutationId,
                    error: error.localizedDescription,
                    rollbackUndoRecord: false
                )
                throw error
            }

            let restoredRowId = findMovedRowId(
                rfcMessageId: id.rawValue,
                afterRowId: maxRowBeforeRestore,
                fallbackRowId: nil
            )
            try? await mutationLedger.markCommitted(
                mutationId: pending.mutationId,
                resolvedRowId: restoredRowId,
                resolvedMailbox: undo.inboxPath
            )
        }

        try? await mutationLedger.removeUndoRecord(for: id.rawValue)
        lastMutationAt = Date()
    }

    public func rescue(id: MessageId) async throws -> MailItem {
        guard let handled = handledItemsCache[id] else {
            throw AppleMailScriptError.messageNotFound(id.rawValue)
        }
        rescuedToQueueIds.insert(id)
        saveLedgerState(messageId: id.rawValue, state: "rescued")

        if let prevUndo = try? await mutationLedger.undoRecord(for: id.rawValue),
           (prevUndo.action == .archived || prevUndo.action == .trashed) {
            let resolvedNewRowId = findMovedRowId(
                rfcMessageId: id.rawValue,
                afterRowId: prevUndo.maxRowIdBeforeMove,
                fallbackRowId: prevUndo.resolvedRowId ?? prevUndo.lastKnownRowId
            )
            let maxRowBeforeRescue = currentMaxRowId()
            let sourceMailboxes = [prevUndo.resolvedMailboxPath, prevUndo.targetMailboxPath].compactMap { $0 }
            lastMutationAt = Date()
            let pending = try await mutationLedger.beginMutation(
                rfcMessageId: id.rawValue,
                action: .rescue,
                accountUUID: prevUndo.accountUUID,
                sourceMailbox: prevUndo.targetMailboxPath,
                destinationMailbox: prevUndo.inboxPath,
                inboxPath: prevUndo.inboxPath,
                expectedRead: false,
                expectedFlagged: nil,
                preMoveRowId: resolvedNewRowId ?? prevUndo.lastKnownRowId,
                maxRowIdBeforeMove: maxRowBeforeRescue
            )
            do {
                try await scriptExecutor.moveMessage(
                    accountUUID: prevUndo.accountUUID,
                    sourceMailboxes: sourceMailboxes,
                    destinationMailbox: prevUndo.inboxPath,
                    createDestinationIfMissing: false,
                    rowId: resolvedNewRowId,
                    rfcMessageId: id.rawValue,
                    markRead: false,
                    markFlagged: nil
                )
            } catch {
                try? await mutationLedger.markFailed(
                    mutationId: pending.mutationId,
                    error: error.localizedDescription,
                    rollbackUndoRecord: false
                )
                throw error
            }
            try? await mutationLedger.markCommitted(
                mutationId: pending.mutationId,
                resolvedRowId: nil,
                resolvedMailbox: prevUndo.inboxPath
            )
            try? await mutationLedger.removeUndoRecord(for: id.rawValue)
            lastMutationAt = Date()
        } else if let loc = liveLocations[id] {
            let undo = UndoRecord(
                messageId: id.rawValue,
                action: .shadowRescued,
                accountUUID: loc.accountUUID,
                inboxPath: loc.inboxPath,
                targetMailboxPath: loc.physicalMailboxPath,
                previousRead: loc.wasRead,
                previousFlagged: loc.wasFlagged,
                lastKnownRowId: loc.rowId,
                maxRowIdBeforeMove: currentMaxRowId()
            )
            try? await mutationLedger.upsertUndoRecord(undo)
        }

        return MailAdapterFunctions.rescuedCard(from: handled)
    }

    public func openInNativeMail(id: MessageId) async throws -> String {
        let urlString = MailAdapterFunctions.nativeMailURLString(for: id)
        // 若邮件已被移入废纸篓，message:// 可能因 Spotlight 排除废纸篓而打不开，优先用 AppleScript 精准打开
        if let undo = try? await mutationLedger.undoRecord(for: id.rawValue), undo.action == .trashed {
            let rowId = findMovedRowId(
                rfcMessageId: id.rawValue,
                afterRowId: undo.maxRowIdBeforeMove,
                fallbackRowId: undo.resolvedRowId ?? undo.lastKnownRowId
            )
            let mailboxes = [undo.resolvedMailboxPath, undo.targetMailboxPath].compactMap { $0 }
            if (try? await scriptExecutor.openMessageWindow(
                accountUUID: undo.accountUUID,
                mailboxes: mailboxes,
                rowId: rowId,
                rfcMessageId: id.rawValue
            )) != nil {
                return urlString
            }
        }

        if let url = URL(string: urlString) {
            _ = await MainActor.run {
                NSWorkspace.shared.open(url)
            }
        }
        return urlString
    }

    public func hydrateMessage(id: MessageId) async throws -> MailContent? {
        guard let loc = liveLocations[id],
              let acc = accountsByUUID[loc.accountUUID],
              let existing = liveContents[id] else {
            return nil
        }

        let hydratedParsed: ParsedEmlx
        if fullEmlxExistsOnDisk(rowId: loc.rowId, physicalMailboxId: loc.physicalMailboxId),
           let diskURL = locateEmlxFile(rowId: loc.rowId, physicalMailboxId: loc.physicalMailboxId),
           let diskParsed = try? EmlxParser.parseFile(at: diskURL),
           (!diskParsed.plainText.isEmpty || diskParsed.htmlBody != nil) {
            hydratedParsed = diskParsed
        } else {
            lastMutationAt = Date()
            let rawSource = try await scriptExecutor.fetchMessageSource(
                accountUUID: acc.uuid,
                mailboxes: [loc.inboxPath, loc.physicalMailboxPath],
                rowId: loc.rowId,
                rfcMessageId: id.rawValue
            )
            lastMutationAt = Date()
            let trimmedSource = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSource.isEmpty else { return nil }
            let normalizedCRLF = rawSource
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\n", with: "\r\n")
            let parsed = EmlxParser.parse(data: Data(normalizedCRLF.utf8), isPartial: false)
            guard !parsed.plainText.isEmpty || parsed.htmlBody != nil else {
                return nil
            }
            hydratedParsed = parsed
        }

        let mergedSubject = !existing.subject.isEmpty && existing.subject != "（无主题）"
            ? existing.subject
            : (hydratedParsed.subject ?? existing.subject)
        let mergedSender = Sender(
            name: !(hydratedParsed.from?.name ?? "").isEmpty ? (hydratedParsed.from?.name ?? existing.from.name) : existing.from.name,
            address: !(hydratedParsed.from?.address ?? "").isEmpty ? (hydratedParsed.from?.address ?? existing.from.address) : existing.from.address
        )
        let mergedTo = !hydratedParsed.to.isEmpty ? hydratedParsed.to : existing.to
        let mergedAttachments = !hydratedParsed.attachments.isEmpty ? hydratedParsed.attachments : existing.attachments
        let mergedPlain = !hydratedParsed.plainText.isEmpty ? hydratedParsed.plainText : existing.plainText

        let payload = CachedMessagePayload(
            rfcMessageId: id.rawValue,
            senderName: mergedSender.name,
            senderAddr: mergedSender.address,
            to: mergedTo,
            subject: mergedSubject,
            dateHeader: hydratedParsed.dateHeader,
            plainText: mergedPlain,
            htmlBody: hydratedParsed.htmlBody ?? existing.htmlBody,
            hasRemoteImages: hydratedParsed.hasRemoteImages || existing.hasRemoteImages,
            attachments: mergedAttachments,
            hasUnsub: hydratedParsed.hasListUnsubscribe,
            hasListId: hydratedParsed.hasListId,
            isReply: hydratedParsed.isReply,
            isAuto: hydratedParsed.isAutoSubmitted,
            unloadedHtmlImages: hydratedParsed.unloadedHtmlImages,
            bodyRepresentation: hydratedParsed.bodyRepresentation,
            isBoilerplateStub: hydratedParsed.isBoilerplateStub,
            bodyIsImageOnly: hydratedParsed.bodyIsImageOnly,
            isPartial: false,
            isTruncated: false
        )
        cacheParsedPayload(rowId: loc.rowId, payload: payload)

        let updatedContent = MailContent(
            id: id,
            from: mergedSender,
            account: existing.account,
            subject: mergedSubject,
            receivedAt: existing.receivedAt,
            plainText: mergedPlain,
            attachments: mergedAttachments,
            isReadInMail: existing.isReadInMail,
            to: mergedTo,
            isFlaggedInMail: existing.isFlaggedInMail,
            sentByOwner: existing.sentByOwner,
            conversation: existing.conversation,
            bodyRepresentation: hydratedParsed.bodyRepresentation,
            isPartial: false,
            isTruncated: false,
            unloadedHtmlImages: hydratedParsed.unloadedHtmlImages,
            bodyIsImageOnly: hydratedParsed.bodyIsImageOnly,
            htmlBody: payload.htmlBody,
            hasRemoteImages: payload.hasRemoteImages
        )
        liveContents[id] = updatedContent
        if var cachedHandled = handledItemsCache[id] {
            cachedHandled.content = updatedContent
            handledItemsCache[id] = cachedHandled
        }
        return updatedContent
    }

    // MARK: - Helpers: Account Metadata, .emlx Lookup & Cache

    private func refreshAccountsAndMailboxes(using mailConn: SQLiteConnection) throws {
        let rows = try mailConn.query("SELECT ROWID, url, total_count FROM mailboxes;") { row in
            (row.int64(0), row.string(1) ?? "", row.int64(2))
        }

        var parsedMailboxes: [Int64: MailboxRecord] = [:]
        var groupedByAccount: [String: [MailboxRecord]] = [:]

        for (rowId, urlStr, totalCount) in rows {
            guard let schemeRange = urlStr.range(of: "://") else { continue }
            let scheme = String(urlStr[..<schemeRange.lowerBound]).lowercased()
            guard scheme == "imap" || scheme == "ews" || scheme == "pop" else { continue }

            let afterScheme = urlStr[schemeRange.upperBound...]
            guard let slash = afterScheme.firstIndex(of: "/") else { continue }
            let uuid = String(afterScheme[..<slash])
            let rawPath = String(afterScheme[afterScheme.index(after: slash)...])
            let decodedPath = rawPath.removingPercentEncoding ?? rawPath
            guard !uuid.isEmpty, !decodedPath.isEmpty else { continue }

            let rec = MailboxRecord(
                rowId: rowId,
                scheme: scheme,
                accountUUID: uuid,
                decodedPath: decodedPath,
                totalCount: totalCount
            )
            parsedMailboxes[rowId] = rec
            groupedByAccount[uuid, default: []].append(rec)
        }
        self.mailboxesById = parsedMailboxes

        var sentIds = Set<Int64>()
        var collectedOwners = extraOwnerAddresses
        let accountMeta = readSystemAccountMetadata()
        var resolved: [String: ResolvedAccount] = [:]

        for (uuid, mbs) in groupedByAccount {
            for mb in mbs where ConversationResolver.isSentMailboxPath(mb.decodedPath) {
                sentIds.insert(mb.rowId)
            }

            let inboxes = mbs.filter { mb in
                let lower = mb.decodedPath.lowercased()
                return lower == "inbox" || mb.decodedPath == "收件箱"
            }.sorted { a, b in
                if a.totalCount != b.totalCount { return a.totalCount > b.totalCount }
                return a.decodedPath == "INBOX"
            }
            guard let primaryInbox = inboxes.first else { continue }

            let archiveCandidates = [
                "[Gmail]/All Mail", "[Gmail]/所有邮件", "[Google Mail]/All Mail",
                "Archive", "Archives", "归档"
            ]
            let archiveMb = archiveCandidates.compactMap { cand in
                mbs.first { $0.decodedPath.caseInsensitiveCompare(cand) == .orderedSame }
            }.first

            let trashCandidates = [
                "[Gmail]/Trash", "[Gmail]/已删除邮件", "[Google Mail]/Trash",
                "Deleted Messages", "Deleted Items", "Trash", "废纸篓", "已删除邮件"
            ]
            let trashMb = trashCandidates.compactMap { cand in
                mbs.first { $0.decodedPath.caseInsensitiveCompare(cand) == .orderedSame }
            }.first

            let meta = accountMeta[uuid]
            let address = meta?.address ?? uuid
            let normalizedOwner = ConversationResolver.normalizeEmailAddress(address)
            if normalizedOwner.contains("@") {
                collectedOwners.insert(normalizedOwner)
            }
            let label = Self.makeShortAccountLabel(rawLabel: meta?.description, address: address, mailboxes: mbs)

            resolved[uuid] = ResolvedAccount(
                uuid: uuid,
                mailAccount: MailAccount(id: uuid, label: label, address: address),
                inboxMailboxes: inboxes.map { ($0.rowId, $0.decodedPath) },
                primaryInboxPath: primaryInbox.decodedPath,
                archivePath: archiveMb?.decodedPath,
                trashPath: trashMb?.decodedPath
            )
        }
        self.sentMailboxIds = sentIds
        self.ownerAddresses = collectedOwners
        self.accountsByUUID = resolved
    }

    private func readSystemAccountMetadata() -> [String: (description: String?, address: String?)] {
        guard let accDBPath = accountsDBPath, !accDBPath.isEmpty,
              let conn = try? SQLiteConnection(readOnlyPath: accDBPath) else { return [:] }
        let sql = """
        SELECT c.ZIDENTIFIER,
               COALESCE(NULLIF(c.ZACCOUNTDESCRIPTION, ''), p.ZACCOUNTDESCRIPTION),
               COALESCE(NULLIF(c.ZUSERNAME, ''), p.ZUSERNAME)
        FROM ZACCOUNT c
        LEFT JOIN ZACCOUNT p ON c.ZPARENTACCOUNT = p.Z_PK
        WHERE c.ZIDENTIFIER IS NOT NULL;
        """
        guard let rows = try? conn.query(sql, map: { ($0.string(0) ?? "", $0.string(1), $0.string(2)) }) else {
            return [:]
        }
        var map: [String: (String?, String?)] = [:]
        for (id, desc, user) in rows where !id.isEmpty {
            map[id] = (desc, user)
        }
        return map
    }

    private static func makeShortAccountLabel(
        rawLabel: String?,
        address: String,
        mailboxes: [MailboxRecord]
    ) -> String {
        if let raw = rawLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if !raw.contains("@") && raw.count <= 10 {
                return raw
            }
        }
        let lowerAddr = address.lowercased()
        if lowerAddr.hasSuffix("@gmail.com") || mailboxes.contains(where: { $0.decodedPath.hasPrefix("[Gmail]") }) {
            return "Gmail"
        }
        if lowerAddr.hasSuffix("@icloud.com") || lowerAddr.hasSuffix("@me.com") {
            return "iCloud"
        }
        if mailboxes.first?.scheme == "ews" {
            return "工作"
        }
        if let domain = address.split(separator: "@").last?.split(separator: ".").first {
            let s = String(domain)
            return s.count <= 8 ? s.uppercased() : String(s.prefix(6))
        }
        return "邮箱"
    }

    private struct CachedMessagePayload {
        let rfcMessageId: String
        let senderName: String
        let senderAddr: String
        let to: [Sender]
        let subject: String
        let dateHeader: String?
        let plainText: String
        let htmlBody: String?
        let hasRemoteImages: Bool
        let attachments: [Attachment]
        let hasUnsub: Bool
        let hasListId: Bool
        let isReply: Bool
        let isAuto: Bool
        let unloadedHtmlImages: Int
        let bodyRepresentation: String
        let isBoilerplateStub: Bool
        let bodyIsImageOnly: Bool
        let isPartial: Bool
        let isTruncated: Bool
    }

    private func cachedOrDiskPlainText(rowId: Int64, physicalMailboxId: Int64) -> String? {
        if let cacheDB,
           let hit = (try? cacheDB.query(
            "SELECT plain_text FROM parsed_emlx_v3 WHERE row_id = ? LIMIT 1;",
            bindings: [.int(rowId)]
           ) { $0.string(0) ?? "" })?.first,
           !hit.isEmpty {
            return hit
        }
        if let emlxURL = locateEmlxFile(rowId: rowId, physicalMailboxId: physicalMailboxId),
           let parsed = try? EmlxParser.parseFile(at: emlxURL),
           !parsed.plainText.isEmpty {
            cacheParsedPayload(
                rowId: rowId,
                payload: CachedMessagePayload(
                    rfcMessageId: parsed.messageId ?? "rowid-\(rowId)@applemail.local",
                    senderName: parsed.from?.name ?? "",
                    senderAddr: parsed.from?.address ?? "",
                    to: parsed.to,
                    subject: parsed.subject ?? "",
                    dateHeader: parsed.dateHeader,
                    plainText: parsed.plainText,
                    htmlBody: parsed.htmlBody,
                    hasRemoteImages: parsed.hasRemoteImages,
                    attachments: parsed.attachments,
                    hasUnsub: parsed.hasListUnsubscribe,
                    hasListId: parsed.hasListId,
                    isReply: parsed.isReply,
                    isAuto: parsed.isAutoSubmitted,
                    unloadedHtmlImages: parsed.unloadedHtmlImages,
                    bodyRepresentation: parsed.bodyRepresentation,
                    isBoilerplateStub: parsed.isBoilerplateStub,
                    bodyIsImageOnly: parsed.bodyIsImageOnly,
                    isPartial: parsed.isPartial,
                    isTruncated: parsed.isTruncated
                )
            )
            return parsed.plainText
        }
        return nil
    }

    private func resolveMessageDetails(
        rowId: Int64,
        physicalMailboxId: Int64,
        fallbackSubject: String,
        fallbackSenderName: String,
        fallbackSenderAddr: String,
        fallbackSummary: String,
        mailConn: SQLiteConnection
    ) -> CachedMessagePayload {
        if let cacheDB,
           let hit = (try? cacheDB.query(
            """
            SELECT rfc_message_id, sender_name, sender_addr, to_json, subject, date_header,
                   plain_text, html_body, has_remote_images, attachments_json,
                   has_unsub, has_list_id, is_reply, is_auto,
                   unloaded_html_images, body_representation, is_boilerplate_stub,
                   body_is_image_only, is_partial, is_truncated
            FROM parsed_emlx_v3
            WHERE row_id = ?
            LIMIT 1;
            """,
            bindings: [.int(rowId)]
           ) { row -> CachedMessagePayload in
               let toJSON = row.string(3) ?? "[]"
               let decodedTo = (try? JSONDecoder().decode([Sender].self, from: Data(toJSON.utf8))) ?? []
               let attJSON = row.string(9) ?? "[]"
               let decodedAtt = (try? JSONDecoder().decode([Attachment].self, from: Data(attJSON.utf8))) ?? []
               return CachedMessagePayload(
                   rfcMessageId: row.string(0) ?? "rowid-\(rowId)@local.mail",
                   senderName: row.string(1) ?? fallbackSenderName,
                   senderAddr: row.string(2) ?? fallbackSenderAddr,
                   to: decodedTo,
                   subject: row.string(4) ?? fallbackSubject,
                   dateHeader: row.string(5),
                   plainText: row.string(6) ?? fallbackSummary,
                   htmlBody: row.string(7),
                   hasRemoteImages: row.int64(8) != 0,
                   attachments: decodedAtt,
                   hasUnsub: row.int64(10) != 0,
                   hasListId: row.int64(11) != 0,
                   isReply: row.int64(12) != 0,
                   isAuto: row.int64(13) != 0,
                   unloadedHtmlImages: Int(row.int64(14)),
                   bodyRepresentation: row.string(15) ?? "empty",
                   isBoilerplateStub: row.int64(16) != 0,
                   bodyIsImageOnly: row.int64(17) != 0,
                   isPartial: row.int64(18) != 0,
                   isTruncated: row.int64(19) != 0
               )
           })?.first,
           (!hit.plainText.isEmpty || hit.htmlBody != nil || hit.bodyIsImageOnly || hit.isPartial || hit.isTruncated) {
            if !hit.isPartial || !fullEmlxExistsOnDisk(rowId: rowId, physicalMailboxId: physicalMailboxId) {
                return hit
            }
        }

        var parsedEmlx: ParsedEmlx? = nil
        if let emlxURL = locateEmlxFile(rowId: rowId, physicalMailboxId: physicalMailboxId) {
            parsedEmlx = try? EmlxParser.parseFile(at: emlxURL)
        }

        let rfcId = parsedEmlx?.messageId ?? "rowid-\(rowId)@applemail.local"
        let senderName = !fallbackSenderName.isEmpty
            ? fallbackSenderName
            : (parsedEmlx?.from?.name ?? fallbackSenderAddr)
        let senderAddr = !fallbackSenderAddr.isEmpty
            ? fallbackSenderAddr
            : (parsedEmlx?.from?.address ?? "")
        let subject = !fallbackSubject.isEmpty
            ? fallbackSubject
            : (parsedEmlx?.subject ?? "")

        var plainText = parsedEmlx?.plainText ?? ""
        if plainText.isEmpty && !fallbackSummary.isEmpty {
            plainText = EmlxParser.normalizePlainText(fallbackSummary)
        }

        var attachments = parsedEmlx?.attachments ?? []
        if attachments.isEmpty {
            // 对 .partial.emlx 补充查一次 Envelope Index 的 attachments 表
            if let sqlAtts = try? mailConn.query(
                "SELECT name FROM attachments WHERE message = ? AND name IS NOT NULL;",
                bindings: [.int(rowId)],
                map: { $0.string(0) ?? "" }
            ) {
                for name in sqlAtts where !name.isEmpty {
                    attachments.append(
                        Attachment(name: name, size: "附件", kind: AttachmentKind.infer(filename: name))
                    )
                }
            }
        }

        let unloadedHtmlImages = parsedEmlx?.unloadedHtmlImages ?? 0
        let bodyRepresentation = parsedEmlx?.bodyRepresentation ?? (plainText.isEmpty ? "empty" : "full_plain_text")
        let isBoilerplateStub = parsedEmlx?.isBoilerplateStub ?? EmlxParser.isBoilerplateStub(plainText)
        let bodyIsImageOnly = parsedEmlx?.bodyIsImageOnly ?? false
        let isPartial = parsedEmlx?.isPartial ?? false
        let isTruncated = parsedEmlx?.isTruncated ?? (parsedEmlx == nil)

        let payload = CachedMessagePayload(
            rfcMessageId: rfcId,
            senderName: senderName,
            senderAddr: senderAddr,
            to: parsedEmlx?.to ?? [],
            subject: subject,
            dateHeader: parsedEmlx?.dateHeader,
            plainText: plainText,
            htmlBody: parsedEmlx?.htmlBody,
            hasRemoteImages: parsedEmlx?.hasRemoteImages ?? false,
            attachments: attachments,
            hasUnsub: parsedEmlx?.hasListUnsubscribe ?? false,
            hasListId: parsedEmlx?.hasListId ?? false,
            isReply: parsedEmlx?.isReply ?? false,
            isAuto: parsedEmlx?.isAutoSubmitted ?? false,
            unloadedHtmlImages: unloadedHtmlImages,
            bodyRepresentation: bodyRepresentation,
            isBoilerplateStub: isBoilerplateStub,
            bodyIsImageOnly: bodyIsImageOnly,
            isPartial: isPartial,
            isTruncated: isTruncated
        )

        if !plainText.isEmpty || parsedEmlx?.htmlBody != nil || bodyIsImageOnly || parsedEmlx != nil {
            cacheParsedPayload(rowId: rowId, payload: payload)
        }

        return payload
    }

    private func cacheParsedPayload(rowId: Int64, payload: CachedMessagePayload) {
        guard let cacheDB else { return }
        let toJSON = (try? String(data: JSONEncoder().encode(payload.to), encoding: .utf8)) ?? "[]"
        let attJSON = (try? String(data: JSONEncoder().encode(payload.attachments), encoding: .utf8)) ?? "[]"
        try? cacheDB.execute("""
            INSERT OR REPLACE INTO parsed_emlx_v3 (
                row_id, rfc_message_id, sender_name, sender_addr, to_json, subject, date_header,
                plain_text, html_body, has_remote_images, attachments_json,
                has_unsub, has_list_id, is_reply, is_auto,
                unloaded_html_images, body_representation, is_boilerplate_stub,
                body_is_image_only, is_partial, is_truncated
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, bindings: [
            .int(rowId),
            .text(payload.rfcMessageId),
            .text(payload.senderName),
            .text(payload.senderAddr),
            .text(toJSON),
            .text(payload.subject),
            payload.dateHeader.map { .text($0) } ?? .null,
            .text(payload.plainText),
            payload.htmlBody.map { .text($0) } ?? .null,
            .int(payload.hasRemoteImages ? 1 : 0),
            .text(attJSON),
            .int(payload.hasUnsub ? 1 : 0),
            .int(payload.hasListId ? 1 : 0),
            .int(payload.isReply ? 1 : 0),
            .int(payload.isAuto ? 1 : 0),
            .int(Int64(payload.unloadedHtmlImages)),
            .text(payload.bodyRepresentation),
            .int(payload.isBoilerplateStub ? 1 : 0),
            .int(payload.bodyIsImageOnly ? 1 : 0),
            .int(payload.isPartial ? 1 : 0),
            .int(payload.isTruncated ? 1 : 0)
        ])
    }

    private func fullEmlxExistsOnDisk(rowId: Int64, physicalMailboxId: Int64) -> Bool {
        guard let dataRoot = resolveMboxDataRoot(for: physicalMailboxId) else { return false }
        let shardDir = Self.shardMessagesDirectory(dataRoot: dataRoot, rowId: rowId)
        let fullURL = shardDir.appendingPathComponent("\(rowId).emlx")
        return FileManager.default.fileExists(atPath: fullURL.path)
    }

    private func locateEmlxFile(rowId: Int64, physicalMailboxId: Int64) -> URL? {
        guard let dataRoot = resolveMboxDataRoot(for: physicalMailboxId) else { return nil }
        let shardDir = Self.shardMessagesDirectory(dataRoot: dataRoot, rowId: rowId)
        let fullURL = shardDir.appendingPathComponent("\(rowId).emlx")
        if FileManager.default.fileExists(atPath: fullURL.path) {
            return fullURL
        }
        let partialURL = shardDir.appendingPathComponent("\(rowId).partial.emlx")
        if FileManager.default.fileExists(atPath: partialURL.path) {
            return partialURL
        }
        return nil
    }

    private func resolveMboxDataRoot(for mailboxId: Int64) -> URL? {
        if let cached = mboxDataRootCache[mailboxId] {
            return cached
        }
        guard let mb = mailboxesById[mailboxId] else { return nil }
        var mboxDir = mailVDir.appendingPathComponent(mb.accountUUID, isDirectory: true)
        for segment in mb.decodedPath.split(separator: "/") {
            mboxDir.appendPathComponent("\(segment).mbox", isDirectory: true)
        }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: mboxDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for child in children {
            let candidateData = child.appendingPathComponent("Data", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidateData.path) {
                mboxDataRootCache[mailboxId] = candidateData
                return candidateData
            }
        }
        return nil
    }

    /// Apple Mail 分片目录算法：`ROWID / 1000` 的十进制各位数字倒序拼接（如 `39350 -> Data/9/3/Messages`）
    public static func shardMessagesDirectory(dataRoot: URL, rowId: Int64) -> URL {
        let thousands = rowId / 1000
        var dir = dataRoot
        if thousands > 0 {
            for ch in String(thousands).reversed() {
                dir.appendPathComponent(String(ch), isDirectory: true)
            }
        }
        dir.appendPathComponent("Messages", isDirectory: true)
        return dir
    }

    private func currentMaxRowId() -> Int64 {
        let indexPath = mailVDir.appendingPathComponent("MailData/Envelope Index").path
        guard let conn = try? SQLiteConnection(readOnlyPath: indexPath),
              let maxId = (try? conn.query("SELECT COALESCE(MAX(ROWID), 0) FROM messages;") { $0.int64(0) })?.first else {
            return 0
        }
        return maxId
    }

    /// 移动邮件后 IMAP 会生成新 `ROWID > afterRowId`，仅扫描刚产生的新行即可 O(1) 定位新 ROWID
    private func findMovedRowId(rfcMessageId: String, afterRowId: Int64, fallbackRowId: Int64?) -> Int64? {
        guard afterRowId > 0 else { return fallbackRowId }
        let indexPath = mailVDir.appendingPathComponent("MailData/Envelope Index").path
        guard let conn = try? SQLiteConnection(readOnlyPath: indexPath) else { return fallbackRowId }
        guard let recentRows = try? conn.query(
            "SELECT ROWID, mailbox FROM messages WHERE ROWID > ? ORDER BY ROWID DESC LIMIT 25;",
            bindings: [.int(afterRowId)],
            map: { ($0.int64(0), $0.int64(1)) }
        ) else {
            return fallbackRowId
        }
        for (newRowId, mbId) in recentRows {
            if let fileURL = locateEmlxFile(rowId: newRowId, physicalMailboxId: mbId),
               let parsed = try? EmlxParser.parseFile(at: fileURL),
               parsed.messageId == rfcMessageId {
                return newRowId
            }
        }
        return fallbackRowId
    }

    private func loadLedgerStates() -> [String: String] {
        guard let cacheDB,
              let rows = try? cacheDB.query("SELECT rfc_message_id, state FROM triage_ledger;", map: {
                  ($0.string(0) ?? "", $0.string(1) ?? "")
              }) else {
            return [:]
        }
        var map: [String: String] = [:]
        for (k, v) in rows where !k.isEmpty { map[k] = v }
        return map
    }

    private func saveLedgerState(messageId: String, state: String) {
        try? cacheDB?.execute(
            "INSERT OR REPLACE INTO triage_ledger (rfc_message_id, state, updated_at) VALUES (?, ?, ?);",
            bindings: [.text(messageId), .text(state), .double(Date().timeIntervalSince1970)]
        )
    }

    private func clearLedgerState(messageId: String) {
        try? cacheDB?.execute(
            "DELETE FROM triage_ledger WHERE rfc_message_id = ?;",
            bindings: [.text(messageId)]
        )
    }
}

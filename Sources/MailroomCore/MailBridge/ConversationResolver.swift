import Foundation

/// A single message within an email conversation thread, resolved from Apple Mail's
/// `Envelope Index` and optional `.emlx` plain-text body cache.
public struct ThreadMessageContext: Sendable, Codable, Equatable, Hashable {
    public let rowId: Int64
    public let rfcMessageId: String?
    public let from: String
    public let subject: String
    public let dateISO: String
    public let bodySnippet: String
    public let sentByOwner: Bool
    public let isFlagged: Bool
    public let mailboxPath: String

    public init(
        rowId: Int64,
        rfcMessageId: String? = nil,
        from: String,
        subject: String,
        dateISO: String,
        bodySnippet: String,
        sentByOwner: Bool,
        isFlagged: Bool,
        mailboxPath: String
    ) {
        self.rowId = rowId
        self.rfcMessageId = rfcMessageId
        self.from = from
        self.subject = subject
        self.dateISO = dateISO
        self.bodySnippet = bodySnippet
        self.sentByOwner = sentByOwner
        self.isFlagged = isFlagged
        self.mailboxPath = mailboxPath
    }
}

/// Thread-level context and safety protection signals for a target inbox message.
public struct ConversationContext: Sendable, Codable, Equatable, Hashable {
    public let conversationId: Int64
    public let messageCount: Int
    public let sentByOwnerInThread: Bool
    public let hasFlaggedInThread: Bool
    public let priorMessages: [ThreadMessageContext]

    public init(
        conversationId: Int64,
        messageCount: Int,
        sentByOwnerInThread: Bool,
        hasFlaggedInThread: Bool,
        priorMessages: [ThreadMessageContext]
    ) {
        self.conversationId = conversationId
        self.messageCount = messageCount
        self.sentByOwnerInThread = sentByOwnerInThread
        self.hasFlaggedInThread = hasFlaggedInThread
        self.priorMessages = priorMessages
    }
}

/// Input target identifying a message whose thread context should be batch-resolved.
public struct ConversationLookupTarget: Sendable, Equatable, Hashable {
    public let rowId: Int64
    public let conversationId: Int64
    public let receivedAtEpoch: Int64

    public init(rowId: Int64, conversationId: Int64, receivedAtEpoch: Int64) {
        self.rowId = rowId
        self.conversationId = conversationId
        self.receivedAtEpoch = receivedAtEpoch
    }
}

/// Batch-resolves `Envelope Index` conversation threads, owner participation (`sentByOwner`),
/// flagged-thread protection, and prior thread message snippets in minimal indexed SQLite queries.
public struct ConversationResolver: Sendable {
    public static let defaultMaxPriorMessages = 12
    public static let defaultMaxBodyCharacters = 8_000

    public let ownerAddresses: Set<String>
    public let maxPriorMessages: Int
    public let maxBodyCharacters: Int
    private let defaultBodyProvider: (@Sendable (_ rowId: Int64, _ mailboxId: Int64) -> String?)?

    public init(
        ownerAddresses: Set<String> = [],
        maxPriorMessages: Int = ConversationResolver.defaultMaxPriorMessages,
        maxBodyCharacters: Int = ConversationResolver.defaultMaxBodyCharacters,
        bodyProvider: (@Sendable (_ rowId: Int64, _ mailboxId: Int64) -> String?)? = nil
    ) {
        self.ownerAddresses = Set(
            ownerAddresses
                .map(Self.normalizeEmailAddress)
                .filter { !$0.isEmpty }
        )
        self.maxPriorMessages = max(0, maxPriorMessages)
        self.maxBodyCharacters = max(0, maxBodyCharacters)
        self.defaultBodyProvider = bodyProvider
    }

    // MARK: - Batch Resolution

    /// Batch-resolves `ConversationContext` keyed by target `rowId` using `defaultBodyProvider`
    /// (or `summaries` fallback when nil/empty).
    public func resolve(
        targets: [ConversationLookupTarget],
        using mailConn: SQLiteConnection
    ) throws -> [Int64: ConversationContext] {
        try resolveInternal(targets: targets, using: mailConn) { rowId, mailboxId in
            defaultBodyProvider?(rowId, mailboxId)
        }
    }

    /// Batch-resolves `ConversationContext` keyed by target `rowId` with a synchronous
    /// `(rowId, mailboxId) -> plainTextBody?` hook for cached `.emlx` bodies.
    public func resolve(
        targets: [ConversationLookupTarget],
        using mailConn: SQLiteConnection,
        bodyProvider: (_ rowId: Int64, _ mailboxId: Int64) -> String?
    ) throws -> [Int64: ConversationContext] {
        try resolveInternal(targets: targets, using: mailConn, bodyProvider: bodyProvider)
    }

    /// Convenience tuple overload for `(rowId, conversationId, receivedAtEpoch)` inputs.
    public func resolve(
        targets: [(rowId: Int64, conversationId: Int64, receivedAtEpoch: Int64)],
        using mailConn: SQLiteConnection
    ) throws -> [Int64: ConversationContext] {
        let mapped = targets.map {
            ConversationLookupTarget(
                rowId: $0.rowId,
                conversationId: $0.conversationId,
                receivedAtEpoch: $0.receivedAtEpoch
            )
        }
        return try resolve(targets: mapped, using: mailConn)
    }

    /// Convenience tuple overload with a synchronous `(rowId, mailboxId) -> plainTextBody?` hook.
    public func resolve(
        targets: [(rowId: Int64, conversationId: Int64, receivedAtEpoch: Int64)],
        using mailConn: SQLiteConnection,
        bodyProvider: (_ rowId: Int64, _ mailboxId: Int64) -> String?
    ) throws -> [Int64: ConversationContext] {
        let mapped = targets.map {
            ConversationLookupTarget(
                rowId: $0.rowId,
                conversationId: $0.conversationId,
                receivedAtEpoch: $0.receivedAtEpoch
            )
        }
        return try resolveInternal(targets: mapped, using: mailConn, bodyProvider: bodyProvider)
    }

    private func resolveInternal(
        targets: [ConversationLookupTarget],
        using mailConn: SQLiteConnection,
        bodyProvider: (_ rowId: Int64, _ mailboxId: Int64) -> String?
    ) throws -> [Int64: ConversationContext] {
        guard !targets.isEmpty else { return [:] }

        // 1. Load mailbox table once (~tens of rows) to decode paths and detect Sent mailboxes.
        let mailboxRows = try mailConn.query("SELECT ROWID, url FROM mailboxes;") { row in
            (row.int64(0), row.string(1) ?? "")
        }
        var mailboxPathById: [Int64: String] = [:]
        mailboxPathById.reserveCapacity(mailboxRows.count)
        var sentMailboxIds = Set<Int64>()
        for (mbId, urlStr) in mailboxRows {
            let decoded = Self.decodeMailboxPath(from: urlStr)
            mailboxPathById[mbId] = decoded
            if Self.isSentMailboxPath(decoded) {
                sentMailboxIds.insert(mbId)
            }
        }

        let threadedTargets = targets.filter { $0.conversationId > 0 }
        let standaloneTargets = targets.filter { $0.conversationId <= 0 }

        var results: [Int64: ConversationContext] = [:]
        results.reserveCapacity(targets.count)

        if !standaloneTargets.isEmpty {
            let standaloneResults = try resolveFallbackStandaloneTargets(
                targets: standaloneTargets,
                sentMailboxIds: sentMailboxIds,
                using: mailConn
            )
            for (rid, ctx) in standaloneResults {
                results[rid] = ctx
            }
        }

        let validConvIds = Array(Set(threadedTargets.map(\.conversationId))).sorted()
        guard !validConvIds.isEmpty else {
            return results
        }

        // 2. Batch-fetch all non-deleted messages across target conversation IDs.
        // Note: `+m.deleted = 0` prevents SQLite from choosing `messages_deleted_index`
        // over `messages_conversation_id_*` indices on 24k+ message stores.
        struct RawThreadRow {
            let rowId: Int64
            let conversationId: Int64
            let messageIdHash: Int64
            let mailboxId: Int64
            let timestamp: Int64
            let isFlagged: Bool
            let subjectPrefix: String
            let subjectBase: String
            let senderAddress: String
            let senderName: String
            let summary: String
        }

        var rawRows: [RawThreadRow] = []
        for chunk in validConvIds.chunked(into: 400) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let sql = """
            SELECT m.ROWID,
                   m.conversation_id,
                   m.message_id,
                   m.mailbox,
                   COALESCE(NULLIF(m.date_received, 0), m.date_sent, 0) AS msg_ts,
                   m.flagged,
                   COALESCE(m.subject_prefix, ''),
                   COALESCE(s.subject, ''),
                   COALESCE(a.address, ''),
                   COALESCE(a.comment, ''),
                   COALESCE(sm.summary, '')
            FROM messages m
            LEFT JOIN subjects s ON m.subject = s.ROWID
            LEFT JOIN addresses a ON m.sender = a.ROWID
            LEFT JOIN summaries sm ON m.summary = sm.ROWID
            WHERE m.conversation_id IN (\(placeholders))
              AND +m.deleted = 0;
            """
            let bindings = chunk.map { SQLiteValue.int($0) }
            let chunkRows = try mailConn.query(sql, bindings: bindings) { row in
                RawThreadRow(
                    rowId: row.int64(0),
                    conversationId: row.int64(1),
                    messageIdHash: row.int64(2),
                    mailboxId: row.int64(3),
                    timestamp: row.int64(4),
                    isFlagged: row.int64(5) != 0,
                    subjectPrefix: row.string(6) ?? "",
                    subjectBase: row.string(7) ?? "",
                    senderAddress: row.string(8) ?? "",
                    senderName: row.string(9) ?? "",
                    summary: row.string(10) ?? ""
                )
            }
            rawRows.append(contentsOf: chunkRows)
        }

        // 3. Check `labels` table (if present, e.g. Gmail IMAP `[Gmail]/Sent Mail` labels on All Mail rows).
        let sentLabeledRowIds = try Self.fetchSentLabeledRowIds(
            rowIds: rawRows.map(\.rowId),
            sentMailboxIds: sentMailboxIds,
            using: mailConn
        )

        // 4. Group rows by conversation_id, deduplicate mirrored IMAP/Gmail copies by non-zero message_id,
        //    and merge `sentByOwner` / `isFlagged` across duplicates.
        struct CanonicalThreadMessage {
            let rowId: Int64
            let alternateLocations: [(rowId: Int64, mailboxId: Int64)]
            let messageIdHash: Int64
            let mailboxId: Int64
            let mailboxPath: String
            let timestamp: Int64
            let from: String
            let subject: String
            let summary: String
            var sentByOwner: Bool
            var isFlagged: Bool
        }

        let rawByConv = Dictionary(grouping: rawRows, by: \.conversationId)
        var targetRowIdSet = Set<Int64>()
        targetRowIdSet.reserveCapacity(targets.count)
        for t in targets {
            targetRowIdSet.insert(t.rowId)
        }

        var messagesByConv: [Int64: [CanonicalThreadMessage]] = [:]
        messagesByConv.reserveCapacity(rawByConv.count)

        var rowMessageIdHashByRowId: [Int64: Int64] = [:]
        rowMessageIdHashByRowId.reserveCapacity(rawRows.count)

        for (convId, rows) in rawByConv {
            var dedupByMsgHash: [Int64: Int] = [:]
            var canonicalList: [CanonicalThreadMessage] = []
            canonicalList.reserveCapacity(rows.count)

            for r in rows {
                rowMessageIdHashByRowId[r.rowId] = r.messageIdHash
                let mbPath = mailboxPathById[r.mailboxId] ?? ""
                let normalizedAddr = Self.normalizeEmailAddress(r.senderAddress)
                let isOwnerAddr = !normalizedAddr.isEmpty && ownerAddresses.contains(normalizedAddr)
                let isSentMb = sentMailboxIds.contains(r.mailboxId) || sentLabeledRowIds.contains(r.rowId)
                let sentByOwner = isSentMb || isOwnerAddr
                let fullSubject = Self.combineSubject(prefix: r.subjectPrefix, base: r.subjectBase)
                let formattedFrom = Self.formatFromHeader(name: r.senderName, address: r.senderAddress)

                if r.messageIdHash != 0, let existingIdx = dedupByMsgHash[r.messageIdHash] {
                    var existing = canonicalList[existingIdx]
                    existing.sentByOwner = existing.sentByOwner || sentByOwner
                    existing.isFlagged = existing.isFlagged || r.isFlagged

                    // Prefer keeping a target rowId or non-All-Mail copy as primary if needed.
                    let shouldPromoteCurrent = targetRowIdSet.contains(r.rowId) && !targetRowIdSet.contains(existing.rowId)
                    if shouldPromoteCurrent {
                        var alts = existing.alternateLocations
                        alts.append((existing.rowId, existing.mailboxId))
                        canonicalList[existingIdx] = CanonicalThreadMessage(
                            rowId: r.rowId,
                            alternateLocations: alts,
                            messageIdHash: r.messageIdHash,
                            mailboxId: r.mailboxId,
                            mailboxPath: mbPath,
                            timestamp: r.timestamp,
                            from: formattedFrom.isEmpty ? existing.from : formattedFrom,
                            subject: fullSubject.isEmpty ? existing.subject : fullSubject,
                            summary: r.summary.isEmpty ? existing.summary : r.summary,
                            sentByOwner: existing.sentByOwner,
                            isFlagged: existing.isFlagged
                        )
                    } else {
                        var alts = existing.alternateLocations
                        alts.append((r.rowId, r.mailboxId))
                        canonicalList[existingIdx] = CanonicalThreadMessage(
                            rowId: existing.rowId,
                            alternateLocations: alts,
                            messageIdHash: existing.messageIdHash,
                            mailboxId: existing.mailboxId,
                            mailboxPath: existing.mailboxPath,
                            timestamp: existing.timestamp,
                            from: existing.from.isEmpty ? formattedFrom : existing.from,
                            subject: existing.subject.isEmpty ? fullSubject : existing.subject,
                            summary: existing.summary.isEmpty ? r.summary : existing.summary,
                            sentByOwner: existing.sentByOwner,
                            isFlagged: existing.isFlagged
                        )
                    }
                } else {
                    let msg = CanonicalThreadMessage(
                        rowId: r.rowId,
                        alternateLocations: [],
                        messageIdHash: r.messageIdHash,
                        mailboxId: r.mailboxId,
                        mailboxPath: mbPath,
                        timestamp: r.timestamp,
                        from: formattedFrom,
                        subject: fullSubject,
                        summary: r.summary,
                        sentByOwner: sentByOwner,
                        isFlagged: r.isFlagged
                    )
                    if r.messageIdHash != 0 {
                        dedupByMsgHash[r.messageIdHash] = canonicalList.count
                    }
                    canonicalList.append(msg)
                }
            }

            canonicalList.sort { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.rowId < rhs.rowId
            }
            messagesByConv[convId] = canonicalList
        }

        // 5. Build ConversationContext per threaded target, caching bodyProvider invocations across the batch.
        var bodyCache: [Int64: String] = [:]

        for target in threadedTargets {
            guard let thread = messagesByConv[target.conversationId] else {
                results[target.rowId] = ConversationContext(
                    conversationId: target.conversationId,
                    messageCount: 1,
                    sentByOwnerInThread: false,
                    hasFlaggedInThread: false,
                    priorMessages: []
                )
                continue
            }

            let targetMsgIdHash = rowMessageIdHashByRowId[target.rowId] ?? 0
            let sentByOwnerInThread = thread.contains(where: \.sentByOwner)
            let hasFlaggedInThread = thread.contains(where: \.isFlagged)

            let allPrior = thread.filter { msg in
                if msg.rowId == target.rowId { return false }
                if targetMsgIdHash != 0 && msg.messageIdHash == targetMsgIdHash { return false }
                if target.receivedAtEpoch > 0 {
                    if msg.timestamp < target.receivedAtEpoch { return true }
                    if msg.timestamp > target.receivedAtEpoch { return false }
                    return msg.rowId < target.rowId
                } else {
                    return msg.rowId < target.rowId
                }
            }

            let cappedPrior = maxPriorMessages > 0 ? Array(allPrior.suffix(maxPriorMessages)) : []
            var priorContexts: [ThreadMessageContext] = []
            priorContexts.reserveCapacity(cappedPrior.count)

            for msg in cappedPrior {
                let snippet: String
                if let cached = bodyCache[msg.rowId] {
                    snippet = cached
                } else {
                    var resolvedBody: String? = nil
                    if let rawProvided = bodyProvider(msg.rowId, msg.mailboxId) {
                        let cleaned = cleanAndTruncateBody(rawProvided)
                        if !cleaned.isEmpty {
                            resolvedBody = cleaned
                        }
                    }
                    if resolvedBody == nil && !msg.alternateLocations.isEmpty {
                        for alt in msg.alternateLocations {
                            if let altRaw = bodyProvider(alt.rowId, alt.mailboxId) {
                                let cleaned = cleanAndTruncateBody(altRaw)
                                if !cleaned.isEmpty {
                                    resolvedBody = cleaned
                                    break
                                }
                            }
                        }
                    }
                    let finalBody = resolvedBody ?? cleanAndTruncateBody(msg.summary)
                    bodyCache[msg.rowId] = finalBody
                    snippet = finalBody
                }

                priorContexts.append(
                    ThreadMessageContext(
                        rowId: msg.rowId,
                        rfcMessageId: nil,
                        from: msg.from,
                        subject: msg.subject,
                        dateISO: Self.formatEpochISO8601(msg.timestamp),
                        bodySnippet: snippet,
                        sentByOwner: msg.sentByOwner,
                        isFlagged: msg.isFlagged,
                        mailboxPath: msg.mailboxPath
                    )
                )
            }

            results[target.rowId] = ConversationContext(
                conversationId: target.conversationId,
                messageCount: thread.count,
                sentByOwnerInThread: sentByOwnerInThread,
                hasFlaggedInThread: hasFlaggedInThread,
                priorMessages: priorContexts
            )
        }

        return results
    }

    private func resolveFallbackStandaloneTargets(
        targets: [ConversationLookupTarget],
        sentMailboxIds: Set<Int64>,
        using mailConn: SQLiteConnection
    ) throws -> [Int64: ConversationContext] {
        var out: [Int64: ConversationContext] = [:]
        let rowIds = Array(Set(targets.map(\.rowId)))
        guard !rowIds.isEmpty else { return out }

        let sentLabeledRowIds = try Self.fetchSentLabeledRowIds(
            rowIds: rowIds,
            sentMailboxIds: sentMailboxIds,
            using: mailConn
        )

        var rowMeta: [Int64: (mailboxId: Int64, flagged: Bool, addr: String)] = [:]
        for chunk in rowIds.chunked(into: 400) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            let sql = """
            SELECT m.ROWID, m.mailbox, m.flagged, COALESCE(a.address, '')
            FROM messages m
            LEFT JOIN addresses a ON m.sender = a.ROWID
            WHERE m.ROWID IN (\(placeholders)) AND +m.deleted = 0;
            """
            let rows = try mailConn.query(sql, bindings: chunk.map { .int($0) }) { row in
                (row.int64(0), row.int64(1), row.int64(2) != 0, row.string(3) ?? "")
            }
            for (rid, mbId, flagged, addr) in rows {
                rowMeta[rid] = (mbId, flagged, addr)
            }
        }

        for target in targets {
            let meta = rowMeta[target.rowId]
            let isSentMailbox = meta.map { sentMailboxIds.contains($0.mailboxId) } ?? false
            let isSentLabel = sentLabeledRowIds.contains(target.rowId)
            let isOwnerAddr = meta.map {
                let norm = Self.normalizeEmailAddress($0.addr)
                return !norm.isEmpty && ownerAddresses.contains(norm)
            } ?? false
            out[target.rowId] = ConversationContext(
                conversationId: target.conversationId,
                messageCount: 1,
                sentByOwnerInThread: isSentMailbox || isSentLabel || isOwnerAddr,
                hasFlaggedInThread: meta?.flagged ?? false,
                priorMessages: []
            )
        }
        return out
    }

    private static func fetchSentLabeledRowIds(
        rowIds: [Int64],
        sentMailboxIds: Set<Int64>,
        using mailConn: SQLiteConnection
    ) throws -> Set<Int64> {
        guard !sentMailboxIds.isEmpty, !rowIds.isEmpty, tableExists("labels", using: mailConn) else {
            return []
        }
        let sentMbArray = sentMailboxIds.sorted()
        let mbPlaceholders = Array(repeating: "?", count: sentMbArray.count).joined(separator: ",")
        let mbBindings = sentMbArray.map { SQLiteValue.int($0) }
        var sentLabeledRowIds = Set<Int64>()
        for rowChunk in rowIds.chunked(into: 400) {
            let rowPlaceholders = Array(repeating: "?", count: rowChunk.count).joined(separator: ",")
            let labelSQL = """
            SELECT DISTINCT message_id
            FROM labels
            WHERE mailbox_id IN (\(mbPlaceholders))
              AND message_id IN (\(rowPlaceholders));
            """
            let bindings = mbBindings + rowChunk.map { SQLiteValue.int($0) }
            let matched = try mailConn.query(labelSQL, bindings: bindings) { $0.int64(0) }
            sentLabeledRowIds.formUnion(matched)
        }
        return sentLabeledRowIds
    }

    // MARK: - Helpers: Normalization, Mailbox Role & Formatting

    /// Normalizes an email address (extracting `<addr>`, lowercasing, trimming, and
    /// canonicalizing Gmail dot-insensitivity / `googlemail.com` alias).
    public static func normalizeEmailAddress(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lt = s.lastIndex(of: "<"),
           let gt = s[lt...].firstIndex(of: ">"),
           lt < gt {
            s = String(s[s.index(after: lt)..<gt])
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'<>")).lowercased()
        guard !s.isEmpty else { return "" }

        let parts = s.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return s }

        var local = String(parts[0])
        var domain = String(parts[1])
        if domain == "googlemail.com" {
            domain = "gmail.com"
        }
        if domain == "gmail.com" {
            if let plus = local.firstIndex(of: "+") {
                let prefix = String(local[..<plus]).replacingOccurrences(of: ".", with: "")
                let suffix = String(local[plus...])
                local = prefix + suffix
            } else {
                local = local.replacingOccurrences(of: ".", with: "")
            }
        }
        return "\(local)@\(domain)"
    }

    /// Extracts and percent-decodes the mailbox folder path from an `Envelope Index` URL
    /// such as `imap://UUID/%5BGmail%5D/Sent%20Mail` or `ews://UUID/Sent%20Items`.
    public static func decodeMailboxPath(from urlString: String) -> String {
        if let schemeRange = urlString.range(of: "://") {
            let afterScheme = urlString[schemeRange.upperBound...]
            guard let slash = afterScheme.firstIndex(of: "/") else { return "" }
            let rawPath = String(afterScheme[afterScheme.index(after: slash)...])
            return rawPath.removingPercentEncoding ?? rawPath
        }
        return urlString.removingPercentEncoding ?? urlString
    }

    /// Returns `true` when a decoded mailbox path represents a Sent folder across
    /// Apple Mail / IMAP / Gmail / Exchange / localized Chinese folders.
    public static func isSentMailboxPath(_ decodedPath: String) -> Bool {
        let normalized = decodedPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ \t\r\n"))
            .lowercased()
        guard !normalized.isEmpty else { return false }

        let exactSentPaths: Set<String> = [
            "sent",
            "sent mail",
            "sent messages",
            "sent items",
            "[gmail]/sent mail",
            "[google mail]/sent mail",
            "[gmail]/已发送邮件",
            "[google mail]/已发送邮件",
            "已发送",
            "已发送邮件",
            "已寄件",
            "寄件备份",
            "寄件備份",
        ]
        if exactSentPaths.contains(normalized) {
            return true
        }

        let leaf = normalized.split(separator: "/").last.map(String.init) ?? normalized
        let sentLeaves: Set<String> = [
            "sent",
            "sent mail",
            "sent messages",
            "sent items",
            "已发送",
            "已发送邮件",
            "已寄件",
            "寄件备份",
            "寄件備份",
        ]
        return sentLeaves.contains(leaf)
    }

    /// Loads normalized owner email addresses from `~/Library/Accounts/Accounts4.sqlite` in strictly read-only mode.
    public static func loadSystemOwnerAddresses() -> Set<String> {
        let accDBPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Accounts/Accounts4.sqlite").path
        guard let conn = try? SQLiteConnection(readOnlyPath: accDBPath) else { return [] }
        guard let rows = try? conn.query(
            "SELECT ZUSERNAME FROM ZACCOUNT WHERE ZUSERNAME IS NOT NULL AND ZUSERNAME LIKE '%@%';",
            map: { $0.string(0) ?? "" }
        ) else {
            return []
        }
        return Set(rows.map(normalizeEmailAddress).filter { !$0.isEmpty })
    }

    /// Formats a Unix epoch timestamp (seconds) as UTC ISO-8601 (`YYYY-MM-DDTHH:MM:SSZ`),
    /// returning an empty string for non-positive timestamps.
    public static func formatEpochISO8601(_ epochSeconds: Int64) -> String {
        guard epochSeconds > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        return Date.ISO8601FormatStyle(timeZone: TimeZone(secondsFromGMT: 0)!).format(date)
    }

    private func cleanAndTruncateBody(_ raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        let stripped = Self.stripInvisibleFillers(raw)
        let normalized = EmlxParser.normalizePlainText(stripped)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard maxBodyCharacters > 0 else { return "" }
        if normalized.count <= maxBodyCharacters {
            return normalized
        }
        return String(normalized.prefix(maxBodyCharacters))
    }

    private static func stripInvisibleFillers(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            let v = scalar.value
            let isInvisibleFiller =
                v == 0x00AD ||
                v == 0x034F ||
                v == 0x2007 ||
                (v >= 0x200B && v <= 0x200F) ||
                (v >= 0x202A && v <= 0x202E) ||
                (v >= 0x2060 && v <= 0x206F) ||
                v == 0xFEFF
            if !isInvisibleFiller {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static func combineSubject(prefix: String, base: String) -> String {
        if prefix.isEmpty { return base }
        if base.isEmpty { return prefix.trimmingCharacters(in: .whitespaces) }
        return prefix + base
    }

    private static func formatFromHeader(name: String, address: String) -> String {
        let cleanAddr = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\""))
        if cleanName.isEmpty { return cleanAddr }
        if cleanAddr.isEmpty { return cleanName }
        if cleanName.caseInsensitiveCompare(cleanAddr) == .orderedSame { return cleanAddr }
        return "\(cleanName) <\(cleanAddr)>"
    }

    private static func tableExists(_ tableName: String, using conn: SQLiteConnection) -> Bool {
        let rows = try? conn.query(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
            bindings: [.text(tableName)]
        ) { $0.int64(0) }
        return !(rows ?? []).isEmpty
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var idx = 0
        while idx < count {
            let end = Swift.min(idx + size, count)
            chunks.append(Array(self[idx..<end]))
            idx = end
        }
        return chunks
    }
}

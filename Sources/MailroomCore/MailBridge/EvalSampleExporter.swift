import AppKit
import Foundation

// MARK: - Redaction Helpers

public enum MailAddressRedactor {
    /// 将邮箱地址脱敏为 `u***@domain.com`；UUID 原样保留；其余非空字符串返回 `***`。
    public static func redactAddress(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let atIdx = trimmed.lastIndex(of: "@") {
            let local = String(trimmed[..<atIdx])
            let domain = String(trimmed[trimmed.index(after: atIdx)...])
            guard !domain.isEmpty else { return "***" }
            if local.isEmpty {
                return "***@\(domain)"
            }
            return "\(local.prefix(1))***@\(domain)"
        }
        if UUID(uuidString: trimmed) != nil {
            return trimmed
        }
        return "***"
    }

    /// 脱敏任意文本中出现的所有邮箱地址，保留其余非邮箱描述文本（如 `Gmail`、`工作`）。
    public static func redactText(_ raw: String) -> String {
        guard raw.contains("@") else { return raw }
        let pattern = #"[^\s<>@"']+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return redactAddress(raw)
        }
        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return raw }
        var output = raw
        for match in matches.reversed() {
            let token = ns.substring(with: match.range)
            let masked = redactAddress(token)
            output = (output as NSString).replacingCharacters(in: match.range, with: masked)
        }
        return output
    }
}

// MARK: - Doctor Report Models

public enum ProviderSemantics: String, Codable, Sendable, Equatable {
    case gmailLabels = "gmail_labels"
    case exchangeEWS = "exchange_ews"
    case icloudOrIMAP = "icloud_or_imap"
}

public struct MailboxResolutionDiagnostic: Codable, Sendable, Equatable {
    public let inboxPaths: [String]
    public let primaryInboxPath: String
    public let archivePath: String?
    public let trashPath: String?
    public let sentPath: String?
    public let totalMailboxCount: Int

    public init(
        inboxPaths: [String],
        primaryInboxPath: String,
        archivePath: String?,
        trashPath: String?,
        sentPath: String?,
        totalMailboxCount: Int
    ) {
        self.inboxPaths = inboxPaths
        self.primaryInboxPath = primaryInboxPath
        self.archivePath = archivePath
        self.trashPath = trashPath
        self.sentPath = sentPath
        self.totalMailboxCount = totalMailboxCount
    }
}

public struct AccountDiagnostic: Codable, Sendable, Equatable {
    public let accountId: String
    public let label: String
    public let redactedAddress: String
    public let scheme: String
    public let providerSemantics: ProviderSemantics
    public let mailboxes: MailboxResolutionDiagnostic
    public let inboxDirectCount: Int
    public let inboxLabelCount: Int
    public let inboxCombinedCount: Int

    public init(
        accountId: String,
        label: String,
        redactedAddress: String,
        scheme: String,
        providerSemantics: ProviderSemantics,
        mailboxes: MailboxResolutionDiagnostic,
        inboxDirectCount: Int,
        inboxLabelCount: Int,
        inboxCombinedCount: Int
    ) {
        self.accountId = accountId
        self.label = label
        self.redactedAddress = redactedAddress
        self.scheme = scheme
        self.providerSemantics = providerSemantics
        self.mailboxes = mailboxes
        self.inboxDirectCount = inboxDirectCount
        self.inboxLabelCount = inboxLabelCount
        self.inboxCombinedCount = inboxCombinedCount
    }
}

public struct ShardResolutionDiagnostic: Codable, Sendable, Equatable {
    public let sampledCount: Int
    public let fullEmlxHits: Int
    public let partialEmlxHits: Int
    public let missingFiles: Int
    public let parseErrors: Int
    public let hitRate: Double

    public init(
        sampledCount: Int,
        fullEmlxHits: Int,
        partialEmlxHits: Int,
        missingFiles: Int,
        parseErrors: Int,
        hitRate: Double
    ) {
        self.sampledCount = sampledCount
        self.fullEmlxHits = fullEmlxHits
        self.partialEmlxHits = partialEmlxHits
        self.missingFiles = missingFiles
        self.parseErrors = parseErrors
        self.hitRate = hitRate
    }
}

public struct BridgeDoctorReport: Codable, Sendable, Equatable {
    public let generatedAtISO: String
    public let mailStorePath: String
    public let accessStatus: String
    public let envelopeIndexWALMode: String
    public let envelopeIndexQueryLatencyMs: Double
    public let mailAppRunning: Bool
    public let sampleLimit: Int
    public let accounts: [AccountDiagnostic]
    public let shardResolution: ShardResolutionDiagnostic
    public let notes: [String]

    public init(
        generatedAtISO: String,
        mailStorePath: String,
        accessStatus: String,
        envelopeIndexWALMode: String,
        envelopeIndexQueryLatencyMs: Double,
        mailAppRunning: Bool,
        sampleLimit: Int,
        accounts: [AccountDiagnostic],
        shardResolution: ShardResolutionDiagnostic,
        notes: [String]
    ) {
        self.generatedAtISO = generatedAtISO
        self.mailStorePath = mailStorePath
        self.accessStatus = accessStatus
        self.envelopeIndexWALMode = envelopeIndexWALMode
        self.envelopeIndexQueryLatencyMs = envelopeIndexQueryLatencyMs
        self.mailAppRunning = mailAppRunning
        self.sampleLimit = sampleLimit
        self.accounts = accounts
        self.shardResolution = shardResolution
        self.notes = notes
    }

    public static func defaultAccountsDBPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Accounts/Accounts4.sqlite")
            .path
    }

    public static func defaultIsMailAppRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty
    }

    /// 严格只读检查 `~/Library/Mail/V*`、`Envelope Index`、`Accounts4.sqlite` 与分片 `.emlx` 命中率。
    /// 绝不输出任何邮件主题、发件人姓名/地址或正文内容。
    public static func inspect(
        mailVDir: URL? = MailStoreEnvironment.locateMailVDirectory(),
        accountsDBPath: String? = defaultAccountsDBPath(),
        limit: Int = 40,
        isMailAppRunning: () -> Bool = defaultIsMailAppRunning
    ) -> BridgeDoctorReport {
        let clampedLimit = max(1, min(limit, 500))
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let mailRunning = isMailAppRunning()

        guard let vDir = mailVDir else {
            return BridgeDoctorReport(
                generatedAtISO: nowISO,
                mailStorePath: "",
                accessStatus: "mail_store_not_found",
                envelopeIndexWALMode: "unknown",
                envelopeIndexQueryLatencyMs: 0,
                mailAppRunning: mailRunning,
                sampleLimit: clampedLimit,
                accounts: [],
                shardResolution: ShardResolutionDiagnostic(
                    sampledCount: 0,
                    fullEmlxHits: 0,
                    partialEmlxHits: 0,
                    missingFiles: 0,
                    parseErrors: 0,
                    hitRate: 0
                ),
                notes: ["Mail V* directory not found."]
            )
        }

        let indexPath = vDir.appendingPathComponent("MailData/Envelope Index").path
        guard FileManager.default.fileExists(atPath: indexPath) else {
            return BridgeDoctorReport(
                generatedAtISO: nowISO,
                mailStorePath: vDir.path,
                accessStatus: "mail_store_not_found",
                envelopeIndexWALMode: "unknown",
                envelopeIndexQueryLatencyMs: 0,
                mailAppRunning: mailRunning,
                sampleLimit: clampedLimit,
                accounts: [],
                shardResolution: ShardResolutionDiagnostic(
                    sampledCount: 0,
                    fullEmlxHits: 0,
                    partialEmlxHits: 0,
                    missingFiles: 0,
                    parseErrors: 0,
                    hitRate: 0
                ),
                notes: ["Envelope Index not found at expected path."]
            )
        }

        let mailConn: SQLiteConnection
        do {
            mailConn = try SQLiteConnection(readOnlyPath: indexPath)
            _ = try mailConn.query("SELECT 1 FROM mailboxes LIMIT 1;") { $0.int64(0) }
        } catch {
            return BridgeDoctorReport(
                generatedAtISO: nowISO,
                mailStorePath: vDir.path,
                accessStatus: "full_disk_access_required",
                envelopeIndexWALMode: "unknown",
                envelopeIndexQueryLatencyMs: 0,
                mailAppRunning: mailRunning,
                sampleLimit: clampedLimit,
                accounts: [],
                shardResolution: ShardResolutionDiagnostic(
                    sampledCount: 0,
                    fullEmlxHits: 0,
                    partialEmlxHits: 0,
                    missingFiles: 0,
                    parseErrors: 0,
                    hitRate: 0
                ),
                notes: ["Failed to open Envelope Index read-only (Full Disk Access may be required)."]
            )
        }

        let walMode = (try? mailConn.query("PRAGMA journal_mode;") { $0.string(0) ?? "unknown" })?.first ?? "unknown"
        var notes: [String] = []
        if walMode.lowercased() != "wal" {
            notes.append("Envelope Index journal_mode is '\(walMode)' (expected 'wal').")
        }

        let accountMeta = MailStoreInspector.readSystemAccountMetadata(accountsDBPath: accountsDBPath)
        let mailboxStore = (try? MailStoreInspector.loadAccountsAndMailboxes(using: mailConn, accountMeta: accountMeta))
            ?? MailStoreInspector.LoadedStore(mailboxesById: [:], accountsByUUID: [:], sentMailboxIds: [], ownerAddresses: [])

        var accountDiagnostics: [AccountDiagnostic] = []
        let sortedAccounts = mailboxStore.accountsByUUID.values.sorted { $0.uuid < $1.uuid }

        for acc in sortedAccounts {
            let inboxIds = acc.inboxMailboxes.map(\.rowId)
            let inClause = inboxIds.map(String.init).joined(separator: ",")

            let directCount = (try? mailConn.query(
                "SELECT COUNT(DISTINCT ROWID) FROM messages WHERE mailbox IN (\(inClause)) AND deleted = 0;"
            ) { Int($0.int64(0)) })?.first ?? 0

            let labelCount = (try? mailConn.query(
                """
                SELECT COUNT(DISTINCT l.message_id)
                FROM labels l
                JOIN messages m ON m.ROWID = l.message_id
                WHERE l.mailbox_id IN (\(inClause)) AND m.deleted = 0;
                """
            ) { Int($0.int64(0)) })?.first ?? 0

            let combinedCount = (try? mailConn.query(
                """
                SELECT COUNT(*) FROM (
                    SELECT ROWID AS rid FROM messages WHERE mailbox IN (\(inClause)) AND deleted = 0
                    UNION
                    SELECT l.message_id AS rid
                    FROM labels l
                    JOIN messages m ON m.ROWID = l.message_id
                    WHERE l.mailbox_id IN (\(inClause)) AND m.deleted = 0
                );
                """
            ) { Int($0.int64(0)) })?.first ?? directCount

            if acc.archivePath == nil {
                notes.append("Account \(acc.uuid) (\(acc.providerSemantics.rawValue)) has no Archive mailbox yet.")
            }
            if acc.trashPath == nil {
                notes.append("Account \(acc.uuid) (\(acc.providerSemantics.rawValue)) has no Trash mailbox resolved.")
            }
            if acc.sentPath == nil {
                notes.append("Account \(acc.uuid) (\(acc.providerSemantics.rawValue)) has no Sent mailbox resolved.")
            }

            accountDiagnostics.append(
                AccountDiagnostic(
                    accountId: acc.uuid,
                    label: MailAddressRedactor.redactText(acc.shortLabel),
                    redactedAddress: MailAddressRedactor.redactAddress(acc.rawAddress),
                    scheme: acc.scheme,
                    providerSemantics: acc.providerSemantics,
                    mailboxes: MailboxResolutionDiagnostic(
                        inboxPaths: acc.inboxMailboxes.map(\.asPath),
                        primaryInboxPath: acc.primaryInboxPath,
                        archivePath: acc.archivePath,
                        trashPath: acc.trashPath,
                        sentPath: acc.sentPath,
                        totalMailboxCount: acc.totalMailboxCount
                    ),
                    inboxDirectCount: directCount,
                    inboxLabelCount: labelCount,
                    inboxCombinedCount: combinedCount
                )
            )
        }

        let allInboxIds = sortedAccounts.flatMap { $0.inboxMailboxes.map(\.rowId) }
        var queryLatencyMs: Double = 0
        var sampledRows: [(rowId: Int64, physicalMailboxId: Int64)] = []

        if !allInboxIds.isEmpty {
            let inClause = allInboxIds.map(String.init).joined(separator: ",")
            let queryStart = ContinuousClock.now
            // 仅验证索引与 JOIN 延迟，不读取或存储主题/地址/正文字符串
            let sql = """
            WITH inbox_candidates AS (
                SELECT ROWID AS rid, mailbox AS inbox_mb FROM messages WHERE mailbox IN (\(inClause)) AND deleted = 0
                UNION
                SELECT message_id AS rid, mailbox_id AS inbox_mb FROM labels WHERE mailbox_id IN (\(inClause))
            )
            SELECT m.ROWID,
                   m.mailbox,
                   ic.inbox_mb,
                   m.read,
                   m.flagged,
                   COALESCE(m.date_received, m.date_sent, 0) AS recv_ts
            FROM inbox_candidates ic
            JOIN messages m ON m.ROWID = ic.rid
            LEFT JOIN subjects s ON m.subject = s.ROWID
            LEFT JOIN addresses a ON m.sender = a.ROWID
            LEFT JOIN summaries sm ON m.summary = sm.ROWID
            WHERE m.deleted = 0
            ORDER BY recv_ts DESC
            LIMIT \(clampedLimit);
            """
            sampledRows = (try? mailConn.query(sql) { row in
                (row.int64(0), row.int64(1))
            }) ?? []
            let elapsed = ContinuousClock.now - queryStart
            queryLatencyMs = Self.durationMilliseconds(elapsed)
        }

        var mboxDataRootCache: [Int64: URL] = [:]
        var fullHits = 0
        var partialHits = 0
        var missing = 0
        var parseErrors = 0

        for (rowId, mbId) in sampledRows {
            guard let located = MailStoreInspector.locateEmlxFile(
                rowId: rowId,
                physicalMailboxId: mbId,
                mailVDir: vDir,
                mailboxesById: mailboxStore.mailboxesById,
                dataRootCache: &mboxDataRootCache
            ) else {
                missing += 1
                continue
            }
            do {
                _ = try EmlxParser.parseFile(at: located.url)
                if located.isPartial {
                    partialHits += 1
                } else {
                    fullHits += 1
                }
            } catch {
                parseErrors += 1
            }
        }

        let sampledCount = sampledRows.count
        let hitRate = sampledCount > 0
            ? ((Double(fullHits + partialHits) / Double(sampledCount)) * 10_000).rounded() / 10_000
            : 0

        return BridgeDoctorReport(
            generatedAtISO: nowISO,
            mailStorePath: vDir.path,
            accessStatus: "ready",
            envelopeIndexWALMode: walMode,
            envelopeIndexQueryLatencyMs: (queryLatencyMs * 100).rounded() / 100,
            mailAppRunning: mailRunning,
            sampleLimit: clampedLimit,
            accounts: accountDiagnostics,
            shardResolution: ShardResolutionDiagnostic(
                sampledCount: sampledCount,
                fullEmlxHits: fullHits,
                partialEmlxHits: partialHits,
                missingFiles: missing,
                parseErrors: parseErrors,
                hitRate: hitRate
            ),
            notes: notes
        )
    }

    public func renderJSON(pretty: Bool = true) throws -> String {
        let encoder = JSONEncoder()
        if pretty {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        } else {
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        }
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    public func renderText() -> String {
        var lines: [String] = []
        lines.append("mailroom-bridge doctor")
        lines.append("  access: \(accessStatus)")
        lines.append("  store: \(mailStorePath)")
        lines.append("  envelope_index_wal: \(envelopeIndexWALMode)")
        lines.append(String(format: "  inbox_query_latency_ms: %.2f", envelopeIndexQueryLatencyMs))
        lines.append("  mail_app_running: \(mailAppRunning)")
        lines.append("  accounts (\(accounts.count)):")
        for acc in accounts {
            lines.append("    - [\(acc.label)] id=\(acc.accountId) addr=\(acc.redactedAddress) scheme=\(acc.scheme) semantics=\(acc.providerSemantics.rawValue)")
            lines.append("      inbox=\(acc.mailboxes.primaryInboxPath) (direct=\(acc.inboxDirectCount), labels=\(acc.inboxLabelCount), combined=\(acc.inboxCombinedCount))")
            lines.append("      archive=\(acc.mailboxes.archivePath ?? "<none>") trash=\(acc.mailboxes.trashPath ?? "<none>") sent=\(acc.mailboxes.sentPath ?? "<none>") total_mailboxes=\(acc.mailboxes.totalMailboxCount)")
        }
        let pct = String(format: "%.1f%%", shardResolution.hitRate * 100.0)
        lines.append("  shard_resolution (sample=\(shardResolution.sampledCount)): full=\(shardResolution.fullEmlxHits) partial=\(shardResolution.partialEmlxHits) missing=\(shardResolution.missingFiles) errors=\(shardResolution.parseErrors) hit_rate=\(pct)")
        if !notes.isEmpty {
            lines.append("  notes:")
            for note in notes {
                lines.append("    * \(note)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func durationMilliseconds(_ duration: Duration) -> Double {
        let comps = duration.components
        return Double(comps.seconds) * 1000.0 + Double(comps.attoseconds) / 1_000_000_000_000_000.0
    }
}

// MARK: - Eval Dataset Exporter (eval_gemini_emails.py / email_rules.py Compatible)

public struct EvalSelectionMetadata: Codable, Sendable, Equatable {
    public let query: String
    public let count: Int
    public let method: String
    public let bodyPolicy: String

    enum CodingKeys: String, CodingKey {
        case query, count, method
        case bodyPolicy = "body_policy"
    }

    public init(query: String, count: Int, method: String, bodyPolicy: String) {
        self.query = query
        self.count = count
        self.method = method
        self.bodyPolicy = bodyPolicy
    }
}

public struct EvalConversationMessage: Codable, Sendable, Equatable {
    public let from: String
    public let subject: String
    public let date: String
    public let body: String
    public let starred: Bool
    public let sentByOwner: Bool

    enum CodingKeys: String, CodingKey {
        case from, subject, date, body, starred
        case sentByOwner = "sent_by_owner"
    }

    public init(
        from: String,
        subject: String,
        date: String,
        body: String,
        starred: Bool,
        sentByOwner: Bool
    ) {
        self.from = from
        self.subject = subject
        self.date = date
        self.body = body
        self.starred = starred
        self.sentByOwner = sentByOwner
    }
}

public struct EvalEmailPayload: Codable, Sendable, Equatable {
    public let from: String
    public let to: String
    public let subject: String
    public let date: String
    public let body: String
    public let bodyRepresentation: String
    public let hasAttachments: Bool
    public let unloadedHtmlImages: Int
    public let bodyIsImageOnly: Bool
    public let conversationContextAvailable: Bool
    public let truncated: Bool
    public let starred: Bool
    public let sentByOwner: Bool

    enum CodingKeys: String, CodingKey {
        case from, to, subject, date, body
        case bodyRepresentation = "body_representation"
        case hasAttachments = "has_attachments"
        case unloadedHtmlImages = "unloaded_html_images"
        case bodyIsImageOnly = "body_is_image_only"
        case conversationContextAvailable = "conversation_context_available"
        case truncated
        case starred
        case sentByOwner = "sent_by_owner"
    }

    public init(
        from: String,
        to: String,
        subject: String,
        date: String,
        body: String,
        bodyRepresentation: String,
        hasAttachments: Bool,
        unloadedHtmlImages: Int,
        bodyIsImageOnly: Bool,
        conversationContextAvailable: Bool,
        truncated: Bool,
        starred: Bool,
        sentByOwner: Bool
    ) {
        self.from = from
        self.to = to
        self.subject = subject
        self.date = date
        self.body = body
        self.bodyRepresentation = bodyRepresentation
        self.hasAttachments = hasAttachments
        self.unloadedHtmlImages = unloadedHtmlImages
        self.bodyIsImageOnly = bodyIsImageOnly
        self.conversationContextAvailable = conversationContextAvailable
        self.truncated = truncated
        self.starred = starred
        self.sentByOwner = sentByOwner
    }
}

public struct EvalDatasetSample: Codable, Sendable, Equatable {
    public let id: String
    public let gmailId: String
    public let sourceUrl: String
    public let email: EvalEmailPayload
    public let conversation: [EvalConversationMessage]

    enum CodingKeys: String, CodingKey {
        case id
        case gmailId = "gmail_id"
        case sourceUrl = "source_url"
        case email
        case conversation
    }

    public init(
        id: String,
        gmailId: String,
        sourceUrl: String,
        email: EvalEmailPayload,
        conversation: [EvalConversationMessage]
    ) {
        self.id = id
        self.gmailId = gmailId
        self.sourceUrl = sourceUrl
        self.email = email
        self.conversation = conversation
    }
}

public struct EvalDatasetDocument: Codable, Sendable, Equatable {
    public let selection: EvalSelectionMetadata
    public let samples: [EvalDatasetSample]

    public init(selection: EvalSelectionMetadata, samples: [EvalDatasetSample]) {
        self.selection = selection
        self.samples = samples
    }
}

public enum EvalExportError: Error, LocalizedError, Equatable {
    case outputFileExists(String)
    case mailStoreUnavailable(String)
    case invalidLimit(Int)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .outputFileExists(let path):
            return "输出文件已存在，拒绝覆盖（传入 --force 可覆盖）：\(path)"
        case .mailStoreUnavailable(let reason):
            return "无法读取 Apple Mail 存储：\(reason)"
        case .invalidLimit(let limit):
            return "无效的 --limit 参数（必须大于 0）：\(limit)"
        case .writeFailed(let msg):
            return "写入评测集失败：\(msg)"
        }
    }
}

public enum EvalDatasetExporter {
    /// 与 `email_rules.py` `INVISIBLE_FILLER_RE` 对齐：清理软连字符、零宽字符、双向控制符及 BOM，并压缩多余空行。
    public static func cleanBodyText(_ text: String) -> String {
        EmlxParser.cleanBodyText(text)
    }

    /// 与 `email_rules.py` `is_boilerplate_stub` 对齐。
    public static func isBoilerplateStub(_ body: String) -> Bool {
        EmlxParser.isBoilerplateStub(body)
    }

    /// 与 `eval_gemini_emails.py` `body_is_image_only` 对齐。
    public static func computeBodyIsImageOnly(unloadedHtmlImages: Int, body: String) -> Bool {
        let nonWhitespaceCount = body.unicodeScalars.filter { !$0.properties.isWhitespace }.count
        let nonEmpty = !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (unloadedHtmlImages > 0 && nonWhitespaceCount < 150) || (nonEmpty && EmlxParser.isBoilerplateStub(body))
    }

    /// 从 V10 只读导出最多 `limit` 条收件箱样本（含同一 `conversation_id` 内最多 12 条历史对话与 `sent_by_owner` 标记）。
    public static func exportDataset(
        mailVDir: URL? = MailStoreEnvironment.locateMailVDirectory(),
        accountsDBPath: String? = BridgeDoctorReport.defaultAccountsDBPath(),
        limit: Int = 20
    ) throws -> EvalDatasetDocument {
        guard limit > 0 else {
            throw EvalExportError.invalidLimit(limit)
        }
        guard let vDir = mailVDir else {
            throw EvalExportError.mailStoreUnavailable("未找到 ~/Library/Mail/V* 目录")
        }
        let indexPath = vDir.appendingPathComponent("MailData/Envelope Index").path
        guard FileManager.default.fileExists(atPath: indexPath) else {
            throw EvalExportError.mailStoreUnavailable("Envelope Index 不存在：\(indexPath)")
        }

        let mailConn: SQLiteConnection
        do {
            mailConn = try SQLiteConnection(readOnlyPath: indexPath)
        } catch {
            throw EvalExportError.mailStoreUnavailable(error.localizedDescription)
        }

        let accountMeta = MailStoreInspector.readSystemAccountMetadata(accountsDBPath: accountsDBPath)
        let store = try MailStoreInspector.loadAccountsAndMailboxes(using: mailConn, accountMeta: accountMeta)
        let allInboxIds = store.accountsByUUID.values.flatMap { $0.inboxMailboxes.map(\.rowId) }

        guard !allInboxIds.isEmpty else {
            return EvalDatasetDocument(
                selection: EvalSelectionMetadata(
                    query: "apple_mail_v10:inbox",
                    count: 0,
                    method: "apple_mail_v10_inbox_latest",
                    bodyPolicy: "full_plain_text_or_html_with_image_alt"
                ),
                samples: []
            )
        }

        let inClause = allInboxIds.map(String.init).joined(separator: ",")
        let candidateLimit = max(limit * 3, limit + 40)

        struct CandidateRow {
            let rowId: Int64
            let physicalMailboxId: Int64
            let conversationId: Int64
            let flagged: Bool
            let recvTs: Int64
            let sqlSubject: String
            let sqlSenderAddr: String
            let sqlSenderName: String
            let sqlSummary: String
        }

        let sql = """
        WITH inbox_candidates AS (
            SELECT ROWID AS rid, mailbox AS inbox_mb FROM messages WHERE mailbox IN (\(inClause)) AND deleted = 0
            UNION
            SELECT message_id AS rid, mailbox_id AS inbox_mb FROM labels WHERE mailbox_id IN (\(inClause))
        )
        SELECT m.ROWID,
               m.mailbox,
               COALESCE(m.conversation_id, 0),
               m.flagged,
               COALESCE(m.date_received, m.date_sent, 0) AS recv_ts,
               COALESCE(s.subject, ''),
               COALESCE(a.address, ''),
               COALESCE(a.comment, ''),
               COALESCE(sm.summary, '')
        FROM inbox_candidates ic
        JOIN messages m ON m.ROWID = ic.rid
        LEFT JOIN subjects s ON m.subject = s.ROWID
        LEFT JOIN addresses a ON m.sender = a.ROWID
        LEFT JOIN summaries sm ON m.summary = sm.ROWID
        WHERE m.deleted = 0
        ORDER BY recv_ts DESC, m.ROWID DESC
        LIMIT \(candidateLimit);
        """

        let rawRows = try mailConn.query(sql) { row in
            CandidateRow(
                rowId: row.int64(0),
                physicalMailboxId: row.int64(1),
                conversationId: row.int64(2),
                flagged: row.int64(3) != 0,
                recvTs: row.int64(4),
                sqlSubject: row.string(5) ?? "",
                sqlSenderAddr: row.string(6) ?? "",
                sqlSenderName: row.string(7) ?? "",
                sqlSummary: row.string(8) ?? ""
            )
        }

        // 先筛选出不重复的最多 `limit` 条收件箱邮件，再交给 ConversationResolver 单次批量查线程
        struct SelectedEntry {
            let row: CandidateRow
            let msgId: MessageId
            let parsed: ParsedEmlx?
            let locatedPartial: Bool
            let hasAttachments: Bool
        }

        var selected: [SelectedEntry] = []
        var seenIds = Set<MessageId>()
        var dataRootCache: [Int64: URL] = [:]

        for row in rawRows {
            if selected.count >= limit { break }

            let located = MailStoreInspector.locateEmlxFile(
                rowId: row.rowId,
                physicalMailboxId: row.physicalMailboxId,
                mailVDir: vDir,
                mailboxesById: store.mailboxesById,
                dataRootCache: &dataRootCache
            )

            let parsed = located.flatMap { try? EmlxParser.parseFile(at: $0.url) }
            let rawId = parsed?.messageId ?? "rowid-\(row.rowId)@applemail.local"
            let msgId = MessageId(rawId)
            guard seenIds.insert(msgId).inserted else { continue }

            var hasAttachments = !(parsed?.attachments.isEmpty ?? true)
            if !hasAttachments {
                let attCount = (try? mailConn.query(
                    "SELECT COUNT(*) FROM attachments WHERE message = ?;",
                    bindings: [.int(row.rowId)]
                ) { Int($0.int64(0)) })?.first ?? 0
                hasAttachments = attCount > 0
            }

            selected.append(
                SelectedEntry(
                    row: row,
                    msgId: msgId,
                    parsed: parsed,
                    locatedPartial: located?.isPartial ?? false,
                    hasAttachments: hasAttachments
                )
            )
        }

        let resolver = ConversationResolver(ownerAddresses: store.ownerAddresses)
        let lookupTargets = selected.map {
            ConversationLookupTarget(
                rowId: $0.row.rowId,
                conversationId: $0.row.conversationId,
                receivedAtEpoch: $0.row.recvTs
            )
        }
        let conversationContexts = try resolver.resolve(
            targets: lookupTargets,
            using: mailConn
        ) { rowId, mailboxId in
            guard let located = MailStoreInspector.locateEmlxFile(
                rowId: rowId,
                physicalMailboxId: mailboxId,
                mailVDir: vDir,
                mailboxesById: store.mailboxesById,
                dataRootCache: &dataRootCache
            ),
            let parsed = try? EmlxParser.parseFile(at: located.url),
            !parsed.plainText.isEmpty else {
                return nil
            }
            return parsed.plainText
        }

        let sentLabeledRowIds = fetchSentLabeledRowIds(
            rowIds: selected.map(\.row.rowId),
            sentMailboxIds: store.sentMailboxIds,
            using: mailConn
        )
        let normalizedOwners = Set(store.ownerAddresses.map(ConversationResolver.normalizeEmailAddress))

        var samples: [EvalDatasetSample] = []
        samples.reserveCapacity(selected.count)
        let isoFormatter = ISO8601DateFormatter()

        for (idx, entry) in selected.enumerated() {
            let row = entry.row
            let parsed = entry.parsed

            let senderName = !row.sqlSenderName.isEmpty
                ? row.sqlSenderName
                : (parsed?.from?.name ?? "")
            let senderAddr = !row.sqlSenderAddr.isEmpty
                ? row.sqlSenderAddr
                : (parsed?.from?.address ?? "")
            let fromHeader = formatDisplayAddress(name: senderName, address: senderAddr)

            let toHeader = (parsed?.to ?? [])
                .map { formatDisplayAddress(name: $0.name, address: $0.address) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")

            let subject = !row.sqlSubject.isEmpty
                ? row.sqlSubject
                : (parsed?.subject ?? "")

            let fallbackDate = row.recvTs > 0
                ? isoFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(row.recvTs)))
                : ""
            let dateString = parsed?.dateHeader ?? fallbackDate

            let body: String
            let representation: String
            let unloadedHtmlImages: Int
            let isImageOnly: Bool

            if let parsed, parsed.bodyRepresentation != "empty" {
                body = parsed.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                representation = parsed.bodyRepresentation
                unloadedHtmlImages = parsed.unloadedHtmlImages
                isImageOnly = parsed.bodyIsImageOnly
            } else if !row.sqlSummary.isEmpty {
                body = EmlxParser.cleanBodyText(row.sqlSummary).trimmingCharacters(in: .whitespacesAndNewlines)
                representation = "summary_fallback"
                unloadedHtmlImages = parsed?.unloadedHtmlImages ?? 0
                isImageOnly = computeBodyIsImageOnly(unloadedHtmlImages: unloadedHtmlImages, body: body)
            } else {
                body = ""
                representation = "empty"
                unloadedHtmlImages = parsed?.unloadedHtmlImages ?? 0
                isImageOnly = false
            }

            let isTruncated = (parsed == nil)
                || (parsed?.isTruncated ?? false)
                || ((parsed?.isPartial ?? entry.locatedPartial) && (representation == "empty" || representation == "summary_fallback"))

            let normalizedSender = ConversationResolver.normalizeEmailAddress(senderAddr)
            let sentByOwner = store.sentMailboxIds.contains(row.physicalMailboxId)
                || sentLabeledRowIds.contains(row.rowId)
                || (!normalizedSender.isEmpty && normalizedOwners.contains(normalizedSender))

            let priorMessages: [EvalConversationMessage] = (conversationContexts[row.rowId]?.priorMessages ?? []).map { msg in
                EvalConversationMessage(
                    from: msg.from,
                    subject: msg.subject,
                    date: msg.dateISO,
                    body: msg.bodySnippet,
                    starred: msg.isFlagged,
                    sentByOwner: msg.sentByOwner
                )
            }

            let sampleId = String(format: "email-%02d", idx + 1)
            let gmailId = "<\(entry.msgId.rawValue)>"
            let sourceUrl = MailAdapterFunctions.nativeMailURLString(for: entry.msgId)

            samples.append(
                EvalDatasetSample(
                    id: sampleId,
                    gmailId: gmailId,
                    sourceUrl: sourceUrl,
                    email: EvalEmailPayload(
                        from: fromHeader,
                        to: toHeader,
                        subject: subject,
                        date: dateString,
                        body: body,
                        bodyRepresentation: representation,
                        hasAttachments: entry.hasAttachments,
                        unloadedHtmlImages: unloadedHtmlImages,
                        bodyIsImageOnly: isImageOnly,
                        conversationContextAvailable: !priorMessages.isEmpty,
                        truncated: isTruncated,
                        starred: row.flagged,
                        sentByOwner: sentByOwner
                    ),
                    conversation: priorMessages
                )
            )
        }

        return EvalDatasetDocument(
            selection: EvalSelectionMetadata(
                query: "apple_mail_v10:inbox",
                count: samples.count,
                method: "apple_mail_v10_inbox_latest",
                bodyPolicy: "full_plain_text_or_html_with_image_alt"
            ),
            samples: samples
        )
    }

    /// 将评测集写为 JSON 文件（强制 `0600` 权限）；若文件已存在且 `force == false` 则拒绝覆盖。
    public static func writeDataset(
        _ document: EvalDatasetDocument,
        to outputURL: URL,
        force: Bool = false
    ) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: outputURL.path) && !force {
            throw EvalExportError.outputFileExists(outputURL.path)
        }

        let parentDir = outputURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parentDir.path) {
            try fm.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(document)
        data.append(UInt8(ascii: "\n"))

        if !fm.createFile(
            atPath: outputURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) {
            throw EvalExportError.writeFailed("createFile failed at \(outputURL.path)")
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
    }

    // MARK: - Private Helpers

    private static func fetchSentLabeledRowIds(
        rowIds: [Int64],
        sentMailboxIds: Set<Int64>,
        using mailConn: SQLiteConnection
    ) -> Set<Int64> {
        guard !rowIds.isEmpty, !sentMailboxIds.isEmpty else { return [] }
        let rowClause = rowIds.map(String.init).joined(separator: ",")
        let sentClause = sentMailboxIds.map(String.init).joined(separator: ",")
        guard let hits = try? mailConn.query(
            "SELECT DISTINCT message_id FROM labels WHERE message_id IN (\(rowClause)) AND mailbox_id IN (\(sentClause));",
            map: { $0.int64(0) }
        ) else {
            return []
        }
        return Set(hits)
    }

    private static func formatDisplayAddress(name: String, address: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddr = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let localPart = trimmedAddr.split(separator: "@", maxSplits: 1).first.map(String.init)
        if !trimmedName.isEmpty
            && !trimmedAddr.isEmpty
            && trimmedName.caseInsensitiveCompare(trimmedAddr) != .orderedSame
            && localPart.map({ trimmedName.caseInsensitiveCompare($0) != .orderedSame }) ?? true {
            return "\(trimmedName) <\(trimmedAddr)>"
        }
        return !trimmedAddr.isEmpty ? trimmedAddr : trimmedName
    }
}

// MARK: - Internal V10 Store Inspector

private enum MailStoreInspector {
    struct MailboxRecord {
        let rowId: Int64
        let scheme: String
        let accountUUID: String
        let decodedPath: String
        let totalCount: Int64
    }

    struct ResolvedAccount {
        let uuid: String
        let shortLabel: String
        let rawAddress: String
        let scheme: String
        let providerSemantics: ProviderSemantics
        let inboxMailboxes: [(rowId: Int64, asPath: String)]
        let primaryInboxPath: String
        let archivePath: String?
        let trashPath: String?
        let sentPath: String?
        let totalMailboxCount: Int
    }

    struct LoadedStore {
        let mailboxesById: [Int64: MailboxRecord]
        let accountsByUUID: [String: ResolvedAccount]
        let sentMailboxIds: Set<Int64>
        let ownerAddresses: Set<String>
    }

    struct LocatedEmlx {
        let url: URL
        let isPartial: Bool
    }

    struct AccountSystemMeta {
        let description: String?
        let address: String?
        let typeIdentifier: String?
    }

    static func readSystemAccountMetadata(accountsDBPath: String?) -> [String: AccountSystemMeta] {
        guard let accountsDBPath, !accountsDBPath.isEmpty,
              FileManager.default.fileExists(atPath: accountsDBPath),
              let conn = try? SQLiteConnection(readOnlyPath: accountsDBPath) else {
            return [:]
        }
        let sql = """
        SELECT c.ZIDENTIFIER,
               COALESCE(NULLIF(c.ZACCOUNTDESCRIPTION, ''), p.ZACCOUNTDESCRIPTION),
               COALESCE(NULLIF(c.ZUSERNAME, ''), p.ZUSERNAME),
               COALESCE(ct.ZIDENTIFIER, pt.ZIDENTIFIER)
        FROM ZACCOUNT c
        LEFT JOIN ZACCOUNT p ON c.ZPARENTACCOUNT = p.Z_PK
        LEFT JOIN ZACCOUNTTYPE ct ON c.ZACCOUNTTYPE = ct.Z_PK
        LEFT JOIN ZACCOUNTTYPE pt ON p.ZACCOUNTTYPE = pt.Z_PK
        WHERE c.ZIDENTIFIER IS NOT NULL;
        """
        guard let rows = try? conn.query(sql, map: {
            ($0.string(0) ?? "", $0.string(1), $0.string(2), $0.string(3))
        }) else {
            // Fallback for minimal synthetic Accounts4 schemas without ZACCOUNTTYPE
            let fallbackSQL = """
            SELECT c.ZIDENTIFIER,
                   COALESCE(NULLIF(c.ZACCOUNTDESCRIPTION, ''), p.ZACCOUNTDESCRIPTION),
                   COALESCE(NULLIF(c.ZUSERNAME, ''), p.ZUSERNAME)
            FROM ZACCOUNT c
            LEFT JOIN ZACCOUNT p ON c.ZPARENTACCOUNT = p.Z_PK
            WHERE c.ZIDENTIFIER IS NOT NULL;
            """
            guard let fallbackRows = try? conn.query(fallbackSQL, map: {
                ($0.string(0) ?? "", $0.string(1), $0.string(2))
            }) else {
                return [:]
            }
            var fallbackMap: [String: AccountSystemMeta] = [:]
            for (id, desc, user) in fallbackRows where !id.isEmpty {
                fallbackMap[id] = AccountSystemMeta(description: desc, address: user, typeIdentifier: nil)
            }
            return fallbackMap
        }
        var map: [String: AccountSystemMeta] = [:]
        for (id, desc, user, typeId) in rows where !id.isEmpty {
            map[id] = AccountSystemMeta(description: desc, address: user, typeIdentifier: typeId)
        }
        return map
    }

    static func loadAccountsAndMailboxes(
        using mailConn: SQLiteConnection,
        accountMeta: [String: AccountSystemMeta]
    ) throws -> LoadedStore {
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

        let archiveCandidates = [
            "[Gmail]/All Mail", "[Gmail]/所有邮件", "[Google Mail]/All Mail",
            "Archive", "Archives", "归档"
        ]
        let trashCandidates = [
            "[Gmail]/Trash", "[Gmail]/已删除邮件", "[Google Mail]/Trash",
            "Deleted Messages", "Deleted Items", "Trash", "废纸篓", "已删除邮件"
        ]
        let sentCandidates = [
            "[Gmail]/Sent Mail", "[Gmail]/已发送邮件", "[Google Mail]/Sent Mail",
            "Sent Items", "Sent Messages", "Sent", "已发送", "已发送邮件"
        ]

        var resolved: [String: ResolvedAccount] = [:]
        var sentMailboxIds = Set<Int64>()
        var ownerAddresses = Set<String>()

        for (uuid, mbs) in groupedByAccount {
            let inboxes = mbs.filter { mb in
                let lower = mb.decodedPath.lowercased()
                return lower == "inbox" || mb.decodedPath == "收件箱"
            }.sorted { a, b in
                if a.totalCount != b.totalCount { return a.totalCount > b.totalCount }
                return a.decodedPath == "INBOX"
            }
            guard let primaryInbox = inboxes.first else { continue }

            let archiveMb = archiveCandidates.compactMap { cand in
                mbs.first { $0.decodedPath.caseInsensitiveCompare(cand) == .orderedSame }
            }.first

            let trashMb = trashCandidates.compactMap { cand in
                mbs.first { $0.decodedPath.caseInsensitiveCompare(cand) == .orderedSame }
            }.first

            let sentMb = sentCandidates.compactMap { cand in
                mbs.first { $0.decodedPath.caseInsensitiveCompare(cand) == .orderedSame }
            }.first

            for mb in mbs {
                if sentCandidates.contains(where: { mb.decodedPath.caseInsensitiveCompare($0) == .orderedSame }) {
                    sentMailboxIds.insert(mb.rowId)
                }
            }

            let meta = accountMeta[uuid]
            let address = meta?.address ?? uuid
            if address.contains("@") {
                ownerAddresses.insert(address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }

            let scheme = primaryInbox.scheme
            let semantics = classifyProviderSemantics(
                scheme: scheme,
                typeIdentifier: meta?.typeIdentifier,
                mailboxes: mbs
            )
            let label = makeShortAccountLabel(rawLabel: meta?.description, address: address, mailboxes: mbs)

            resolved[uuid] = ResolvedAccount(
                uuid: uuid,
                shortLabel: label,
                rawAddress: address,
                scheme: scheme,
                providerSemantics: semantics,
                inboxMailboxes: inboxes.map { ($0.rowId, $0.decodedPath) },
                primaryInboxPath: primaryInbox.decodedPath,
                archivePath: archiveMb?.decodedPath,
                trashPath: trashMb?.decodedPath,
                sentPath: sentMb?.decodedPath,
                totalMailboxCount: mbs.count
            )
        }

        return LoadedStore(
            mailboxesById: parsedMailboxes,
            accountsByUUID: resolved,
            sentMailboxIds: sentMailboxIds,
            ownerAddresses: ownerAddresses
        )
    }

    static func classifyProviderSemantics(
        scheme: String,
        typeIdentifier: String?,
        mailboxes: [MailboxRecord]
    ) -> ProviderSemantics {
        if scheme == "ews" {
            return .exchangeEWS
        }
        if mailboxes.contains(where: {
            $0.decodedPath.hasPrefix("[Gmail]") || $0.decodedPath.hasPrefix("[Google Mail]")
        }) {
            return .gmailLabels
        }
        if typeIdentifier == "com.apple.account.Google" {
            return .gmailLabels
        }
        return .icloudOrIMAP
    }

    static func makeShortAccountLabel(
        rawLabel: String?,
        address: String,
        mailboxes: [MailboxRecord]
    ) -> String {
        if let raw = rawLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            if !raw.contains("@") && raw.count <= 12 {
                return raw
            }
        }
        let lowerAddr = address.lowercased()
        if lowerAddr.hasSuffix("@gmail.com")
            || lowerAddr.hasSuffix("@googlemail.com")
            || mailboxes.contains(where: { $0.decodedPath.hasPrefix("[Gmail]") }) {
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

    static func locateEmlxFile(
        rowId: Int64,
        physicalMailboxId: Int64,
        mailVDir: URL,
        mailboxesById: [Int64: MailboxRecord],
        dataRootCache: inout [Int64: URL]
    ) -> LocatedEmlx? {
        guard let dataRoot = resolveMboxDataRoot(
            for: physicalMailboxId,
            mailVDir: mailVDir,
            mailboxesById: mailboxesById,
            cache: &dataRootCache
        ) else {
            return nil
        }
        let shardDir = AppleMailAdapter.shardMessagesDirectory(dataRoot: dataRoot, rowId: rowId)
        let fullURL = shardDir.appendingPathComponent("\(rowId).emlx")
        if FileManager.default.fileExists(atPath: fullURL.path) {
            return LocatedEmlx(url: fullURL, isPartial: false)
        }
        let partialURL = shardDir.appendingPathComponent("\(rowId).partial.emlx")
        if FileManager.default.fileExists(atPath: partialURL.path) {
            return LocatedEmlx(url: partialURL, isPartial: true)
        }
        return nil
    }

    private static func resolveMboxDataRoot(
        for mailboxId: Int64,
        mailVDir: URL,
        mailboxesById: [Int64: MailboxRecord],
        cache: inout [Int64: URL]
    ) -> URL? {
        if let cached = cache[mailboxId] {
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
                cache[mailboxId] = candidateData
                return candidateData
            }
        }
        return nil
    }
}


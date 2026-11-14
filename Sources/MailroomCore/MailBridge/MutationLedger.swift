import Foundation

public enum MutationAction: String, Codable, Sendable, CaseIterable {
    case archive
    case keep
    case trash
    case restore
    case rescue
}

public enum MutationStatus: String, Codable, Sendable, CaseIterable {
    case inFlight
    case committed
    case failed
}

public enum UndoAction: String, Codable, Sendable, CaseIterable {
    case archived
    case kept
    case trashed
    case shadowRescued
}

public struct PendingMutationRecord: Equatable, Codable, Sendable, Identifiable {
    public var id: String { mutationId }
    public let mutationId: String
    public let rfcMessageId: String
    public let action: MutationAction
    public let status: MutationStatus
    public let accountUUID: String
    public let sourceMailbox: String
    public let destinationMailbox: String
    public let inboxPath: String
    public let expectedRead: Bool?
    public let expectedFlagged: Bool?
    public let preMoveRowId: Int64
    public let maxRowIdBeforeMove: Int64
    public let resolvedRowId: Int64?
    public let resolvedMailbox: String?
    public let retryCount: Int
    public let lastError: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let settledAt: Date?

    public init(
        mutationId: String = UUID().uuidString,
        rfcMessageId: String,
        action: MutationAction,
        status: MutationStatus = .inFlight,
        accountUUID: String,
        sourceMailbox: String,
        destinationMailbox: String,
        inboxPath: String,
        expectedRead: Bool? = nil,
        expectedFlagged: Bool? = nil,
        preMoveRowId: Int64,
        maxRowIdBeforeMove: Int64,
        resolvedRowId: Int64? = nil,
        resolvedMailbox: String? = nil,
        retryCount: Int = 0,
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        settledAt: Date? = nil
    ) {
        self.mutationId = mutationId
        self.rfcMessageId = rfcMessageId
        self.action = action
        self.status = status
        self.accountUUID = accountUUID
        self.sourceMailbox = sourceMailbox
        self.destinationMailbox = destinationMailbox
        self.inboxPath = inboxPath
        self.expectedRead = expectedRead
        self.expectedFlagged = expectedFlagged
        self.preMoveRowId = preMoveRowId
        self.maxRowIdBeforeMove = maxRowIdBeforeMove
        self.resolvedRowId = resolvedRowId
        self.resolvedMailbox = resolvedMailbox
        self.retryCount = retryCount
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.settledAt = settledAt
    }
}

public struct UndoRecord: Equatable, Codable, Sendable {
    public let messageId: String
    public let action: UndoAction
    public let accountUUID: String
    public let inboxPath: String
    public let targetMailboxPath: String
    public let previousRead: Bool
    public let previousFlagged: Bool
    public let lastKnownRowId: Int64
    public let maxRowIdBeforeMove: Int64
    public var resolvedRowId: Int64?
    public var resolvedMailboxPath: String?
    public let timestamp: Date

    public init(
        messageId: String,
        action: UndoAction,
        accountUUID: String,
        inboxPath: String,
        targetMailboxPath: String,
        previousRead: Bool,
        previousFlagged: Bool,
        lastKnownRowId: Int64,
        maxRowIdBeforeMove: Int64,
        resolvedRowId: Int64? = nil,
        resolvedMailboxPath: String? = nil,
        timestamp: Date = Date()
    ) {
        self.messageId = messageId
        self.action = action
        self.accountUUID = accountUUID
        self.inboxPath = inboxPath
        self.targetMailboxPath = targetMailboxPath
        self.previousRead = previousRead
        self.previousFlagged = previousFlagged
        self.lastKnownRowId = lastKnownRowId
        self.maxRowIdBeforeMove = maxRowIdBeforeMove
        self.resolvedRowId = resolvedRowId
        self.resolvedMailboxPath = resolvedMailboxPath
        self.timestamp = timestamp
    }
}

public struct ObservedInboxState: Equatable, Sendable {
    public let messageId: String
    public let rowId: Int64
    public let mailboxPath: String
    public let isRead: Bool
    public let isFlagged: Bool
    public let isInInbox: Bool

    public init(
        messageId: String,
        rowId: Int64,
        mailboxPath: String,
        isRead: Bool,
        isFlagged: Bool,
        isInInbox: Bool = true
    ) {
        self.messageId = messageId
        self.rowId = rowId
        self.mailboxPath = mailboxPath
        self.isRead = isRead
        self.isFlagged = isFlagged
        self.isInInbox = isInInbox
    }
}

public enum ReconciliationDecision: Equatable, Sendable {
    case useEnvelopeState
    case suppressFromInbox(action: MutationAction, status: MutationStatus)
    case awaitingInboxConvergence(action: MutationAction, status: MutationStatus)
}

public struct ReconciliationReport: Equatable, Sendable {
    public let suppressedMessageIds: Set<String>
    public let awaitingInboxMessageIds: Set<String>
    public let convergedMessageIds: Set<String>
    public let expiredMessageIds: Set<String>
    public let timedOutInFlightIds: [String]

    public init(
        suppressedMessageIds: Set<String> = [],
        awaitingInboxMessageIds: Set<String> = [],
        convergedMessageIds: Set<String> = [],
        expiredMessageIds: Set<String> = [],
        timedOutInFlightIds: [String] = []
    ) {
        self.suppressedMessageIds = suppressedMessageIds
        self.awaitingInboxMessageIds = awaitingInboxMessageIds
        self.convergedMessageIds = convergedMessageIds
        self.expiredMessageIds = expiredMessageIds
        self.timedOutInFlightIds = timedOutInFlightIds
    }
}

/// Persistent SQLite write-ahead outbox & undo ledger for Mail.app mutations.
/// Ensures optimistic actions are durable before AppleEvents fire, prevents stale `Envelope Index`
/// reads from snapping recently moved cards back into the queue during `FSEvents` echo windows,
/// and preserves undo context across app restarts.
public actor MutationLedger {
    public static func defaultDatabasePath() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("MailroomDeck", isDirectory: true)
            .appendingPathComponent("mutation_ledger_v1.sqlite")
            .path
    }

    private let db: SQLiteConnection
    private let echoSuppressionWindow: TimeInterval
    private let inFlightTimeout: TimeInterval

    public init(
        dbPath: String = MutationLedger.defaultDatabasePath(),
        echoSuppressionWindow: TimeInterval = 15.0,
        inFlightTimeout: TimeInterval = 60.0
    ) throws {
        self.db = try SQLiteConnection(readWritePath: dbPath)
        self.echoSuppressionWindow = max(0, echoSuppressionWindow)
        self.inFlightTimeout = max(1, inFlightTimeout)
        try Self.migrateSchema(on: db)
    }

    private static func migrateSchema(on db: SQLiteConnection) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS pending_mutations (
                mutation_id TEXT PRIMARY KEY,
                rfc_message_id TEXT NOT NULL,
                action TEXT NOT NULL,
                status TEXT NOT NULL,
                account_uuid TEXT NOT NULL,
                source_mailbox TEXT NOT NULL,
                destination_mailbox TEXT NOT NULL,
                inbox_path TEXT NOT NULL,
                expected_read INTEGER,
                expected_flagged INTEGER,
                pre_move_row_id INTEGER NOT NULL,
                max_row_id_before_move INTEGER NOT NULL,
                resolved_row_id INTEGER,
                resolved_mailbox TEXT,
                retry_count INTEGER NOT NULL DEFAULT 0,
                last_error TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                settled_at REAL
            );
        """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_pending_mutations_msg
            ON pending_mutations (rfc_message_id, updated_at DESC);
        """)
        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_pending_mutations_status
            ON pending_mutations (status, updated_at DESC);
        """)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS undo_ledger (
                rfc_message_id TEXT PRIMARY KEY,
                action TEXT NOT NULL,
                account_uuid TEXT NOT NULL,
                inbox_path TEXT NOT NULL,
                target_mailbox_path TEXT NOT NULL,
                previous_read INTEGER NOT NULL,
                previous_flagged INTEGER NOT NULL,
                last_known_row_id INTEGER NOT NULL,
                max_row_id_before_move INTEGER NOT NULL,
                resolved_row_id INTEGER,
                resolved_mailbox_path TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            );
        """)
    }

    // MARK: - Outbox Lifecycle

    @discardableResult
    public func beginMutation(
        mutationId: String = UUID().uuidString,
        rfcMessageId: String,
        action: MutationAction,
        accountUUID: String,
        sourceMailbox: String,
        destinationMailbox: String,
        inboxPath: String,
        expectedRead: Bool? = nil,
        expectedFlagged: Bool? = nil,
        preMoveRowId: Int64,
        maxRowIdBeforeMove: Int64,
        undoRecord: UndoRecord? = nil,
        now: Date = Date()
    ) throws -> PendingMutationRecord {
        let ts = now.timeIntervalSince1970
        let record = PendingMutationRecord(
            mutationId: mutationId,
            rfcMessageId: rfcMessageId,
            action: action,
            status: .inFlight,
            accountUUID: accountUUID,
            sourceMailbox: sourceMailbox,
            destinationMailbox: destinationMailbox,
            inboxPath: inboxPath,
            expectedRead: expectedRead,
            expectedFlagged: expectedFlagged,
            preMoveRowId: preMoveRowId,
            maxRowIdBeforeMove: maxRowIdBeforeMove,
            createdAt: now,
            updatedAt: now
        )

        try db.execute("BEGIN IMMEDIATE;")
        do {
            // Supersede any earlier settled/in-flight records for the same message so newer intent wins.
            try db.execute(
                "DELETE FROM pending_mutations WHERE rfc_message_id = ?;",
                bindings: [.text(rfcMessageId)]
            )
            try db.execute("""
                INSERT INTO pending_mutations (
                    mutation_id, rfc_message_id, action, status, account_uuid,
                    source_mailbox, destination_mailbox, inbox_path,
                    expected_read, expected_flagged,
                    pre_move_row_id, max_row_id_before_move,
                    resolved_row_id, resolved_mailbox,
                    retry_count, last_error, created_at, updated_at, settled_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL, 0, NULL, ?, ?, NULL);
            """, bindings: [
                .text(record.mutationId),
                .text(record.rfcMessageId),
                .text(record.action.rawValue),
                .text(record.status.rawValue),
                .text(record.accountUUID),
                .text(record.sourceMailbox),
                .text(record.destinationMailbox),
                .text(record.inboxPath),
                expectedRead.map { .int($0 ? 1 : 0) } ?? .null,
                expectedFlagged.map { .int($0 ? 1 : 0) } ?? .null,
                .int(record.preMoveRowId),
                .int(record.maxRowIdBeforeMove),
                .double(ts),
                .double(ts)
            ])

            if let undoRecord {
                try upsertUndoRecordUnlocked(undoRecord, now: now)
            }
            try db.execute("COMMIT;")
            return record
        } catch {
            try? db.execute("ROLLBACK;")
            throw error
        }
    }

    public func markCommitted(
        mutationId: String,
        resolvedRowId: Int64? = nil,
        resolvedMailbox: String? = nil,
        now: Date = Date()
    ) throws {
        let ts = now.timeIntervalSince1970
        let rows = try db.query(
            "SELECT rfc_message_id FROM pending_mutations WHERE mutation_id = ? LIMIT 1;",
            bindings: [.text(mutationId)],
            map: { $0.string(0) ?? "" }
        )
        let messageId = rows.first

        try db.execute("BEGIN IMMEDIATE;")
        do {
            try db.execute("""
                UPDATE pending_mutations
                SET status = ?,
                    resolved_row_id = COALESCE(?, resolved_row_id),
                    resolved_mailbox = COALESCE(?, resolved_mailbox),
                    last_error = NULL,
                    updated_at = ?,
                    settled_at = ?
                WHERE mutation_id = ?;
            """, bindings: [
                .text(MutationStatus.committed.rawValue),
                resolvedRowId.map { .int($0) } ?? .null,
                resolvedMailbox.map { .text($0) } ?? .null,
                .double(ts),
                .double(ts),
                .text(mutationId)
            ])

            if let messageId, !messageId.isEmpty, (resolvedRowId != nil || resolvedMailbox != nil) {
                try db.execute("""
                    UPDATE undo_ledger
                    SET resolved_row_id = COALESCE(?, resolved_row_id),
                        resolved_mailbox_path = COALESCE(?, resolved_mailbox_path),
                        updated_at = ?
                    WHERE rfc_message_id = ?;
                """, bindings: [
                    resolvedRowId.map { .int($0) } ?? .null,
                    resolvedMailbox.map { .text($0) } ?? .null,
                    .double(ts),
                    .text(messageId)
                ])
            }
            try db.execute("COMMIT;")
        } catch {
            try? db.execute("ROLLBACK;")
            throw error
        }
    }

    public func markFailed(
        mutationId: String,
        error: String,
        rollbackUndoRecord: Bool = false,
        now: Date = Date()
    ) throws {
        let ts = now.timeIntervalSince1970
        let msgId = try db.query(
            "SELECT rfc_message_id FROM pending_mutations WHERE mutation_id = ? LIMIT 1;",
            bindings: [.text(mutationId)],
            map: { $0.string(0) ?? "" }
        ).first

        try db.execute("BEGIN IMMEDIATE;")
        do {
            try db.execute("""
                UPDATE pending_mutations
                SET status = ?,
                    retry_count = retry_count + 1,
                    last_error = ?,
                    updated_at = ?,
                    settled_at = NULL
                WHERE mutation_id = ?;
            """, bindings: [
                .text(MutationStatus.failed.rawValue),
                .text(error),
                .double(ts),
                .text(mutationId)
            ])

            if rollbackUndoRecord, let msgId, !msgId.isEmpty {
                try db.execute(
                    "DELETE FROM undo_ledger WHERE rfc_message_id = ?;",
                    bindings: [.text(msgId)]
                )
            }
            try db.execute("COMMIT;")
        } catch {
            try? db.execute("ROLLBACK;")
            throw error
        }
    }

    @discardableResult
    public func prepareRetry(mutationId: String, now: Date = Date()) throws -> PendingMutationRecord? {
        let ts = now.timeIntervalSince1970
        try db.execute("""
            UPDATE pending_mutations
            SET status = ?,
                updated_at = ?,
                settled_at = NULL
            WHERE mutation_id = ?;
        """, bindings: [
            .text(MutationStatus.inFlight.rawValue),
            .double(ts),
            .text(mutationId)
        ])
        return try mutation(withId: mutationId)
    }

    // MARK: - Persistent Undo Ledger

    public func upsertUndoRecord(_ record: UndoRecord, now: Date = Date()) throws {
        try upsertUndoRecordUnlocked(record, now: now)
    }

    private func upsertUndoRecordUnlocked(_ record: UndoRecord, now: Date) throws {
        let createdTs = record.timestamp.timeIntervalSince1970
        let updatedTs = now.timeIntervalSince1970
        try db.execute("""
            INSERT OR REPLACE INTO undo_ledger (
                rfc_message_id, action, account_uuid, inbox_path, target_mailbox_path,
                previous_read, previous_flagged, last_known_row_id, max_row_id_before_move,
                resolved_row_id, resolved_mailbox_path, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, bindings: [
            .text(record.messageId),
            .text(record.action.rawValue),
            .text(record.accountUUID),
            .text(record.inboxPath),
            .text(record.targetMailboxPath),
            .int(record.previousRead ? 1 : 0),
            .int(record.previousFlagged ? 1 : 0),
            .int(record.lastKnownRowId),
            .int(record.maxRowIdBeforeMove),
            record.resolvedRowId.map { .int($0) } ?? .null,
            record.resolvedMailboxPath.map { .text($0) } ?? .null,
            .double(createdTs),
            .double(updatedTs)
        ])
    }

    public func updateUndoResolvedLocation(
        messageId: String,
        resolvedRowId: Int64?,
        resolvedMailboxPath: String?,
        now: Date = Date()
    ) throws {
        try db.execute("""
            UPDATE undo_ledger
            SET resolved_row_id = COALESCE(?, resolved_row_id),
                resolved_mailbox_path = COALESCE(?, resolved_mailbox_path),
                updated_at = ?
            WHERE rfc_message_id = ?;
        """, bindings: [
            resolvedRowId.map { .int($0) } ?? .null,
            resolvedMailboxPath.map { .text($0) } ?? .null,
            .double(now.timeIntervalSince1970),
            .text(messageId)
        ])
    }

    public func undoRecord(for messageId: String) throws -> UndoRecord? {
        try db.query("""
            SELECT rfc_message_id, action, account_uuid, inbox_path, target_mailbox_path,
                   previous_read, previous_flagged, last_known_row_id, max_row_id_before_move,
                   resolved_row_id, resolved_mailbox_path, created_at
            FROM undo_ledger
            WHERE rfc_message_id = ?
            LIMIT 1;
        """, bindings: [.text(messageId)], map: Self.decodeUndoRecord).first
    }

    public func allUndoRecords() throws -> [UndoRecord] {
        try db.query("""
            SELECT rfc_message_id, action, account_uuid, inbox_path, target_mailbox_path,
                   previous_read, previous_flagged, last_known_row_id, max_row_id_before_move,
                   resolved_row_id, resolved_mailbox_path, created_at
            FROM undo_ledger
            ORDER BY updated_at DESC;
        """, map: Self.decodeUndoRecord)
    }

    public func removeUndoRecord(for messageId: String) throws {
        try db.execute(
            "DELETE FROM undo_ledger WHERE rfc_message_id = ?;",
            bindings: [.text(messageId)]
        )
    }

    // MARK: - Queries & Diagnostics

    public func mutation(withId mutationId: String) throws -> PendingMutationRecord? {
        try db.query("""
            SELECT mutation_id, rfc_message_id, action, status, account_uuid,
                   source_mailbox, destination_mailbox, inbox_path,
                   expected_read, expected_flagged,
                   pre_move_row_id, max_row_id_before_move,
                   resolved_row_id, resolved_mailbox,
                   retry_count, last_error, created_at, updated_at, settled_at
            FROM pending_mutations
            WHERE mutation_id = ?
            LIMIT 1;
        """, bindings: [.text(mutationId)], map: Self.decodePendingMutation).first
    }

    public func latestMutation(for messageId: String) throws -> PendingMutationRecord? {
        try db.query("""
            SELECT mutation_id, rfc_message_id, action, status, account_uuid,
                   source_mailbox, destination_mailbox, inbox_path,
                   expected_read, expected_flagged,
                   pre_move_row_id, max_row_id_before_move,
                   resolved_row_id, resolved_mailbox,
                   retry_count, last_error, created_at, updated_at, settled_at
            FROM pending_mutations
            WHERE rfc_message_id = ?
            ORDER BY updated_at DESC
            LIMIT 1;
        """, bindings: [.text(messageId)], map: Self.decodePendingMutation).first
    }

    public func pendingMutations(status: MutationStatus? = nil) throws -> [PendingMutationRecord] {
        if let status {
            return try db.query("""
                SELECT mutation_id, rfc_message_id, action, status, account_uuid,
                       source_mailbox, destination_mailbox, inbox_path,
                       expected_read, expected_flagged,
                       pre_move_row_id, max_row_id_before_move,
                       resolved_row_id, resolved_mailbox,
                       retry_count, last_error, created_at, updated_at, settled_at
                FROM pending_mutations
                WHERE status = ?
                ORDER BY updated_at DESC;
            """, bindings: [.text(status.rawValue)], map: Self.decodePendingMutation)
        }
        return try db.query("""
            SELECT mutation_id, rfc_message_id, action, status, account_uuid,
                   source_mailbox, destination_mailbox, inbox_path,
                   expected_read, expected_flagged,
                   pre_move_row_id, max_row_id_before_move,
                   resolved_row_id, resolved_mailbox,
                   retry_count, last_error, created_at, updated_at, settled_at
            FROM pending_mutations
            ORDER BY updated_at DESC;
        """, map: Self.decodePendingMutation)
    }

    public func failedMutations() throws -> [PendingMutationRecord] {
        try pendingMutations(status: .failed)
    }

    public func inFlightMutations() throws -> [PendingMutationRecord] {
        try pendingMutations(status: .inFlight)
    }

    // MARK: - FSEvents Echo Suppression & Reconciliation

    /// Returns `true` when any mutation is still `inFlight` or settled within the echo-suppression window.
    public func shouldSuppressFilesystemEcho(now: Date = Date()) throws -> Bool {
        let active = try db.query("""
            SELECT status, updated_at, settled_at
            FROM pending_mutations
            WHERE status IN ('inFlight', 'committed')
            ORDER BY updated_at DESC;
        """) { row in
            (
                row.string(0) ?? "",
                row.double(1),
                row.optionalDouble(2)
            )
        }

        let nowTs = now.timeIntervalSince1970
        for (statusRaw, updatedAt, settledAt) in active {
            if statusRaw == MutationStatus.inFlight.rawValue {
                if (nowTs - updatedAt) < inFlightTimeout {
                    return true
                }
            } else if statusRaw == MutationStatus.committed.rawValue {
                let anchor = settledAt ?? updatedAt
                if (nowTs - anchor) < echoSuppressionWindow {
                    return true
                }
            }
        }
        return false
    }

    /// Reconciles `pending_mutations` against an `Envelope Index` snapshot.
    /// - Prevents stale `Envelope Index` reads from snapping recently archived/kept/trashed messages
    ///   back into `queue` while a mutation is `inFlight` or within `echoSuppressionWindow`.
    /// - Retires `committed` entries once `Envelope Index` reflects the move/flag change or the timeout expires.
    /// - Marks crashed/abandoned `inFlight` entries older than `inFlightTimeout` as `.failed`.
    @discardableResult
    public func reconcile(
        observedInboxMessages: [ObservedInboxState],
        now: Date = Date()
    ) throws -> ReconciliationReport {
        var observedById: [String: ObservedInboxState] = [:]
        for obs in observedInboxMessages {
            observedById[obs.messageId] = obs
        }

        let activeRows = try db.query("""
            SELECT mutation_id, rfc_message_id, action, status, account_uuid,
                   source_mailbox, destination_mailbox, inbox_path,
                   expected_read, expected_flagged,
                   pre_move_row_id, max_row_id_before_move,
                   resolved_row_id, resolved_mailbox,
                   retry_count, last_error, created_at, updated_at, settled_at
            FROM pending_mutations
            WHERE status IN ('inFlight', 'committed')
            ORDER BY updated_at DESC;
        """, map: Self.decodePendingMutation)

        var suppressed: Set<String> = []
        var awaitingInbox: Set<String> = []
        var converged: Set<String> = []
        var expired: Set<String> = []
        var timedOutIds: [String] = []
        var retiredMutationIds: [String] = []
        var seenMessageIds: Set<String> = []

        for row in activeRows {
            // Keep only the newest active mutation per message; retire older duplicates.
            if !seenMessageIds.insert(row.rfcMessageId).inserted {
                retiredMutationIds.append(row.mutationId)
                continue
            }

            let obs = observedById[row.rfcMessageId]
            let inInboxNow = obs?.isInInbox ?? false

            switch row.status {
            case .failed:
                continue

            case .inFlight:
                if now.timeIntervalSince(row.updatedAt) >= inFlightTimeout {
                    try markFailed(
                        mutationId: row.mutationId,
                        error: "Interrupted in-flight mutation timed out",
                        rollbackUndoRecord: false,
                        now: now
                    )
                    timedOutIds.append(row.mutationId)
                } else {
                    switch row.action {
                    case .archive, .keep, .trash:
                        suppressed.insert(row.rfcMessageId)
                    case .restore, .rescue:
                        awaitingInbox.insert(row.rfcMessageId)
                    }
                }

            case .committed:
                let anchor = row.settledAt ?? row.updatedAt
                let withinWindow = now.timeIntervalSince(anchor) < echoSuppressionWindow

                switch row.action {
                case .archive, .trash:
                    if !inInboxNow {
                        converged.insert(row.rfcMessageId)
                        retiredMutationIds.append(row.mutationId)
                    } else if withinWindow {
                        suppressed.insert(row.rfcMessageId)
                    } else {
                        expired.insert(row.rfcMessageId)
                        retiredMutationIds.append(row.mutationId)
                    }

                case .keep:
                    let flagsConverged = !inInboxNow || ((obs?.isRead ?? false) && (obs?.isFlagged ?? false))
                    if flagsConverged {
                        converged.insert(row.rfcMessageId)
                        retiredMutationIds.append(row.mutationId)
                    } else if withinWindow {
                        suppressed.insert(row.rfcMessageId)
                    } else {
                        expired.insert(row.rfcMessageId)
                        retiredMutationIds.append(row.mutationId)
                    }

                case .restore, .rescue:
                    if inInboxNow {
                        converged.insert(row.rfcMessageId)
                        retiredMutationIds.append(row.mutationId)
                    } else if withinWindow {
                        awaitingInbox.insert(row.rfcMessageId)
                    } else {
                        expired.insert(row.rfcMessageId)
                        retiredMutationIds.append(row.mutationId)
                    }
                }
            }
        }

        if !retiredMutationIds.isEmpty {
            try db.execute("BEGIN IMMEDIATE;")
            do {
                for id in retiredMutationIds {
                    try db.execute(
                        "DELETE FROM pending_mutations WHERE mutation_id = ?;",
                        bindings: [.text(id)]
                    )
                }
                try db.execute("COMMIT;")
            } catch {
                try? db.execute("ROLLBACK;")
                throw error
            }
        }

        return ReconciliationReport(
            suppressedMessageIds: suppressed,
            awaitingInboxMessageIds: awaitingInbox,
            convergedMessageIds: converged,
            expiredMessageIds: expired,
            timedOutInFlightIds: timedOutIds
        )
    }

    /// Evaluates reconciliation state for a single message without retiring rows globally.
    public func reconciliationDecision(
        for messageId: String,
        observedInInbox: Bool,
        observedRead: Bool,
        observedFlagged: Bool,
        now: Date = Date()
    ) throws -> ReconciliationDecision {
        guard let row = try latestMutation(for: messageId) else {
            return .useEnvelopeState
        }

        switch row.status {
        case .failed:
            return .useEnvelopeState

        case .inFlight:
            guard now.timeIntervalSince(row.updatedAt) < inFlightTimeout else {
                return .useEnvelopeState
            }
            switch row.action {
            case .archive, .keep, .trash:
                return .suppressFromInbox(action: row.action, status: .inFlight)
            case .restore, .rescue:
                return .awaitingInboxConvergence(action: row.action, status: .inFlight)
            }

        case .committed:
            let anchor = row.settledAt ?? row.updatedAt
            guard now.timeIntervalSince(anchor) < echoSuppressionWindow else {
                return .useEnvelopeState
            }
            switch row.action {
            case .archive, .trash:
                return observedInInbox
                    ? .suppressFromInbox(action: row.action, status: .committed)
                    : .useEnvelopeState
            case .keep:
                let flagsConverged = !observedInInbox || (observedRead && observedFlagged)
                return flagsConverged
                    ? .useEnvelopeState
                    : .suppressFromInbox(action: row.action, status: .committed)
            case .restore, .rescue:
                return observedInInbox
                    ? .useEnvelopeState
                    : .awaitingInboxConvergence(action: row.action, status: .committed)
            }
        }
    }

    public func purgeFailedMutations(olderThan interval: TimeInterval, now: Date = Date()) throws {
        let cutoff = now.timeIntervalSince1970 - interval
        try db.execute(
            "DELETE FROM pending_mutations WHERE status = ? AND updated_at < ?;",
            bindings: [.text(MutationStatus.failed.rawValue), .double(cutoff)]
        )
    }

    // MARK: - Row Decoding

    private static func decodePendingMutation(_ row: SQLiteRow) -> PendingMutationRecord {
        PendingMutationRecord(
            mutationId: row.string(0) ?? "",
            rfcMessageId: row.string(1) ?? "",
            action: MutationAction(rawValue: row.string(2) ?? "") ?? .archive,
            status: MutationStatus(rawValue: row.string(3) ?? "") ?? .failed,
            accountUUID: row.string(4) ?? "",
            sourceMailbox: row.string(5) ?? "",
            destinationMailbox: row.string(6) ?? "",
            inboxPath: row.string(7) ?? "",
            expectedRead: row.optionalInt64(8).map { $0 != 0 },
            expectedFlagged: row.optionalInt64(9).map { $0 != 0 },
            preMoveRowId: row.int64(10),
            maxRowIdBeforeMove: row.int64(11),
            resolvedRowId: row.optionalInt64(12),
            resolvedMailbox: row.string(13),
            retryCount: Int(row.int64(14)),
            lastError: row.string(15),
            createdAt: Date(timeIntervalSince1970: row.double(16)),
            updatedAt: Date(timeIntervalSince1970: row.double(17)),
            settledAt: row.optionalDouble(18).map { Date(timeIntervalSince1970: $0) }
        )
    }

    private static func decodeUndoRecord(_ row: SQLiteRow) -> UndoRecord {
        UndoRecord(
            messageId: row.string(0) ?? "",
            action: UndoAction(rawValue: row.string(1) ?? "") ?? .archived,
            accountUUID: row.string(2) ?? "",
            inboxPath: row.string(3) ?? "",
            targetMailboxPath: row.string(4) ?? "",
            previousRead: row.int64(5) != 0,
            previousFlagged: row.int64(6) != 0,
            lastKnownRowId: row.int64(7),
            maxRowIdBeforeMove: row.int64(8),
            resolvedRowId: row.optionalInt64(9),
            resolvedMailboxPath: row.string(10),
            timestamp: Date(timeIntervalSince1970: row.double(11))
        )
    }
}

private extension SQLiteRow {
    func optionalDouble(_ col: Int32) -> Double? {
        optionalInt64(col) == nil ? nil : double(col)
    }
}

import Foundation
import Testing
@testable import MailroomCore

@Suite("ConversationResolver Tests")
struct ConversationResolverTests {
    // MARK: - Synthetic SQLite Fixture Helper

    private func makeTempEnvelopeDB(includeLabelsTable: Bool = true) throws -> (url: URL, conn: SQLiteConnection) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mailroom-conv-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("Envelope Index")
        let conn = try SQLiteConnection(readWritePath: dbURL.path)

        try conn.execute("""
            CREATE TABLE mailboxes (
                ROWID INTEGER PRIMARY KEY,
                url TEXT NOT NULL,
                total_count INTEGER NOT NULL DEFAULT 0
            );
        """)
        try conn.execute("""
            CREATE TABLE addresses (
                ROWID INTEGER PRIMARY KEY,
                address TEXT NOT NULL,
                comment TEXT NOT NULL
            );
        """)
        try conn.execute("""
            CREATE TABLE subjects (
                ROWID INTEGER PRIMARY KEY,
                subject TEXT NOT NULL
            );
        """)
        try conn.execute("""
            CREATE TABLE summaries (
                ROWID INTEGER PRIMARY KEY,
                summary TEXT NOT NULL
            );
        """)
        try conn.execute("""
            CREATE TABLE messages (
                ROWID INTEGER PRIMARY KEY,
                message_id INTEGER NOT NULL DEFAULT 0,
                sender INTEGER,
                subject_prefix TEXT,
                subject INTEGER NOT NULL,
                summary INTEGER,
                date_sent INTEGER,
                date_received INTEGER,
                mailbox INTEGER NOT NULL,
                flags INTEGER NOT NULL DEFAULT 0,
                read INTEGER NOT NULL DEFAULT 0,
                flagged INTEGER NOT NULL DEFAULT 0,
                deleted INTEGER NOT NULL DEFAULT 0,
                conversation_id INTEGER NOT NULL DEFAULT 0
            );
        """)
        try conn.execute("CREATE INDEX messages_conversation_id_index ON messages(conversation_id);")
        try conn.execute("CREATE INDEX messages_deleted_index ON messages(deleted);")

        if includeLabelsTable {
            try conn.execute("""
                CREATE TABLE labels (
                    message_id INTEGER NOT NULL,
                    mailbox_id INTEGER NOT NULL,
                    PRIMARY KEY (message_id, mailbox_id)
                );
            """)
        }

        return (dir, conn)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Unit Tests

    @Test("Multi-message thread resolution, chronological priorMessages, and summary fallback")
    func multiMessageThreadAndSummaries() throws {
        let (dir, conn) = try makeTempEnvelopeDB()
        defer { cleanup(dir) }

        try conn.execute("INSERT INTO mailboxes (ROWID, url) VALUES (1, 'imap://ACC-1/INBOX'), (2, 'imap://ACC-1/Archive');")
        try conn.execute("""
            INSERT INTO addresses (ROWID, address, comment) VALUES
            (1, 'alice@example.com', 'Alice'),
            (2, 'bob@example.com', 'Bob');
        """)
        try conn.execute("INSERT INTO subjects (ROWID, subject) VALUES (1, 'Contract Review');")
        try conn.execute("""
            INSERT INTO summaries (ROWID, summary) VALUES
            (1, 'Initial draft attached.'),
            (2, 'Please check section 3.'),
            (3, 'Updated version looks good.');
        """)

        // Out-of-order ROWIDs to confirm sorting is chronological by epoch
        try conn.execute("""
            INSERT INTO messages (ROWID, message_id, sender, subject_prefix, subject, summary, date_sent, date_received, mailbox, flagged, deleted, conversation_id) VALUES
            (10, 1001, 1, NULL, 1, 1, 1700000100, 1700000100, 2, 0, 0, 500),
            (12, 1002, 2, 'Re: ', 1, 2, 1700000200, 1700000200, 2, 0, 0, 500),
            (11, 1003, 1, 'Re: ', 1, 3, 1700000300, 1700000300, 1, 0, 0, 500),
            (13, 1004, 2, 'Re: ', 1, 1, 1700000150, 1700000150, 2, 0, 1, 500);
        """)

        let resolver = ConversationResolver()
        let result = try resolver.resolve(
            targets: [(rowId: 11, conversationId: 500, receivedAtEpoch: 1700000300)],
            using: conn
        )

        let ctx = try #require(result[11])
        #expect(ctx.conversationId == 500)
        #expect(ctx.messageCount == 3) // deleted row 13 excluded
        #expect(ctx.sentByOwnerInThread == false)
        #expect(ctx.hasFlaggedInThread == false)
        #expect(ctx.priorMessages.count == 2)
        #expect(ctx.priorMessages.map(\.rowId) == [10, 12])
        #expect(ctx.priorMessages[0].from == "Alice <alice@example.com>")
        #expect(ctx.priorMessages[0].subject == "Contract Review")
        #expect(ctx.priorMessages[0].bodySnippet == "Initial draft attached.")
        #expect(ctx.priorMessages[0].mailboxPath == "Archive")
        #expect(ctx.priorMessages[0].dateISO == "2023-11-14T22:15:00Z")
        #expect(ctx.priorMessages[1].from == "Bob <bob@example.com>")
        #expect(ctx.priorMessages[1].subject == "Re: Contract Review")
        #expect(ctx.priorMessages[1].bodySnippet == "Please check section 3.")
    }

    @Test("Owner reply detection via Sent mailbox variants, Gmail labels, and normalized owner addresses")
    func sentByOwnerDetection() throws {
        let (dir, conn) = try makeTempEnvelopeDB()
        defer { cleanup(dir) }

        try conn.execute("""
            INSERT INTO mailboxes (ROWID, url) VALUES
            (1, 'imap://ACC-1/INBOX'),
            (2, 'imap://ACC-1/%5BGmail%5D/Sent%20Mail'),
            (3, 'ews://ACC-2/Sent%20Items'),
            (4, 'imap://ACC-3/Sent%20Messages'),
            (5, 'imap://ACC-1/%5BGmail%5D/All%20Mail'),
            (6, 'imap://ACC-4/%E5%B7%B2%E5%8F%91%E9%80%81');
        """)
        try conn.execute("""
            INSERT INTO addresses (ROWID, address, comment) VALUES
            (1, 'vendor@saas.io', 'SaaS Vendor'),
            (2, 'J.Doe@googlemail.com', 'Jane Doe'),
            (3, 'jane@work.org', 'Jane Work'),
            (4, 'other@random.net', 'Other');
        """)
        try conn.execute("INSERT INTO subjects (ROWID, subject) VALUES (1, 'Thread');")
        try conn.execute("INSERT INTO summaries (ROWID, summary) VALUES (1, 'Snippet');")

        // Thread 1: owner reply in [Gmail]/Sent Mail (mailbox 2), occurs AFTER target 101
        try conn.execute("""
            INSERT INTO messages (ROWID, message_id, sender, subject, summary, date_received, mailbox, flagged, deleted, conversation_id) VALUES
            (101, 2001, 1, 1, 1, 1700001000, 1, 0, 0, 1),
            (102, 2002, 4, 1, 1, 1700002000, 2, 0, 0, 1);
        """)

        // Thread 2: prior message in EWS Sent Items (mailbox 3)
        try conn.execute("""
            INSERT INTO messages (ROWID, message_id, sender, subject, summary, date_received, mailbox, flagged, deleted, conversation_id) VALUES
            (201, 2003, 4, 1, 1, 1700001000, 3, 0, 0, 2),
            (202, 2004, 1, 1, 1, 1700002000, 1, 0, 0, 2);
        """)

        // Thread 3: prior message physically in All Mail (mailbox 5) with [Gmail]/Sent Mail label (mailbox 2)
        try conn.execute("""
            INSERT INTO messages (ROWID, message_id, sender, subject, summary, date_received, mailbox, flagged, deleted, conversation_id) VALUES
            (301, 2005, 4, 1, 1, 1700001000, 5, 0, 0, 3),
            (302, 2006, 1, 1, 1, 1700002000, 1, 0, 0, 3);
        """)
        try conn.execute("INSERT INTO labels (message_id, mailbox_id) VALUES (301, 2);")

        // Thread 4: prior message sent from Gmail alias normalized via ownerAddresses (jdoe@gmail.com matches J.Doe@googlemail.com)
        try conn.execute("""
            INSERT INTO messages (ROWID, message_id, sender, subject, summary, date_received, mailbox, flagged, deleted, conversation_id) VALUES
            (401, 2007, 2, 1, 1, 1700001000, 5, 0, 0, 4),
            (402, 2008, 1, 1, 1, 1700002000, 1, 0, 0, 4);
        """)

        // Thread 5: Chinese Sent mailbox (已发送)
        try conn.execute("""
            INSERT INTO messages (ROWID, message_id, sender, subject, summary, date_received, mailbox, flagged, deleted, conversation_id) VALUES
            (501, 2009, 4, 1, 1, 1700001000, 6, 0, 0, 5),
            (502, 2010, 1, 1, 1, 1700002000, 1, 0, 0, 5);
        """)

        // Thread 6: Sent Messages (mailbox 4) + non-owner thread 7
        try conn.execute("""
            INSERT INTO messages (ROWID, message_id, sender, subject, summary, date_received, mailbox, flagged, deleted, conversation_id) VALUES
            (601, 2011, 4, 1, 1, 1700001000, 4, 0, 0, 6),
            (602, 2012, 1, 1, 1, 1700002000, 1, 0, 0, 6),
            (701, 2013, 1, 1, 1, 1700001000, 1, 0, 0, 7);
        """)

        let resolver = ConversationResolver(ownerAddresses: ["jdoe@gmail.com", "Jane <jane@work.org>"])
        let results = try resolver.resolve(
            targets: [
                (101, 1, 1700001000),
                (202, 2, 1700002000),
                (302, 3, 1700002000),
                (402, 4, 1700002000),
                (502, 5, 1700002000),
                (602, 6, 1700002000),
                (701, 7, 1700001000),
            ],
            using: conn
        )

        // Thread 1: future owner reply protects thread, even though priorMessages is empty
        #expect(results[101]?.sentByOwnerInThread == true)
        #expect(results[101]?.priorMessages.isEmpty == true)

        #expect(results[202]?.sentByOwnerInThread == true)
        #expect(results[202]?.priorMessages.first?.sentByOwner == true)

        #expect(results[302]?.sentByOwnerInThread == true)
        #expect(results[302]?.priorMessages.first?.sentByOwner == true)

        #expect(results[402]?.sentByOwnerInThread == true)
        #expect(results[402]?.priorMessages.first?.sentByOwner == true)

        #expect(results[502]?.sentByOwnerInThread == true)
        #expect(results[602]?.sentByOwnerInThread == true)
        #expect(results[701]?.sentByOwnerInThread == false)

        // Ensure non-Gmail domains do NOT collapse dots
        #expect(ConversationResolver.normalizeEmailAddress("first.last@company.com") == "first.last@company.com")
        #expect(ConversationResolver.isSentMailboxPath("Archive/Consent") == false)
    }

    @Test("Flagged thread protection and 12-message chronological cap")
    func flaggedThreadAndTwelveMessageCap() throws {
        let (dir, conn) = try makeTempEnvelopeDB(includeLabelsTable: false)
        defer { cleanup(dir) }

        try conn.execute("INSERT INTO mailboxes (ROWID, url) VALUES (1, 'imap://ACC-1/INBOX'), (2, 'imap://ACC-1/Archive');")
        try conn.execute("INSERT INTO addresses (ROWID, address, comment) VALUES (1, 'peer@example.com', 'Peer');")
        try conn.execute("INSERT INTO subjects (ROWID, subject) VALUES (1, 'Long Thread');")
        try conn.execute("INSERT INTO summaries (ROWID, summary) VALUES (1, 'Summary body');")

        // Insert 16 messages (ROWIDs 1..16). Message 2 (outside the last-12 window!) is flagged.
        for i in 1...16 {
            let mb = (i == 16) ? 1 : 2
            let flagged = (i == 2) ? 1 : 0
            let ts = 1700000000 + (i * 60)
            try conn.execute("""
                INSERT INTO messages (ROWID, message_id, sender, subject, summary, date_received, mailbox, flagged, deleted, conversation_id)
                VALUES (\(i), \(9000 + i), 1, 1, 1, \(ts), \(mb), \(flagged), 0, 777);
            """)
        }

        let resolver = ConversationResolver()
        let results = try resolver.resolve(
            targets: [(rowId: 16, conversationId: 777, receivedAtEpoch: 1700000000 + 16 * 60)],
            using: conn
        )

        let ctx = try #require(results[16])
        #expect(ctx.messageCount == 16)
        #expect(ctx.hasFlaggedInThread == true)
        #expect(ctx.priorMessages.count == 12)
        // Last 12 prior messages are ROWIDs 4..15 in chronological order
        #expect(ctx.priorMessages.map(\.rowId) == Array(4...15).map(Int64.init))
    }

    @Test("Body provider hook overrides summary, strips invisible fillers, caps at 8000 chars, and caches per batch")
    func bodyProviderHookAndTruncation() throws {
        let (dir, conn) = try makeTempEnvelopeDB()
        defer { cleanup(dir) }

        try conn.execute("INSERT INTO mailboxes (ROWID, url) VALUES (1, 'imap://ACC-1/INBOX'), (2, 'imap://ACC-1/Archive');")
        try conn.execute("INSERT INTO addresses (ROWID, address, comment) VALUES (1, 'sender@example.com', 'Sender');")
        try conn.execute("INSERT INTO subjects (ROWID, subject) VALUES (1, 'Long Body');")
        try conn.execute("INSERT INTO summaries (ROWID, summary) VALUES (1, 'Fallback summary text');")

        try conn.execute("""
            INSERT INTO messages (ROWID, message_id, sender, subject, summary, date_received, mailbox, flagged, deleted, conversation_id) VALUES
            (1, 5001, 1, 1, 1, 1700000100, 2, 0, 0, 888),
            (2, 5002, 1, 1, 1, 1700000200, 2, 0, 0, 888),
            (3, 5003, 1, 1, 1, 1700000300, 1, 0, 0, 888),
            (4, 5004, 1, 1, 1, 1700000400, 1, 0, 0, 888);
        """)

        let longBody = "\u{200B}\u{FEFF}\u{00AD}Hello" + String(repeating: "A", count: 8500)
        var providerCalls: [Int64: Int] = [:]

        let resolver = ConversationResolver()
        let results = try resolver.resolve(
            targets: [
                (rowId: 3, conversationId: 888, receivedAtEpoch: 1700000300),
                (rowId: 4, conversationId: 888, receivedAtEpoch: 1700000400),
            ],
            using: conn
        ) { rowId, mailboxId in
            providerCalls[rowId, default: 0] += 1
            if rowId == 1 && mailboxId == 2 {
                return longBody
            }
            return nil
        }

        let ctx3 = try #require(results[3])
        #expect(ctx3.priorMessages.count == 2)
        #expect(ctx3.priorMessages[0].bodySnippet.count == 8000)
        #expect(ctx3.priorMessages[0].bodySnippet.hasPrefix("HelloAAAA"))
        #expect(!ctx3.priorMessages[0].bodySnippet.contains("\u{200B}"))
        #expect(!ctx3.priorMessages[0].bodySnippet.contains("\u{FEFF}"))
        #expect(ctx3.priorMessages[1].bodySnippet == "Fallback summary text")

        // Message 1 was needed by both target 3 and target 4, but cached within the batch
        #expect(providerCalls[1] == 1)
    }

    @Test("Duplicate Gmail/IMAP rows sharing message_id are deduplicated without losing flags")
    func deduplicateMirroredImapRows() throws {
        let (dir, conn) = try makeTempEnvelopeDB()
        defer { cleanup(dir) }

        try conn.execute("""
            INSERT INTO mailboxes (ROWID, url) VALUES
            (1, 'imap://ACC-1/INBOX'),
            (2, 'imap://ACC-1/%5BGmail%5D/All%20Mail'),
            (3, 'imap://ACC-1/%5BGmail%5D/Sent%20Mail');
        """)
        try conn.execute("INSERT INTO addresses (ROWID, address, comment) VALUES (1, 'other@example.com', 'Other');")
        try conn.execute("INSERT INTO subjects (ROWID, subject) VALUES (1, 'Mirror');")
        try conn.execute("INSERT INTO summaries (ROWID, summary) VALUES (1, 'Mirror summary');")

        // Prior message (message_id 7001) exists in both All Mail (flagged) and Sent Mail
        // Target message (message_id 7002) exists in both INBOX (ROWID 30) and All Mail (ROWID 31)
        try conn.execute("""
            INSERT INTO messages (ROWID, message_id, sender, subject, summary, date_received, mailbox, flagged, deleted, conversation_id) VALUES
            (20, 7001, 1, 1, 1, 1700000100, 2, 1, 0, 999),
            (21, 7001, 1, 1, 1, 1700000100, 3, 0, 0, 999),
            (30, 7002, 1, 1, 1, 1700000200, 1, 0, 0, 999),
            (31, 7002, 1, 1, 1, 1700000200, 2, 0, 0, 999);
        """)

        let resolver = ConversationResolver()
        let results = try resolver.resolve(
            targets: [(rowId: 30, conversationId: 999, receivedAtEpoch: 1700000200)],
            using: conn
        )

        let ctx = try #require(results[30])
        #expect(ctx.messageCount == 2)
        #expect(ctx.sentByOwnerInThread == true)
        #expect(ctx.hasFlaggedInThread == true)
        #expect(ctx.priorMessages.count == 1)
        #expect(ctx.priorMessages[0].sentByOwner == true)
        #expect(ctx.priorMessages[0].isFlagged == true)
    }

    @Test("Codable round-trip and Swift 6 actor caller with synchronous bodyProvider")
    func codableAndActorCompatibility() async throws {
        let (dir, conn) = try makeTempEnvelopeDB()
        defer { cleanup(dir) }

        try conn.execute("INSERT INTO mailboxes (ROWID, url) VALUES (1, 'imap://ACC-1/INBOX');")
        try conn.execute("INSERT INTO addresses (ROWID, address, comment) VALUES (1, 'a@b.com', 'A');")
        try conn.execute("INSERT INTO subjects (ROWID, subject) VALUES (1, 'Hello');")
        try conn.execute("""
            INSERT INTO messages (ROWID, message_id, sender, subject, summary, date_received, mailbox, flagged, deleted, conversation_id) VALUES
            (1, 11, 1, 1, NULL, 1700000100, 1, 0, 0, 42),
            (2, 12, 1, 1, NULL, 1700000200, 1, 0, 0, 42);
        """)

        actor MockActorCaller {
            private var localCache: [Int64: String] = [1: "Cached body from actor"]

            func run(dbPath: String) throws -> ConversationContext? {
                let c = try SQLiteConnection(readOnlyPath: dbPath)
                let resolver = ConversationResolver()
                let map = try resolver.resolve(
                    targets: [(rowId: 2, conversationId: 42, receivedAtEpoch: 1700000200)],
                    using: c
                ) { rowId, _ in
                    self.localCache[rowId]
                }
                return map[2]
            }
        }

        let caller = MockActorCaller()
        let ctx = try #require(try await caller.run(dbPath: dir.appendingPathComponent("Envelope Index").path))
        #expect(ctx.priorMessages.first?.bodySnippet == "Cached body from actor")

        let encoded = try JSONEncoder().encode(ctx)
        let decoded = try JSONDecoder().decode(ConversationContext.self, from: encoded)
        #expect(decoded == ctx)
    }

    @Test("Mixed batch partitions standalone (conversationId <= 0) targets and checks Sent labels and flags")
    func mixedBatchThreadedAndStandaloneTargets() throws {
        let (dir, conn) = try makeTempEnvelopeDB()
        defer { cleanup(dir) }

        try conn.execute("""
            INSERT INTO mailboxes (ROWID, url) VALUES
            (1, 'imap://ACC-1/INBOX'),
            (2, 'imap://ACC-1/%5BGmail%5D/All%20Mail'),
            (3, 'imap://ACC-1/%5BGmail%5D/Sent%20Mail');
        """)
        try conn.execute("""
            INSERT INTO addresses (ROWID, address, comment) VALUES
            (1, 'peer@example.com', 'Peer'),
            (2, 'owner@example.com', 'Owner');
        """)
        try conn.execute("INSERT INTO subjects (ROWID, subject) VALUES (1, 'Subject');")
        try conn.execute("INSERT INTO summaries (ROWID, summary) VALUES (1, 'Prior snippet');")

        try conn.execute("""
            INSERT INTO messages (ROWID, message_id, sender, subject, summary, date_received, mailbox, flagged, deleted, conversation_id) VALUES
            (10, 8001, 1, 1, 1, 1700000100, 1, 0, 0, 100),
            (11, 8002, 1, 1, 1, 1700000200, 1, 0, 0, 100),
            (20, 8003, 1, 1, 1, 1700000300, 2, 0, 0, 0),
            (21, 8004, 1, 1, 1, 1700000400, 1, 1, 0, -1),
            (22, 8005, 2, 1, 1, 1700000500, 1, 0, 0, 0);
        """)
        // Standalone row 20 is in All Mail (mailbox 2) with [Gmail]/Sent Mail label (mailbox 3)
        try conn.execute("INSERT INTO labels (message_id, mailbox_id) VALUES (20, 3);")

        let resolver = ConversationResolver(ownerAddresses: ["owner@example.com"])
        let results = try resolver.resolve(
            targets: [
                (rowId: 11, conversationId: 100, receivedAtEpoch: 1700000200),
                (rowId: 20, conversationId: 0, receivedAtEpoch: 1700000300),
                (rowId: 21, conversationId: -1, receivedAtEpoch: 1700000400),
                (rowId: 22, conversationId: 0, receivedAtEpoch: 1700000500),
            ],
            using: conn
        )

        #expect(results[11]?.messageCount == 2)
        #expect(results[11]?.priorMessages.map(\.rowId) == [10])
        #expect(results[11]?.sentByOwnerInThread == false)
        #expect(results[11]?.hasFlaggedInThread == false)

        // Standalone via Gmail Sent label
        #expect(results[20]?.conversationId == 0)
        #expect(results[20]?.messageCount == 1)
        #expect(results[20]?.sentByOwnerInThread == true)
        #expect(results[20]?.hasFlaggedInThread == false)
        #expect(results[20]?.priorMessages.isEmpty == true)

        // Standalone flagged
        #expect(results[21]?.conversationId == -1)
        #expect(results[21]?.sentByOwnerInThread == false)
        #expect(results[21]?.hasFlaggedInThread == true)

        // Standalone via ownerAddresses
        #expect(results[22]?.sentByOwnerInThread == true)
        #expect(results[22]?.hasFlaggedInThread == false)
    }

    // MARK: - Live V10 Read-Only Smoke Benchmark

    @Test("Live V10 read-only batch resolution for 40 inbox items completes in <100ms")
    func liveV10BatchResolutionBenchmark() throws {
        guard case .ready(let mailDir) = MailStoreEnvironment.checkAccess() else {
            return
        }

        let indexPath = URL(fileURLWithPath: mailDir)
            .appendingPathComponent("MailData/Envelope Index")
            .path
        let conn = try SQLiteConnection(readOnlyPath: indexPath)

        // Verify conversation_id index is present in V10
        let indices = try conn.query("PRAGMA index_list(messages);") { $0.string(1) ?? "" }
        #expect(indices.contains(where: { $0.contains("conversation_id") }))

        // Fetch 40 latest non-deleted inbox items via both direct mailbox and Gmail `labels`
        // (matching AppleMailAdapter's inbox_candidates query; IDs & timestamps ONLY — no PII printed)
        let inboxIds = try conn.query("SELECT ROWID, url FROM mailboxes;") { row -> Int64? in
            let path = ConversationResolver.decodeMailboxPath(from: row.string(1) ?? "").lowercased()
            return (path == "inbox" || path == "收件箱") ? row.int64(0) : nil
        }.compactMap { $0 }

        guard !inboxIds.isEmpty else { return }
        let inClause = inboxIds.map(String.init).joined(separator: ",")
        let targets = try conn.query("""
            WITH inbox_candidates AS (
                SELECT ROWID AS rid FROM messages WHERE mailbox IN (\(inClause)) AND deleted = 0
                UNION
                SELECT message_id AS rid FROM labels WHERE mailbox_id IN (\(inClause))
            )
            SELECT m.ROWID, m.conversation_id, COALESCE(NULLIF(m.date_received, 0), m.date_sent, 0) AS recv_ts
            FROM inbox_candidates ic
            JOIN messages m ON m.ROWID = ic.rid
            WHERE m.deleted = 0
            ORDER BY recv_ts DESC
            LIMIT 40;
        """) { row in
            ConversationLookupTarget(
                rowId: row.int64(0),
                conversationId: row.int64(1),
                receivedAtEpoch: row.int64(2)
            )
        }

        #expect(!targets.isEmpty)

        let ownerAddresses = ConversationResolver.loadSystemOwnerAddresses()
        let resolver = ConversationResolver(ownerAddresses: ownerAddresses)

        let clock = ContinuousClock()
        let t0 = clock.now
        let resolved = try resolver.resolve(targets: targets, using: conn)
        let elapsed = clock.now - t0

        #expect(resolved.count == targets.count)

        var multiMsgCount = 0
        var sentByOwnerThreads = 0
        var flaggedThreads = 0
        var totalPrior = 0

        for target in targets {
            let ctx = try #require(resolved[target.rowId])
            #expect(ctx.conversationId == target.conversationId)
            #expect(ctx.priorMessages.count <= 12)
            if ctx.messageCount > 1 { multiMsgCount += 1 }
            if ctx.sentByOwnerInThread { sentByOwnerThreads += 1 }
            if ctx.hasFlaggedInThread { flaggedThreads += 1 }
            totalPrior += ctx.priorMessages.count

            // Chronological order & snippet length invariants
            var prevDate = ""
            for pm in ctx.priorMessages {
                #expect(pm.bodySnippet.count <= 8000)
                if !prevDate.isEmpty && !pm.dateISO.isEmpty {
                    #expect(prevDate <= pm.dateISO)
                }
                if !pm.dateISO.isEmpty {
                    prevDate = pm.dateISO
                }
            }
        }

        let elapsedMs = Double(elapsed.components.seconds) * 1000.0
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
        #expect(elapsedMs < 100.0)

        // Also benchmark 40 multi-message conversations in V10 to verify real thread traversal latency
        let multiTargets = try conn.query("""
            SELECT MAX(m.ROWID), m.conversation_id, MAX(COALESCE(NULLIF(m.date_received, 0), m.date_sent, 0)) AS max_ts
            FROM messages m
            WHERE +m.deleted = 0 AND m.conversation_id > 0
            GROUP BY m.conversation_id
            HAVING count(*) > 1
            ORDER BY max_ts DESC
            LIMIT 40;
        """) { row in
            ConversationLookupTarget(
                rowId: row.int64(0),
                conversationId: row.int64(1),
                receivedAtEpoch: row.int64(2)
            )
        }
        let mt0 = clock.now
        let multiResolved = try resolver.resolve(targets: multiTargets, using: conn)
        let multiElapsed = clock.now - mt0
        let multiElapsedMs = Double(multiElapsed.components.seconds) * 1000.0
            + Double(multiElapsed.components.attoseconds) / 1_000_000_000_000_000.0
        #expect(multiResolved.count == multiTargets.count)
        #expect(multiElapsedMs < 100.0)
        let multiOwnerCount = multiResolved.values.filter(\.sentByOwnerInThread).count
        let multiFlaggedCount = multiResolved.values.filter(\.hasFlaggedInThread).count
        let multiPriorTotal = multiResolved.values.reduce(0) { $0 + $1.priorMessages.count }

        print(
            String(
                format: "[ConversationResolverTests] V10 inbox batch (%d items, %d owner addrs): %.2f ms | multiMsg=%d sentByOwner=%d flagged=%d totalPrior=%d || V10 multi-thread batch (%d convs): %.2f ms | sentByOwner=%d flagged=%d totalPrior=%d",
                targets.count,
                ownerAddresses.count,
                elapsedMs,
                multiMsgCount,
                sentByOwnerThreads,
                flaggedThreads,
                totalPrior,
                multiTargets.count,
                multiElapsedMs,
                multiOwnerCount,
                multiFlaggedCount,
                multiPriorTotal
            )
        )
    }
}

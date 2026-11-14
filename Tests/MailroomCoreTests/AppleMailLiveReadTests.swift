import Foundation
import Testing
@testable import MailroomCore

@Suite("AppleMailAdapter Live Read-Only Smoke Tests")
struct AppleMailLiveReadTests {
    @Test("Shard directory calculation matches V10 reversed thousands digits")
    func shardDirectoryFormula() {
        let root = URL(fileURLWithPath: "/tmp/Data")
        let sub39350 = AppleMailAdapter.shardMessagesDirectory(dataRoot: root, rowId: 39350)
        #expect(sub39350.path == "/tmp/Data/9/3/Messages")

        let sub123456 = AppleMailAdapter.shardMessagesDirectory(dataRoot: root, rowId: 123456)
        #expect(sub123456.path == "/tmp/Data/3/2/1/Messages")

        let sub512 = AppleMailAdapter.shardMessagesDirectory(dataRoot: root, rowId: 512)
        #expect(sub512.path == "/tmp/Data/Messages")
    }

    @Test("Live read-only fetchDeck parses real V10 Inbox messages fast and preserves evidence invariant")
    func liveReadOnlyFetch() async throws {
        guard case .ready = MailStoreEnvironment.checkAccess() else {
            return
        }
        let adapter = try AppleMailAdapter(maxInboxFetch: 40)

        let t0 = ContinuousClock.now
        let snapshot = try await adapter.fetchDeck()
        let coldDuration = ContinuousClock.now - t0

        let totalFetched = snapshot.queue.count + snapshot.handled.count
        #expect(totalFetched > 0)

        // Verify every evidence string is strictly a verbatim substring of plainText
        for mail in snapshot.queue {
            #expect(!mail.id.rawValue.isEmpty)
            if let ev = mail.meta.evidence {
                #expect(mail.plainText.contains(ev))
            }
        }

        // Second fetch hits local parsed_emlx SQLite cache and should be sub-25ms
        let t1 = ContinuousClock.now
        let cachedSnapshot = try await adapter.fetchDeck()
        let warmDuration = ContinuousClock.now - t1
        #expect(cachedSnapshot.queue.count == snapshot.queue.count)
        print("[AppleMailLiveReadTests] Cold fetch (\(totalFetched) items): \(coldDuration), Warm cached fetch: \(warmDuration), queue=\(snapshot.queue.count), handled=\(snapshot.handled.count)")
    }
}

@Suite("RuleBasedClassifier Safety Gates")
struct RuleBasedClassifierSafetyGateTests {
    private func makePromoSignals(
        id: String = "safety-test-1",
        isFlagged: Bool = false,
        sentByOwner: Bool = false,
        conversation: ConversationContext? = nil,
        isPartial: Bool = false,
        isTruncated: Bool = false,
        unloadedHtmlImages: Int = 0,
        bodyIsImageOnly: Bool = false
    ) -> ClassificationInput {
        let content = MailContent(
            id: MessageId(id),
            from: Sender(name: "Promo Sender", address: "deals@example.invalid"),
            account: MailAccount(id: "acc-1", label: "Work", address: "owner@example.invalid"),
            subject: "Limited time 50% off flash sale - unsubscribe",
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000),
            plainText: "Limited time 50% off flash sale! View in browser or unsubscribe anytime.",
            attachments: [],
            isReadInMail: false,
            to: [Sender(name: "Owner", address: "owner@example.invalid")],
            isFlaggedInMail: isFlagged,
            sentByOwner: sentByOwner,
            conversation: conversation,
            isPartial: isPartial,
            isTruncated: isTruncated,
            unloadedHtmlImages: unloadedHtmlImages,
            bodyIsImageOnly: bodyIsImageOnly
        )
        return ClassificationInput(
            content: content,
            hasListUnsubscribe: true,
            conversation: conversation,
            sentByOwner: sentByOwner,
            isPartial: isPartial,
            isTruncated: isTruncated,
            unloadedHtmlImages: unloadedHtmlImages,
            bodyIsImageOnly: bodyIsImageOnly,
            isFlagged: isFlagged
        )
    }

    @Test("Flagged message stays in queue instead of auto-handling")
    func flaggedStaysInQueue() {
        let classifier = RuleBasedClassifier()
        let outcome = classifier.classify(makePromoSignals(isFlagged: true))
        guard case .triage = outcome else {
            Issue.record("Expected flagged message to remain in triage queue, got \(outcome)")
            return
        }
    }

    @Test("Partial, truncated, and image-only bodies route to uncertain")
    func incompleteBodiesRouteToUncertain() {
        let classifier = RuleBasedClassifier()
        for input in [
            makePromoSignals(id: "partial", isPartial: true),
            makePromoSignals(id: "truncated", isTruncated: true),
            makePromoSignals(id: "image-only", bodyIsImageOnly: true),
        ] {
            let outcome = classifier.classify(input)
            guard case .triage(let meta) = outcome else {
                Issue.record("Expected triage(.uncertain), got \(outcome)")
                continue
            }
            #expect(meta.kind == .uncertain)
        }
    }

    @Test("sentByOwner, sentByOwnerInThread, and hasFlaggedInThread block auto-trash")
    func ownerAndFlaggedThreadBlockAutoTrash() {
        let classifier = RuleBasedClassifier()
        let ownerSentOutcome = classifier.classify(makePromoSignals(id: "owner-sent", sentByOwner: true))
        guard case .triage(let ownerSentMeta) = ownerSentOutcome else {
            Issue.record("Expected owner-sent message to avoid auto-trash, got \(ownerSentOutcome)")
            return
        }
        #expect(ownerSentMeta.kind == .uncertain)

        let ownerThread = ConversationContext(
            conversationId: 1001,
            messageCount: 2,
            sentByOwnerInThread: true,
            hasFlaggedInThread: false,
            priorMessages: []
        )
        let ownerThreadOutcome = classifier.classify(makePromoSignals(id: "owner-thread", conversation: ownerThread))
        guard case .triage(let ownerThreadMeta) = ownerThreadOutcome else {
            Issue.record("Expected owner thread message to avoid auto-trash, got \(ownerThreadOutcome)")
            return
        }
        #expect(ownerThreadMeta.kind == .uncertain)

        let flaggedThread = ConversationContext(
            conversationId: 1002,
            messageCount: 2,
            sentByOwnerInThread: false,
            hasFlaggedInThread: true,
            priorMessages: []
        )
        let flaggedThreadOutcome = classifier.classify(makePromoSignals(id: "flagged-thread", conversation: flaggedThread))
        guard case .triage(let flaggedThreadMeta) = flaggedThreadOutcome else {
            Issue.record("Expected flagged thread message to avoid auto-trash, got \(flaggedThreadOutcome)")
            return
        }
        #expect(flaggedThreadMeta.kind == .uncertain)
    }
}

@Suite("AppleMailAdapter Mutation, Reconciliation, and Context Integration")
struct AppleMailAdapterIntegrationTests {
    private func makeFixture() throws -> (
        root: URL,
        mailVDir: URL,
        cacheDBPath: String,
        ledgerDBPath: String,
        accountsDBPath: String
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mailroom-adapter-integ-\(UUID().uuidString)", isDirectory: true)
        let mailVDir = root.appendingPathComponent("Mail", isDirectory: true)
        let v10Dir = mailVDir.appendingPathComponent("V10", isDirectory: true)
        let mailDataDir = v10Dir.appendingPathComponent("MailData", isDirectory: true)
        try FileManager.default.createDirectory(at: mailDataDir, withIntermediateDirectories: true)

        let envelopePath = mailDataDir.appendingPathComponent("Envelope Index").path
        let conn = try SQLiteConnection(readWritePath: envelopePath)
        try conn.execute("CREATE TABLE mailboxes (ROWID INTEGER PRIMARY KEY, url TEXT NOT NULL, total_count INTEGER NOT NULL DEFAULT 0, unread_count INTEGER NOT NULL DEFAULT 0);")
        try conn.execute("CREATE TABLE addresses (ROWID INTEGER PRIMARY KEY, address TEXT, comment TEXT);")
        try conn.execute("CREATE TABLE subjects (ROWID INTEGER PRIMARY KEY, subject TEXT);")
        try conn.execute("CREATE TABLE summaries (ROWID INTEGER PRIMARY KEY, summary TEXT);")
        try conn.execute("""
            CREATE TABLE messages (
                ROWID INTEGER PRIMARY KEY,
                message_id INTEGER NOT NULL DEFAULT 0,
                conversation_id INTEGER NOT NULL DEFAULT 0,
                mailbox INTEGER NOT NULL,
                sender INTEGER,
                subject_prefix TEXT,
                subject INTEGER,
                summary INTEGER,
                date_received INTEGER,
                date_sent INTEGER,
                flags INTEGER NOT NULL DEFAULT 0,
                read INTEGER NOT NULL DEFAULT 0,
                flagged INTEGER NOT NULL DEFAULT 0,
                deleted INTEGER NOT NULL DEFAULT 0,
                size INTEGER DEFAULT 0,
                list_id_hash INTEGER,
                unsubscribe_type INTEGER,
                automated_conversation INTEGER DEFAULT 0
            );
        """)
        try conn.execute("""
            CREATE TABLE labels (
                message_id INTEGER NOT NULL,
                mailbox_id INTEGER NOT NULL
            );
        """)
        try conn.execute("""
            CREATE TABLE attachments (
                ROWID INTEGER PRIMARY KEY,
                message INTEGER NOT NULL,
                name TEXT
            );
        """)

        let accountUUID = "GMAIL-ACC-1111"
        let inboxURL = "imap://\(accountUUID)/INBOX"
        let allMailURL = "imap://\(accountUUID)/%5BGmail%5D/All%20Mail"
        let sentURL = "imap://\(accountUUID)/%5BGmail%5D/Sent%20Mail"

        try conn.execute(
            "INSERT INTO mailboxes (ROWID, url) VALUES (1, ?), (2, ?), (3, ?);",
            bindings: [.text(inboxURL), .text(allMailURL), .text(sentURL)]
        )
        try conn.execute(
            "INSERT INTO addresses (ROWID, address, comment) VALUES (1, 'deals@example.invalid', 'Promo Sender'), (2, 'owner@example.invalid', 'Owner'), (3, 'service@example.invalid', 'Service Notice');"
        )
        try conn.execute(
            "INSERT INTO subjects (ROWID, subject) VALUES (1, 'Flash sale unsubscribe test'), (2, 'Re: Flash sale unsubscribe test'), (3, 'Image only update');"
        )

        // ROWID 101: Gmail INBOX message physically stored in [Gmail]/All Mail, tagged via labels
        // ROWID 102: Owner reply in same conversation 5001 (in Sent Mail)
        // ROWID 103: Image-only HTML partial message in INBOX (conversation 5002)
        try conn.execute("""
            INSERT INTO messages (ROWID, message_id, conversation_id, mailbox, sender, subject, date_received, date_sent, read, flagged, deleted, size) VALUES
            (101, 90101, 5001, 2, 1, 1, 1700000100, 1700000100, 0, 0, 0, 1024),
            (102, 90102, 5001, 3, 2, 2, 1700000200, 1700000200, 1, 0, 0, 512),
            (103, 90103, 5002, 1, 3, 3, 1700000300, 1700000300, 0, 0, 0, 800);
        """)
        try conn.execute("INSERT INTO labels (message_id, mailbox_id) VALUES (101, 1);")

        // Write .emlx files in V10/<accountUUID>/<mbox>.mbox/Data/Messages/<ROWID>.emlx
        let allMailDataRoot = v10Dir
            .appendingPathComponent(accountUUID, isDirectory: true)
            .appendingPathComponent("[Gmail].mbox/All Mail.mbox/UUID-1/Data", isDirectory: true)
        let allMailMsgs = AppleMailAdapter.shardMessagesDirectory(dataRoot: allMailDataRoot, rowId: 101)
        try FileManager.default.createDirectory(at: allMailMsgs, withIntermediateDirectories: true)
        try writeEmlx(
            to: allMailMsgs.appendingPathComponent("101.emlx"),
            rfcMessageId: "<gmail-msg-101@example.invalid>",
            from: "Promo Sender <deals@example.invalid>",
            to: "owner@example.invalid",
            subject: "Flash sale unsubscribe test",
            body: "50% off limited time flash sale! Unsubscribe anytime."
        )

        let sentDataRoot = v10Dir
            .appendingPathComponent(accountUUID, isDirectory: true)
            .appendingPathComponent("[Gmail].mbox/Sent Mail.mbox/UUID-2/Data", isDirectory: true)
        let sentMsgs = AppleMailAdapter.shardMessagesDirectory(dataRoot: sentDataRoot, rowId: 102)
        try FileManager.default.createDirectory(at: sentMsgs, withIntermediateDirectories: true)
        try writeEmlx(
            to: sentMsgs.appendingPathComponent("102.emlx"),
            rfcMessageId: "<owner-reply-102@example.invalid>",
            from: "Owner <owner@example.invalid>",
            to: "deals@example.invalid",
            subject: "Re: Flash sale unsubscribe test",
            body: "Please keep my account active."
        )

        let inboxDataRoot = v10Dir
            .appendingPathComponent(accountUUID, isDirectory: true)
            .appendingPathComponent("INBOX.mbox/UUID-3/Data", isDirectory: true)
        let inboxMsgs = AppleMailAdapter.shardMessagesDirectory(dataRoot: inboxDataRoot, rowId: 103)
        try FileManager.default.createDirectory(at: inboxMsgs, withIntermediateDirectories: true)
        try writeEmlx(
            to: inboxMsgs.appendingPathComponent("103.partial.emlx"),
            rfcMessageId: "<partial-103@example.invalid>",
            from: "Service Notice <service@example.invalid>",
            to: "owner@example.invalid",
            subject: "Image only update",
            contentType: "text/html; charset=utf-8",
            body: "<html><body><img src=\"https://cdn.example.invalid/banner.png\" alt=\"\" /></body></html>"
        )

        let cacheDBPath = root.appendingPathComponent("cache.sqlite").path
        let ledgerDBPath = root.appendingPathComponent("ledger.sqlite").path
        let accountsDBPath = root.appendingPathComponent("nonexistent-accounts.sqlite").path
        return (root, v10Dir, cacheDBPath, ledgerDBPath, accountsDBPath)
    }

    private func writeEmlx(
        to url: URL,
        rfcMessageId: String,
        from: String,
        to: String,
        subject: String,
        contentType: String = "text/plain; charset=utf-8",
        body: String
    ) throws {
        let raw = """
        From: \(from)\r
        To: \(to)\r
        Subject: \(subject)\r
        Message-ID: \(rfcMessageId)\r
        MIME-Version: 1.0\r
        Content-Type: \(contentType)\r
        \r
        \(body)
        """
        let byteCount = raw.utf8.count
        let content = "\(byteCount)\n\(raw)\n<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict/></plist>\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test("Gmail archive passes INBOX + [Gmail]/All Mail, suppresses echo, and restores across restart")
    func gmailArchiveEchoSuppressionAndCrossRestartRestore() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let executor = MockAppleMailExecutor(verifyScriptSyntax: true)
        let adapter1 = try AppleMailAdapter(
            mailVDir: fixture.mailVDir,
            maxInboxFetch: 20,
            scriptExecutor: executor,
            cacheDBPath: fixture.cacheDBPath,
            mutationLedgerDBPath: fixture.ledgerDBPath,
            accountsDBPath: fixture.accountsDBPath,
            ownerAddresses: ["owner@example.invalid"],
            echoSuppressionWindow: 60.0
        )

        let initial = try await adapter1.fetchDeck()
        #expect(initial.queue.count + initial.handled.count == 2)

        // Item 101 is in conversation 5001 where owner replied (sentByOwnerInThread == true) -> stays uncertain in queue
        let gmailItem = try #require(initial.queue.first(where: { $0.id == MessageId("gmail-msg-101@example.invalid") }))
        #expect(gmailItem.content.conversation?.sentByOwnerInThread == true)
        #expect(gmailItem.meta.kind == .uncertain)

        // Item 103 is partial + image-only -> stays uncertain in queue
        let partialItem = try #require(initial.queue.first(where: { $0.id == MessageId("partial-103@example.invalid") }))
        #expect(partialItem.content.isPartial == true)
        #expect(partialItem.content.bodyIsImageOnly == true)
        #expect(partialItem.meta.kind == .uncertain)

        // Archive Gmail item 101: sourceMailboxes must include INBOX even when physical mailbox is [Gmail]/All Mail
        try await adapter1.archive(id: gmailItem.id)
        let archiveInvocations = await executor.invocations
        #expect(archiveInvocations.count == 1)
        let archiveCall = try #require(archiveInvocations.first)
        #expect(archiveCall.kind == .moveMessage)
        #expect(archiveCall.sourceMailboxes.contains("INBOX"))
        #expect(archiveCall.destinationMailbox == "[Gmail]/All Mail")
        #expect(archiveCall.rowId == 101)

        // Immediately refetch with stale Envelope Index (still has INBOX label): echo suppression hides 101
        let afterArchive = try await adapter1.fetchDeck()
        #expect(!afterArchive.queue.contains(where: { $0.id == gmailItem.id }))
        #expect(!afterArchive.handled.contains(where: { $0.id == gmailItem.id }))

        // Simulate app restart with a fresh AppleMailAdapter instance pointing to the same ledger/cache DBs
        let executorAfterRestart = MockAppleMailExecutor(verifyScriptSyntax: true)
        let adapter2 = try AppleMailAdapter(
            mailVDir: fixture.mailVDir,
            maxInboxFetch: 20,
            scriptExecutor: executorAfterRestart,
            cacheDBPath: fixture.cacheDBPath,
            mutationLedgerDBPath: fixture.ledgerDBPath,
            accountsDBPath: fixture.accountsDBPath,
            ownerAddresses: ["owner@example.invalid"],
            echoSuppressionWindow: 60.0
        )

        let persistedUndo = await adapter2.undoRecord(for: gmailItem.id)
        #expect(persistedUndo != nil)
        try await adapter2.restore(id: gmailItem.id)

        let restoreInvocations = await executorAfterRestart.invocations
        #expect(restoreInvocations.count == 1)
        let restoreCall = try #require(restoreInvocations.first)
        #expect(restoreCall.kind == .moveMessage)
        #expect(restoreCall.destinationMailbox == "INBOX")
        #expect(restoreCall.rfcMessageId.contains("gmail-msg-101@example.invalid"))

        // After restore, item reappears in queue immediately
        let afterRestore = try await adapter2.fetchDeck()
        #expect(afterRestore.queue.contains(where: { $0.id == gmailItem.id }))
    }

    @Test("Failed moveToTrash rolls back undo record and preserves item in queue")
    func failedMutationRollsBackLedgerAndQueueVisibility() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        enum TestFailure: Error { case appleEventFailed }

        let executor = MockAppleMailExecutor(verifyScriptSyntax: true)
        await executor.enqueueError(TestFailure.appleEventFailed)

        let adapter = try AppleMailAdapter(
            mailVDir: fixture.mailVDir,
            maxInboxFetch: 20,
            scriptExecutor: executor,
            cacheDBPath: fixture.cacheDBPath,
            mutationLedgerDBPath: fixture.ledgerDBPath,
            accountsDBPath: fixture.accountsDBPath,
            ownerAddresses: ["owner@example.invalid"]
        )

        let initial = try await adapter.fetchDeck()
        let target = try #require(initial.queue.first(where: { $0.id == MessageId("partial-103@example.invalid") }))

        await #expect(throws: TestFailure.self) {
            try await adapter.moveToTrash(id: target.id, reason: .userPromo)
        }

        let undo = await adapter.undoRecord(for: target.id)
        #expect(undo == nil)

        let afterFailure = try await adapter.fetchDeck()
        #expect(afterFailure.queue.contains(where: { $0.id == target.id }))
    }

    @Test("Hydrates .partial.emlx via AppleScript source fetch (preserving read status) and caches full HTML in SQLite")
    func hydratePartialMessageUpdatesHtmlAndCachesInSQLite() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let executor = MockAppleMailExecutor(verifyScriptSyntax: true)
        // Simulate classic AppleEvent `source of msg` returning CR (\r) line endings + full multipart HTML
        let fullMimeLines = [
            "From: Service Notice <service@example.invalid>",
            "To: owner@example.invalid",
            "Subject: Image only update",
            "Message-ID: <partial-103@example.invalid>",
            "MIME-Version: 1.0",
            "Content-Type: multipart/alternative; boundary=\"hydr-b\"",
            "",
            "--hydr-b",
            "Content-Type: text/plain; charset=\"utf-8\"",
            "",
            "Complete hydrated billing statement: USD 128.00 due on Nov 30.",
            "--hydr-b",
            "Content-Type: text/html; charset=\"utf-8\"",
            "",
            "<html><body><h2>Billing Statement</h2><p>Complete hydrated billing statement: <strong>USD 128.00</strong> due on Nov 30.</p><img src=\"https://cdn.example.invalid/logo.png\"></body></html>",
            "--hydr-b--",
            ""
        ]
        let crSeparatedMime = fullMimeLines.joined(separator: "\r")
        await executor.setMockMessageSource(crSeparatedMime, for: "partial-103@example.invalid")

        let adapter = try AppleMailAdapter(
            mailVDir: fixture.mailVDir,
            maxInboxFetch: 20,
            scriptExecutor: executor,
            cacheDBPath: fixture.cacheDBPath,
            mutationLedgerDBPath: fixture.ledgerDBPath,
            accountsDBPath: fixture.accountsDBPath,
            ownerAddresses: ["owner@example.invalid"]
        )

        let initial = try await adapter.fetchDeck()
        let partialItem = try #require(initial.queue.first(where: { $0.id == MessageId("partial-103@example.invalid") }))
        #expect(partialItem.isPartial == true)
        #expect(partialItem.hasRemoteImages == true)

        let hydrated = try #require(try await adapter.hydrateMessage(id: partialItem.id))
        #expect(hydrated.isPartial == false)
        #expect(hydrated.isTruncated == false)
        #expect(hydrated.plainText.contains("USD 128.00 due on Nov 30"))
        #expect(hydrated.htmlBody?.contains("<strong>USD 128.00</strong>") == true)
        #expect(hydrated.hasRemoteImages == true)
        #expect(hydrated.isReadInMail == false)

        let calls = await executor.invocations
        #expect(calls.count == 1)
        #expect(calls[0].kind == .fetchMessageSource)
        #expect(calls[0].generatedScript?.contains("source of msg") == true)
        #expect(calls[0].generatedScript?.contains("wasReadBefore") == true)

        // Subsequent fetchDeck reads hydrated payload directly from parsed_emlx_v3 SQLite cache
        let reloaded = try await adapter.fetchDeck()
        let allItemsContent = reloaded.queue.map(\.content) + reloaded.handled.map(\.content)
        let cachedContent = try #require(allItemsContent.first(where: { $0.id == partialItem.id }))
        #expect(cachedContent.isPartial == false)
        #expect(cachedContent.plainText.contains("USD 128.00 due on Nov 30"))
        #expect(cachedContent.htmlBody?.contains("Billing Statement") == true)
    }
}

import Foundation
import Testing
@testable import MailroomCore

@Suite("AppleMailScriptRunner & MutationLedger Tests")
struct MutationLedgerAndScriptTests {

    // MARK: - AppleScript Generation & Compilation (Offline)

    @Test("Gmail archive prepends INBOX when caller only passes [Gmail]/All Mail and compiles cleanly")
    func gmailArchiveFixesSameMailboxBug() throws {
        let script = AppleMailScriptBuilder.buildMoveScript(
            accountUUID: "GMAIL-UUID-1",
            sourceMailboxes: ["[Gmail]/All Mail"],
            destinationMailbox: "[Gmail]/All Mail",
            createDestinationIfMissing: false,
            rowId: 39350,
            rfcMessageId: "<msg-39350@example.com>",
            markRead: true,
            markFlagged: nil
        )

        // INBOX must be searched before [Gmail]/All Mail so matchedBoxPath != "[Gmail]/All Mail" and move executes
        let inboxRange = try #require(script.range(of: #"set matchedBoxPath to "INBOX""#))
        let allMailRange = try #require(script.range(of: #"set matchedBoxPath to "[Gmail]/All Mail""#))
        #expect(inboxRange.lowerBound < allMailRange.lowerBound)
        #expect(script.contains(#"if matchedBoxPath is not "[Gmail]/All Mail" then"#))
        #expect(script.contains("move msg to dstBox"))
        #expect(script.contains("set read status of msg to true"))
        // Normalized message-id searches both unbracketed and bracketed
        #expect(script.contains(#"whose message id is "msg-39350@example.com""#))
        #expect(script.contains(#"whose message id is "<msg-39350@example.com>""#))
        // Protected Gmail mailbox is never auto-created
        #expect(!script.contains("make new mailbox"))

        try AppleMailScriptBuilder.compileCheck(script).get()
    }

    @Test("Gmail restore from [Gmail]/All Mail and [Gmail]/Trash to INBOX restores flags and compiles")
    func gmailRestoreScriptsCompile() throws {
        for source in ["[Gmail]/All Mail", "[Gmail]/Trash"] {
            let script = AppleMailScriptBuilder.buildMoveScript(
                accountUUID: "GMAIL-UUID-1",
                sourceMailboxes: [source],
                destinationMailbox: "INBOX",
                createDestinationIfMissing: false,
                rowId: 40001,
                rfcMessageId: "restore-1@example.com",
                markRead: false,
                markFlagged: true
            )
            #expect(script.contains("set read status of msg to false"))
            #expect(script.contains("set flagged status of msg to true"))
            #expect(script.contains(#"if matchedBoxPath is not "INBOX" then"#))
            try AppleMailScriptBuilder.compileCheck(script).get()
        }
    }

    @Test("iCloud missing Archive creation and nested mailbox creation compile cleanly")
    func icloudAndNestedMailboxCreation() throws {
        // Top-level Archive creation for iCloud
        let icloudScript = AppleMailScriptBuilder.buildMoveScript(
            accountUUID: "ICLOUD-UUID-2",
            sourceMailboxes: ["INBOX"],
            destinationMailbox: "Archive",
            createDestinationIfMissing: true,
            rowId: 250,
            rfcMessageId: "icloud-1@example.com",
            markRead: true,
            markFlagged: nil
        )
        #expect(icloudScript.contains(#"make new mailbox with properties {name:"Archive"} at curBox"#))
        #expect(icloudScript.contains(#"error "MAILBOX_NOT_FOUND:Archive""#))
        try AppleMailScriptBuilder.compileCheck(icloudScript).get()

        // Nested mailbox lookup + creation ("Archive/2026")
        let nestedScript = AppleMailScriptBuilder.buildMoveScript(
            accountUUID: "IMAP-UUID-3",
            sourceMailboxes: ["Tasks/ASU application"],
            destinationMailbox: "Archive/2026",
            createDestinationIfMissing: true,
            rowId: nil,
            rfcMessageId: #"quoted"id\test@example.com"#,
            markRead: nil,
            markFlagged: false
        )
        #expect(nestedScript.contains(#"mailbox "Tasks/ASU application" of acc"#))
        #expect(nestedScript.contains(#"mailbox "ASU application" of curBox"#))
        #expect(nestedScript.contains(#"make new mailbox with properties {name:"Archive"} at curBox"#))
        #expect(nestedScript.contains(#"make new mailbox with properties {name:"2026"} at curBox"#))
        #expect(nestedScript.contains(#"quoted\"id\\test@example.com"#))
        try AppleMailScriptBuilder.compileCheck(nestedScript).get()

        // Protected Gmail path must NOT emit make new mailbox even if createDestinationIfMissing is true
        let protectedScript = AppleMailScriptBuilder.buildMoveScript(
            accountUUID: "GMAIL-UUID-1",
            sourceMailboxes: ["INBOX"],
            destinationMailbox: "[Gmail]/All Mail",
            createDestinationIfMissing: true,
            rowId: 123,
            rfcMessageId: "prot@example.com",
            markRead: true,
            markFlagged: nil
        )
        #expect(!protectedScript.contains("make new mailbox"))
        try AppleMailScriptBuilder.compileCheck(protectedScript).get()
    }

    @Test("updateFlags and openMessageWindow scripts compile cleanly across nested mailboxes")
    func updateFlagsAndOpenWindowCompile() throws {
        let flagScript = AppleMailScriptBuilder.buildUpdateFlagsScript(
            accountUUID: "EWS-UUID-4",
            mailboxes: ["Inbox", "Archive"],
            rowId: 4429,
            rfcMessageId: "ews-1@example.com",
            markRead: true,
            markFlagged: true
        )
        #expect(flagScript.contains("set read status of msg to true"))
        #expect(flagScript.contains("set flagged status of msg to true"))
        try AppleMailScriptBuilder.compileCheck(flagScript).get()

        let openScript = AppleMailScriptBuilder.buildOpenMessageScript(
            accountUUID: "GMAIL-UUID-1",
            mailboxes: ["[Gmail]/Trash", "[Gmail]/All Mail"],
            rowId: 999,
            rfcMessageId: "trash-1@example.com"
        )
        #expect(openScript.contains("open msg"))
        #expect(openScript.contains("activate"))
        try AppleMailScriptBuilder.compileCheck(openScript).get()
    }

    // MARK: - Runner Retries & MockAppleMailExecutor

    @Test("AppleMailScriptRunner retries transient execution errors but fails fast on messageNotFound")
    func runnerRetryAndErrorPolicy() async throws {
        final class Counter: @unchecked Sendable {
            var count = 0
        }

        // Transient failure x2 -> succeeds on 3rd attempt
        let transientCounter = Counter()
        let runner = AppleMailScriptRunner(
            maxRetries: 2,
            retryDelayNanoseconds: 1_000_000,
            ensureRunningHook: {},
            rawScriptEvaluator: { _, _ in
                transientCounter.count += 1
                if transientCounter.count < 3 {
                    throw AppleMailScriptError.executionFailed("AppleEvent timed out (-1712)")
                }
                return "ok"
            }
        )
        try await runner.moveMessage(
            accountUUID: "ACC-1",
            sourceMailbox: "INBOX",
            destinationMailbox: "Archive",
            rowId: 10,
            rfcMessageId: "retry@example.com",
            markRead: true,
            markFlagged: nil
        )
        #expect(transientCounter.count == 3)

        // Non-retryable messageNotFound -> fails after 1 attempt
        let notFoundCounter = Counter()
        let notFoundRunner = AppleMailScriptRunner(
            maxRetries: 2,
            retryDelayNanoseconds: 1_000_000,
            ensureRunningHook: {},
            rawScriptEvaluator: { _, hint in
                notFoundCounter.count += 1
                throw AppleMailScriptRunner.mapExecutionErrorMessage("MESSAGE_NOT_FOUND", messageIdHint: hint)
            }
        )
        await #expect(throws: AppleMailScriptError.messageNotFound("missing@example.com")) {
            try await notFoundRunner.updateFlags(
                accountUUID: "ACC-1",
                mailbox: "INBOX",
                rowId: 11,
                rfcMessageId: "missing@example.com",
                markRead: true,
                markFlagged: true
            )
        }
        #expect(notFoundCounter.count == 1)

        // MAILBOX_NOT_FOUND mapping
        let mapped = AppleMailScriptRunner.mapExecutionErrorMessage(
            "MAILBOX_NOT_FOUND:Archive/2026",
            messageIdHint: "x"
        )
        #expect(mapped == .mailboxNotFound("Archive/2026"))
    }

    @Test("MockAppleMailExecutor captures backwards-compatible and multi-mailbox invocations")
    func mockExecutorCapturesAndInjectsErrors() async throws {
        let mock = MockAppleMailExecutor(verifyScriptSyntax: true)
        try await mock.moveMessage(
            accountUUID: "GMAIL-1",
            sourceMailbox: "[Gmail]/All Mail",
            destinationMailbox: "[Gmail]/All Mail",
            createDestinationIfMissing: false,
            rowId: 101,
            rfcMessageId: "m1@example.com",
            markRead: true,
            markFlagged: nil
        )
        let recorded = await mock.invocations
        #expect(recorded.count == 1)
        #expect(recorded[0].sourceMailboxes == ["INBOX", "[Gmail]/All Mail"])
        #expect(recorded[0].generatedScript != nil)

        await mock.enqueueError(AppleMailScriptError.mailboxNotFound("Archive"))
        await #expect(throws: AppleMailScriptError.mailboxNotFound("Archive")) {
            try await mock.moveMessage(
                accountUUID: "ICLOUD-1",
                sourceMailboxes: ["INBOX"],
                destinationMailbox: "Archive",
                createDestinationIfMissing: false,
                rowId: 102,
                rfcMessageId: "m2@example.com",
                markRead: true,
                markFlagged: nil
            )
        }
    }

    // MARK: - MutationLedger Persistence & Reconciliation

    @Test("MutationLedger persists undo records across restarts and updates resolved ROWID")
    func ledgerPersistsAcrossRestarts() async throws {
        let dbPath = tempDBPath()
        defer { cleanupTempDB(at: dbPath) }

        let t0 = Date(timeIntervalSince1970: 1_760_000_000)
        do {
            let ledger = try MutationLedger(dbPath: dbPath, echoSuppressionWindow: 15.0)
            let undo = UndoRecord(
                messageId: "gmail-msg-1@example.com",
                action: .archived,
                accountUUID: "GMAIL-UUID",
                inboxPath: "INBOX",
                targetMailboxPath: "[Gmail]/All Mail",
                previousRead: false,
                previousFlagged: true,
                lastKnownRowId: 39350,
                maxRowIdBeforeMove: 39400,
                timestamp: t0
            )
            let pending = try await ledger.beginMutation(
                rfcMessageId: "gmail-msg-1@example.com",
                action: .archive,
                accountUUID: "GMAIL-UUID",
                sourceMailbox: "INBOX",
                destinationMailbox: "[Gmail]/All Mail",
                inboxPath: "INBOX",
                expectedRead: true,
                preMoveRowId: 39350,
                maxRowIdBeforeMove: 39400,
                undoRecord: undo,
                now: t0
            )
            #expect(pending.status == .inFlight)

            try await ledger.markCommitted(
                mutationId: pending.mutationId,
                resolvedRowId: 39405,
                resolvedMailbox: "[Gmail]/All Mail",
                now: t0.addingTimeInterval(0.4)
            )
        }

        // Re-open with a fresh MutationLedger instance (simulating app restart)
        let restarted = try MutationLedger(dbPath: dbPath, echoSuppressionWindow: 15.0)
        let restoredUndo = try #require(try await restarted.undoRecord(for: "gmail-msg-1@example.com"))
        #expect(restoredUndo.accountUUID == "GMAIL-UUID")
        #expect(restoredUndo.inboxPath == "INBOX")
        #expect(restoredUndo.targetMailboxPath == "[Gmail]/All Mail")
        #expect(restoredUndo.previousRead == false)
        #expect(restoredUndo.previousFlagged == true)
        #expect(restoredUndo.lastKnownRowId == 39350)
        #expect(restoredUndo.resolvedRowId == 39405)
        #expect(restoredUndo.resolvedMailboxPath == "[Gmail]/All Mail")

        let latest = try #require(try await restarted.latestMutation(for: "gmail-msg-1@example.com"))
        #expect(latest.status == .committed)
        #expect(latest.resolvedRowId == 39405)
    }

    @Test("MutationLedger suppresses stale Envelope Index echoes until convergence or timeout while preserving undo")
    func echoSuppressionAndReconciliation() async throws {
        let dbPath = tempDBPath()
        defer { cleanupTempDB(at: dbPath) }

        let ledger = try MutationLedger(dbPath: dbPath, echoSuppressionWindow: 10.0, inFlightTimeout: 30.0)
        let t0 = Date(timeIntervalSince1970: 1_760_000_100)

        // 1. Archive is inFlight -> stale Envelope Index still lists message in INBOX
        let mArchive = try await ledger.beginMutation(
            rfcMessageId: "arch@example.com",
            action: .archive,
            accountUUID: "ACC-1",
            sourceMailbox: "INBOX",
            destinationMailbox: "Archive",
            inboxPath: "INBOX",
            preMoveRowId: 100,
            maxRowIdBeforeMove: 105,
            undoRecord: UndoRecord(
                messageId: "arch@example.com",
                action: .archived,
                accountUUID: "ACC-1",
                inboxPath: "INBOX",
                targetMailboxPath: "Archive",
                previousRead: false,
                previousFlagged: false,
                lastKnownRowId: 100,
                maxRowIdBeforeMove: 105,
                timestamp: t0
            ),
            now: t0
        )
        #expect(try await ledger.shouldSuppressFilesystemEcho(now: t0.addingTimeInterval(0.5)) == true)

        let staleObs = ObservedInboxState(
            messageId: "arch@example.com",
            rowId: 100,
            mailboxPath: "INBOX",
            isRead: false,
            isFlagged: false,
            isInInbox: true
        )
        let reportWhileInFlight = try await ledger.reconcile(
            observedInboxMessages: [staleObs],
            now: t0.addingTimeInterval(0.5)
        )
        #expect(reportWhileInFlight.suppressedMessageIds.contains("arch@example.com"))

        // 2. Archive commits, FSEvents fires 2s later before Envelope Index drops INBOX row -> still suppressed!
        try await ledger.markCommitted(
            mutationId: mArchive.mutationId,
            resolvedRowId: 106,
            resolvedMailbox: "Archive",
            now: t0.addingTimeInterval(1.0)
        )
        let reportDuringEchoWindow = try await ledger.reconcile(
            observedInboxMessages: [staleObs],
            now: t0.addingTimeInterval(3.0)
        )
        #expect(reportDuringEchoWindow.suppressedMessageIds.contains("arch@example.com"))

        // 3. Envelope Index syncs (message disappears from INBOX) -> converges & retires pending_mutations, keeps undo_ledger
        let reportConverged = try await ledger.reconcile(
            observedInboxMessages: [],
            now: t0.addingTimeInterval(4.0)
        )
        #expect(reportConverged.convergedMessageIds.contains("arch@example.com"))
        #expect(reportConverged.suppressedMessageIds.isEmpty)
        #expect(try await ledger.latestMutation(for: "arch@example.com") == nil)
        #expect(try await ledger.undoRecord(for: "arch@example.com")?.resolvedRowId == 106)

        // 4. Keep mutation expires if Envelope Index still shows unflagged after echoSuppressionWindow
        let mKeep = try await ledger.beginMutation(
            rfcMessageId: "keep@example.com",
            action: .keep,
            accountUUID: "ACC-1",
            sourceMailbox: "INBOX",
            destinationMailbox: "INBOX",
            inboxPath: "INBOX",
            expectedRead: true,
            expectedFlagged: true,
            preMoveRowId: 200,
            maxRowIdBeforeMove: 200,
            now: t0
        )
        try await ledger.markCommitted(mutationId: mKeep.mutationId, now: t0.addingTimeInterval(0.5))
        let unflaggedObs = ObservedInboxState(
            messageId: "keep@example.com",
            rowId: 200,
            mailboxPath: "INBOX",
            isRead: false,
            isFlagged: false,
            isInInbox: true
        )
        let keepSuppressed = try await ledger.reconcile(
            observedInboxMessages: [unflaggedObs],
            now: t0.addingTimeInterval(5.0)
        )
        #expect(keepSuppressed.suppressedMessageIds.contains("keep@example.com"))

        let keepExpired = try await ledger.reconcile(
            observedInboxMessages: [unflaggedObs],
            now: t0.addingTimeInterval(12.0)
        )
        #expect(keepExpired.expiredMessageIds.contains("keep@example.com"))
        #expect(!keepExpired.suppressedMessageIds.contains("keep@example.com"))
    }

    @Test("MutationLedger tracks failures, retries, and times out abandoned in-flight rows")
    func failureRetryAndInFlightTimeout() async throws {
        let dbPath = tempDBPath()
        defer { cleanupTempDB(at: dbPath) }

        let ledger = try MutationLedger(dbPath: dbPath, echoSuppressionWindow: 10.0, inFlightTimeout: 20.0)
        let t0 = Date(timeIntervalSince1970: 1_760_000_200)

        let rec = try await ledger.beginMutation(
            rfcMessageId: "fail@example.com",
            action: .trash,
            accountUUID: "ACC-2",
            sourceMailbox: "INBOX",
            destinationMailbox: "Deleted Messages",
            inboxPath: "INBOX",
            preMoveRowId: 300,
            maxRowIdBeforeMove: 300,
            undoRecord: UndoRecord(
                messageId: "fail@example.com",
                action: .trashed,
                accountUUID: "ACC-2",
                inboxPath: "INBOX",
                targetMailboxPath: "Deleted Messages",
                previousRead: true,
                previousFlagged: false,
                lastKnownRowId: 300,
                maxRowIdBeforeMove: 300,
                timestamp: t0
            ),
            now: t0
        )
        try await ledger.markFailed(
            mutationId: rec.mutationId,
            error: "Mail busy",
            rollbackUndoRecord: true,
            now: t0.addingTimeInterval(1)
        )

        let failedList = try await ledger.failedMutations()
        #expect(failedList.count == 1)
        #expect(failedList[0].retryCount == 1)
        #expect(failedList[0].lastError == "Mail busy")
        #expect(try await ledger.undoRecord(for: "fail@example.com") == nil)

        // Failed mutation must NOT suppress the message from queue
        let dec = try await ledger.reconciliationDecision(
            for: "fail@example.com",
            observedInInbox: true,
            observedRead: true,
            observedFlagged: false,
            now: t0.addingTimeInterval(2)
        )
        #expect(dec == .useEnvelopeState)

        // Retry transitions back to inFlight
        let retried = try #require(try await ledger.prepareRetry(mutationId: rec.mutationId, now: t0.addingTimeInterval(3)))
        #expect(retried.status == .inFlight)
        #expect(retried.retryCount == 1)

        // Abandoned inFlight mutation past inFlightTimeout transitions to failed on reconcile
        let timeoutReport = try await ledger.reconcile(
            observedInboxMessages: [],
            now: t0.addingTimeInterval(25)
        )
        #expect(timeoutReport.timedOutInFlightIds == [rec.mutationId])
        let timedOut = try #require(try await ledger.latestMutation(for: "fail@example.com"))
        #expect(timedOut.status == .failed)
    }

    // MARK: - Helpers

    private func tempDBPath() -> String {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("mailroom-ledger-tests-\(UUID().uuidString)", isDirectory: true)
        return dir.appendingPathComponent("ledger.sqlite").path
    }

    private func cleanupTempDB(at path: String) {
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
    }
}

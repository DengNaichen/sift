import Foundation
import Testing
@testable import MailroomCore

@Suite("BridgeDoctorReport & EvalDatasetExporter Tests")
struct BridgeExporterTests {

    @Test("Address and label redaction masks local parts while preserving domains and non-email labels")
    func addressRedaction() {
        #expect(MailAddressRedactor.redactAddress("alice.chen@gmail.com") == "a***@gmail.com")
        #expect(MailAddressRedactor.redactAddress("u@domain.com") == "u***@domain.com")
        #expect(MailAddressRedactor.redactAddress("  bob@corp.example  ") == "b***@corp.example")
        #expect(MailAddressRedactor.redactAddress("") == "")
        let sampleUUID = "11111111-2222-3333-4444-555555555555"
        #expect(MailAddressRedactor.redactAddress(sampleUUID) == sampleUUID)

        #expect(MailAddressRedactor.redactText("Gmail") == "Gmail")
        #expect(MailAddressRedactor.redactText("工作") == "工作")
        #expect(MailAddressRedactor.redactText("Personal <alice.chen@gmail.com>") == "Personal <a***@gmail.com>")
    }

    @Test("BridgeDoctorReport resolves Gmail labels vs Exchange EWS vs iCloud IMAP, shard hits, and redacts PII")
    func syntheticDoctorInspection() throws {
        let fixture = try SyntheticMailStoreFixture.create()
        defer { fixture.cleanup() }

        let report = BridgeDoctorReport.inspect(
            mailVDir: fixture.vDir,
            accountsDBPath: fixture.accountsDBPath,
            limit: 40,
            isMailAppRunning: { false }
        )

        #expect(report.accessStatus == "ready")
        #expect(report.envelopeIndexWALMode.lowercased() == "wal")
        #expect(report.mailAppRunning == false)
        #expect(report.accounts.count == 3)

        let byId = Dictionary(uniqueKeysWithValues: report.accounts.map { ($0.accountId, $0) })

        let gmail = try #require(byId[fixture.gmailUUID])
        #expect(gmail.providerSemantics == .gmailLabels)
        #expect(gmail.redactedAddress == "a***@gmail.com")
        #expect(gmail.mailboxes.archivePath == "[Gmail]/All Mail")
        #expect(gmail.mailboxes.trashPath == "[Gmail]/Trash")
        #expect(gmail.mailboxes.sentPath == "[Gmail]/Sent Mail")
        #expect(gmail.inboxDirectCount == 0)
        #expect(gmail.inboxLabelCount == 2)
        #expect(gmail.inboxCombinedCount == 2)

        let ews = try #require(byId[fixture.ewsUUID])
        #expect(ews.providerSemantics == .exchangeEWS)
        #expect(ews.redactedAddress == "b***@acme-corp.example")
        #expect(ews.mailboxes.archivePath == "Archive")
        #expect(ews.mailboxes.trashPath == "Deleted Items")
        #expect(ews.mailboxes.sentPath == "Sent Items")
        #expect(ews.inboxDirectCount == 1)
        #expect(ews.inboxLabelCount == 0)
        #expect(ews.inboxCombinedCount == 1)

        let icloud = try #require(byId[fixture.icloudUUID])
        #expect(icloud.providerSemantics == .icloudOrIMAP)
        #expect(icloud.redactedAddress == "c***@icloud.com")
        #expect(icloud.mailboxes.archivePath == nil)
        #expect(icloud.mailboxes.trashPath == "Deleted Messages")
        #expect(icloud.mailboxes.sentPath == "Sent Messages")
        #expect(icloud.inboxDirectCount == 1)
        #expect(report.notes.contains(where: { $0.contains(fixture.icloudUUID) && $0.contains("Archive") }))

        // 4 inbox messages: 2 full .emlx, 1 .partial.emlx, 1 missing
        #expect(report.shardResolution.sampledCount == 4)
        #expect(report.shardResolution.fullEmlxHits == 2)
        #expect(report.shardResolution.partialEmlxHits == 1)
        #expect(report.shardResolution.missingFiles == 1)
        #expect(report.shardResolution.parseErrors == 0)
        #expect(report.shardResolution.hitRate == 0.75)

        // Zero PII in doctor text or JSON output
        let renderedText = report.renderText()
        let renderedJSON = try report.renderJSON(pretty: true)
        for rendered in [renderedText, renderedJSON] {
            #expect(!rendered.contains("alice.secret@gmail.com"))
            #expect(!rendered.contains("bob.work@acme-corp.example"))
            #expect(!rendered.contains("carol.personal@icloud.com"))
            #expect(!rendered.contains("CONFIDENTIAL_SUBJECT"))
            #expect(!rendered.contains("CONFIDENTIAL_BODY"))
            #expect(!rendered.contains("Secret Sender Name"))
        }
        #expect(renderedText.contains("a***@gmail.com"))
        #expect(renderedText.contains("b***@acme-corp.example"))
        #expect(renderedText.contains("c***@icloud.com"))
    }

    @Test("EvalDatasetExporter produces email_rules.py-compatible JSON, enforces 0600 permissions and --force")
    func syntheticEvalExportAndSchema() throws {
        let fixture = try SyntheticMailStoreFixture.create()
        defer { fixture.cleanup() }

        let doc = try EvalDatasetExporter.exportDataset(
            mailVDir: fixture.vDir,
            accountsDBPath: fixture.accountsDBPath,
            limit: 10
        )

        #expect(doc.selection.count == 4)
        #expect(doc.samples.count == 4)
        #expect(doc.samples.map(\.id) == ["email-01", "email-02", "email-03", "email-04"])

        // Sample 1 (newest): HTML-only newsletter with <img> alt & invisible fillers -> body_is_image_only == true
        let s1 = try #require(doc.samples.first(where: { $0.gmailId == "<msg-html@example.com>" }))
        #expect(s1.sourceUrl == "message://%3Cmsg-html@example.com%3E")
        #expect(s1.email.bodyRepresentation == "text_extracted_from_full_html_with_image_alt")
        #expect(s1.email.unloadedHtmlImages == 1)
        #expect(s1.email.body.contains("[image alt: Promo Banner]"))
        #expect(!s1.email.body.contains("\u{200B}"))
        #expect(s1.email.bodyIsImageOnly == true)
        #expect(s1.email.truncated == false)
        #expect(s1.email.to == "alice.secret@gmail.com")

        // Sample 2: Plain-text thread message with prior owner reply in Sent & 12-message cap
        let s2 = try #require(doc.samples.first(where: { $0.gmailId == "<msg-thread@example.com>" }))
        #expect(s2.email.bodyRepresentation == "full_plain_text")
        #expect(s2.email.unloadedHtmlImages == 0)
        #expect(s2.email.bodyIsImageOnly == false)
        #expect(s2.email.starred == true)
        #expect(s2.email.hasAttachments == true)
        #expect(s2.email.conversationContextAvailable == true)
        #expect(s2.conversation.count == 12)
        #expect(s2.conversation.contains(where: { $0.sentByOwner == true }))
        // Chronological check: last item in capped conversation should be the newest prior reply
        #expect(s2.conversation.last?.body.contains("Owner final reply") == true)

        // Sample 3: .partial.emlx with truncated byte-count header -> truncated == true
        let s3 = try #require(doc.samples.first(where: { $0.gmailId == "<msg-partial@example.com>" }))
        #expect(s3.email.truncated == true)

        // Sample 4: missing .emlx -> summary_fallback & truncated == true
        let s4 = try #require(doc.samples.first(where: { $0.gmailId == "<rowid-104@applemail.local>" }))
        #expect(s4.email.bodyRepresentation == "summary_fallback")
        #expect(s4.email.truncated == true)

        // Write with 0600 permissions and refuse overwrite unless --force
        let outURL = fixture.rootDir.appendingPathComponent("exports/emails.json")
        try EvalDatasetExporter.writeDataset(doc, to: outURL, force: false)

        let attrs = try FileManager.default.attributesOfItem(atPath: outURL.path)
        let posix = attrs[.posixPermissions] as? NSNumber
        #expect(posix?.intValue == 0o600)

        #expect(throws: EvalExportError.outputFileExists(outURL.path)) {
            try EvalDatasetExporter.writeDataset(doc, to: outURL, force: false)
        }

        // Overwrite with force: true succeeds and retains 0600
        try EvalDatasetExporter.writeDataset(doc, to: outURL, force: true)
        let attrsAfter = try FileManager.default.attributesOfItem(atPath: outURL.path)
        let posixAfter = attrsAfter[.posixPermissions] as? NSNumber
        #expect(posixAfter?.intValue == 0o600)

        // Cross-check exported JSON directly against Python email_rules.py (input_data & build_request)
        let scriptsDir = "/Users/nd/Developer/mailroom/scripts"
        let rulesPath = "\(scriptsDir)/email_rules.py"
        if FileManager.default.fileExists(atPath: rulesPath) {
            let py = Process()
            py.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            py.arguments = [
                "-c",
                """
                import json, sys
                sys.path.insert(0, sys.argv[1])
                import email_rules
                doc = json.load(open(sys.argv[2], encoding="utf-8"))
                policy = email_rules.load_policy()
                assert set(doc.keys()) == {"selection", "samples"}
                assert len(doc["samples"]) == 4
                for s in doc["samples"]:
                    req = email_rules.build_request(s["email"], policy, "gemini-decision-1", s.get("conversation", []))
                    assert "input" in req and "questions" in req
                    # Also validate resolve_decision flag checks
                    fake_answers = {k: {"type": "noul", "noul": 0.1} for k in policy["questions"]}
                    dec = email_rules.resolve_decision({"answers": fake_answers}, s["email"], policy, s.get("conversation", []))
                    assert dec["action"] in email_rules.ACTIONS
                print("OK")
                """,
                scriptsDir,
                outURL.path
            ]
            let pipe = Pipe()
            py.standardOutput = pipe
            py.standardError = pipe
            try py.run()
            py.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            #expect(py.terminationStatus == 0, "Python email_rules.py validation failed: \(output)")
        }
    }

    @Test("Live read-only BridgeDoctorReport inspects V10 with zero unredacted email addresses")
    func liveReadOnlyDoctorOnV10() throws {
        guard case .ready = MailStoreEnvironment.checkAccess() else {
            return
        }

        let report = BridgeDoctorReport.inspect(limit: 40)
        #expect(report.accessStatus == "ready")
        #expect(report.envelopeIndexWALMode.lowercased() == "wal")
        #expect(!report.accounts.isEmpty)
        #expect(report.envelopeIndexQueryLatencyMs >= 0)
        #expect(report.shardResolution.sampledCount > 0)

        for acc in report.accounts {
            if acc.redactedAddress.contains("@") {
                #expect(acc.redactedAddress.contains("***@"))
            }
        }

        let rendered = report.renderText()
        // Every email address token in rendered doctor text must be masked with ***@
        let emailPattern = #"[^\s<>@"']+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#
        let regex = try NSRegularExpression(pattern: emailPattern)
        let matches = regex.matches(in: rendered, range: NSRange(rendered.startIndex..<rendered.endIndex, in: rendered))
        for m in matches {
            let token = (rendered as NSString).substring(with: m.range)
            #expect(token.contains("***@"), "Unredacted address token found in doctor output")
        }

        let summaryLine = report.accounts.map { "\($0.providerSemantics.rawValue)(direct=\($0.inboxDirectCount),labels=\($0.inboxLabelCount))" }.joined(separator: ", ")
        print("[BridgeExporterTests] Live V10 doctor: accounts=\(report.accounts.count) [\(summaryLine)], wal=\(report.envelopeIndexWALMode), latencyMs=\(report.envelopeIndexQueryLatencyMs), shardHitRate=\(report.shardResolution.hitRate)")
    }
}

// MARK: - Synthetic V10 Fixture

private struct SyntheticMailStoreFixture {
    let rootDir: URL
    let vDir: URL
    let accountsDBPath: String
    let gmailUUID = "AAAAAAAA-1111-2222-3333-444444444444"
    let ewsUUID = "BBBBBBBB-1111-2222-3333-444444444444"
    let icloudUUID = "CCCCCCCC-1111-2222-3333-444444444444"

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDir)
    }

    static func create() throws -> SyntheticMailStoreFixture {
        let fm = FileManager.default
        let rootDir = fm.temporaryDirectory.appendingPathComponent("mailroom-bridge-test-\(UUID().uuidString)", isDirectory: true)
        let vDir = rootDir.appendingPathComponent("V10", isDirectory: true)
        let mailDataDir = vDir.appendingPathComponent("MailData", isDirectory: true)
        try fm.createDirectory(at: mailDataDir, withIntermediateDirectories: true)

        let fixture = SyntheticMailStoreFixture(
            rootDir: rootDir,
            vDir: vDir,
            accountsDBPath: rootDir.appendingPathComponent("Accounts4.sqlite").path
        )

        // Create Accounts4.sqlite
        let accConn = try SQLiteConnection(readWritePath: fixture.accountsDBPath)
        try accConn.execute("""
            CREATE TABLE ZACCOUNT (
                Z_PK INTEGER PRIMARY KEY,
                ZIDENTIFIER TEXT,
                ZPARENTACCOUNT INTEGER,
                ZACCOUNTDESCRIPTION TEXT,
                ZUSERNAME TEXT
            );
        """)
        try accConn.execute("INSERT INTO ZACCOUNT VALUES (1, ?, NULL, 'Gmail', 'alice.secret@gmail.com');", bindings: [.text(fixture.gmailUUID)])
        try accConn.execute("INSERT INTO ZACCOUNT VALUES (2, ?, NULL, 'Work', 'bob.work@acme-corp.example');", bindings: [.text(fixture.ewsUUID)])
        try accConn.execute("INSERT INTO ZACCOUNT VALUES (3, ?, NULL, 'iCloud', 'carol.personal@icloud.com');", bindings: [.text(fixture.icloudUUID)])

        // Create Envelope Index
        let indexPath = mailDataDir.appendingPathComponent("Envelope Index").path
        let mailConn = try SQLiteConnection(readWritePath: indexPath)
        let tableDDLs = [
            """
            CREATE TABLE mailboxes (
                ROWID INTEGER PRIMARY KEY,
                url TEXT NOT NULL,
                total_count INTEGER NOT NULL DEFAULT 0,
                unread_count INTEGER NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE TABLE subjects (
                ROWID INTEGER PRIMARY KEY,
                subject TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE addresses (
                ROWID INTEGER PRIMARY KEY,
                address TEXT NOT NULL,
                comment TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE summaries (
                ROWID INTEGER PRIMARY KEY,
                summary TEXT NOT NULL
            );
            """,
            """
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
                conversation_id INTEGER NOT NULL DEFAULT 0,
                list_id_hash INTEGER,
                unsubscribe_type INTEGER,
                automated_conversation INTEGER DEFAULT 0
            );
            """,
            """
            CREATE TABLE labels (
                message_id INTEGER,
                mailbox_id INTEGER,
                PRIMARY KEY (message_id, mailbox_id)
            ) WITHOUT ROWID;
            """,
            """
            CREATE TABLE attachments (
                ROWID INTEGER PRIMARY KEY,
                message INTEGER NOT NULL,
                name TEXT
            );
            """
        ]
        for ddl in tableDDLs {
            try mailConn.execute(ddl)
        }

        // Mailboxes:
        // Gmail: 1=INBOX, 2=[Gmail]/All Mail, 3=[Gmail]/Trash, 4=[Gmail]/Sent Mail
        // EWS:   5=Inbox, 6=Archive, 7=Deleted Items, 8=Sent Items
        // iCloud: 9=INBOX, 10=Deleted Messages, 11=Sent Messages (no Archive)
        let mbEntries: [(Int64, String, Int64)] = [
            (1, "imap://\(fixture.gmailUUID)/INBOX", 2),
            (2, "imap://\(fixture.gmailUUID)/%5BGmail%5D/All%20Mail", 10),
            (3, "imap://\(fixture.gmailUUID)/%5BGmail%5D/Trash", 0),
            (4, "imap://\(fixture.gmailUUID)/%5BGmail%5D/Sent%20Mail", 5),
            (5, "ews://\(fixture.ewsUUID)/Inbox", 1),
            (6, "ews://\(fixture.ewsUUID)/Archive", 0),
            (7, "ews://\(fixture.ewsUUID)/Deleted%20Items", 0),
            (8, "ews://\(fixture.ewsUUID)/Sent%20Items", 0),
            (9, "imap://\(fixture.icloudUUID)/INBOX", 1),
            (10, "imap://\(fixture.icloudUUID)/Deleted%20Messages", 0),
            (11, "imap://\(fixture.icloudUUID)/Sent%20Messages", 0)
        ]
        for (id, url, count) in mbEntries {
            try mailConn.execute("INSERT INTO mailboxes (ROWID, url, total_count) VALUES (?, ?, ?);", bindings: [.int(id), .text(url), .int(count)])
        }

        // Subjects, addresses, summaries
        try mailConn.execute("INSERT INTO subjects VALUES (1, 'CONFIDENTIAL_SUBJECT_HTML');")
        try mailConn.execute("INSERT INTO subjects VALUES (2, 'CONFIDENTIAL_SUBJECT_THREAD');")
        try mailConn.execute("INSERT INTO subjects VALUES (3, 'CONFIDENTIAL_SUBJECT_PARTIAL');")
        try mailConn.execute("INSERT INTO subjects VALUES (4, 'CONFIDENTIAL_SUBJECT_MISSING');")

        try mailConn.execute("INSERT INTO addresses VALUES (1, 'promo@shop.example', 'Secret Sender Name');")
        try mailConn.execute("INSERT INTO addresses VALUES (2, 'partner@client.example', 'Partner');")
        try mailConn.execute("INSERT INTO addresses VALUES (3, 'alice.secret@gmail.com', 'Alice');")

        try mailConn.execute("INSERT INTO summaries VALUES (1, 'CONFIDENTIAL_BODY_SUMMARY_HTML');")
        try mailConn.execute("INSERT INTO summaries VALUES (2, 'CONFIDENTIAL_BODY_SUMMARY_THREAD');")
        try mailConn.execute("INSERT INTO summaries VALUES (3, 'CONFIDENTIAL_BODY_SUMMARY_PARTIAL');")
        try mailConn.execute("INSERT INTO summaries VALUES (4, 'Summary fallback body when emlx is missing');")

        // 4 inbox messages (newest to oldest):
        // 101: Gmail physical in [Gmail]/All Mail (mb=2) + labeled INBOX (mb=1), HTML only with <img> alt
        // 102: Gmail physical in [Gmail]/All Mail (mb=2) + labeled INBOX (mb=1), plain text, flagged, attachment, conv_id=777
        // 103: EWS physical in Inbox (mb=5), .partial.emlx with truncated byte count
        // 104: iCloud physical in INBOX (mb=9), missing .emlx file
        try mailConn.execute("INSERT INTO messages (ROWID, sender, subject, summary, date_sent, date_received, mailbox, read, flagged, deleted, conversation_id) VALUES (101, 1, 1, 1, 1760000400, 1760000400, 2, 0, 0, 0, 0);")
        try mailConn.execute("INSERT INTO messages (ROWID, sender, subject, summary, date_sent, date_received, mailbox, read, flagged, deleted, conversation_id) VALUES (102, 2, 2, 2, 1760000300, 1760000300, 2, 0, 1, 0, 777);")
        try mailConn.execute("INSERT INTO messages (ROWID, sender, subject, summary, date_sent, date_received, mailbox, read, flagged, deleted, conversation_id) VALUES (103, 2, 3, 3, 1760000200, 1760000200, 5, 0, 0, 0, 0);")
        try mailConn.execute("INSERT INTO messages (ROWID, sender, subject, summary, date_sent, date_received, mailbox, read, flagged, deleted, conversation_id) VALUES (104, 1, 4, 4, 1760000100, 1760000100, 9, 0, 0, 0, 0);")

        try mailConn.execute("INSERT INTO labels (message_id, mailbox_id) VALUES (101, 1);")
        try mailConn.execute("INSERT INTO labels (message_id, mailbox_id) VALUES (102, 1);")
        try mailConn.execute("INSERT INTO attachments (ROWID, message, name) VALUES (1, 102, 'agreement.pdf');")

        // Insert 14 prior messages in conversation 777 (13 older partner messages + 1 owner reply in [Gmail]/Sent Mail mb=4)
        // so we verify the 12-message chronological cap and sent_by_owner detection!
        for i in 1...13 {
            let rowId = Int64(200 + i)
            let ts = Int64(1760000000 + i * 10)
            try mailConn.execute("INSERT INTO summaries VALUES (?, ?);", bindings: [.int(rowId), .text("Prior partner message \(i)")])
            try mailConn.execute(
                "INSERT INTO messages (ROWID, sender, subject, summary, date_sent, date_received, mailbox, read, flagged, deleted, conversation_id) VALUES (?, 2, 2, ?, ?, ?, 2, 1, 0, 0, 777);",
                bindings: [.int(rowId), .int(rowId), .int(ts), .int(ts)]
            )
        }
        try mailConn.execute("INSERT INTO summaries VALUES (214, 'Owner final reply confirming terms');")
        try mailConn.execute(
            "INSERT INTO messages (ROWID, sender, subject, summary, date_sent, date_received, mailbox, read, flagged, deleted, conversation_id) VALUES (214, 3, 2, 214, 1760000250, 1760000250, 4, 1, 0, 0, 777);"
        )

        // Write .emlx files on disk matching V10 shard layout
        // Gmail [Gmail]/All Mail: V10/<gmailUUID>/[Gmail].mbox/All Mail.mbox/<mboxUUID>/Data/Messages/
        let gmailAllMailDataRoot = vDir
            .appendingPathComponent(fixture.gmailUUID, isDirectory: true)
            .appendingPathComponent("[Gmail].mbox", isDirectory: true)
            .appendingPathComponent("All Mail.mbox", isDirectory: true)
            .appendingPathComponent("MBOX-UUID", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)

        let ewsInboxDataRoot = vDir
            .appendingPathComponent(fixture.ewsUUID, isDirectory: true)
            .appendingPathComponent("Inbox.mbox", isDirectory: true)
            .appendingPathComponent("MBOX-UUID", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)

        try writeEmlx(
            dataRoot: gmailAllMailDataRoot,
            rowId: 101,
            isPartial: false,
            mime: """
            Message-ID: <msg-html@example.com>\r
            From: Secret Sender Name <promo@shop.example>\r
            To: alice.secret@gmail.com\r
            Subject: CONFIDENTIAL_SUBJECT_HTML\r
            Date: Thu, 12 Nov 2026 10:00:00 +0000\r
            Content-Type: text/html; charset="utf-8"\r
            \r
            <html><head><style>.x{display:none}</style></head><body><p>\u{200B}Short text</p><img src="https://cdn.example/banner.png" alt="Promo Banner"></body></html>\r
            """
        )

        try writeEmlx(
            dataRoot: gmailAllMailDataRoot,
            rowId: 102,
            isPartial: false,
            mime: """
            Message-ID: <msg-thread@example.com>\r
            From: Partner <partner@client.example>\r
            To: alice.secret@gmail.com\r
            Subject: CONFIDENTIAL_SUBJECT_THREAD\r
            Date: Thu, 12 Nov 2026 09:58:00 +0000\r
            Content-Type: text/plain; charset="utf-8"\r
            \r
            CONFIDENTIAL_BODY plain text message in thread.\r
            """
        )

        // Truncated .partial.emlx (declared byte count 5000 > actual bytes)
        let partialMime = """
        Message-ID: <msg-partial@example.com>\r
        From: Partner <partner@client.example>\r
        To: bob.work@acme-corp.example\r
        Subject: CONFIDENTIAL_SUBJECT_PARTIAL\r
        Date: Thu, 12 Nov 2026 09:55:00 +0000\r
        Content-Type: text/plain; charset="utf-8"\r
        \r
        Partial body prefix...\r
        """
        let partialDir = AppleMailAdapter.shardMessagesDirectory(dataRoot: ewsInboxDataRoot, rowId: 103)
        try fm.createDirectory(at: partialDir, withIntermediateDirectories: true)
        let partialURL = partialDir.appendingPathComponent("103.partial.emlx")
        var partialData = Data("5000\n".utf8)
        partialData.append(Data(partialMime.utf8))
        try partialData.write(to: partialURL)

        return fixture
    }

    private static func writeEmlx(dataRoot: URL, rowId: Int64, isPartial: Bool, mime: String) throws {
        let dir = AppleMailAdapter.shardMessagesDirectory(dataRoot: dataRoot, rowId: rowId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let filename = isPartial ? "\(rowId).partial.emlx" : "\(rowId).emlx"
        let url = dir.appendingPathComponent(filename)
        let mimeData = Data(mime.utf8)
        var emlx = Data("\(mimeData.count)\n".utf8)
        emlx.append(mimeData)
        emlx.append(Data("<?xml version=\"1.0\"?><plist><dict></dict></plist>".utf8))
        try emlx.write(to: url)
    }
}

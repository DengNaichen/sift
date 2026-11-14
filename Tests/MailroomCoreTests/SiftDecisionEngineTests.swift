import Foundation
import Testing
@testable import MailroomCore

@Suite("Sift Classification Engine, Cache, SecretStore & Gemini Client Tests")
struct SiftDecisionEngineTests {

    private let sampleEmail = SiftEmailMessage(
        from: "sender@example.com",
        subject: "Sample",
        body: "Complete sample message."
    )

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/MailroomCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }

    private func makeResponse(_ overrides: [String: Double] = [:], policy: SiftClassificationPolicy = .default) -> GeminiDecisionResponse {
        var answers: [String: GeminiDecisionAnswer] = [:]
        let defaultHighKeys: Set<String> = ["context_sufficient", "discardable", "topic_marketing"]
        for name in policy.questions.keys {
            let fallback = defaultHighKeys.contains(name) ? 0.98 : 0.01
            answers[name] = GeminiDecisionAnswer(type: "noul", noul: overrides[name] ?? fallback)
        }
        return GeminiDecisionResponse(
            answers: answers,
            usage: GeminiDecisionUsage(totalInputTokens: 100, totalOutputTokens: 0)
        )
    }

    private func decide(
        email: SiftEmailMessage? = nil,
        conversation: [SiftConversationMessage] = [],
        policy: SiftClassificationPolicy = .default,
        overrides: [String: Double] = [:]
    ) throws -> SiftDecision {
        try SiftDecisionEngine.resolveDecision(
            response: makeResponse(overrides, policy: policy),
            email: email ?? sampleEmail,
            policy: policy,
            conversation: conversation
        )
    }

    // MARK: - 1. Policy Bundle Resource & Type Contracts

    @Test("Loads bundled policy via Bundle.module and matches evals/email_classification_policy.json")
    func bundledPolicyParityAndDisplayMetadata() throws {
        let bundled = try SiftClassificationPolicy.loadFromBundleModule()
        let embedded = try SiftClassificationPolicy.loadEmbeddedFallback()
        let evalsURL = repoRootURL().appendingPathComponent("evals/email_classification_policy.json")
        let fromEvals = try SiftClassificationPolicy.load(from: evalsURL)

        #expect(bundled == fromEvals)
        #expect(embedded == fromEvals)
        #expect(SiftClassificationPolicy.default == fromEvals)
        #expect(bundled.version == "2026-11-15-sift-v1")
        #expect(bundled.topics.count == 7)
        #expect(bundled.questions.count == 14)

        #expect(SiftCategory.respond.badgeTitle == "需处理")
        #expect(SiftCategory.fyi.badgeTitle == "知悉留档")
        #expect(SiftCategory.security.badgeTitle == "安全验证")
        #expect(SiftCategory.news.badgeTitle == "资讯简报")
        #expect(SiftCategory.pitch.badgeTitle == "推销与荐岗")
        #expect(SiftCategory.social.badgeTitle == "社交动态")
        #expect(SiftCategory.marketing.badgeTitle == "促销广告")
        #expect(SiftCategory.review.badgeTitle == "待核实")

        #expect(!SiftCategory.fyi.allowsTrashPreference)
        #expect(!SiftCategory.security.allowsTrashPreference)
        #expect(SiftCategory.news.allowsTrashPreference)
        #expect(SiftCategory.pitch.allowsTrashPreference)
        #expect(SiftCategory.social.allowsTrashPreference)
        #expect(SiftCategory.marketing.allowsTrashPreference)

        #expect(SiftPreferences.balancedDefault.matchingPreset == .balancedDefault)
        #expect(SiftPreferences.zeroAutoTrash.matchingPreset == .zeroAutoTrash)
        #expect(SiftPreferences.jobHunting.matchingPreset == .jobHunting)
        #expect(SiftPreferences.jobHunting.pitch == .keep)
    }

    // MARK: - 2. All 16 Cases from evals/test_email_rules.py

    @Test("Superhuman 7 categories and 4 review guardrails match all 16 Python state-machine cases")
    func superhumanSevenCategoriesAndReviewGuardrails() throws {
        struct CaseSpec {
            let name: String
            let signals: [String: Double]
            let action: SiftAction
            let category: SiftCategory
            let review: SiftReviewReason?
        }

        let cases: [CaseSpec] = [
            CaseSpec(name: "marketing flyer", signals: [:], action: .trash, category: .marketing, review: nil),
            CaseSpec(name: "fyi paid receipt", signals: ["topic_finance": 0.99, "retain_record": 0.99, "discardable": 0.01], action: .archive, category: .fyi, review: nil),
            CaseSpec(name: "subscribed newsletter", signals: ["topic_newsletter": 0.99, "retain_record": 0.02, "discardable": 0.02], action: .archive, category: .news, review: nil),
            CaseSpec(name: "product changelog", signals: ["topic_newsletter": 0.55, "topic_product": 0.85, "discardable": 0.05], action: .archive, category: .news, review: nil),
            CaseSpec(name: "respond pending task", signals: ["needs_attention": 0.92, "discardable": 0.01], action: .keep, category: .respond, review: nil),
            CaseSpec(name: "security OTP notice", signals: ["security_event": 0.95, "topic_account_security": 0.99, "retain_record": 0.95, "discardable": 0.01], action: .keep, category: .security, review: nil),
            CaseSpec(name: "cold B2B pitch or job digest", signals: ["pitch_outreach": 0.95, "topic_marketing": 0.90, "discardable": 0.02], action: .trash, category: .pitch, review: nil),
            CaseSpec(name: "cold pitch even if discardable also high", signals: ["pitch_outreach": 0.93, "discardable": 0.92], action: .trash, category: .pitch, review: nil),
            CaseSpec(name: "social roundup default trash", signals: ["social_digest": 0.95, "topic_newsletter": 0.90, "discardable": 0.01], action: .trash, category: .social, review: nil),
            CaseSpec(name: "protected work blocks pitch trash", signals: ["pitch_outreach": 0.95, "topic_work": 0.80, "retain_record": 0.90, "discardable": 0.01], action: .review, category: .review, review: .protectionConflict),
            CaseSpec(name: "gray-zone attention", signals: ["needs_attention": 0.30, "discardable": 0.02], action: .review, category: .review, review: .uncertainAttention),
            CaseSpec(name: "gray-zone security", signals: ["security_event": 0.30, "discardable": 0.02], action: .review, category: .review, review: .uncertainAttention),
            CaseSpec(name: "record blocks marketing deletion", signals: ["retain_record": 0.60, "discardable": 0.95], action: .review, category: .review, review: .protectionConflict),
            CaseSpec(name: "possible work blocks deletion", signals: ["topic_work": 0.20, "discardable": 0.95], action: .review, category: .review, review: .protectionConflict),
            CaseSpec(name: "insufficient context", signals: ["context_sufficient": 0.50, "discardable": 0.02], action: .review, category: .review, review: .insufficientContext),
            CaseSpec(name: "gray-zone disposal", signals: ["discardable": 0.60], action: .review, category: .review, review: .uncertainDisposal),
        ]

        for spec in cases {
            let result = try decide(overrides: spec.signals)
            #expect(result.action == spec.action, "Action mismatch in \(spec.name)")
            #expect(result.category == spec.category, "Category mismatch in \(spec.name)")
            #expect(result.reviewReason == spec.review, "ReviewReason mismatch in \(spec.name)")
        }
    }

    // MARK: - 3. Preference Mode Switching & ALLOWED_PREFERENCES Validation

    @Test("Switches preferences without prompt changes and enforces ALLOWED_PREFERENCES")
    func preferenceModeSwitchingAndValidation() throws {
        var policy = SiftClassificationPolicy.default

        policy.preferences.pitch = .archive
        let pitchArchive = try decide(policy: policy, overrides: ["pitch_outreach": 0.95, "discardable": 0.01])
        #expect(pitchArchive.action == .archive)
        #expect(pitchArchive.category == .pitch)

        policy.preferences = .jobHunting
        let pitchKeep = try decide(policy: policy, overrides: ["pitch_outreach": 0.95, "discardable": 0.01])
        #expect(pitchKeep.action == .keep)
        #expect(pitchKeep.category == .pitch)

        var quietSecurity = SiftClassificationPolicy.default
        quietSecurity.preferences.security = .archive
        let secArchive = try decide(
            policy: quietSecurity,
            overrides: ["security_event": 0.95, "topic_account_security": 0.99, "retain_record": 0.95, "discardable": 0.01]
        )
        #expect(secArchive.action == .archive)
        #expect(secArchive.category == .security)

        var zeroTrashPolicy = SiftClassificationPolicy.default
        zeroTrashPolicy.preferences = .zeroAutoTrash
        let mktArchive = try decide(policy: zeroTrashPolicy, overrides: ["discardable": 0.96])
        #expect(mktArchive.action == .archive)
        #expect(mktArchive.category == .marketing)

        // Illegal fyi = trash and security = trash must fail validation
        var illegalFYI = SiftPreferences.balancedDefault
        #expect(illegalFYI.setAction(.trash, for: .fyi) == false)
        #expect(illegalFYI.fyi == .archive)
        #expect(illegalFYI.setAction(.trash, for: .security) == false)
        #expect(illegalFYI.security == .keep)

        illegalFYI.fyi = .trash
        #expect(throws: SiftPolicyError.invalidPreference(category: "fyi", value: "trash")) {
            try illegalFYI.validate()
        }
        #expect(illegalFYI.sanitized().fyi == .archive)

        var illegalSecPolicy = SiftClassificationPolicy.default
        illegalSecPolicy.preferences.security = .trash
        let encodedBad = try JSONEncoder().encode(illegalSecPolicy)
        #expect(throws: SiftPolicyError.invalidPreference(category: "security", value: "trash")) {
            _ = try SiftClassificationPolicy.decodeAndValidate(from: encodedBad)
        }
    }

    // MARK: - 4. Local Protection, Boilerplate Stub, Truncation, Preambles & Invalid Responses

    @Test("Enforces local flags, boilerplate stub, VIP/blocked senders, truncation, and reviewIncompleteMails toggle")
    func localProtectionBoilerplateTruncationAndSenders() throws {
        var withAttachment = sampleEmail
        withAttachment.hasAttachments = true
        let attRes = try decide(email: withAttachment, overrides: ["discardable": 0.01])
        #expect(attRes.action == .review)
        #expect(attRes.reviewReason == .insufficientContext)

        // When reviewIncompleteMails == false, only the incomplete flag check is skipped
        var skipIncompletePolicy = SiftClassificationPolicy.default
        skipIncompletePolicy.preferences.reviewIncompleteMails = false
        let attSkippedRes = try decide(email: withAttachment, policy: skipIncompletePolicy, overrides: ["discardable": 0.01, "topic_newsletter": 0.90])
        #expect(attSkippedRes.action == .archive)
        #expect(attSkippedRes.category == .news)
        // Context insufficient from model still triggers review even when reviewIncompleteMails == false
        let lowCtxRes = try decide(email: withAttachment, policy: skipIncompletePolicy, overrides: ["context_sufficient": 0.50, "discardable": 0.01])
        #expect(lowCtxRes.action == .review)
        #expect(lowCtxRes.reviewReason == .insufficientContext)

        var truncatedMail = sampleEmail
        truncatedMail.truncated = true
        #expect(try decide(email: truncatedMail, overrides: ["discardable": 0.01]).action == .review)

        var imageOnlyMail = sampleEmail
        imageOnlyMail.bodyIsImageOnly = true
        #expect(try decide(email: imageOnlyMail, overrides: ["discardable": 0.01]).action == .review)

        var blankMail = sampleEmail
        blankMail.body = " "
        #expect(try decide(email: blankMail).action == .review)

        var unsubStubMail = sampleEmail
        unsubStubMail.body = "如不想收到此类邮件,点击退订"
        #expect(try decide(email: unsubStubMail).action == .review)

        var starredMail = sampleEmail
        starredMail.starred = true
        #expect(try decide(email: starredMail).category == .respond)

        let ownerReply = [SiftConversationMessage(sentByOwner: true)]
        #expect(try decide(conversation: ownerReply, overrides: ["discardable": 0.98]).action == .review)
        #expect(try decide(conversation: ownerReply, overrides: ["discardable": 0.02]).category == .fyi)

        var customPolicy = SiftClassificationPolicy.default
        customPolicy.preferences.vipSenders = ["boss@company.com"]
        customPolicy.preferences.blockedSenders = ["spam@promo.example"]

        var bossMail = sampleEmail
        bossMail.from = "Boss <boss@company.com>"
        #expect(try decide(email: bossMail, policy: customPolicy, overrides: ["discardable": 0.02]).action == .keep)

        var spamMail = sampleEmail
        spamMail.from = "spam@promo.example"
        #expect(try decide(email: spamMail, policy: customPolicy, overrides: ["discardable": 0.40]).action == .trash)
        #expect(
            try decide(
                email: spamMail,
                policy: customPolicy,
                overrides: ["discardable": 0.40, "topic_finance": 0.50]
            ).action == .review
        )

        // 30,001-scalar body truncation -> preprocessing.truncated == true -> review
        var overlongMail = sampleEmail
        overlongMail.body = String(repeating: "x", count: 30_001)
        let req = try SiftDecisionEngine.buildRequest(email: overlongMail, policy: .default)
        let decodedPayload = try JSONDecoder().decode(SiftInputPayload.self, from: Data(req.input.utf8))
        #expect(decodedPayload.untrustedEmail.body.unicodeScalars.count == 30_000)
        #expect(decodedPayload.preprocessing.truncated == true)
        #expect(try decide(email: overlongMail, overrides: ["discardable": 0.02]).action == .review)

        // 13-message conversation clips to newest 12 and marks truncated == true
        let thirteenConv = (1...13).map { SiftConversationMessage(from: "u@example.com", subject: "S", date: "", body: "msg-\($0)") }
        let convPayload = SiftDecisionEngine.inputData(email: sampleEmail, conversation: thirteenConv)
        #expect(convPayload.untrustedConversation.count == 12)
        #expect(convPayload.untrustedConversation.first?.body == "msg-2")
        #expect(convPayload.untrustedConversation.last?.body == "msg-13")
        #expect(convPayload.preprocessing.truncated == true)
    }

    @Test("Strips invisible fillers, isolates untrusted email fields, attaches preambles, and rejects malformed answers")
    func requestIsolationPreamblesAndInvalidAnswerRejection() throws {
        var mail = sampleEmail
        mail.body = "Hello\u{034F}\u{2007}\u{00AD} world"
        mail.starred = true
        mail.sentByOwner = true

        let payload = try SiftDecisionEngine.buildRequest(email: mail, policy: .default)
        let serialized = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        #expect(!serialized.contains("\u{034F}"))
        #expect(!serialized.contains("starred"))
        #expect(!serialized.contains("sent_by_owner"))
        #expect(payload.input.contains("Hello world"))

        let policy = SiftClassificationPolicy.default
        for (name, q) in payload.questions {
            #expect(q.instructions.hasPrefix(policy.instructions))
            if SiftSignalKey(rawValue: name) != nil {
                #expect(q.instructions.contains(policy.signalInstructions))
            } else {
                #expect(!q.instructions.contains(policy.signalInstructions))
            }
        }

        // Invalid probabilities
        for bad in [-0.1, 1.1, Double.nan, Double.infinity] {
            #expect(throws: SiftPolicyError.invalidProbability("needs_attention")) {
                _ = try decide(overrides: ["needs_attention": bad])
            }
        }

        // Boolean noul in JSON must be rejected
        let boolJSON = #"{"answers":{"needs_attention":{"type":"noul","noul":true}}}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(GeminiDecisionResponse.self, from: Data(boolJSON.utf8))
        }

        // Missing answer key
        var missingAns = makeResponse()
        missingAns.answers.removeValue(forKey: "context_sufficient")
        #expect(throws: SiftPolicyError.missingAnswer("context_sufficient")) {
            _ = try SiftDecisionEngine.resolveDecision(response: missingAns, email: sampleEmail)
        }

        // Wrong question type
        var wrongType = makeResponse()
        wrongType.answers["needs_attention"] = GeminiDecisionAnswer(type: "choice", noul: 0.99)
        #expect(throws: SiftPolicyError.invalidAnswerType("needs_attention")) {
            _ = try SiftDecisionEngine.resolveDecision(response: wrongType, email: sampleEmail)
        }
    }

    // MARK: - 5. ClassificationOutcome Mapping & Confidence Gate

    @Test("Maps SiftDecision to ClassificationOutcome with verbatim evidence and optional raised confidenceGate")
    func classificationOutcomeMappingAndConfidenceGate() throws {
        let account = MailAccount(id: "work", label: "Work", address: "me@company.com")

        let contractContent = MailContent(
            id: "m-contract",
            from: Sender(name: "Legal", address: "legal@partner.com"),
            account: account,
            subject: "MSA Agreement v2",
            receivedAt: Date(),
            plainText: "您好，\n请于本周五前确认合同条款并完成签署。",
            attachments: [Attachment(name: "msa.pdf", size: "420 KB", kind: .pdf)]
        )
        let respondDecision = try decide(overrides: ["needs_attention": 0.94, "discardable": 0.01])
        if case .triage(let meta) = respondDecision.toClassificationOutcome(for: contractContent) {
            #expect(meta.kind == .contract)
            #expect(meta.badge == "重要附件")
            #expect(meta.intent == "需处理")
            #expect(meta.evidence != nil)
            #expect(contractContent.plainText.contains(meta.evidence!))
        } else {
            Issue.record("Expected contract triage")
        }

        // Pitch trash with confidence ~0.88 stays autoHandled at default gate (0.90), but routes to uncertain when gate raised to 0.95
        let pitchDecision = try decide(overrides: ["pitch_outreach": 0.88, "context_sufficient": 0.95, "discardable": 0.01])
        #expect(pitchDecision.action == .trash)
        #expect(pitchDecision.confidence == 0.88)

        let genericContent = MailContent(
            id: "m-pitch",
            from: Sender(name: "Outreach", address: "sales@agency.example"),
            account: account,
            subject: "Scale your SEO",
            receivedAt: Date(),
            plainText: "Hi there, please reply if you want more leads.",
            attachments: []
        )
        if case .autoHandled(let disp, let cat, _) = pitchDecision.toClassificationOutcome(for: genericContent, confidenceGate: 0.90) {
            #expect(disp == .trashed)
            #expect(cat == "推销与荐岗")
        } else {
            Issue.record("Expected default confidenceGate=0.90 to preserve email_rules.py trash outcome")
        }

        if case .triage(let gatedMeta) = pitchDecision.toClassificationOutcome(for: genericContent, confidenceGate: 0.95) {
            #expect(gatedMeta.kind == .uncertain)
            #expect(gatedMeta.badge == "待你拍板")
        } else {
            Issue.record("Expected raised confidenceGate=0.95 to intercept 0.88 support into triage")
        }
    }

    // MARK: - 6. InMemorySecretStore & DecisionSignalCache

    @Test("InMemorySecretStore and SQLite DecisionSignalCache support hit, invalidation, byte size, and clear")
    func secretStoreAndDecisionSignalCache() throws {
        let store = InMemorySecretStore()
        #expect(try store.readSecret(key: SiftSecretKey.classifierAPIKey) == nil)
        try store.writeSecret(key: SiftSecretKey.classifierAPIKey, value: "test-key-123")
        #expect(try store.readSecret(key: SiftSecretKey.classifierAPIKey) == "test-key-123")
        try store.writeSecret(key: SiftSecretKey.classifierAPIKey, value: "")
        #expect(try store.readSecret(key: SiftSecretKey.classifierAPIKey) == nil)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-signal-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbPath = tempDir.appendingPathComponent("classifier_decisions_v1.sqlite").path
        let cache = try DecisionSignalCache(dbPath: dbPath)
        #expect(cache.entryCount() == 0)

        let resp = makeResponse(["pitch_outreach": 0.94, "discardable": 0.02])
        let sha1 = DecisionSignalCache.computeContentSHA256(for: "{\"body\":\"v1\"}")
        let sha2 = DecisionSignalCache.computeContentSHA256(for: "{\"body\":\"v2\"}")
        try cache.put(messageId: "msg-1", contentSHA256: sha1, policyVersion: "2026-11-15-sift-v1", response: resp)

        #expect(cache.entryCount() == 1)
        #expect(cache.databaseByteSize() > 0)
        #expect(cache.get(messageId: "msg-1", contentSHA256: sha1, policyVersion: "2026-11-15-sift-v1") == GeminiDecisionResponse(answers: resp.answers))
        #expect(cache.get(messageId: "msg-1", contentSHA256: sha2, policyVersion: "2026-11-15-sift-v1") == nil)
        #expect(cache.get(messageId: "msg-1", contentSHA256: sha1, policyVersion: "other-version") == nil)

        try cache.clear()
        #expect(cache.entryCount() == 0)
    }

    // MARK: - 7. GeminiDecisionsClient, Retry, Redaction & HybridMailClassifier Live Reconfiguration

    @Test("GeminiDecisionsClient normalizes endpoints, retries 429/503, redacts API keys, and HybridMailClassifier re-evaluates preferences with zero extra HTTP calls")
    func geminiClientMockProtocolAndHybridClassifier() async throws {
        let baseURL = try GeminiDecisionsClient.resolveDecisionsURL(from: "https://generativelanguage.googleapis.com/v1beta")
        let fullURL = try GeminiDecisionsClient.resolveDecisionsURL(from: "https://generativelanguage.googleapis.com/v1beta/decisions/")
        #expect(baseURL.absoluteString == "https://generativelanguage.googleapis.com/v1beta/decisions")
        #expect(fullURL == baseURL)

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockGeminiURLProtocol.self]
        let session = URLSession(configuration: sessionConfig)

        let sleepCalls = LockedBox<Int>(0)
        let client = GeminiDecisionsClient(
            session: session,
            maxRetries: 2,
            maxRetryDelaySeconds: 2.0,
            sleep: { _ in
                sleepCalls.withValue { $0 += 1 }
            }
        )

        let secret = "AIzaSyFAKE_UNIT_TEST_KEY_999"

        // 7a. Connection probe succeeds after transient 429 retry
        let probeAttempt = LockedBox<Int>(0)
        MockGeminiURLProtocol.setHandler { request in
            let current = probeAttempt.withValue { val -> Int in
                val += 1
                return val
            }
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == secret)
            #expect(request.url?.path == "/v1beta/decisions")
            if current == 1 {
                let errData = Data(#"{"error":{"message":"Quota exceeded, please retry in 0.2s \#(secret)"}}"#.utf8)
                let http = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
                return (http, errData)
            }
            let okData = Data(#"{"answers":{"ping":{"type":"noul","noul":0.97}}}"#.utf8)
            let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (http, okData)
        }

        let latencyMs = try await client.testConnection(
            endpoint: "https://generativelanguage.googleapis.com/v1beta",
            model: "gemini-decision-1",
            apiKey: secret
        )
        #expect(latencyMs >= 1.0)
        #expect(probeAttempt.value == 2)
        #expect(sleepCalls.value == 1)

        // 7b. Non-retryable 401/400 redacts API key from error description
        MockGeminiURLProtocol.setHandler { request in
            let errData = Data(#"{"error":{"message":"Invalid key \#(secret) rejected"}}"#.utf8)
            let http = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (http, errData)
        }
        do {
            _ = try await client.testConnection(apiKey: secret)
            Issue.record("Expected 400 HTTP error")
        } catch {
            let desc = error.localizedDescription
            #expect(!desc.contains(secret))
            #expect(desc.contains("[REDACTED]"))
        }

        // 7c. HybridMailClassifier caches signals and re-evaluates jobHunting preset in memory with 0 extra HTTP requests
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-hybrid-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = try DecisionSignalCache(dbPath: tempDir.appendingPathComponent("decisions.sqlite").path)
        let secretStore = InMemorySecretStore(initialSecrets: [SiftSecretKey.classifierAPIKey: secret])

        let pitchAPIResponse = makeResponse(["pitch_outreach": 0.96, "discardable": 0.02, "topic_marketing": 0.90])
        let pitchResponseData = try JSONEncoder().encode(pitchAPIResponse)
        let hybridAPICount = LockedBox<Int>(0)

        MockGeminiURLProtocol.setHandler { request in
            hybridAPICount.withValue { $0 += 1 }
            let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (http, pitchResponseData)
        }

        let hybrid = HybridMailClassifier(
            configuration: SiftClassifierConfiguration(
                engineMode: .hybrid,
                preferences: .balancedDefault
            ),
            client: client,
            signalCache: cache,
            secretStore: secretStore
        )

        let pitchMail = MailContent(
            id: "pitch-msg-01@example.com",
            from: Sender(name: "Jobs Digest", address: "alerts@jobboard.example"),
            account: MailAccount(id: "personal", label: "Personal", address: "me@example.com"),
            subject: "Top 10 engineering jobs for you this week",
            receivedAt: Date(timeIntervalSince1970: 1_760_000_000),
            plainText: "Here are 10 open software roles matching your profile. Click to view listings.",
            attachments: []
        )
        let signals = RawMailSignals(content: pitchMail, hasListUnsubscribe: true)

        let firstOutcome = await hybrid.classifyAsync(signals)
        #expect(hybridAPICount.value == 1)
        #expect(firstOutcome == .autoHandled(disposition: .trashed, category: "推销与荐岗", probability: 0.96))

        // Switch user preset to jobHunting (pitch = .keep): must flip to .triage WITHOUT a second HTTP call!
        hybrid.updatePreferences(.jobHunting)
        let secondOutcome = await hybrid.classifyAsync(signals)
        #expect(hybridAPICount.value == 1)
        if case .triage(let meta) = secondOutcome {
            #expect(meta.badge == "推销与荐岗")
            #expect(meta.intent == "偏好保留")
        } else {
            Issue.record("Expected jobHunting preset to keep pitch email in triage")
        }
    }

    // MARK: - 8. 37 / 37 Real open-inbox-v1 Parity with Python

    @Test("Achieves 37/37 exact action, category, reviewReason, topics, and confidence parity on open-inbox-v1 saved API responses")
    func openInboxV1ExactPythonParity() throws {
        let root = repoRootURL()
        let datasetURL = root.appendingPathComponent("evals/datasets/open-inbox-v1/emails.json")
        guard FileManager.default.fileExists(atPath: datasetURL.path) else {
            return
        }

        let candidateRuns = [
            "evals/runs/open-inbox-v1-run02",
            "evals/runs/open-inbox-v1-run03",
            "evals/runs/open-inbox-v1-run01",
        ]
        var selectedResultsURL: URL?
        let bundledPolicy = SiftClassificationPolicy.default

        for rel in candidateRuns {
            let dir = root.appendingPathComponent(rel, isDirectory: true)
            let resultsURL = dir.appendingPathComponent("results.json")
            let policyURL = dir.appendingPathComponent("policy.json")
            guard FileManager.default.fileExists(atPath: resultsURL.path) else { continue }
            if let runPolicy = try? SiftClassificationPolicy.load(from: policyURL),
               runPolicy == bundledPolicy {
                selectedResultsURL = resultsURL
                break
            }
        }

        guard let resultsURL = selectedResultsURL else {
            return
        }

        struct DatasetDoc: Decodable {
            struct Sample: Decodable {
                let id: String
                let email: SiftEmailMessage
                let conversation: [SiftConversationMessage]?
            }
            let samples: [Sample]
        }

        struct SavedRow: Decodable {
            let id: String
            let response: GeminiDecisionResponse
            let decision: SiftDecision
        }

        let dataset = try JSONDecoder().decode(DatasetDoc.self, from: Data(contentsOf: datasetURL))
        let savedRows = try JSONDecoder().decode([SavedRow].self, from: Data(contentsOf: resultsURL))

        #expect(dataset.samples.count == 37)
        #expect(savedRows.count == 37)

        let sampleById = Dictionary(uniqueKeysWithValues: dataset.samples.map { ($0.id, $0) })

        for row in savedRows {
            let sample = try #require(sampleById[row.id])
            let swiftDecision = try SiftDecisionEngine.resolveDecision(
                response: row.response,
                email: sample.email,
                policy: bundledPolicy,
                conversation: sample.conversation ?? []
            )

            #expect(swiftDecision.action == row.decision.action, "Action mismatch on \(row.id)")
            #expect(swiftDecision.category == row.decision.category, "Category mismatch on \(row.id)")
            #expect(swiftDecision.reviewReason == row.decision.reviewReason, "ReviewReason mismatch on \(row.id)")
            #expect(swiftDecision.suggestedAction == row.decision.suggestedAction, "SuggestedAction mismatch on \(row.id)")
            #expect(swiftDecision.suggestedCategory == row.decision.suggestedCategory, "SuggestedCategory mismatch on \(row.id)")
            #expect(swiftDecision.protectedFromTrash == row.decision.protectedFromTrash, "Protected mismatch on \(row.id)")
            #expect(swiftDecision.topics == row.decision.topics, "Topics mismatch on \(row.id)")
            #expect(abs(swiftDecision.confidence - row.decision.confidence) <= 1e-6, "Confidence mismatch on \(row.id)")
        }
    }
}

// MARK: - Test Helpers

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    init(_ initial: T) {
        self._value = initial
    }

    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    @discardableResult
    func withValue<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&_value)
    }
}

private final class MockGeminiURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private nonisolated(unsafe) static var handler: Handler?

    static func setHandler(_ newHandler: @escaping Handler) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let activeHandler = Self.handler
        Self.lock.unlock()

        guard let activeHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try activeHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

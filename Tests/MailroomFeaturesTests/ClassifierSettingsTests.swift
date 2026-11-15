import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MailroomCore
@testable import MailroomFeatures

private actor ClassifierBackedMockLiveAdapter: MailAdapter {
    nonisolated let sourceLabel: String = "Mock Live Mail"
    nonisolated let supportsDemoControls: Bool = false

    private let classifier: HybridMailClassifier
    private let sampleSignals: RawMailSignals
    private(set) var fetchCount: Int = 0

    init(classifier: HybridMailClassifier, sampleSignals: RawMailSignals) {
        self.classifier = classifier
        self.sampleSignals = sampleSignals
    }

    func fetchDeck() async throws -> DeckSnapshot {
        fetchCount += 1
        let outcome = await classifier.classifyAsync(sampleSignals)
        switch outcome {
        case .triage(let meta):
            return DeckSnapshot(
                queue: [MailItem(content: sampleSignals.content, meta: meta)],
                handled: []
            )
        case .autoHandled(let disposition, let category, let probability):
            return DeckSnapshot(
                queue: [],
                handled: [
                    HandledItem(
                        content: sampleSignals.content,
                        disposition: disposition,
                        category: category,
                        probability: probability,
                        handledAt: sampleSignals.content.receivedAt,
                        manual: false
                    )
                ]
            )
        }
    }

    func archive(id: MessageId) async throws {}
    func flagImportant(id: MessageId) async throws {}
    func moveToTrash(id: MessageId, reason: TrashReason) async throws {}
    func restore(id: MessageId) async throws {}
    func rescue(id: MessageId) async throws -> MailItem {
        MailItem(
            content: sampleSignals.content,
            meta: DecisionMeta(kind: .rescued, badge: "拉回", confidence: 0.95)
        )
    }
    func openInNativeMail(id: MessageId) async throws -> String { "message://mock" }
}

@MainActor
@Suite("Classifier & Superhuman Triage Settings", .serialized)
struct ClassifierSettingsTests {
    @Test("Superhuman 6-category matrix, 3 presets, and security/fyi non-trashable enforcement")
    func presetsAndNonTrashableEnforcement() async {
        let defaults = makeIsolatedDefaults()
        let secretStore = InMemorySecretStore()
        let env = makeTestEnvironment(defaults: defaults, secretStore: secretStore)
        let app = AppModel(environment: env)
        await waitUntil { app.deck.state.phase == .ready }

        let form = app.settingsForm

        // 1. 默认状态对齐 Superhuman 6 类可配矩阵与「平衡默认」预设
        #expect(form.triageMatrix.map(\.category) == [.security, .fyi, .news, .pitch, .social, .marketing])
        #expect(form.triageMatrix.map(\.title) == [
            "安全验证通知",
            "知悉留档记录",
            "资讯简报 Newsletter",
            "陌生推销与荐岗",
            "社交与社区动态",
            "商业促销与广告"
        ])
        #expect(form.activePreset == .balancedDefault)
        #expect(form.siftPreferences == .balancedDefault)

        // 2. security 与 fyi 仅允许 [.inbox, .archive]，严禁设为 .trash
        #expect(form.triageMatrix[0].allowedChoices == [.inbox, .archive])
        #expect(form.triageMatrix[1].allowedChoices == [.inbox, .archive])
        #expect(form.triageMatrix[2].allowedChoices == [.inbox, .archive, .trash])

        #expect(form.setDisposition(.trash, for: .security) == false)
        #expect(form.setDisposition(.trash, for: .fyi) == false)
        #expect(form.disposition(for: .security) == .inbox)
        #expect(form.disposition(for: .fyi) == .archive)

        // 直接写行属性同样拦截非法 .trash
        form.triageMatrix[0].choice = .trash
        form.triageMatrix[1].choice = .trash
        #expect(form.triageMatrix[0].choice == .inbox)
        #expect(form.triageMatrix[1].choice == .archive)

        // 合法修改 security -> .archive 与 fyi -> .inbox 正常生效
        #expect(form.setDisposition(.archive, for: .security) == true)
        #expect(form.setDisposition(.inbox, for: .fyi) == true)
        #expect(form.siftPreferences.security == .archive)
        #expect(form.siftPreferences.fyi == .keep)
        #expect(form.activePreset == nil)

        // 3. 切换「零自动删信」与「求职优先」预设，同时保留 VIP / 屏蔽列表与残缺核实开关
        form.reviewIncompleteMails = false
        form.protectedDraft = "partner.org"
        form.submitProtectedDraft()
        form.blockedDraft = "noisy-ads.example"
        form.submitBlockedDraft()

        form.applyPreset(.zeroAutoTrash)
        #expect(form.activePreset == .zeroAutoTrash)
        #expect(form.siftPreferences.security == .keep)
        #expect(form.siftPreferences.fyi == .archive)
        #expect(form.siftPreferences.news == .archive)
        #expect(form.siftPreferences.pitch == .archive)
        #expect(form.siftPreferences.social == .archive)
        #expect(form.siftPreferences.marketing == .archive)
        #expect(form.reviewIncompleteMails == false)
        #expect(form.vipSenders == ["partner.org"])
        #expect(form.blockedSenders == ["noisy-ads.example"])

        form.applyPreset(.jobHunting)
        #expect(form.activePreset == .jobHunting)
        #expect(form.siftPreferences.pitch == .keep)
        #expect(form.siftPreferences.marketing == .trash)
        #expect(form.siftPreferences.social == .trash)

        form.applyPreset(.balancedDefault)
        #expect(form.activePreset == .balancedDefault)

        // 4. 即便外部篡改 UserDefaults JSON 将 security/fyi 写成 trash，重新加载也自动收敛为合法偏好
        let tamperedJSON = Data(#"{"fyi":"trash","security":"trash","news":"archive","pitch":"trash","social":"trash","marketing":"trash"}"#.utf8)
        defaults.set(tamperedJSON, forKey: SettingsFormState.StorageKey.triagePreferences)
        let reloaded = AppModel(environment: makeTestEnvironment(defaults: defaults, secretStore: secretStore))
        #expect(reloaded.settingsForm.siftPreferences.security == .keep)
        #expect(reloaded.settingsForm.siftPreferences.fyi == .archive)
    }

    @Test("Settings persist across AppModel re-init while API key stays strictly in SecretStore and never enters UserDefaults")
    func persistenceAndSecretIsolation() async throws {
        let defaults = makeIsolatedDefaults()
        let secretStore = InMemorySecretStore()
        let fakeKey = "test-only-fake-key-do-not-persist-in-defaults-918273"

        do {
            let app1 = AppModel(environment: makeTestEnvironment(defaults: defaults, secretStore: secretStore))
            await waitUntil { app1.deck.state.phase == .ready }
            let s = app1.settingsForm

            // 验证 Gemini 默认模型与端点
            #expect(LLMProviderChoice.gemini.defaultModel == "gemini-decision-1")
            #expect(LLMProviderChoice.gemini.defaultEndpoint == "https://generativelanguage.googleapis.com/v1beta")
            #expect(s.provider == .gemini)
            #expect(s.modelName == "gemini-decision-1")
            #expect(s.endpoint == "https://generativelanguage.googleapis.com/v1beta")

            s.applyPreset(.jobHunting)
            s.reviewIncompleteMails = false
            s.protectedDraft = "vip@investor.vc"
            s.submitProtectedDraft()
            s.blockedDraft = "cold@outreach.biz"
            s.submitBlockedDraft()

            s.apiKey = fakeKey
            s.confidenceThreshold = 95
            s.payloadScope = .headerOnly
            s.cacheDecisions = false
            s.syncLimit = 200
            s.aliasDraft = "me@alumni.edu"
            s.submitAliasDraft()
            s.remoteImageChoice = .alwaysLoad
        }

        // 断言 SecretStore 持有密钥，而 UserDefaults 的任何键或值中绝不包含密钥明文
        #expect(try secretStore.readSecret(key: SiftSecretKey.classifierAPIKey) == fakeKey)
        #expect(try secretStore.readSecret(key: SiftSecretKey.geminiAPIKey) == fakeKey)

        for (key, rawVal) in defaults.dictionaryRepresentation() {
            #expect(!key.contains(fakeKey))
            if let str = rawVal as? String {
                #expect(!str.contains(fakeKey))
            } else if let data = rawVal as? Data, let decoded = String(data: data, encoding: .utf8) {
                #expect(!decoded.contains(fakeKey))
            } else {
                #expect(!String(describing: rawVal).contains(fakeKey))
            }
        }

        // 重新构造 AppModel，验证所有设置与启动时注入的分类器配置完整恢复
        var capturedInitialConfig: SiftClassifierConfiguration?
        var env2 = makeTestEnvironment(defaults: defaults, secretStore: secretStore)
        env2.updateClassifierConfiguration = { cfg in
            capturedInitialConfig = cfg
        }
        let app2 = AppModel(environment: env2)
        await waitUntil { app2.deck.state.phase == .ready }

        let s2 = app2.settingsForm
        #expect(s2.activePreset == .jobHunting)
        #expect(s2.siftPreferences.pitch == .keep)
        #expect(s2.reviewIncompleteMails == false)
        #expect(s2.vipSenders == ["vip@investor.vc"])
        #expect(s2.blockedSenders == ["cold@outreach.biz"])
        #expect(s2.apiKey == fakeKey)
        #expect(s2.confidenceThreshold == 95)
        #expect(s2.payloadScope == .headerOnly)
        #expect(s2.cacheDecisions == false)
        #expect(s2.syncLimit == 200)
        #expect(s2.customAliases == ["me@alumni.edu"])
        #expect(s2.remoteImageChoice == .alwaysLoad)

        let initCfg = try #require(capturedInitialConfig)
        #expect(initCfg.model == "gemini-decision-1")
        #expect(initCfg.confidenceGate == 0.95)
        #expect(initCfg.payloadScope == .headerOnly)
        #expect(initCfg.cacheDecisions == false)
        #expect(initCfg.preferences.pitch == .keep)
        #expect(initCfg.apiKeyOverride == fakeKey)

        // 切换服务商时隔离不同服务商的密钥，切回 Gemini 时恢复原密钥，清空时删除
        s2.selectProvider(.openai)
        #expect(s2.apiKey == "")
        #expect(s2.modelName == "gpt-4o-mini")
        s2.selectProvider(.gemini)
        #expect(s2.apiKey == fakeKey)
        #expect(s2.modelName == "gemini-decision-1")

        s2.apiKey = ""
        #expect(try secretStore.readSecret(key: SiftSecretKey.classifierAPIKey) == nil)
        #expect(try secretStore.readSecret(key: SiftSecretKey.geminiAPIKey) == nil)
    }

    @Test("Connection test callback displays latency on success and redacts API key on error")
    func connectionTestWiringAndRedaction() async {
        let defaults = makeIsolatedDefaults()
        let secretStore = InMemorySecretStore()
        let probeSecret = "fake-probe-secret-776655"

        struct EchoingProbeError: LocalizedError {
            let message: String
            var errorDescription: String? { message }
        }

        final class ProbeState: @unchecked Sendable {
            var calls: [(endpoint: String, model: String, apiKey: String)] = []
            var shouldFail = false
        }
        let probeState = ProbeState()

        var env = makeTestEnvironment(defaults: defaults, secretStore: secretStore)
        env.testAIConnection = { endpoint, model, apiKey in
            probeState.calls.append((endpoint, model, apiKey))
            if probeState.shouldFail {
                throw EchoingProbeError(message: "Invalid credential \(apiKey) at gateway")
            }
            return 184.6
        }

        let app = AppModel(environment: env)
        await waitUntil { app.deck.state.phase == .ready }
        let s = app.settingsForm

        s.apiKey = probeSecret
        await s.testConnection()

        #expect(probeState.calls.count == 1)
        #expect(probeState.calls.first?.endpoint == "https://generativelanguage.googleapis.com/v1beta")
        #expect(probeState.calls.first?.model == "gemini-decision-1")
        #expect(probeState.calls.first?.apiKey == probeSecret)
        #expect(s.connectionTestStatus == "✓ 185ms")
        #expect(s.connectionTestError == nil)

        // 失败分支：必须脱敏任何回显的密钥文本
        probeState.shouldFail = true
        await s.testConnection()
        #expect(s.connectionTestStatus == "✕ 失败")
        #expect(s.connectionTestError != nil)
        #expect(s.connectionTestError?.contains("[REDACTED]") == true)
        #expect(s.connectionTestError?.contains(probeSecret) == false)

        // 修改模型配置后自动清除旧测试状态
        s.modelName = "gemini-decision-1-exp"
        #expect(s.connectionTestStatus == nil)
        #expect(s.connectionTestError == nil)
    }

    @Test("Live classifier configuration propagation re-evaluates cached signals instantly and Diagnostics rebuild clears cache")
    func liveClassifierPropagationAndCacheRebuild() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-ui-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cachePath = tempDir.appendingPathComponent("decisions.sqlite").path
        let signalCache = try DecisionSignalCache(dbPath: cachePath)
        let secretStore = InMemorySecretStore()
        let defaults = makeIsolatedDefaults()

        let classifier = HybridMailClassifier(
            configuration: SiftClassifierConfiguration(
                engineMode: .hybrid,
                provider: .gemini,
                payloadScope: .excerpt1500,
                cacheDecisions: true,
                preferences: .balancedDefault
            ),
            signalCache: signalCache,
            secretStore: secretStore
        )

        let pitchMail = MailContent(
            id: MessageId("pitch-job-001@recruiter.io"),
            from: Sender(name: "Tech Recruiter", address: "talent@recruiter.io"),
            account: MockSeedData.workAccount,
            subject: "Recommended jobs for you: Staff Systems Engineer",
            receivedAt: fixtureNow,
            plainText: "Hi, check out our open roles this week. Unsubscribe anytime.",
            attachments: []
        )
        let rawSignals = RawMailSignals(content: pitchMail, hasListUnsubscribe: true)

        // 预先写入一笔 pitch_outreach 正交信号到 SQLite 缓存（验证切换偏好零网络即时重算）
        let (siftEmail, siftConv) = SiftDecisionEngine.makeInputs(from: rawSignals, payloadScope: .excerpt1500)
        let builtReq = try SiftDecisionEngine.buildRequest(
            email: siftEmail,
            policy: .default,
            model: GeminiDecisionsClient.defaultModel,
            conversation: siftConv
        )
        let sha = DecisionSignalCache.computeContentSHA256(for: builtReq.input)
        var answers: [String: GeminiDecisionAnswer] = [:]
        for key in SiftClassificationPolicy.default.questions.keys {
            let score: Double
            switch key {
            case "context_sufficient": score = 0.99
            case "pitch_outreach": score = 0.97
            case "topic_marketing": score = 0.80
            default: score = 0.02
            }
            answers[key] = GeminiDecisionAnswer(noul: score)
        }
        try signalCache.put(
            messageId: pitchMail.id.rawValue,
            contentSHA256: sha,
            policyVersion: SiftClassificationPolicy.default.version,
            response: GeminiDecisionResponse(answers: answers)
        )
        #expect(signalCache.entryCount() == 1)

        let liveAdapter = ClassifierBackedMockLiveAdapter(classifier: classifier, sampleSignals: rawSignals)
        var env = makeTestEnvironment(
            defaults: defaults,
            secretStore: secretStore,
            access: .ready(mailDir: tempDir.path)
        )
        env.makeLiveAdapter = { liveAdapter }
        env.updateClassifierConfiguration = { config in
            classifier.updateConfiguration(config)
        }
        env.rebuildClassifierCache = {
            try classifier.clearCache()
        }
        env.classifierCacheSizeText = {
            signalCache.formattedByteSize()
        }

        let app = AppModel(environment: env)
        await waitUntil { app.deck.state.phase == .ready }

        // 初始「平衡默认」下 pitch -> trash，邮件自动进入废纸篓（handled）
        #expect(app.deck.sourceMode == .appleMail)
        #expect(app.deck.state.queue.isEmpty)
        #expect(app.deck.state.handled.count == 1)
        #expect(app.deck.state.handled.first?.disposition == .trashed)
        #expect(app.deck.state.handled.first?.category == SiftCategory.pitch.badgeTitle)

        // 切换到「求职优先」（pitch -> keep），无需任何网络请求即可实时重同步回待处理收件箱！
        app.settingsForm.applyPreset(.jobHunting)
        await waitUntil { app.deck.state.queue.count == 1 }
        #expect(app.deck.state.handled.isEmpty)
        #expect(app.deck.state.queue.first?.id == pitchMail.id)
        #expect(app.deck.state.queue.first?.meta.badge == SiftCategory.pitch.badgeTitle)
        #expect(await liveAdapter.fetchCount >= 2)

        // 打开诊断页并执行「确认重建缓存」，验证真实清空 DecisionSignalCache
        app.perform(.openSettings(.diagnostics))
        #expect(signalCache.entryCount() == 1)
        await app.settingsForm.rebuildCache()
        #expect(signalCache.entryCount() == 0)
        #expect(app.settingsForm.transientBannerText != nil)

        // 验证三个升级后的设置页在 NSHostingView 中渲染无异常
        for section in [SettingsSection.triage, .ai, .diagnostics] {
            app.perform(.openSettings(section))
            let host = NSHostingView(
                rootView: RootThemeHostView(model: RootViewModel(app: app))
                    .frame(width: 1220, height: 780)
            )
            host.frame = NSRect(x: 0, y: 0, width: 1220, height: 780)
            host.layoutSubtreeIfNeeded()
            #expect(host.bounds.size == CGSize(width: 1220, height: 780))
        }
    }
}

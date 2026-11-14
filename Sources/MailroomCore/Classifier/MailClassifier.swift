import Foundation

public typealias ClassificationInput = RawMailSignals

public struct RawMailSignals: Sendable {
    public let content: MailContent
    public let hasListUnsubscribe: Bool
    public let hasListId: Bool
    public let isReply: Bool
    public let isAutoSubmitted: Bool
    public let sqlAutomatedFlag: Bool
    public let conversation: ConversationContext?
    public let sentByOwner: Bool
    public let isPartial: Bool
    public let isTruncated: Bool
    public let unloadedHtmlImages: Int
    public let bodyIsImageOnly: Bool
    public let isFlagged: Bool
    public let isBoilerplateStub: Bool

    public init(
        content: MailContent,
        hasListUnsubscribe: Bool = false,
        hasListId: Bool = false,
        isReply: Bool = false,
        isAutoSubmitted: Bool = false,
        sqlAutomatedFlag: Bool = false,
        conversation: ConversationContext? = nil,
        sentByOwner: Bool = false,
        isPartial: Bool = false,
        isTruncated: Bool = false,
        unloadedHtmlImages: Int = 0,
        bodyIsImageOnly: Bool = false,
        isFlagged: Bool = false,
        isBoilerplateStub: Bool = false
    ) {
        self.content = content
        self.hasListUnsubscribe = hasListUnsubscribe
        self.hasListId = hasListId
        self.isReply = isReply
        self.isAutoSubmitted = isAutoSubmitted
        self.sqlAutomatedFlag = sqlAutomatedFlag
        self.conversation = conversation ?? content.conversation
        self.sentByOwner = sentByOwner || content.sentByOwner
        self.isPartial = isPartial || content.isPartial
        self.isTruncated = isTruncated || content.isTruncated
        self.unloadedHtmlImages = max(unloadedHtmlImages, content.unloadedHtmlImages)
        self.bodyIsImageOnly = bodyIsImageOnly || content.bodyIsImageOnly
        self.isFlagged = isFlagged || content.isFlaggedInMail
        self.isBoilerplateStub = isBoilerplateStub
    }
}

public enum ClassificationOutcome: Equatable, Sendable {
    case triage(DecisionMeta)
    case autoHandled(disposition: Disposition, category: String, probability: Double)
}

/// 同步可插拔分类器协议。
public protocol MailClassifier: Sendable {
    func classify(_ input: RawMailSignals) -> ClassificationOutcome
}

/// 异步分类器协议：支持调用远端 `gemini-decision-1` 正交信号模型并结合本地 SQLite 缓存与状态机合成最终动作。
public protocol AsyncMailClassifier: MailClassifier {
    func classifyAsync(_ input: RawMailSignals) async -> ClassificationOutcome
}

public extension AsyncMailClassifier {
    func classifyAsync(_ input: RawMailSignals) async -> ClassificationOutcome {
        classify(input)
    }
}

// MARK: - RuleBasedClassifier (Superhuman 7-Category Local Deterministic Engine)

public struct RuleBasedClassifier: AsyncMailClassifier {
    public let preferences: SiftPreferences

    public init(preferences: SiftPreferences = .balancedDefault) {
        self.preferences = preferences.sanitized()
    }

    public func classify(_ input: RawMailSignals) -> ClassificationOutcome {
        let mail = input.content
        let subj = mail.subject.lowercased()
        let body = mail.plainText
        let bodyLower = body.lowercased()
        let addr = mail.from.address.lowercased()
        let formattedSender = SiftDecisionEngine.formatSender(mail.from)

        let isFlagged = input.isFlagged
        let isVIP = SiftDecisionEngine.senderMatches(formattedSender, patterns: preferences.vipSenders)
        let isBlocked = SiftDecisionEngine.senderMatches(formattedSender, patterns: preferences.blockedSenders)
        let sentByOwner = input.sentByOwner || (input.conversation?.sentByOwnerInThread ?? false)
        let hasFlaggedInThread = isFlagged || (input.conversation?.hasFlaggedInThread ?? false)
        let protectedFromTrash = sentByOwner || hasFlaggedInThread || isVIP

        let isAutomatedSender = addr.contains("noreply") || addr.contains("no-reply") || addr.contains("no_reply")
            || addr.contains("donotreply") || addr.contains("newsletter")
            || addr.contains("digest") || addr.contains("promo") || addr.contains("marketing")
            || addr.contains("bounce") || addr.contains("mailer-daemon")
        let hasUnsubHeader = input.hasListUnsubscribe || bodyLower.contains("unsubscribe") || body.contains("退订")
        let hasBulkSignal = hasUnsubHeader || input.hasListId || input.isAutoSubmitted || isAutomatedSender

        // 0a. 星标邮件与 VIP 发件人绝对保护：优先保持高利害标签，否则留在收件箱队列
        if isFlagged || isVIP {
            if let highStakes = classifyHighStakes(
                mail: mail,
                subj: subj,
                body: body,
                bodyLower: bodyLower,
                hasUnsubHeader: hasUnsubHeader
            ) {
                return highStakes
            }
            let ev = extractEvidenceSentence(from: body, keywords: ["?", "？", "请", "确认", "回复", "please", "confirm", "review", "deadline"])
            return .triage(
                DecisionMeta(
                    kind: .human,
                    badge: isFlagged ? "已加星标" : SiftCategory.respond.badgeTitle,
                    confidence: 1.0,
                    intent: isFlagged ? "需关注" : "需处理",
                    evidence: ev
                )
            )
        }

        // 0b. 不完整/仅图片/样板占位正文：对齐 email_rules.py `incomplete -> review`（绝不自动归档或删信）
        let isIncomplete = input.isPartial
            || input.isTruncated
            || input.bodyIsImageOnly
            || input.isBoilerplateStub
            || SiftDecisionEngine.isBoilerplateStub(body)
        if preferences.reviewIncompleteMails && isIncomplete {
            let ev = extractEvidenceSentence(from: body, keywords: ["?", "？", "请", "确认", "回复", "please", "confirm"])
            let badge = input.bodyIsImageOnly ? "仅图片或摘要" : "正文待核实"
            return .triage(
                DecisionMeta(
                    kind: .uncertain,
                    badge: badge,
                    confidence: 0.58,
                    evidence: ev
                )
            )
        }

        let rawOutcome = classifyComplete(
            input: input,
            mail: mail,
            subj: subj,
            body: body,
            bodyLower: bodyLower,
            addr: addr,
            isBlocked: isBlocked,
            isAutomatedSender: isAutomatedSender,
            hasUnsubHeader: hasUnsubHeader,
            hasBulkSignal: hasBulkSignal,
            protectedFromTrash: protectedFromTrash
        )

        // 0c. 线程保护闸门：所有者参与过回复或线程内有星标邮件时，绝不允许自动移入废纸篓
        if protectedFromTrash, case .autoHandled(let disposition, _, _) = rawOutcome, disposition == .trashed {
            let ev = extractEvidenceSentence(from: body, keywords: ["?", "？", "请", "确认", "回复", "please", "confirm"])
            return .triage(
                DecisionMeta(
                    kind: .uncertain,
                    badge: "对话受保护",
                    confidence: 0.72,
                    evidence: ev
                )
            )
        }

        return rawOutcome
    }

    internal func classifyHighStakes(
        mail: MailContent,
        subj: String,
        body: String,
        bodyLower: String,
        hasUnsubHeader: Bool
    ) -> ClassificationOutcome? {
        // 3a. 合同 / 签署 / 正式文档附件 / Offer
        let contractKeywords = ["合同", "协议", "签署", "法务", "盖章", "报价单", "contract", "agreement", "docusign", "nda", "offer letter", "admission", "i-20", "visa"]
        let hasPdfOrSheet = mail.attachments.contains { $0.kind == .pdf || $0.kind == .sheet }
        if contractKeywords.contains(where: { subj.contains($0) })
            || (hasPdfOrSheet && (contractKeywords.contains(where: { bodyLower.contains($0) }) || !hasUnsubHeader)) {
            let ev = extractEvidenceSentence(from: body, keywords: ["确认", "签署", "回复", "合同", "协议", "附件", "please", "sign", "review", "confirm", "attached", "deadline"])
            return .triage(
                DecisionMeta(
                    kind: .contract,
                    badge: mail.attachments.isEmpty ? "合同/协议" : "重要附件",
                    confidence: 0.95,
                    intent: "需确认",
                    evidence: ev
                )
            )
        }

        // 3b. 条款 / 额度 / 涨价 / 账户重要变更
        let policyKeywords = ["条款", "隐私政策", "额度", "价格将从", "调整为", "涨价", "即将到期", "exceed", "terms of service", "pricing update", "quota", "usage limit", "policy update", "important update", "security alert"]
        if policyKeywords.contains(where: { subj.contains($0) || bodyLower.contains($0) }) {
            let ev = extractEvidenceSentence(from: body, keywords: ["调整为", "价格", "额度", "自 20", "exceed", "limit", "terms", "update", "取消", "alert", "security"])
            return .triage(
                DecisionMeta(
                    kind: .policy,
                    badge: "条款/额度变更",
                    confidence: 0.92,
                    intent: "需决定",
                    evidence: ev
                )
            )
        }

        // 3c. 账单与扣款（需核对的账单/付款异常进待处理）
        let billingKeywords = ["信用卡", "电子账单", "应还金额", "逾期", "扣款失败", "payment failed", "action required", "past due", "statement is ready", "tuition", "学费", "报销"]
        if billingKeywords.contains(where: { subj.contains($0) || bodyLower.contains($0) }) {
            let ev = extractEvidenceSentence(from: body, keywords: ["¥", "$", "USD", "应还", "金额", "due", "failed", "total", "balance"])
            return .triage(
                DecisionMeta(
                    kind: .billing,
                    badge: "账单异动",
                    confidence: 0.89,
                    intent: "需核对",
                    evidence: ev
                )
            )
        }

        return nil
    }

    private func applyRulePreference(
        category: SiftCategory,
        probability: Double,
        protectedFromTrash: Bool,
        body: String,
        kindIfKeep: DecisionKind = .human,
        intentIfKeep: String = "偏好保留"
    ) -> ClassificationOutcome {
        let targetAction = preferences.action(for: category)
        switch targetAction {
        case .keep:
            let ev = extractEvidenceSentence(
                from: body,
                keywords: ["?", "？", "请", "确认", "回复", "验证码", "登录", "please", "confirm", "code", "login"]
            )
            return .triage(
                DecisionMeta(
                    kind: kindIfKeep,
                    badge: category.badgeTitle,
                    confidence: probability,
                    intent: intentIfKeep,
                    evidence: ev
                )
            )
        case .archive:
            return .autoHandled(
                disposition: .archived,
                category: category.badgeTitle,
                probability: probability
            )
        case .trash:
            if protectedFromTrash {
                let ev = extractEvidenceSentence(from: body, keywords: ["?", "？", "请", "确认", "回复", "please", "confirm"])
                return .triage(
                    DecisionMeta(
                        kind: .uncertain,
                        badge: "对话受保护",
                        confidence: 0.72,
                        evidence: ev
                    )
                )
            }
            return .autoHandled(
                disposition: .trashed,
                category: category.badgeTitle,
                probability: probability
            )
        case .review:
            let ev = extractEvidenceSentence(from: body, keywords: ["?", "？", "请", "确认", "回复", "please", "confirm"])
            return .triage(
                DecisionMeta(
                    kind: .uncertain,
                    badge: "待你拍板",
                    confidence: 0.72,
                    evidence: ev
                )
            )
        }
    }

    private func classifyComplete(
        input: RawMailSignals,
        mail: MailContent,
        subj: String,
        body: String,
        bodyLower: String,
        addr: String,
        isBlocked: Bool,
        isAutomatedSender: Bool,
        hasUnsubHeader: Bool,
        hasBulkSignal: Bool,
        protectedFromTrash: Bool
    ) -> ClassificationOutcome {
        // 1. 安全验证通知（`security` -> 默认留待核验或按用户偏好归档，绝不可删）
        let securityKeywords = [
            "验证码", "动态码", "安全码", "新设备登录", "异地登录", "密码重置",
            "verification code", "security code", "one-time passcode", "verify your device",
            "sign-in code", "new sign-in", "personal access token", "password reset"
        ]
        if securityKeywords.contains(where: { subj.contains($0) || bodyLower.contains($0) })
            && (hasBulkSignal || input.sqlAutomatedFlag || addr.contains("security") || addr.contains("account") || addr.contains("noreply")) {
            return applyRulePreference(
                category: .security,
                probability: 0.98,
                protectedFromTrash: true,
                body: body,
                kindIfKeep: .policy,
                intentIfKeep: "请核验"
            )
        }

        // 2. 高利害优先拦截（即便邮件底部含「退订」或发件人被屏蔽也必须优先保护）
        if let highStakes = classifyHighStakes(
            mail: mail,
            subj: subj,
            body: body,
            bodyLower: bodyLower,
            hasUnsubHeader: hasUnsubHeader
        ) {
            return highStakes
        }

        // 3. 知悉留档记录（`fyi`：物流通知、已付收据、订单确认等）
        let shippingKeywords = ["派送中", "已签收", "快件", "运单", "顺丰", "京东快递", "out for delivery", "has shipped", "your package", "tracking number"]
        if shippingKeywords.contains(where: { subj.contains($0) || bodyLower.contains($0) }) && (hasBulkSignal || input.sqlAutomatedFlag) {
            return applyRulePreference(
                category: .fyi,
                probability: 0.96,
                protectedFromTrash: true,
                body: body
            )
        }

        let routineInvoiceKeywords = ["invoice", "receipt", "收据", "续费提醒", "renews on", "payment received", "order confirmation", "订单确认"]
        if (hasBulkSignal || input.sqlAutomatedFlag) && routineInvoiceKeywords.contains(where: { subj.contains($0) || bodyLower.contains($0) }) {
            return applyRulePreference(
                category: .fyi,
                probability: 0.94,
                protectedFromTrash: true,
                body: body
            )
        }

        // 4. 用户自定义屏蔽发件人（仍受护栏拦截保护）
        if isBlocked {
            if protectedFromTrash {
                let ev = extractEvidenceSentence(from: body, keywords: ["?", "？", "请", "确认", "回复", "please", "confirm"])
                return .triage(
                    DecisionMeta(
                        kind: .uncertain,
                        badge: SiftReviewReason.protectionConflict.badgeTitle,
                        confidence: 0.72,
                        evidence: ev
                    )
                )
            }
            return .autoHandled(
                disposition: .trashed,
                category: SiftCategory.marketing.badgeTitle,
                probability: 0.99
            )
        }

        // 5. 教育/政务域名及工作求职日程直达（`respond` -> 绝不误删）
        let importantHumanDomains = addr.hasSuffix(".edu") || addr.hasSuffix(".edu.cn") || addr.hasSuffix(".gov")
        let pitchOutreachSignals = [
            "jobs for you", "job alert", "recommended jobs", "career fair", "jobfair",
            "book a demo", "cold outreach", "seo", "lead generation", "热招职位", "职位推荐"
        ]
        let isMassPitch = pitchOutreachSignals.contains(where: { subj.contains($0) || bodyLower.contains($0) })

        let workOrCareerSignals = [
            "邀请", "圆桌", "interview", "invitation", "application", "申请", "面试",
            "recruiting", "candidacy", "assessment", "schedule", "meeting", "calendar",
            "assignment", "course", "grade", "deadline", "canvas", "professor", "advisor"
        ]
        if importantHumanDomains && !hasUnsubHeader {
            let ev = extractEvidenceSentence(from: body, keywords: ["?", "？", "please", "due", "meeting", "schedule", "confirm", "请", "时间"])
            return .triage(
                DecisionMeta(
                    kind: .human,
                    badge: "真人来信",
                    confidence: 0.94,
                    intent: (subj.contains("?") || bodyLower.contains("please")) ? "需关注" : nil,
                    evidence: ev
                )
            )
        }
        if workOrCareerSignals.contains(where: { subj.contains($0) }) && !isMassPitch {
            let ev = extractEvidenceSentence(from: body, keywords: workOrCareerSignals + ["please", "confirm", "next steps", "请", "确认", "时间"])
            if hasBulkSignal || isAutomatedSender {
                return .triage(DecisionMeta(kind: .uncertain, badge: "待你拍板", confidence: 0.79, evidence: ev))
            } else {
                return .triage(DecisionMeta(kind: .human, badge: "真人来信", confidence: 0.95, intent: "需回复", evidence: ev))
            }
        }

        // 6. 群发四类（`pitch` / `social` / `news` / `marketing`）按用户 `SiftPreferences` 分拣
        if hasUnsubHeader || isAutomatedSender || input.hasListId {
            let promoKeywords = ["限时", "立减", "买一赠一", "折起", "优惠券", "早鸟", "% off", "sale", "deal", "discount", "special offer", "奖励", "礼包", "free trial", "upgrade"]
            let digestKeywords = ["digest", "weekly", "周报", "日报", "精选", "newsletter", "top 5", "stories for you", "订阅", "recommended for you", "daily dispatch", "webinar", "直播"]
            let socialKeywords = ["linkedin", "github", "twitter", "reddit", "discord", "slack", "查看了你的", "followed you", "mentioned you", "notification", "mailing list"]

            if isMassPitch {
                return applyRulePreference(
                    category: .pitch,
                    probability: 0.93,
                    protectedFromTrash: protectedFromTrash,
                    body: body
                )
            }
            if promoKeywords.contains(where: { subj.contains($0) || bodyLower.contains($0) }) {
                return applyRulePreference(
                    category: .marketing,
                    probability: 0.96,
                    protectedFromTrash: protectedFromTrash,
                    body: body
                )
            }
            if socialKeywords.contains(where: { addr.contains($0) || subj.contains($0) }) {
                return applyRulePreference(
                    category: .social,
                    probability: 0.92,
                    protectedFromTrash: protectedFromTrash,
                    body: body
                )
            }
            if digestKeywords.contains(where: { subj.contains($0) || bodyLower.contains($0) }) {
                return applyRulePreference(
                    category: .news,
                    probability: 0.93,
                    protectedFromTrash: protectedFromTrash,
                    body: body
                )
            }
            if hasUnsubHeader && (input.sqlAutomatedFlag || isAutomatedSender) {
                return applyRulePreference(
                    category: .marketing,
                    probability: 0.91,
                    protectedFromTrash: protectedFromTrash,
                    body: body
                )
            }
            let ev = extractEvidenceSentence(from: body, keywords: ["please", "update", "action", "请", "通知", "确认"])
            return .triage(DecisionMeta(kind: .uncertain, badge: "待你拍板", confidence: 0.74, evidence: ev))
        }

        // 7. 普通真人来信 vs 低确信度待拍板
        let actionKeywords = ["?", "？", "方便", "请回复", "确认", "约", "看看", "let me know", "could you", "would you", "can we", "thoughts", "please"]
        let hasQuestionOrReply = input.isReply || subj.hasPrefix("re:") || subj.hasPrefix("回复:")
            || actionKeywords.contains(where: { bodyLower.contains($0) })

        if hasQuestionOrReply || !input.sqlAutomatedFlag || protectedFromTrash {
            let ev = extractEvidenceSentence(from: body, keywords: ["?", "？", "请", "方便", "下周", "周", "明天", "let me know", "would", "could", "confirm", "please"])
            let needsReply = actionKeywords.contains(where: { bodyLower.contains($0) })
            return .triage(
                DecisionMeta(
                    kind: .human,
                    badge: "真人来信",
                    confidence: needsReply ? 0.96 : 0.91,
                    intent: needsReply ? "需回复" : nil,
                    evidence: ev
                )
            )
        }

        return .triage(DecisionMeta(kind: .uncertain, badge: "待你拍板", confidence: 0.72))
    }

    /// 从正文中抽取包含指定关键词的完整原句，严格保证是 `plainText` 的逐字子串。
    public func extractEvidenceSentence(from plainText: String, keywords: [String]) -> String? {
        guard !plainText.isEmpty else { return nil }
        let lines = plainText.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 6, trimmed.count <= 140 else { continue }
            let sentenceRanges = splitSentenceRanges(in: trimmed)
            for range in sentenceRanges {
                let candidate = String(trimmed[range]).trimmingCharacters(in: .whitespaces)
                guard candidate.count >= 6, candidate.count <= 110 else { continue }
                let lower = candidate.lowercased()
                if keywords.contains(where: { lower.contains($0.lowercased()) }),
                   plainText.contains(candidate) {
                    return candidate
                }
            }
            let lowerLine = trimmed.lowercased()
            if trimmed.count <= 95,
               keywords.contains(where: { lowerLine.contains($0.lowercased()) }),
               plainText.contains(trimmed) {
                return trimmed
            }
        }
        return nil
    }

    private func splitSentenceRanges(in text: String) -> [Range<String.Index>] {
        let terminators: Set<Character> = ["。", "！", "？", "!", "?", "；", ";"]
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        var idx = text.startIndex
        while idx < text.endIndex {
            let ch = text[idx]
            let next = text.index(after: idx)
            if terminators.contains(ch) {
                ranges.append(start..<next)
                start = next
            }
            idx = next
        }
        if start < text.endIndex {
            ranges.append(start..<text.endIndex)
        }
        return ranges
    }
}

// MARK: - HybridMailClassifier & Live Configuration

public enum SiftEngineMode: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case rules
    case hybrid
    case local
}

public enum SiftProviderKind: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case gemini
    case claude
    case openai
    case custom
}

public enum SiftPayloadScope: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case fullText
    case excerpt1500
    case headerOnly
}

public struct SiftClassifierConfiguration: Sendable, Equatable {
    public var engineMode: SiftEngineMode
    public var provider: SiftProviderKind
    public var endpoint: String
    public var model: String
    public var confidenceGate: Double
    public var payloadScope: SiftPayloadScope
    public var cacheDecisions: Bool
    public var preferences: SiftPreferences
    /// 可选的内存临时覆盖密钥；为空时自动从 `SecretStore` 读取。
    public var apiKeyOverride: String?

    public init(
        engineMode: SiftEngineMode = .hybrid,
        provider: SiftProviderKind = .gemini,
        endpoint: String = GeminiDecisionsClient.defaultBaseEndpoint,
        model: String = GeminiDecisionsClient.defaultModel,
        confidenceGate: Double = SiftDecisionEngine.defaultConfidenceGate,
        payloadScope: SiftPayloadScope = .fullText,
        cacheDecisions: Bool = true,
        preferences: SiftPreferences = .balancedDefault,
        apiKeyOverride: String? = nil
    ) {
        self.engineMode = engineMode
        self.provider = provider
        self.endpoint = endpoint
        self.model = model
        let normalizedGate = confidenceGate > 1.0 ? (confidenceGate / 100.0) : confidenceGate
        self.confidenceGate = min(1.0, max(0.0, normalizedGate))
        self.payloadScope = payloadScope
        self.cacheDecisions = cacheDecisions
        self.preferences = preferences.sanitized()
        self.apiKeyOverride = apiKeyOverride
    }
}

private actor ClassificationConcurrencyLimiter {
    private let limit: Int
    private var activeCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async {
        if activeCount < limit {
            activeCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        } else {
            activeCount = max(0, activeCount - 1)
        }
    }
}

/// 混合分类器（本地快速护栏 + SQLite 信号缓存 + `gemini-decision-1` 正交信号 + `SiftDecisionEngine` 合成）：
/// - 支持运行时线程安全热更新 `SiftClassifierConfiguration` / `SiftPreferences`
/// - 修改 `SiftPreferences` 时命中 `DecisionSignalCache` 直接内存秒级重算，零额外 API 请求
/// - 未配置 API Key 或网络异常时自动优雅降级至 `RuleBasedClassifier`
public final class HybridMailClassifier: AsyncMailClassifier, @unchecked Sendable {
    public let policy: SiftClassificationPolicy
    public let client: GeminiDecisionsClient
    public let signalCache: DecisionSignalCache?
    public let secretStore: (any SecretStore)?
    public let secretKey: String

    private let lock = NSLock()
    private var _configuration: SiftClassifierConfiguration
    private let concurrencyLimiter: ClassificationConcurrencyLimiter

    public init(
        configuration: SiftClassifierConfiguration = SiftClassifierConfiguration(),
        policy: SiftClassificationPolicy = .default,
        client: GeminiDecisionsClient = GeminiDecisionsClient(),
        signalCache: DecisionSignalCache? = nil,
        secretStore: (any SecretStore)? = nil,
        secretKey: String = SiftSecretKey.classifierAPIKey,
        maxConcurrentRequests: Int = 4
    ) {
        self._configuration = configuration
        self.policy = policy
        self.client = client
        self.signalCache = signalCache
        self.secretStore = secretStore
        self.secretKey = secretKey
        self.concurrencyLimiter = ClassificationConcurrencyLimiter(limit: maxConcurrentRequests)
    }

    public var configuration: SiftClassifierConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return _configuration
    }

    public func updateConfiguration(_ newConfiguration: SiftClassifierConfiguration) {
        lock.lock()
        var sanitized = newConfiguration
        sanitized.preferences = newConfiguration.preferences.sanitized()
        _configuration = sanitized
        lock.unlock()
    }

    public func updatePreferences(_ newPreferences: SiftPreferences) {
        lock.lock()
        _configuration.preferences = newPreferences.sanitized()
        lock.unlock()
    }

    public func clearCache() throws {
        try signalCache?.clear()
    }

    public func cacheByteSize() -> Int64 {
        signalCache?.databaseByteSize() ?? 0
    }

    public func classify(_ input: RawMailSignals) -> ClassificationOutcome {
        let config = configuration
        let ruleFallback = RuleBasedClassifier(preferences: config.preferences)
        guard config.engineMode != .rules else {
            return ruleFallback.classify(input)
        }

        // 同步路径下若本地缓存已命中正交信号，直接执行 SiftDecisionEngine 合成
        if config.cacheDecisions,
           let signalCache {
            let effectivePolicy = policy.withPreferences(config.preferences)
            let (siftEmail, siftConversation) = SiftDecisionEngine.makeInputs(
                from: input,
                payloadScope: config.payloadScope
            )
            if let request = try? SiftDecisionEngine.buildRequest(
                email: siftEmail,
                policy: effectivePolicy,
                model: config.model,
                conversation: siftConversation
            ) {
                let sha = DecisionSignalCache.computeContentSHA256(for: request.input)
                if let cached = signalCache.get(
                    messageId: input.content.id.rawValue,
                    contentSHA256: sha,
                    policyVersion: effectivePolicy.version
                ),
                   let decision = try? SiftDecisionEngine.resolveDecision(
                       response: cached,
                       email: siftEmail,
                       policy: effectivePolicy,
                       conversation: siftConversation
                   ) {
                    return decision.toClassificationOutcome(
                        for: input.content,
                        confidenceGate: config.confidenceGate
                    )
                }
            }
        }

        return ruleFallback.classify(input)
    }

    public func classifyAsync(_ input: RawMailSignals) async -> ClassificationOutcome {
        let config = configuration
        let ruleFallback = RuleBasedClassifier(preferences: config.preferences)

        guard config.engineMode != .rules else {
            return ruleFallback.classify(input)
        }

        let effectivePolicy = policy.withPreferences(config.preferences)
        let (siftEmail, siftConversation) = SiftDecisionEngine.makeInputs(
            from: input,
            payloadScope: config.payloadScope
        )

        // 本地快速通道 1：加星或命中 VIP 白名单在状态机中恒为最高优先级 keep/respond，无需消耗网络请求
        if siftEmail.starred || SiftDecisionEngine.senderMatches(siftEmail.from, patterns: config.preferences.vipSenders) {
            return ruleFallback.classify(input)
        }

        // 本地快速通道 2：.partial.emlx / 截断 / 纯图片 / 空白退订占位在开启残缺保护时恒进 review，无需消耗网络请求
        let unreadableStub = input.isPartial
            || input.isTruncated
            || input.bodyIsImageOnly
            || input.isBoilerplateStub
            || (config.payloadScope != .headerOnly && SiftDecisionEngine.isBoilerplateStub(siftEmail.body))
        if config.preferences.reviewIncompleteMails && unreadableStub {
            return ruleFallback.classify(input)
        }

        guard let request = try? SiftDecisionEngine.buildRequest(
            email: siftEmail,
            policy: effectivePolicy,
            model: config.model,
            conversation: siftConversation
        ) else {
            return ruleFallback.classify(input)
        }

        let contentSHA256 = DecisionSignalCache.computeContentSHA256(for: request.input)

        // 命中本地 SQLite 正交信号缓存 -> 直接零延迟合成用户最新偏好
        if config.cacheDecisions,
           let cachedResponse = signalCache?.get(
               messageId: input.content.id.rawValue,
               contentSHA256: contentSHA256,
               policyVersion: effectivePolicy.version
           ),
           let decision = try? SiftDecisionEngine.resolveDecision(
               response: cachedResponse,
               email: siftEmail,
               policy: effectivePolicy,
               conversation: siftConversation
           ) {
            return decision.toClassificationOutcome(
                for: input.content,
                confidenceGate: config.confidenceGate
            )
        }

        guard let apiKey = resolveAPIKey(for: config), !apiKey.isEmpty else {
            return ruleFallback.classify(input)
        }

        await concurrencyLimiter.acquire()
        let apiResponse: GeminiDecisionResponse?
        do {
            let fetched = try await client.decide(
                request: request,
                endpoint: config.endpoint,
                apiKey: apiKey
            )
            await concurrencyLimiter.release()
            apiResponse = fetched
        } catch {
            await concurrencyLimiter.release()
            apiResponse = nil
        }

        guard let response = apiResponse,
              let decision = try? SiftDecisionEngine.resolveDecision(
                  response: response,
                  email: siftEmail,
                  policy: effectivePolicy,
                  conversation: siftConversation
              ) else {
            return ruleFallback.classify(input)
        }

        if config.cacheDecisions {
            try? signalCache?.put(
                messageId: input.content.id.rawValue,
                contentSHA256: contentSHA256,
                policyVersion: effectivePolicy.version,
                response: response
            )
        }

        return decision.toClassificationOutcome(
            for: input.content,
            confidenceGate: config.confidenceGate
        )
    }

    private func resolveAPIKey(for config: SiftClassifierConfiguration) -> String? {
        if let override = config.apiKeyOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        guard let secretStore else { return nil }
        let candidateKeys = [
            secretKey,
            SiftSecretKey.apiKey(for: config.provider.rawValue),
            SiftSecretKey.geminiAPIKey,
            SiftSecretKey.classifierAPIKey,
        ]
        var seen = Set<String>()
        for key in candidateKeys where seen.insert(key).inserted {
            if let found = (try? secretStore.readSecret(key: key))?.trimmingCharacters(in: .whitespacesAndNewlines),
               !found.isEmpty {
                return found
            }
        }
        return nil
    }
}

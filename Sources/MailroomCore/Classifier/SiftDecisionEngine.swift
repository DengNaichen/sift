import Foundation

public struct SiftEmailMessage: Codable, Sendable, Equatable, Hashable {
    public var from: String
    public var subject: String
    public var date: String
    public var body: String
    public var hasAttachments: Bool
    public var truncated: Bool
    public var bodyIsImageOnly: Bool
    public var starred: Bool
    public var sentByOwner: Bool

    public init(
        from: String = "",
        subject: String = "",
        date: String = "",
        body: String = "",
        hasAttachments: Bool = false,
        truncated: Bool = false,
        bodyIsImageOnly: Bool = false,
        starred: Bool = false,
        sentByOwner: Bool = false
    ) {
        self.from = from
        self.subject = subject
        self.date = date
        self.body = body
        self.hasAttachments = hasAttachments
        self.truncated = truncated
        self.bodyIsImageOnly = bodyIsImageOnly
        self.starred = starred
        self.sentByOwner = sentByOwner
    }

    enum CodingKeys: String, CodingKey {
        case from
        case subject
        case date
        case body
        case hasAttachments = "has_attachments"
        case truncated
        case bodyIsImageOnly = "body_is_image_only"
        case starred
        case sentByOwner = "sent_by_owner"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        self.subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        self.date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        self.body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        self.hasAttachments = try c.decodeIfPresent(Bool.self, forKey: .hasAttachments) ?? false
        self.truncated = try c.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
        self.bodyIsImageOnly = try c.decodeIfPresent(Bool.self, forKey: .bodyIsImageOnly) ?? false
        self.starred = try c.decodeIfPresent(Bool.self, forKey: .starred) ?? false
        self.sentByOwner = try c.decodeIfPresent(Bool.self, forKey: .sentByOwner) ?? false
    }
}

public struct SiftConversationMessage: Codable, Sendable, Equatable, Hashable {
    public var from: String
    public var subject: String
    public var date: String
    public var body: String
    public var starred: Bool
    public var sentByOwner: Bool

    public init(
        from: String = "",
        subject: String = "",
        date: String = "",
        body: String = "",
        starred: Bool = false,
        sentByOwner: Bool = false
    ) {
        self.from = from
        self.subject = subject
        self.date = date
        self.body = body
        self.starred = starred
        self.sentByOwner = sentByOwner
    }

    enum CodingKeys: String, CodingKey {
        case from
        case subject
        case date
        case body
        case starred
        case sentByOwner = "sent_by_owner"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        self.subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? ""
        self.date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        self.body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        self.starred = try c.decodeIfPresent(Bool.self, forKey: .starred) ?? false
        self.sentByOwner = try c.decodeIfPresent(Bool.self, forKey: .sentByOwner) ?? false
    }
}

public struct SiftUntrustedMessageFields: Codable, Sendable, Equatable, Hashable {
    public var from: String
    public var subject: String
    public var date: String
    public var body: String

    public init(from: String, subject: String, date: String, body: String) {
        self.from = from
        self.subject = subject
        self.date = date
        self.body = body
    }
}

public struct SiftPreprocessingFlags: Codable, Sendable, Equatable, Hashable {
    public var hasUnreadAttachments: Bool
    public var truncated: Bool
    public var bodyIsImageOnly: Bool

    public init(hasUnreadAttachments: Bool, truncated: Bool, bodyIsImageOnly: Bool) {
        self.hasUnreadAttachments = hasUnreadAttachments
        self.truncated = truncated
        self.bodyIsImageOnly = bodyIsImageOnly
    }

    public var anyFlagSet: Bool {
        hasUnreadAttachments || truncated || bodyIsImageOnly
    }

    enum CodingKeys: String, CodingKey {
        case hasUnreadAttachments = "has_unread_attachments"
        case truncated
        case bodyIsImageOnly = "body_is_image_only"
    }
}

public struct SiftInputPayload: Codable, Sendable, Equatable, Hashable {
    public var untrustedEmail: SiftUntrustedMessageFields
    public var untrustedConversation: [SiftUntrustedMessageFields]
    public var preprocessing: SiftPreprocessingFlags

    public init(
        untrustedEmail: SiftUntrustedMessageFields,
        untrustedConversation: [SiftUntrustedMessageFields],
        preprocessing: SiftPreprocessingFlags
    ) {
        self.untrustedEmail = untrustedEmail
        self.untrustedConversation = untrustedConversation
        self.preprocessing = preprocessing
    }

    enum CodingKeys: String, CodingKey {
        case untrustedEmail = "untrusted_email"
        case untrustedConversation = "untrusted_conversation"
        case preprocessing
    }
}

public struct GeminiDecisionRequest: Codable, Sendable, Equatable {
    public var model: String
    public var input: String
    public var questions: [String: SiftQuestion]

    public init(model: String, input: String, questions: [String: SiftQuestion]) {
        self.model = model
        self.input = input
        self.questions = questions
    }
}

public struct GeminiDecisionAnswer: Codable, Sendable, Equatable, Hashable {
    public var type: String
    public var noul: Double?
    public var confidence: Double?

    public init(type: String = "noul", noul: Double?, confidence: Double? = nil) {
        self.type = type
        self.noul = noul
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case type
        case noul
        case confidence
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decode(String.self, forKey: .type)
        if c.contains(.noul) {
            // 严格区分 JSON Bool 与 JSON Number，拒绝 true/false 混充概率
            if (try? c.decode(Bool.self, forKey: .noul)) != nil {
                throw SiftPolicyError.invalidProbability("noul(bool)")
            }
            self.noul = try c.decode(Double.self, forKey: .noul)
        } else {
            self.noul = nil
        }
        self.confidence = try c.decodeIfPresent(Double.self, forKey: .confidence)
    }
}

public struct GeminiDecisionUsage: Codable, Sendable, Equatable, Hashable {
    public var totalInputTokens: Int?
    public var totalOutputTokens: Int?

    public init(totalInputTokens: Int? = nil, totalOutputTokens: Int? = nil) {
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
    }

    enum CodingKeys: String, CodingKey {
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
    }
}

public struct GeminiDecisionResponse: Codable, Sendable, Equatable {
    public var answers: [String: GeminiDecisionAnswer]
    public var usage: GeminiDecisionUsage?

    public init(answers: [String: GeminiDecisionAnswer], usage: GeminiDecisionUsage? = nil) {
        self.answers = answers
        self.usage = usage
    }
}

public struct SiftSignals: Codable, Sendable, Equatable, Hashable {
    public var needsAttention: Double
    public var securityEvent: Double
    public var retainRecord: Double
    public var pitchOutreach: Double
    public var socialDigest: Double
    public var discardable: Double
    public var contextSufficient: Double
    public var topicScores: [SiftTopic: Double]

    public init(
        needsAttention: Double,
        securityEvent: Double,
        retainRecord: Double,
        pitchOutreach: Double,
        socialDigest: Double,
        discardable: Double,
        contextSufficient: Double,
        topicScores: [SiftTopic: Double]
    ) {
        self.needsAttention = needsAttention
        self.securityEvent = securityEvent
        self.retainRecord = retainRecord
        self.pitchOutreach = pitchOutreach
        self.socialDigest = socialDigest
        self.discardable = discardable
        self.contextSufficient = contextSufficient
        self.topicScores = topicScores
    }

    enum CodingKeys: String, CodingKey {
        case needsAttention = "needs_attention"
        case securityEvent = "security_event"
        case retainRecord = "retain_record"
        case pitchOutreach = "pitch_outreach"
        case socialDigest = "social_digest"
        case discardable
        case contextSufficient = "context_sufficient"
        case topicScores = "topic_scores"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.needsAttention = try c.decode(Double.self, forKey: .needsAttention)
        self.securityEvent = try c.decode(Double.self, forKey: .securityEvent)
        self.retainRecord = try c.decode(Double.self, forKey: .retainRecord)
        self.pitchOutreach = try c.decode(Double.self, forKey: .pitchOutreach)
        self.socialDigest = try c.decode(Double.self, forKey: .socialDigest)
        self.discardable = try c.decode(Double.self, forKey: .discardable)
        self.contextSufficient = try c.decode(Double.self, forKey: .contextSufficient)
        let rawTopics = try c.decode([String: Double].self, forKey: .topicScores)
        var mapped: [SiftTopic: Double] = [:]
        for (k, v) in rawTopics {
            if let topic = SiftTopic(rawValue: k) {
                mapped[topic] = v
            }
        }
        self.topicScores = mapped
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(needsAttention, forKey: .needsAttention)
        try c.encode(securityEvent, forKey: .securityEvent)
        try c.encode(retainRecord, forKey: .retainRecord)
        try c.encode(pitchOutreach, forKey: .pitchOutreach)
        try c.encode(socialDigest, forKey: .socialDigest)
        try c.encode(discardable, forKey: .discardable)
        try c.encode(contextSufficient, forKey: .contextSufficient)
        let rawTopics = Dictionary(uniqueKeysWithValues: topicScores.map { ($0.key.rawValue, $0.value) })
        try c.encode(rawTopics, forKey: .topicScores)
    }
}

public struct SiftDecision: Codable, Sendable, Equatable {
    public var topics: [SiftTopic]
    public var category: SiftCategory
    public var reviewReason: SiftReviewReason?
    public var suggestedAction: SiftAction
    public var suggestedCategory: SiftCategory
    public var action: SiftAction
    public var confidence: Double
    public var protectedFromTrash: Bool
    public var reason: String
    public var signals: SiftSignals

    public init(
        topics: [SiftTopic],
        category: SiftCategory,
        reviewReason: SiftReviewReason?,
        suggestedAction: SiftAction,
        suggestedCategory: SiftCategory,
        action: SiftAction,
        confidence: Double,
        protectedFromTrash: Bool,
        reason: String,
        signals: SiftSignals
    ) {
        self.topics = topics
        self.category = category
        self.reviewReason = reviewReason
        self.suggestedAction = suggestedAction
        self.suggestedCategory = suggestedCategory
        self.action = action
        self.confidence = confidence
        self.protectedFromTrash = protectedFromTrash
        self.reason = reason
        self.signals = signals
    }

    enum CodingKeys: String, CodingKey {
        case topics
        case category
        case reviewReason = "review_reason"
        case suggestedAction = "suggested_action"
        case suggestedCategory = "suggested_category"
        case action
        case confidence
        case protectedFromTrash = "protected_from_trash"
        case reason
        case signals
    }
}

/// 1:1 对应 `evals/email_rules.py` 的确定性本地状态机（Superhuman 7 类 + 安全护栏）。
public enum SiftDecisionEngine {
    public static let maxEmailBodyCharacters = 30_000
    public static let maxConversationMessages = 12
    public static let maxConversationBodyCharacters = 8_000
    public static let defaultModel = "gemini-decision-1"
    public static let defaultConfidenceGate = 0.90

    private static let excessiveBlankLinesRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "\n[ \t\u{00A0}]*\n(?:[ \t\u{00A0}]*\n)+")
    }()

    private static let boilerplateRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\[image alt:[^\]]*\]|https?://\S+|(?:如不想收到此类邮件[,，\s]*点击退订|点击退订|退订|unsubscribe|privacy policy|view in browser|online version)"#,
            options: [.caseInsensitive]
        )
    }()

    private static let nonSubstantivePunctuationRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"[\s|.,;:!?()<>—\-_/\\]+"#)
    }()

    private static func isInvisibleFiller(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00AD,
             0x034F,
             0x2007,
             0x200B...0x200F,
             0x202A...0x202E,
             0x2060...0x206F,
             0xFEFF:
            return true
        default:
            return false
        }
    }

    /// 精确对齐 `email_rules.py` 的 `clean_body_text`：
    /// 去除隐形填充字符、将 `\r\n` 规范为 `\n`，并折叠连续空行为 `\n\n`。
    public static func cleanBodyText(_ text: String) -> String {
        var strippedScalars = String.UnicodeScalarView()
        strippedScalars.reserveCapacity(text.unicodeScalars.count)

        var prevWasCR = false
        for scalar in text.unicodeScalars {
            if isInvisibleFiller(scalar) {
                continue
            }
            if prevWasCR {
                if scalar.value == 0x000A {
                    strippedScalars.append(Unicode.Scalar(0x000A)!)
                    prevWasCR = false
                    continue
                } else {
                    strippedScalars.append(Unicode.Scalar(0x000D)!)
                    prevWasCR = false
                }
            }
            if scalar.value == 0x000D {
                prevWasCR = true
            } else {
                strippedScalars.append(scalar)
            }
        }
        if prevWasCR {
            strippedScalars.append(Unicode.Scalar(0x000D)!)
        }

        let cleaned = String(strippedScalars)
        let ns = cleaned as NSString
        return excessiveBlankLinesRegex.stringByReplacingMatches(
            in: cleaned,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: "\n\n"
        )
    }

    /// 精确对齐 `email_rules.py` 的 `is_boilerplate_stub`。
    public static func isBoilerplateStub(_ body: String) -> Bool {
        let cleaned = cleanBodyText(body)
        let nsCleaned = cleaned as NSString
        let withoutBoilerplate = boilerplateRegex.stringByReplacingMatches(
            in: cleaned,
            range: NSRange(location: 0, length: nsCleaned.length),
            withTemplate: " "
        )
        let nsStripped = withoutBoilerplate as NSString
        let substantive = nonSubstantivePunctuationRegex.stringByReplacingMatches(
            in: withoutBoilerplate,
            range: NSRange(location: 0, length: nsStripped.length),
            withTemplate: ""
        )
        return substantive.isEmpty
    }

    /// 精确对齐 `email_rules.py` 的 `sender_matches`。
    public static func senderMatches(_ sender: String, patterns: [String]) -> Bool {
        let lowered = sender.lowercased()
        for rawPattern in patterns {
            let trimmed = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmed.isEmpty, lowered.contains(trimmed) {
                return true
            }
        }
        return false
    }

    public static func validateProbability(_ value: Double, name: String) throws -> Double {
        try SiftProbabilityValidator.validate(value, name: name)
    }

    private static func clipCleanBody(_ body: String, limit: Int) -> (cleaned: String, clipped: Bool) {
        let cleaned = cleanBodyText(body)
        let scalars = cleaned.unicodeScalars
        if scalars.count > limit {
            return (String(scalars.prefix(limit)), true)
        }
        return (cleaned, false)
    }

    /// 精确对齐 `email_rules.py` 的 `input_data`：
    /// 仅提取必要头与正文，清理隐形字符，按 30,000 / 12 封 × 8,000 字符裁剪，不泄露本地私有属性。
    public static func inputData(
        email: SiftEmailMessage,
        conversation: [SiftConversationMessage] = []
    ) -> SiftInputPayload {
        let (emailBody, bodyClipped) = clipCleanBody(email.body, limit: maxEmailBodyCharacters)
        let original = SiftUntrustedMessageFields(
            from: email.from,
            subject: email.subject,
            date: email.date,
            body: emailBody
        )

        var clipped = bodyClipped || (conversation.count > maxConversationMessages)
        var history: [SiftUntrustedMessageFields] = []
        let recent = conversation.suffix(maxConversationMessages)
        history.reserveCapacity(recent.count)
        for msg in recent {
            let (convBody, convShortened) = clipCleanBody(msg.body, limit: maxConversationBodyCharacters)
            history.append(
                SiftUntrustedMessageFields(
                    from: msg.from,
                    subject: msg.subject,
                    date: msg.date,
                    body: convBody
                )
            )
            clipped = clipped || convShortened
        }

        let hasSubstance = !original.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let flags = SiftPreprocessingFlags(
            hasUnreadAttachments: email.hasAttachments,
            truncated: email.truncated || clipped,
            bodyIsImageOnly: email.bodyIsImageOnly || (hasSubstance && isBoilerplateStub(original.body))
        )

        return SiftInputPayload(
            untrustedEmail: original,
            untrustedConversation: history,
            preprocessing: flags
        )
    }

    /// 编码规范化的 `input` JSON 字符串（键有序且不转义 `/`），便于稳定计算 SHA-256 缓存键。
    public static func encodeInputPayload(_ payload: SiftInputPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    /// 精确对齐 `email_rules.py` 的 `build_request`：
    /// 组装顶层防注入 `instructions`、客观信号 `signal_instructions` 与各 `noul` 问题指令。
    public static func buildRequest(
        email: SiftEmailMessage,
        policy: SiftClassificationPolicy = .default,
        model: String = SiftDecisionEngine.defaultModel,
        conversation: [SiftConversationMessage] = []
    ) throws -> GeminiDecisionRequest {
        let payload = inputData(email: email, conversation: conversation)
        let inputJSON = try encodeInputPayload(payload)

        var builtQuestions: [String: SiftQuestion] = [:]
        builtQuestions.reserveCapacity(policy.questions.count)
        for (name, question) in policy.questions {
            var parts = [policy.instructions]
            if SiftSignalKey(rawValue: name) != nil {
                parts.append(policy.signalInstructions)
            }
            parts.append(question.instructions)
            builtQuestions[name] = SiftQuestion(
                type: question.type,
                instructions: parts.joined(separator: "\n\n")
            )
        }

        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultModel
            : model.trimmingCharacters(in: .whitespacesAndNewlines)

        return GeminiDecisionRequest(
            model: resolvedModel,
            input: inputJSON,
            questions: builtQuestions
        )
    }

    /// 精确对齐 `email_rules.py` 的 `directional_suggestion`（0.5 中点方向性读数）。
    public static func directionalSuggestion(
        signals: SiftSignals,
        preferences: SiftPreferences
    ) -> (action: SiftAction, category: SiftCategory) {
        if signals.contextSufficient < 0.5 {
            return (.review, .review)
        }
        if signals.needsAttention >= 0.5 {
            return (.keep, .respond)
        }
        if signals.securityEvent >= 0.5 {
            return (preferences.security, .security)
        }
        if signals.pitchOutreach >= 0.5 && signals.retainRecord < 0.5 {
            return (preferences.pitch, .pitch)
        }
        if signals.socialDigest >= 0.5 && signals.retainRecord < 0.5 {
            return (preferences.social, .social)
        }
        if signals.discardable >= 0.5 && signals.retainRecord < 0.5 {
            return (preferences.marketing, .marketing)
        }
        if signals.retainRecord >= 0.5 {
            return (preferences.fyi, .fyi)
        }
        return (preferences.news, .news)
    }

    /// 精确对齐 `email_rules.py` 的 `apply_preference_action`。
    public static func applyPreferenceAction(
        targetAction: SiftAction,
        category: SiftCategory,
        label: String,
        signalScore: Double,
        protected: Bool,
        signals: SiftSignals,
        threshold: SiftThresholds
    ) -> (action: SiftAction, category: SiftCategory, reviewReason: SiftReviewReason?, reason: String, support: Double) {
        if targetAction == .keep {
            return (.keep, category, nil, "命中\(label)偏好（留在收件箱）。", signalScore)
        }
        if targetAction == .archive {
            return (
                .archive,
                category,
                nil,
                "命中\(label)偏好（归档保留）。",
                min(signals.contextSufficient, signalScore)
            )
        }
        if !protected && signals.retainRecord <= threshold.recordMaxForTrash {
            let support = min(
                min(signals.contextSufficient, 1.0 - signals.needsAttention),
                min(1.0 - signals.retainRecord, signalScore)
            )
            return (
                .trash,
                category,
                nil,
                "命中\(label)偏好且无受保护信号，移入垃圾箱。",
                support
            )
        }
        return (
            .review,
            .review,
            .protectionConflict,
            "\(label)删除偏好与受保护记录信号冲突，等待人工复核。",
            signalScore
        )
    }

    /// 精确对齐 `email_rules.py` 的 `resolve_decision`。
    public static func resolveDecision(
        response: GeminiDecisionResponse,
        email: SiftEmailMessage,
        policy: SiftClassificationPolicy = .default,
        conversation: [SiftConversationMessage] = []
    ) throws -> SiftDecision {
        try policy.thresholds.validate()
        try policy.preferences.validate()

        var values: [String: Double] = [:]
        values.reserveCapacity(policy.questions.count)
        for (name, question) in policy.questions {
            guard let answer = response.answers[name] else {
                throw SiftPolicyError.missingAnswer(name)
            }
            guard answer.type == question.type else {
                throw SiftPolicyError.invalidAnswerType(name)
            }
            guard let rawNoul = answer.noul else {
                throw SiftPolicyError.invalidProbability(name)
            }
            values[name] = try validateProbability(rawNoul, name: name)
        }

        let threshold = policy.thresholds
        let prefs = policy.preferences

        var topicScores: [SiftTopic: Double] = [:]
        for topic in policy.topics.keys {
            guard let score = values[topic.questionKey] else {
                throw SiftPolicyError.missingAnswer(topic.questionKey)
            }
            topicScores[topic] = score
        }

        func reqSignal(_ key: SiftSignalKey) throws -> Double {
            guard let v = values[key.rawValue] else {
                throw SiftPolicyError.missingAnswer(key.rawValue)
            }
            return v
        }

        let signals = SiftSignals(
            needsAttention: try reqSignal(.needsAttention),
            securityEvent: try reqSignal(.securityEvent),
            retainRecord: try reqSignal(.retainRecord),
            pitchOutreach: try reqSignal(.pitchOutreach),
            socialDigest: try reqSignal(.socialDigest),
            discardable: try reqSignal(.discardable),
            contextSufficient: try reqSignal(.contextSufficient),
            topicScores: topicScores
        )

        let vip = senderMatches(email.from, patterns: prefs.vipSenders)
        let blocked = senderMatches(email.from, patterns: prefs.blockedSenders)

        var protected = policy.topics.contains { topic, cfg in
            cfg.protectFromTrash && (topicScores[topic] ?? 0.0) >= threshold.protection
        }
        protected = protected || signals.retainRecord > threshold.recordMaxForTrash
        protected = protected
            || vip
            || email.starred
            || conversation.contains(where: \.starred)
            || email.sentByOwner
            || conversation.contains(where: \.sentByOwner)

        let data = inputData(email: email, conversation: conversation)
        let rawIncomplete = isBoilerplateStub(data.untrustedEmail.body) || data.preprocessing.anyFlagSet
        let incomplete = prefs.reviewIncompleteMails ? rawIncomplete : false
        let (suggestedAction, suggestedCategory) = directionalSuggestion(signals: signals, preferences: prefs)

        let action: SiftAction
        let category: SiftCategory
        let reviewReason: SiftReviewReason?
        let reason: String
        let support: Double

        if email.starred || vip {
            (action, category, reviewReason, reason, support) = (
                .keep,
                .respond,
                nil,
                "邮件已加星或命中重要发件人偏好，留在收件箱优先处理。",
                1.0
            )
        } else if signals.needsAttention >= threshold.attentionHigh {
            (action, category, reviewReason, reason, support) = (
                .keep,
                .respond,
                nil,
                "邮件存在未解决待办、回复请求、故障或面试安排，留在收件箱。",
                signals.needsAttention
            )
        } else if signals.securityEvent >= threshold.attentionHigh && prefs.security == .keep {
            (action, category, reviewReason, reason, support) = (
                .keep,
                .security,
                nil,
                "安全登录、验证码或权限变动提醒，留在收件箱供核验。",
                signals.securityEvent
            )
        } else if incomplete || signals.contextSufficient < threshold.contextMin {
            (action, category, reviewReason, reason, support) = (
                .review,
                .review,
                .insufficientContext,
                "正文、图片、附件或可读上下文不足，等待人工复核。",
                1.0 - signals.contextSufficient
            )
        } else if signals.needsAttention > threshold.attentionLow || (
            prefs.security == .keep && signals.securityEvent > threshold.attentionLow
        ) {
            (action, category, reviewReason, reason, support) = (
                .review,
                .review,
                .uncertainAttention,
                "待办或安全核验信号处于不确定灰区，暂停归档或删除，等待人工复核。",
                max(signals.needsAttention, signals.securityEvent)
            )
        } else if signals.securityEvent >= threshold.attentionHigh {
            (action, category, reviewReason, reason, support) = applyPreferenceAction(
                targetAction: prefs.security,
                category: .security,
                label: "安全验证通知",
                signalScore: signals.securityEvent,
                protected: true,
                signals: signals,
                threshold: threshold
            )
        } else if blocked {
            if !protected {
                (action, category, reviewReason, reason, support) = (
                    .trash,
                    .marketing,
                    nil,
                    "命中用户屏蔽发件人偏好且无受保护信号，移入垃圾箱。",
                    1.0
                )
            } else {
                (action, category, reviewReason, reason, support) = (
                    .review,
                    .review,
                    .protectionConflict,
                    "屏蔽发件人邮件含受保护信号，等待人工复核。",
                    1.0
                )
            }
        } else if signals.pitchOutreach >= threshold.digestMin {
            (action, category, reviewReason, reason, support) = applyPreferenceAction(
                targetAction: prefs.pitch,
                category: .pitch,
                label: "陌生推销与群发荐岗",
                signalScore: signals.pitchOutreach,
                protected: protected,
                signals: signals,
                threshold: threshold
            )
        } else if signals.socialDigest >= threshold.digestMin {
            (action, category, reviewReason, reason, support) = applyPreferenceAction(
                targetAction: prefs.social,
                category: .social,
                label: "社交与公共社区动态",
                signalScore: signals.socialDigest,
                protected: protected,
                signals: signals,
                threshold: threshold
            )
        } else if signals.discardable >= threshold.trashMin {
            (action, category, reviewReason, reason, support) = applyPreferenceAction(
                targetAction: prefs.marketing,
                category: .marketing,
                label: "商业打折促销",
                signalScore: signals.discardable,
                protected: protected,
                signals: signals,
                threshold: threshold
            )
        } else if (prefs.marketing == .trash && signals.discardable > threshold.archiveMaxDiscardable)
            || (prefs.pitch == .trash && signals.pitchOutreach > threshold.archiveMaxDiscardable)
            || (prefs.social == .trash && signals.socialDigest > threshold.archiveMaxDiscardable) {
            (action, category, reviewReason, reason, support) = (
                .review,
                .review,
                .uncertainDisposal,
                "可删除类别信号处于不确定灰区，等待人工复核。",
                max(signals.discardable, max(signals.pitchOutreach, signals.socialDigest))
            )
        } else if protected || signals.retainRecord > threshold.recordMaxForTrash {
            let fyiScore = min(
                signals.contextSufficient,
                min(1.0 - signals.needsAttention, 1.0 - signals.discardable)
            )
            (action, category, reviewReason, reason, support) = applyPreferenceAction(
                targetAction: prefs.fyi,
                category: .fyi,
                label: "知悉留档记录",
                signalScore: fyiScore,
                protected: true,
                signals: signals,
                threshold: threshold
            )
        } else {
            let newsScore = 1.0 - max(signals.discardable, max(signals.pitchOutreach, signals.socialDigest))
            (action, category, reviewReason, reason, support) = applyPreferenceAction(
                targetAction: prefs.news,
                category: .news,
                label: "资讯简报与产品动态",
                signalScore: newsScore,
                protected: protected,
                signals: signals,
                threshold: threshold
            )
        }

        let roundedConfidence = (support * 1_000_000.0).rounded(.toNearestOrEven) / 1_000_000.0
        let matchedTopics = topicScores
            .compactMap { $0.value >= threshold.topic ? $0.key : nil }
            .sorted()

        return SiftDecision(
            topics: matchedTopics,
            category: category,
            reviewReason: reviewReason,
            suggestedAction: suggestedAction,
            suggestedCategory: suggestedCategory,
            action: action,
            confidence: roundedConfidence,
            protectedFromTrash: protected,
            reason: reason,
            signals: signals
        )
    }

    // MARK: - RawMailSignals Conversion

    public static func formatSender(_ sender: Sender) -> String {
        let name = sender.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let addr = sender.address.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return addr }
        if addr.isEmpty { return name }
        if name.caseInsensitiveCompare(addr) == .orderedSame { return addr }
        return "\(name) <\(addr)>"
    }

    public static func makeInputs(
        from raw: RawMailSignals,
        payloadScope: SiftPayloadScope = .fullText
    ) -> (email: SiftEmailMessage, conversation: [SiftConversationMessage]) {
        let content = raw.content
        let isoDate = Date.ISO8601FormatStyle(timeZone: TimeZone(secondsFromGMT: 0)!).format(content.receivedAt)

        let effectiveBody: String
        let effectiveTruncated: Bool
        switch payloadScope {
        case .fullText:
            effectiveBody = content.plainText
            effectiveTruncated = raw.isTruncated || raw.isPartial
        case .excerpt1500:
            let cleaned = cleanBodyText(content.plainText)
            effectiveBody = cleaned.unicodeScalars.count > 1_500
                ? String(cleaned.unicodeScalars.prefix(1_500))
                : content.plainText
            effectiveTruncated = raw.isTruncated || raw.isPartial
        case .headerOnly:
            effectiveBody = ""
            effectiveTruncated = raw.isTruncated || raw.isPartial
        }

        let email = SiftEmailMessage(
            from: formatSender(content.from),
            subject: content.subject,
            date: isoDate,
            body: effectiveBody,
            hasAttachments: !content.attachments.isEmpty,
            truncated: effectiveTruncated,
            bodyIsImageOnly: raw.bodyIsImageOnly || raw.isBoilerplateStub,
            starred: raw.isFlagged,
            sentByOwner: raw.sentByOwner
        )

        var convMessages: [SiftConversationMessage] = []
        if let conv = raw.conversation {
            convMessages.reserveCapacity(conv.priorMessages.count)
            for msg in conv.priorMessages {
                convMessages.append(
                    SiftConversationMessage(
                        from: msg.from,
                        subject: msg.subject,
                        date: msg.dateISO,
                        body: payloadScope == .headerOnly ? "" : msg.bodySnippet,
                        starred: msg.isFlagged,
                        sentByOwner: msg.sentByOwner
                    )
                )
            }
            // 若线程聚合标记存在 owner 回复或星标、但被 12 封窗口截断在更早历史里，补充保留保护位
            if conv.sentByOwnerInThread && !convMessages.contains(where: \.sentByOwner) && !email.sentByOwner {
                if !convMessages.isEmpty {
                    convMessages[0].sentByOwner = true
                } else {
                    convMessages.append(SiftConversationMessage(sentByOwner: true))
                }
            }
            if conv.hasFlaggedInThread && !convMessages.contains(where: \.starred) && !email.starred {
                if !convMessages.isEmpty {
                    convMessages[0].starred = true
                } else {
                    convMessages.append(SiftConversationMessage(starred: true))
                }
            }
        }

        return (email, convMessages)
    }
}

// MARK: - Mapping SiftDecision -> ClassificationOutcome

public extension SiftDecision {
    /// 将 `SiftDecision` 映射为生产 UI 使用的 `ClassificationOutcome`。
    ///
    /// - Note: 关于 `confidenceGate`：
    ///   在默认策略下（`confidenceGate <= 0.90`），`email_rules.py` 已通过内置策略门槛
    ///   （`context_min = 0.85`、`digest_min = 0.85`、`trash_min = 0.90`、`1 - attention_low = 0.85`）
    ///   对保守支持度 `min(...)` 完成门控（合法归档/删除支持度可处于 `0.85...1.0`），故保持与 `email_rules.py` 100% 动作一致；
    ///   当用户在设置页主动将阈值上调至高于默认值（`confidenceGate > 0.90`，如 `0.95`）时，任何支持度低于 `confidenceGate`
    ///   的自动归档/删信动作都会被额外拦截回待处理（`.uncertain`）。
    func toClassificationOutcome(
        for content: MailContent,
        confidenceGate: Double = SiftDecisionEngine.defaultConfidenceGate
    ) -> ClassificationOutcome {
        let normalizedGate = confidenceGate > 1.0 ? (confidenceGate / 100.0) : confidenceGate
        let extractor = RuleBasedClassifier()
        let body = content.plainText
        let subjLower = content.subject.lowercased()
        let bodyLower = body.lowercased()

        let defaultEvidenceKeywords = [
            "?", "？", "请", "确认", "回复", "签署", "合同", "协议", "账单", "金额", "验证码",
            "please", "confirm", "reply", "sign", "review", "invoice", "payment", "due", "code", "deadline"
        ]
        let ev = extractor.extractEvidenceSentence(from: body, keywords: defaultEvidenceKeywords)

        if (action == .archive || action == .trash),
           normalizedGate > SiftDecisionEngine.defaultConfidenceGate,
           confidence < normalizedGate {
            return .triage(
                DecisionMeta(
                    kind: .uncertain,
                    badge: "待你拍板",
                    confidence: min(0.84, max(0.55, confidence)),
                    evidence: ev
                )
            )
        }

        switch action {
        case .keep:
            let keepConfidence = min(1.0, max(0.90, confidence))
            switch category {
            case .respond:
                let contractKeywords = [
                    "合同", "协议", "签署", "法务", "盖章", "报价单",
                    "contract", "agreement", "docusign", "nda", "offer letter", "admission", "i-20", "visa"
                ]
                let hasPdfOrSheet = content.attachments.contains { $0.kind == .pdf || $0.kind == .sheet }
                if hasPdfOrSheet || contractKeywords.contains(where: { subjLower.contains($0) || bodyLower.contains($0) }) {
                    let badge = hasPdfOrSheet ? "重要附件" : "合同/协议"
                    return .triage(
                        DecisionMeta(
                            kind: .contract,
                            badge: badge,
                            confidence: keepConfidence,
                            intent: "需处理",
                            evidence: ev
                        )
                    )
                }

                let billingKeywords = [
                    "账单", "应还", "逾期", "扣款失败", "付款", "汇款", "电汇", "学费", "报销",
                    "invoice", "payment", "wire", "past due", "billing", "tuition", "statement"
                ]
                let financeScore = signals.topicScores[.finance] ?? 0.0
                if financeScore >= 0.5 || billingKeywords.contains(where: { subjLower.contains($0) || bodyLower.contains($0) }) {
                    return .triage(
                        DecisionMeta(
                            kind: .billing,
                            badge: "账单待办",
                            confidence: keepConfidence,
                            intent: "需处理",
                            evidence: ev
                        )
                    )
                }

                return .triage(
                    DecisionMeta(
                        kind: .human,
                        badge: SiftCategory.respond.badgeTitle,
                        confidence: keepConfidence,
                        intent: "需处理",
                        evidence: ev
                    )
                )

            case .security:
                return .triage(
                    DecisionMeta(
                        kind: .policy,
                        badge: SiftCategory.security.badgeTitle,
                        confidence: keepConfidence,
                        intent: "请核验",
                        evidence: ev
                    )
                )

            default:
                return .triage(
                    DecisionMeta(
                        kind: .human,
                        badge: category.badgeTitle,
                        confidence: keepConfidence,
                        intent: "偏好保留",
                        evidence: ev
                    )
                )
            }

        case .review:
            let reviewBadge = reviewReason?.badgeTitle ?? "待你拍板"
            return .triage(
                DecisionMeta(
                    kind: .uncertain,
                    badge: reviewBadge,
                    confidence: min(0.84, max(0.55, confidence)),
                    evidence: ev
                )
            )

        case .archive:
            return .autoHandled(
                disposition: .archived,
                category: category.badgeTitle,
                probability: min(1.0, max(0.91, confidence))
            )

        case .trash:
            return .autoHandled(
                disposition: .trashed,
                category: category.badgeTitle,
                probability: min(1.0, max(0.91, confidence))
            )
        }
    }
}

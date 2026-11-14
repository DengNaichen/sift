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

/// 可插拔分类器协议：当前默认由本地确定性规则分类器实现，后续可无缝替换为 System 1 分类模型服务。
public protocol MailClassifier: Sendable {
    func classify(_ input: RawMailSignals) -> ClassificationOutcome
}

public struct RuleBasedClassifier: MailClassifier {
    public init() {}

    public func classify(_ input: RawMailSignals) -> ClassificationOutcome {
        let mail = input.content
        let subj = mail.subject.lowercased()
        let body = mail.plainText
        let bodyLower = body.lowercased()
        let addr = mail.from.address.lowercased()

        let isFlagged = input.isFlagged
        let sentByOwner = input.sentByOwner || (input.conversation?.sentByOwnerInThread ?? false)
        let hasFlaggedInThread = isFlagged || (input.conversation?.hasFlaggedInThread ?? false)
        let protectedFromTrash = sentByOwner || hasFlaggedInThread

        let isAutomatedSender = addr.contains("noreply") || addr.contains("no-reply") || addr.contains("no_reply")
            || addr.contains("donotreply") || addr.contains("newsletter")
            || addr.contains("digest") || addr.contains("promo") || addr.contains("marketing")
            || addr.contains("bounce") || addr.contains("mailer-daemon")
        let hasUnsubHeader = input.hasListUnsubscribe || bodyLower.contains("unsubscribe") || body.contains("退订")
        let hasBulkSignal = hasUnsubHeader || input.hasListId || input.isAutoSubmitted || isAutomatedSender

        // 0a. 星标邮件绝对保护：优先保持高利害标签，否则以真人/星标待办留在收件箱队列
        if isFlagged {
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
                    badge: "已加星标",
                    confidence: 1.0,
                    intent: "需关注",
                    evidence: ev
                )
            )
        }

        // 0b. 不完整/仅图片/样板占位正文：对齐 email_rules.py `incomplete -> review`（绝不自动归档或删信）
        let isIncomplete = input.isPartial
            || input.isTruncated
            || input.bodyIsImageOnly
            || input.isBoilerplateStub
            || EmlxParser.isBoilerplateStub(body)
        if isIncomplete {
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

    private func classifyHighStakes(
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

    private func classifyComplete(
        input: RawMailSignals,
        mail: MailContent,
        subj: String,
        body: String,
        bodyLower: String,
        addr: String,
        isAutomatedSender: Bool,
        hasUnsubHeader: Bool,
        hasBulkSignal: Bool,
        protectedFromTrash: Bool
    ) -> ClassificationOutcome {
        // 1. 验证码 / 安全登录码 → 高确信度自动归档
        let otpKeywords = ["验证码", "动态码", "安全码", "verification code", "security code", "one-time passcode", "verify your device", "sign-in code"]
        if otpKeywords.contains(where: { subj.contains($0) || bodyLower.contains($0) }) && (hasBulkSignal || input.sqlAutomatedFlag) {
            return .autoHandled(disposition: .archived, category: "验证码", probability: 0.98)
        }

        // 2. 物流通知 → 高确信度自动归档
        let shippingKeywords = ["派送中", "已签收", "快件", "运单", "顺丰", "京东快递", "out for delivery", "has shipped", "your package", "tracking number"]
        if shippingKeywords.contains(where: { subj.contains($0) || bodyLower.contains($0) }) && (hasBulkSignal || input.sqlAutomatedFlag) {
            return .autoHandled(disposition: .archived, category: "物流通知", probability: 0.96)
        }

        // 3. 高利害优先拦截（即便邮件底部含「退订」也必须留在待处理！）
        if let highStakes = classifyHighStakes(
            mail: mail,
            subj: subj,
            body: body,
            bodyLower: bodyLower,
            hasUnsubHeader: hasUnsubHeader
        ) {
            return highStakes
        }

        let routineInvoiceKeywords = ["invoice", "receipt", "收据", "续费提醒", "renews on", "payment received", "order confirmation", "订单确认"]
        if (hasBulkSignal || input.sqlAutomatedFlag) && routineInvoiceKeywords.contains(where: { subj.contains($0) || bodyLower.contains($0) }) {
            return .autoHandled(disposition: .archived, category: "账单通知", probability: 0.94)
        }

        // 4. 工作/学业/求职/日程等需人工知悉或拿不准的邮件 → 绝不误删，进 human 或 uncertain
        let importantHumanDomains = addr.hasSuffix(".edu") || addr.hasSuffix(".edu.cn") || addr.hasSuffix(".gov")
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
        if workOrCareerSignals.contains(where: { subj.contains($0) }) {
            let ev = extractEvidenceSentence(from: body, keywords: workOrCareerSignals + ["please", "confirm", "next steps", "请", "确认", "时间"])
            if hasBulkSignal || isAutomatedSender {
                return .triage(DecisionMeta(kind: .uncertain, badge: "待你拍板", confidence: 0.79, evidence: ev))
            } else {
                return .triage(DecisionMeta(kind: .human, badge: "真人来信", confidence: 0.95, intent: "需回复", evidence: ev))
            }
        }

        // 5. 高确信度营销推广 / 资讯订阅 / 社交群发 → 自动处理（受保护线程由外层闸门兜底拦回队列）
        if hasUnsubHeader || isAutomatedSender || input.hasListId {
            let promoKeywords = ["限时", "立减", "买一赠一", "折起", "优惠券", "早鸟", "% off", "sale", "deal", "discount", "special offer", "奖励", "礼包", "free trial", "upgrade", "webinar", "直播"]
            let digestKeywords = ["digest", "weekly", "周报", "日报", "精选", "newsletter", "top 5", "stories for you", "订阅", "recommended for you", "new jobs", "job alert"]
            let socialKeywords = ["linkedin", "github", "twitter", "reddit", "discord", "slack", "查看了你的", "followed you", "mentioned you", "new sign-in", "notification"]

            if promoKeywords.contains(where: { subj.contains($0) || bodyLower.contains($0) }) {
                return .autoHandled(disposition: .trashed, category: "营销推广", probability: 0.96)
            }
            if digestKeywords.contains(where: { subj.contains($0) || bodyLower.contains($0) }) {
                return .autoHandled(disposition: .trashed, category: "资讯订阅", probability: 0.93)
            }
            if socialKeywords.contains(where: { addr.contains($0) || subj.contains($0) }) {
                return .autoHandled(disposition: .archived, category: "平台通知", probability: 0.92)
            }
            if hasUnsubHeader && (input.sqlAutomatedFlag || isAutomatedSender) {
                return .autoHandled(disposition: .trashed, category: "推广与通知", probability: 0.91)
            }
            // 仅有轻微群发信号但内容不明确 → 保守交给人拍板（< 90% 确信度）
            let ev = extractEvidenceSentence(from: body, keywords: ["please", "update", "action", "请", "通知", "确认"])
            return .triage(DecisionMeta(kind: .uncertain, badge: "待你拍板", confidence: 0.74, evidence: ev))
        }

        // 6. 普通真人来信 vs 低确信度待拍板
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
            // Split line into clauses/sentences while keeping verbatim slices
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

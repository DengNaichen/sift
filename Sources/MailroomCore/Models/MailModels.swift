import Foundation

/// RFC 5322 Message-ID（不含尖括号），作为全局唯一键与 `message://` 链接来源。
public struct MessageId: Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ raw: String) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<") { trimmed.removeFirst() }
        if trimmed.hasSuffix(">") { trimmed.removeLast() }
        self.rawValue = trimmed
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String { rawValue }
}

public struct Sender: Equatable, Hashable, Codable, Sendable {
    public let name: String
    public let address: String

    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }
}

public struct MailAccount: Equatable, Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let address: String

    public init(id: String, label: String, address: String) {
        self.id = id
        self.label = label
        self.address = address
    }
}

public enum AttachmentKind: String, Equatable, Hashable, Codable, Sendable {
    case pdf
    case image
    case sheet
    case other

    public static func infer(filename: String, mimeType: String? = nil) -> AttachmentKind {
        let lower = filename.lowercased()
        let mime = (mimeType ?? "").lowercased()
        if lower.hasSuffix(".pdf") || mime.contains("pdf") {
            return .pdf
        }
        if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg")
            || lower.hasSuffix(".gif") || lower.hasSuffix(".webp") || lower.hasSuffix(".heic")
            || mime.hasPrefix("image/") {
            return .image
        }
        if lower.hasSuffix(".xlsx") || lower.hasSuffix(".xls") || lower.hasSuffix(".csv")
            || lower.hasSuffix(".numbers") || mime.contains("spreadsheet") || mime.contains("excel")
            || mime.contains("csv") {
            return .sheet
        }
        return .other
    }
}

public struct Attachment: Equatable, Hashable, Codable, Sendable, Identifiable {
    public var id: String { "\(name)|\(size)" }
    public let name: String
    public let size: String
    public let kind: AttachmentKind

    public init(name: String, size: String, kind: AttachmentKind) {
        self.name = name
        self.size = size
        self.kind = kind
    }

    public static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(max(1, bytes)) B"
        }
        let kb = Double(bytes) / 1024.0
        if kb < 1024.0 {
            return kb >= 100 ? String(format: "%.0f KB", kb) : String(format: "%.1f KB", kb).replacingOccurrences(of: ".0 KB", with: " KB")
        }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}

public enum DecisionKind: String, Equatable, Hashable, Codable, Sendable, CaseIterable {
    case human
    case policy
    case contract
    case billing
    case uncertain
    case rescued
}

public struct DecisionMeta: Equatable, Hashable, Codable, Sendable {
    public let kind: DecisionKind
    public let badge: String
    public let confidence: Double
    public let intent: String?
    public let evidence: String?

    public init(
        kind: DecisionKind,
        badge: String,
        confidence: Double,
        intent: String? = nil,
        evidence: String? = nil
    ) {
        self.kind = kind
        self.badge = badge
        self.confidence = confidence
        self.intent = intent
        self.evidence = evidence
    }
}

public struct MailContent: Equatable, Hashable, Codable, Sendable, Identifiable {
    public let id: MessageId
    public let from: Sender
    public let to: [Sender]
    public let account: MailAccount
    public let subject: String
    public let receivedAt: Date
    public let plainText: String
    public let attachments: [Attachment]
    /// 对应 Apple Mail 中的原始已读状态（用于初始未读小圆点与双向同步）
    public var isReadInMail: Bool
    /// 对应 Apple Mail 中的原始旗标状态（用于线程保护与状态同步）
    public var isFlaggedInMail: Bool
    /// 该邮件是否由邮箱所有者发出（发件箱角色或匹配所有者地址）
    public let sentByOwner: Bool
    /// 所属对话线程的上下文与安全保护信号（可选）
    public let conversation: ConversationContext?
    /// 正文来源表示（`full_plain_text` / `text_extracted_from_full_html_with_image_alt` / `empty`）
    public let bodyRepresentation: String
    /// 是否来自 `.partial.emlx`
    public let isPartial: Bool
    /// MIME 字节切片是否短于声明长度或正文缺失
    public let isTruncated: Bool
    /// HTML 正文中未加载图片数量
    public let unloadedHtmlImages: Int
    /// 是否仅包含图片或退订/样板占位内容
    public let bodyIsImageOnly: Bool
    /// 富文本 HTML 原文（内嵌 `cid:` 已解析为 `data:` URI，用于原生 WebKit 渲染）
    public let htmlBody: String?
    /// HTML 中是否引用了外部远程图片资源（默认拦截以防追踪像素）
    public let hasRemoteImages: Bool

    public init(
        id: MessageId,
        from: Sender,
        account: MailAccount,
        subject: String,
        receivedAt: Date,
        plainText: String,
        attachments: [Attachment],
        isReadInMail: Bool = false,
        to: [Sender] = [],
        isFlaggedInMail: Bool = false,
        sentByOwner: Bool = false,
        conversation: ConversationContext? = nil,
        bodyRepresentation: String = "full_plain_text",
        isPartial: Bool = false,
        isTruncated: Bool = false,
        unloadedHtmlImages: Int = 0,
        bodyIsImageOnly: Bool = false,
        htmlBody: String? = nil,
        hasRemoteImages: Bool = false
    ) {
        self.id = id
        self.from = from
        self.to = to
        self.account = account
        self.subject = subject
        self.receivedAt = receivedAt
        self.plainText = plainText
        self.attachments = attachments
        self.isReadInMail = isReadInMail
        self.isFlaggedInMail = isFlaggedInMail
        self.sentByOwner = sentByOwner
        self.conversation = conversation
        self.bodyRepresentation = bodyRepresentation
        self.isPartial = isPartial
        self.isTruncated = isTruncated
        self.unloadedHtmlImages = unloadedHtmlImages
        self.bodyIsImageOnly = bodyIsImageOnly
        self.htmlBody = htmlBody
        self.hasRemoteImages = hasRemoteImages
    }
}

public struct MailItem: Equatable, Hashable, Codable, Sendable, Identifiable {
    public var id: MessageId { content.id }
    public var content: MailContent
    public var meta: DecisionMeta

    public init(content: MailContent, meta: DecisionMeta) {
        self.content = content
        self.meta = meta
    }

    public var from: Sender { content.from }
    public var to: [Sender] { content.to }
    public var account: MailAccount { content.account }
    public var subject: String { content.subject }
    public var receivedAt: Date { content.receivedAt }
    public var plainText: String { content.plainText }
    public var attachments: [Attachment] { content.attachments }
    public var isFlaggedInMail: Bool { content.isFlaggedInMail }
    public var sentByOwner: Bool { content.sentByOwner }
    public var conversation: ConversationContext? { content.conversation }
    public var bodyRepresentation: String { content.bodyRepresentation }
    public var isPartial: Bool { content.isPartial }
    public var isTruncated: Bool { content.isTruncated }
    public var unloadedHtmlImages: Int { content.unloadedHtmlImages }
    public var bodyIsImageOnly: Bool { content.bodyIsImageOnly }
    public var htmlBody: String? { content.htmlBody }
    public var hasRemoteImages: Bool { content.hasRemoteImages }
}

public enum Disposition: String, Equatable, Hashable, Codable, Sendable {
    case archived
    case trashed
}

public struct HandledItem: Equatable, Hashable, Codable, Sendable, Identifiable {
    public var id: MessageId { content.id }
    public var content: MailContent
    public var disposition: Disposition
    public var category: String
    public var probability: Double
    public var handledAt: Date
    public var manual: Bool

    public init(
        content: MailContent,
        disposition: Disposition,
        category: String,
        probability: Double,
        handledAt: Date,
        manual: Bool = false
    ) {
        self.content = content
        self.disposition = disposition
        self.category = category
        self.probability = probability
        self.handledAt = handledAt
        self.manual = manual
    }

    public var from: Sender { content.from }
    public var to: [Sender] { content.to }
    public var account: MailAccount { content.account }
    public var subject: String { content.subject }
    public var receivedAt: Date { content.receivedAt }
    public var plainText: String { content.plainText }
    public var attachments: [Attachment] { content.attachments }
    public var isFlaggedInMail: Bool { content.isFlaggedInMail }
    public var sentByOwner: Bool { content.sentByOwner }
    public var conversation: ConversationContext? { content.conversation }
    public var bodyRepresentation: String { content.bodyRepresentation }
    public var isPartial: Bool { content.isPartial }
    public var isTruncated: Bool { content.isTruncated }
    public var unloadedHtmlImages: Int { content.unloadedHtmlImages }
    public var bodyIsImageOnly: Bool { content.bodyIsImageOnly }
    public var htmlBody: String? { content.htmlBody }
    public var hasRemoteImages: Bool { content.hasRemoteImages }
}

public struct DeckSnapshot: Equatable, Sendable {
    public var queue: [MailItem]
    public var handled: [HandledItem]

    public init(queue: [MailItem], handled: [HandledItem]) {
        self.queue = queue
        self.handled = handled
    }
}

public enum TrashReason: String, Sendable {
    case autoPromo = "auto-promo"
    case userPromo = "user-promo"
}

public enum MailAdapterFunctions {
    /// 生成 Apple Mail `message:` URL，形如 `message://%3C<message-id>%3E`
    public static func nativeMailURLString(for id: MessageId) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "<>?#[] ")
        let encoded = id.rawValue.addingPercentEncoding(withAllowedCharacters: allowed) ?? id.rawValue
        return "message://%3C\(encoded)%3E"
    }

    public static func toManualHandled(_ mail: MailItem, handledAt: Date = Date()) -> HandledItem {
        var updatedContent = mail.content
        updatedContent.isReadInMail = true
        return HandledItem(
            content: updatedContent,
            disposition: .trashed,
            category: "你判为推广",
            probability: 1.0,
            handledAt: handledAt,
            manual: true
        )
    }

    public static func rescuedCard(from item: HandledItem) -> MailItem {
        var updatedContent = item.content
        updatedContent.isReadInMail = false
        return MailItem(
            content: updatedContent,
            meta: DecisionMeta(
                kind: .rescued,
                badge: "你拉回的 · 原判\(item.category)",
                confidence: item.probability
            )
        )
    }
}

public protocol MailAdapter: Sendable {
    var sourceLabel: String { get }
    var supportsDemoControls: Bool { get }

    func fetchDeck() async throws -> DeckSnapshot
    func archive(id: MessageId) async throws
    func flagImportant(id: MessageId) async throws
    func moveToTrash(id: MessageId, reason: TrashReason) async throws
    func restore(id: MessageId) async throws
    func rescue(id: MessageId) async throws -> MailItem
    func openInNativeMail(id: MessageId) async throws -> String

    func simulateIncoming(count: Int) async throws -> [MailItem]
    func resetDemo() async throws

    /// 按需补全 `.partial.emlx` 未下载完全的正文与 HTML（不修改原已读状态）
    func hydrateMessage(id: MessageId) async throws -> MailContent?

    /// 外部变化通知流（如 Apple Mail 中读信/删信/新信到达）
    func externalChanges() -> AsyncStream<Void>
}

public extension MailAdapter {
    var supportsDemoControls: Bool { false }
    func simulateIncoming(count: Int) async throws -> [MailItem] { [] }
    func resetDemo() async throws {}
    func hydrateMessage(id: MessageId) async throws -> MailContent? { nil }
    func externalChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

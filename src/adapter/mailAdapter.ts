/**
 * Mailroom Deck 数据层契约。
 *
 * 边界：后端是只做判断的 System 1 分类模型，不生成任何文字。所以这里的每个字段只能来自
 *   1. 邮件原始字段（发件人、主题、正文、附件）；
 *   2. 分类器输出（标签 + 校准概率）。
 * 不允许出现摘要、改写、生成的行动建议。
 *
 * UI 只认识这里的类型与 `MailAdapter` 接口。当前由 `MockMailAdapter` 提供本地数据，
 * 将来替换为 Apple Mail 本机桥接实现时，UI 层无需改动。
 */

/** RFC 5322 Message-ID（不含尖括号），同时作为全局唯一键与 `message://` 链接的来源。 */
export type MessageId = string & { readonly __brand: 'MessageId' }

export const asMessageId = (raw: string): MessageId => raw.replace(/^<|>$/g, '') as MessageId

export interface Sender {
  name: string
  address: string
}

/** 收件邮箱身份：解决多邮箱混流时的身份归属与公私过滤 */
export interface MailAccount {
  id: string
  /** 简短名称，如 `工作`、`个人` */
  label: string
  address: string
}

export interface Attachment {
  name: string
  /** 人类可读大小，如 `1.2 MB` */
  size: string
  kind: 'pdf' | 'image' | 'sheet' | 'other'
}

/** 决策卡的类别，决定角标文案与点缀色。 */
export type DecisionKind =
  | 'human' // 真人来信（工作 / 私人）
  | 'policy' // 条款 / 额度 / 价格变更
  | 'contract' // 带合同等需确认的附件
  | 'billing' // 账单金额异动
  | 'uncertain' // 模型确信度 < 90%，交给人拍板
  | 'rescued' // 你从自动处理里拉回

export interface DecisionMeta {
  kind: DecisionKind
  /** 分类器标签的展示文案，如 `条款/额度变更` */
  badge: string
  /** 分类器对本次判定的校准确信度，0–1；低于 0.9 时卡片会标出确信度 */
  confidence: number
  /**
   * 可选：分类器判断「这封信要你做什么」的标签，如 `需回复`。标签集合由分类模型决定。
   * 缺省时卡片只显示类别。
   */
  intent?: string
  /**
   * 可选：触发判定的原句，必须是 `plainText` 中逐字存在的片段（句子级判断的输出）。
   * 卡片引用它，右栏原文里标亮它。缺省时卡片显示正文开头。
   */
  evidence?: string
}

/** 一封邮件的原始内容，所有视图共用。 */
export interface MailContent {
  id: MessageId
  from: Sender
  /** 这封信发到了用户的哪个邮箱账户 */
  account: MailAccount
  subject: string
  /** ISO 8601 */
  receivedAt: string
  /** 纯文本正文 */
  plainText: string
  attachments: Attachment[]
}

/** 「待处理」里的一件事：分类器判断需要你拍板的邮件。 */
export interface MailItem extends MailContent {
  meta: DecisionMeta
}

/** 分类器对一封不需要你的邮件做了什么 */
export type Disposition = 'archived' | 'trashed'

/** 「自动处理」里的一封邮件：没有进待处理，分类器直接归档或移入了废纸篓。 */
export interface HandledItem extends MailContent {
  disposition: Disposition
  /** 分类器类别标签，如 `营销推广`、`账单通知` */
  category: string
  /** 校准后的概率，0–1 */
  probability: number
  /** ISO 8601 */
  handledAt: string
  /** 由你在待处理里手动判为推广 */
  manual?: boolean
}

export interface DeckSnapshot {
  queue: MailItem[]
  /** 今天自动处理的邮件 */
  handled: HandledItem[]
}

export type TrashReason = 'auto-promo' | 'user-promo'

export interface MailAdapter {
  /** 拉取工作台快照 */
  fetchDeck(): Promise<DeckSnapshot>
  /** 阅毕归档 */
  archive(id: MessageId): Promise<void>
  /** 标记为重要并保留在收件箱（Apple Mail 中为旗标） */
  flagImportant(id: MessageId): Promise<void>
  /** 标已读并移入废纸篓 */
  moveToTrash(id: MessageId, reason: TrashReason): Promise<void>
  /** 撤销：把邮件恢复为收件箱中的未处理状态（取消归档 / 旗标 / 删除） */
  restore(id: MessageId): Promise<void>
  /** 把一封自动处理的邮件拉回收件箱，返回它在待处理里的卡片 */
  rescue(id: MessageId): Promise<MailItem>
  /** 在系统邮件客户端打开原信，返回实际调用的 URL */
  openInNativeMail(id: MessageId): Promise<{ url: string }>
}

/** 仅演示环境提供的能力。真实桥接无需实现。 */
export interface DemoControls {
  reset(): Promise<void>
  simulateIncoming(count: number): Promise<MailItem[]>
}

export const hasDemoControls = (a: MailAdapter): a is MailAdapter & DemoControls =>
  'reset' in a && 'simulateIncoming' in a

/** Apple Mail 的 `message:` URL 形如 `message://%3C<message-id>%3E` */
export const nativeMailUrl = (id: MessageId): string => `message://%3C${encodeURIComponent(id)}%3E`

/** 你在待处理里把一封信判为推广后，它在自动处理里的样子。 */
export const toManualHandled = ({ meta: _meta, ...content }: MailItem, handledAt: string): HandledItem => ({
  ...content,
  disposition: 'trashed',
  category: '你判为推广',
  probability: 1,
  handledAt,
  manual: true,
})

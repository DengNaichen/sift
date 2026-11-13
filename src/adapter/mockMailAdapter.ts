import {
  asMessageId,
  nativeMailUrl,
  toManualHandled,
  type HandledItem,
  type DeckSnapshot,
  type DemoControls,
  type MailAdapter,
  type MailItem,
  type MessageId,
  type TrashReason,
} from './mailAdapter'
import { incomingPool, seedDeck } from './mockData'

type Mailbox = 'inbox' | 'archive' | 'trash'

interface StoredMessage {
  mailbox: Mailbox
  flagged: boolean
  read: boolean
}

/**
 * 内存版 MailAdapter：模拟一个只有收件箱 / 归档 / 废纸篓三个邮箱的账户。
 * 所有方法都带一点可配置的延迟，以便检验 UI 的乐观更新。
 */
export class MockMailAdapter implements MailAdapter, DemoControls {
  private deck: DeckSnapshot = seedDeck(Date.now())
  private store = new Map<MessageId, StoredMessage>()
  private incomingCursor = 0
  private incomingSerial = 0

  constructor(private readonly latencyMs = 80) {
    this.index()
  }

  private index() {
    this.store.clear()
    for (const m of this.deck.queue) this.store.set(m.id, { mailbox: 'inbox', flagged: false, read: false })
    for (const h of this.deck.handled) this.store.set(h.id, { mailbox: h.disposition === 'archived' ? 'archive' : 'trash', flagged: false, read: true })
  }

  private wait() {
    return new Promise<void>((r) => setTimeout(r, this.latencyMs))
  }

  private patch(id: MessageId, next: Partial<StoredMessage>) {
    const cur = this.store.get(id)
    if (!cur) throw new Error(`MockMailAdapter: 未知邮件 ${id}`)
    this.store.set(id, { ...cur, ...next })
  }

  async fetchDeck(): Promise<DeckSnapshot> {
    await this.wait()
    const pending = (id: MessageId) => {
      const m = this.store.get(id)
      return m?.mailbox === 'inbox' && !m.read
    }
    return structuredClone({
      ...this.deck,
      queue: this.deck.queue.filter((m) => pending(m.id)),
      handled: this.deck.handled.filter((h) => this.store.get(h.id)?.mailbox !== 'inbox'),
    })
  }

  async archive(id: MessageId) {
    await this.wait()
    this.patch(id, { mailbox: 'archive', read: true })
  }

  async flagImportant(id: MessageId) {
    await this.wait()
    // 留在收件箱并插旗，标已读后离开工作台
    this.patch(id, { flagged: true, read: true })
  }

  async moveToTrash(id: MessageId, reason: TrashReason) {
    await this.wait()
    this.patch(id, { mailbox: 'trash', read: true })
    const mail = this.deck.queue.find((m) => m.id === id)
    if (reason === 'user-promo' && mail && !this.deck.handled.some((h) => h.id === id)) {
      this.deck.handled.push(toManualHandled(mail, new Date().toISOString()))
    }
  }

  async restore(id: MessageId) {
    await this.wait()
    this.patch(id, { mailbox: 'inbox', flagged: false, read: false })
  }

  async rescue(id: MessageId): Promise<MailItem> {
    await this.wait()
    const handled = this.deck.handled.find((h) => h.id === id)
    if (!handled) throw new Error(`MockMailAdapter: 自动处理里没有 ${id}`)
    this.patch(id, { mailbox: 'inbox', read: false })
    const mail = rescuedCard(handled)
    this.deck.queue = [...this.deck.queue.filter((m) => m.id !== id), mail]
    return structuredClone(mail)
  }

  async openInNativeMail(id: MessageId) {
    // 真实桥接会在这里交给系统打开 URL；原型只返回调用目标。
    return { url: nativeMailUrl(id) }
  }

  async reset() {
    this.deck = seedDeck(Date.now())
    this.incomingCursor = 0
    this.index()
    await this.wait()
  }

  async simulateIncoming(count: number): Promise<MailItem[]> {
    await this.wait()
    const now = Date.now()
    const items: MailItem[] = []
    for (let i = 0; i < count; i++) {
      const tpl = incomingPool[this.incomingCursor % incomingPool.length]!
      this.incomingCursor++
      this.incomingSerial++
      const mail: MailItem = {
        ...structuredClone(tpl),
        id: asMessageId(`incoming-${this.incomingSerial}-${now.toString(36)}@mock.local`),
        receivedAt: new Date(now - i * 40_000).toISOString(),
      }
      this.deck.queue.push(mail)
      this.store.set(mail.id, { mailbox: 'inbox', flagged: false, read: false })
      items.push(mail)
    }
    return structuredClone(items)
  }
}

function rescuedCard({ disposition: _d, category, probability, handledAt: _h, manual: _m, ...content }: HandledItem): MailItem {
  return {
    ...content,
    meta: { kind: 'rescued', badge: `你拉回的 · 原判${category}`, confidence: probability },
  }
}

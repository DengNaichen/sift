import {
  toManualHandled,
  type DeckSnapshot,
  type HandledItem,
  type MailAccount,
  type MailContent,
  type MailItem,
  type MessageId,
} from '../adapter/mailAdapter'

export type CardAction = 'archive' | 'keep' | 'trash'

/**
 * 左侧边栏的分拣视图标识。
 * 后续调整分类体系时，只需增删这里的分支与 `FOLDER_DEFS`。
 */
export type FolderId =
  | 'inbox'
  | 'inbox:human'
  | 'inbox:stakes'
  | 'inbox:uncertain'
  | 'kept'
  | 'archived'
  | 'trashed'

export type AccountScope = 'all' | string

export interface FolderDef {
  id: FolderId
  group: 'triage' | 'processed'
  label: string
  shortcut?: string
  /** 子筛选缩进展示 */
  sub?: boolean
}

export const FOLDER_DEFS: readonly FolderDef[] = [
  { id: 'inbox', group: 'triage', label: '全部待处理', shortcut: '1' },
  { id: 'inbox:human', group: 'triage', label: '真人来信', sub: true },
  { id: 'inbox:stakes', group: 'triage', label: '合同 · 账单 · 条款', sub: true },
  { id: 'inbox:uncertain', group: 'triage', label: '待你拍板', sub: true },
  { id: 'kept', group: 'processed', label: '重要保留' },
  { id: 'archived', group: 'processed', label: '已自动归档', shortcut: '2' },
  { id: 'trashed', group: 'processed', label: '废纸篓', shortcut: '3' },
]

/** 列表与阅读区消费的统一判别联合行，无需类型断言 */
export type FolderRow =
  | { kind: 'inbox'; mail: MailItem }
  | { kind: 'kept'; mail: MailItem }
  | { kind: 'handled'; item: HandledItem }

export const rowContent = (r: FolderRow): MailContent => (r.kind === 'handled' ? r.item : r.mail)
export const rowId = (r: FolderRow): MessageId => rowContent(r).id

/** 每个可撤销操作记录足够把界面恢复原样的信息。 */
export type UndoEntry =
  | { kind: 'card'; action: CardAction; mail: MailItem; index: number; folder: FolderId }
  | { kind: 'rescue'; item: HandledItem; mail: MailItem; folder: FolderId }

export interface Tally {
  archived: number
  kept: number
  trashed: number
  rescued: number
}

export type Toast =
  | { seq: number; kind: 'done'; entry: UndoEntry }
  | { seq: number; kind: 'undone'; entry: UndoEntry }

export interface DeckState {
  phase: 'loading' | 'ready'
  folder: FolderId
  accountScope: AccountScope
  queue: MailItem[]
  /** 本次会话中按 ⇧K 标为重要保留的邮件 */
  kept: MailItem[]
  /** 已按 `orderHandled` 排好序 */
  handled: HandledItem[]
  /** 本次会话中已查看过的邮件 ID，用于列表中展示「未读小圆点」 */
  readIds: ReadonlySet<MessageId>
  focusId: MessageId | null
  undo: UndoEntry[]
  tally: Tally
  toast: Toast | null
  seq: number
}

const zeroTally: Tally = { archived: 0, kept: 0, trashed: 0, rescued: 0 }

export const initialDeck: DeckState = {
  phase: 'loading',
  folder: 'inbox',
  accountScope: 'all',
  queue: [],
  kept: [],
  handled: [],
  readIds: new Set(),
  focusId: null,
  undo: [],
  tally: zeroTally,
  toast: null,
  seq: 0,
}

export function orderHandled(list: readonly HandledItem[]): HandledItem[] {
  const rank = (h: HandledItem) => (h.disposition === 'archived' ? 0 : 1)
  return list.slice().sort((a, b) => rank(a) - rank(b) || b.handledAt.localeCompare(a.handledAt))
}

const matchesAccount = (m: MailContent, scope: AccountScope): boolean =>
  scope === 'all' || m.account.id === scope

/** 计算指定文件夹与邮箱范围下的行列表 */
export function rowsFor(
  s: Pick<DeckState, 'queue' | 'kept' | 'handled'>,
  folder: FolderId,
  scope: AccountScope,
): FolderRow[] {
  switch (folder) {
    case 'inbox':
      return s.queue.filter((m) => matchesAccount(m, scope)).map((mail) => ({ kind: 'inbox', mail }))
    case 'inbox:human':
      return s.queue
        .filter((m) => matchesAccount(m, scope) && m.meta.kind === 'human')
        .map((mail) => ({ kind: 'inbox', mail }))
    case 'inbox:stakes':
      return s.queue
        .filter((m) => matchesAccount(m, scope) && ['policy', 'contract', 'billing'].includes(m.meta.kind))
        .map((mail) => ({ kind: 'inbox', mail }))
    case 'inbox:uncertain':
      return s.queue
        .filter((m) => matchesAccount(m, scope) && (m.meta.kind === 'uncertain' || m.meta.kind === 'rescued'))
        .map((mail) => ({ kind: 'inbox', mail }))
    case 'kept':
      return s.kept.filter((m) => matchesAccount(m, scope)).map((mail) => ({ kind: 'kept', mail }))
    case 'archived':
      return s.handled
        .filter((h) => matchesAccount(h, scope) && h.disposition === 'archived')
        .map((item) => ({ kind: 'handled', item }))
    case 'trashed':
      return s.handled
        .filter((h) => matchesAccount(h, scope) && h.disposition === 'trashed')
        .map((item) => ({ kind: 'handled', item }))
  }
}

export function visibleRows(s: DeckState): FolderRow[] {
  return rowsFor(s, s.folder, s.accountScope)
}

export function folderCounts(
  s: Pick<DeckState, 'queue' | 'kept' | 'handled'>,
  scope: AccountScope,
): Record<FolderId, number> {
  return {
    inbox: rowsFor(s, 'inbox', scope).length,
    'inbox:human': rowsFor(s, 'inbox:human', scope).length,
    'inbox:stakes': rowsFor(s, 'inbox:stakes', scope).length,
    'inbox:uncertain': rowsFor(s, 'inbox:uncertain', scope).length,
    kept: rowsFor(s, 'kept', scope).length,
    archived: rowsFor(s, 'archived', scope).length,
    trashed: rowsFor(s, 'trashed', scope).length,
  }
}

/** 从当前数据集中提取去重后的收件邮箱列表 */
export function accountsOf(s: Pick<DeckState, 'queue' | 'kept' | 'handled'>): MailAccount[] {
  const seen = new Map<string, MailAccount>()
  for (const m of s.queue) if (!seen.has(m.account.id)) seen.set(m.account.id, m.account)
  for (const m of s.kept) if (!seen.has(m.account.id)) seen.set(m.account.id, m.account)
  for (const h of s.handled) if (!seen.has(h.account.id)) seen.set(h.account.id, h.account)
  return [...seen.values()]
}

export const isInboxFolder = (f: FolderId): boolean => f === 'inbox' || f.startsWith('inbox:')

export type DeckEvent =
  | { type: 'loaded'; snapshot: DeckSnapshot }
  | { type: 'folder'; folder: FolderId }
  | { type: 'accountScope'; scope: AccountScope }
  | { type: 'card'; id: MessageId; action: CardAction; now: string }
  | { type: 'rescued'; mail: MailItem }
  | { type: 'undo' }
  | { type: 'incoming'; mails: MailItem[] }
  | { type: 'focus'; id: MessageId }
  | { type: 'moveFocus'; delta: 1 | -1 }
  | { type: 'toastExpired'; seq: number }

const insertAt = <T,>(list: readonly T[], index: number, item: T): T[] => {
  const next = list.slice()
  next.splice(Math.min(index, next.length), 0, item)
  return next
}

const focusAfterRemoval = (rows: readonly FolderRow[], prevIndex: number): MessageId | null => {
  if (rows.length === 0) return null
  const row = rows[Math.min(Math.max(0, prevIndex), rows.length - 1)]
  return row ? rowId(row) : null
}

const reconcileFocus = (s: DeckState): MessageId | null => {
  const rows = visibleRows(s)
  if (rows.length === 0) return null
  if (s.focusId && rows.some((r) => rowId(r) === s.focusId)) return s.focusId
  return rowId(rows[0]!)
}

const markFocusedRead = (s: DeckState, focusId: MessageId | null): DeckState => {
  if (!focusId || !(isInboxFolder(s.folder) || s.folder === 'kept') || s.readIds.has(focusId)) {
    return s.focusId === focusId ? s : { ...s, focusId }
  }
  const readIds = new Set(s.readIds)
  readIds.add(focusId)
  return { ...s, focusId, readIds }
}

const tallyKey: Record<CardAction, keyof Tally> = { archive: 'archived', keep: 'kept', trash: 'trashed' }
const bump = (t: Tally, key: keyof Tally, by: 1 | -1): Tally => ({ ...t, [key]: t[key] + by })

function pushUndo(s: DeckState, entry: UndoEntry): Pick<DeckState, 'undo' | 'toast' | 'seq'> {
  const seq = s.seq + 1
  return { undo: [...s.undo, entry].slice(-50), toast: { seq, kind: 'done', entry }, seq }
}

export function deckReducer(s: DeckState, e: DeckEvent): DeckState {
  switch (e.type) {
    case 'loaded': {
      const handled = orderHandled(e.snapshot.handled)
      const next: DeckState = {
        ...initialDeck,
        phase: 'ready',
        folder: s.folder,
        accountScope: s.accountScope,
        queue: e.snapshot.queue,
        kept: [],
        handled,
        focusId: null,
        seq: s.seq,
      }
      return markFocusedRead(next, reconcileFocus(next))
    }

    case 'folder': {
      if (s.folder === e.folder) return s
      const next = { ...s, folder: e.folder }
      return markFocusedRead(next, reconcileFocus(next))
    }

    case 'accountScope': {
      if (s.accountScope === e.scope) return s
      const next = { ...s, accountScope: e.scope }
      return markFocusedRead(next, reconcileFocus(next))
    }

    case 'card': {
      const queueIndex = s.queue.findIndex((m) => m.id === e.id)
      const mail = s.queue[queueIndex]
      if (!mail) return s
      const beforeRows = visibleRows(s)
      const visIndex = beforeRows.findIndex((r) => rowId(r) === e.id)

      const queue = s.queue.filter((m) => m.id !== e.id)
      const kept = e.action === 'keep' ? [mail, ...s.kept.filter((m) => m.id !== e.id)] : s.kept
      const handled = e.action === 'trash' ? orderHandled([...s.handled, toManualHandled(mail, e.now)]) : s.handled

      const updated: DeckState = {
        ...s,
        ...pushUndo(s, { kind: 'card', action: e.action, mail, index: queueIndex, folder: s.folder }),
        queue,
        kept,
        handled,
        tally: bump(s.tally, tallyKey[e.action], 1),
      }
      const afterRows = visibleRows(updated)
      const focusId =
        s.focusId === e.id ? focusAfterRemoval(afterRows, visIndex >= 0 ? visIndex : 0) : reconcileFocus(updated)
      return markFocusedRead(updated, focusId)
    }

    case 'rescued': {
      const item = s.handled.find((h) => h.id === e.mail.id)
      if (!item) return s
      const beforeRows = visibleRows(s)
      const visIndex = beforeRows.findIndex((r) => rowId(r) === item.id)

      const handled = s.handled.filter((h) => h.id !== item.id)
      const queue = [...s.queue.filter((m) => m.id !== e.mail.id), e.mail]
      const readIds = new Set(s.readIds)
      readIds.delete(e.mail.id)
      const updated: DeckState = {
        ...s,
        ...pushUndo(s, { kind: 'rescue', item, mail: e.mail, folder: s.folder }),
        handled,
        queue,
        readIds,
        tally: bump(s.tally, 'rescued', 1),
      }
      const afterRows = visibleRows(updated)
      const focusId =
        s.focusId === item.id ? focusAfterRemoval(afterRows, visIndex >= 0 ? visIndex : 0) : reconcileFocus(updated)
      return markFocusedRead(updated, focusId)
    }

    case 'undo': {
      const entry = s.undo.at(-1)
      if (!entry) return s
      const seq = s.seq + 1
      const base = { ...s, undo: s.undo.slice(0, -1), toast: { seq, kind: 'undone', entry } as const, seq }
      if (entry.kind === 'card') {
        const accountScope = matchesAccount(entry.mail, s.accountScope) ? s.accountScope : 'all'
        const targetFolder: FolderId = isInboxFolder(entry.folder) ? entry.folder : 'inbox'
        const next: DeckState = {
          ...base,
          folder: targetFolder,
          accountScope,
          queue: insertAt(s.queue, entry.index, entry.mail),
          kept: entry.action === 'keep' ? s.kept.filter((m) => m.id !== entry.mail.id) : s.kept,
          handled: entry.action === 'trash' ? s.handled.filter((h) => h.id !== entry.mail.id) : s.handled,
          focusId: entry.mail.id,
          tally: bump(s.tally, tallyKey[entry.action], -1),
        }
        return { ...next, focusId: reconcileFocus(next) }
      }
      const accountScope = matchesAccount(entry.item, s.accountScope) ? s.accountScope : 'all'
      const targetFolder: FolderId = entry.item.disposition === 'archived' ? 'archived' : 'trashed'
      const next: DeckState = {
        ...base,
        folder: targetFolder,
        accountScope,
        queue: s.queue.filter((m) => m.id !== entry.mail.id),
        handled: orderHandled([...s.handled, entry.item]),
        focusId: entry.item.id,
        tally: bump(s.tally, 'rescued', -1),
      }
      return { ...next, focusId: reconcileFocus(next) }
    }

    case 'incoming': {
      const next: DeckState = {
        ...s,
        queue: [...s.queue, ...e.mails],
      }
      return markFocusedRead(next, reconcileFocus(next))
    }

    case 'focus':
      return markFocusedRead(s, e.id)

    case 'moveFocus': {
      const rows = visibleRows(s)
      if (rows.length === 0) return s
      const cur = Math.max(0, rows.findIndex((r) => rowId(r) === s.focusId))
      const target = rows[Math.min(rows.length - 1, Math.max(0, cur + e.delta))]!
      return markFocusedRead(s, rowId(target))
    }

    case 'toastExpired':
      return s.toast?.seq === e.seq ? { ...s, toast: null } : s
  }
}

export function describeEntry(entry: UndoEntry): string {
  if (entry.kind === 'rescue') return `已拉回待处理「${entry.mail.subject}」`
  return {
    archive: `已归档「${entry.mail.subject}」`,
    keep: `已标为重要保留「${entry.mail.subject}」`,
    trash: `已判为推广，移入废纸篓「${entry.mail.subject}」`,
  }[entry.action]
}

import { MotionConfig } from 'framer-motion'
import {
  Archive,
  ArrowUpRight,
  Flag,
  Inbox,
  Mail,
  Moon,
  PanelLeft,
  RotateCcw,
  Sun,
  Trash2,
  Undo2,
} from 'lucide-react'
import { useCallback, useEffect, useMemo, useState } from 'react'
import type { MailAdapter, MessageId } from './adapter/mailAdapter'
import { CommandPalette, type Command } from './components/CommandPalette'
import type { HudItem } from './components/KeyboardHUD'
import { MailList } from './components/MailList'
import { NativeNotice, type Notice } from './components/NativeNotice'
import { ReadingPane } from './components/ReadingPane'
import { Sidebar } from './components/Sidebar'
import { useMediaQuery } from './lib/useMediaQuery'
import { useTheme } from './lib/useTheme'
import {
  FOLDER_DEFS,
  accountsOf,
  folderCounts,
  isInboxFolder,
  rowContent,
  rowId,
  visibleRows,
  type AccountScope,
  type FolderId,
} from './state/deck'
import { useDeck } from './state/useDeck'

const isTyping = (t: EventTarget | null) =>
  t instanceof HTMLElement && (t.isContentEditable || ['INPUT', 'TEXTAREA', 'SELECT'].includes(t.tagName))

export default function App({ adapter }: { adapter: MailAdapter }) {
  const deck = useDeck(adapter)
  const { state, dispatch, actOnCard, rescue, undo, openNative, demo } = deck
  const { theme, toggle: toggleTheme } = useTheme()
  const [paletteOpen, setPaletteOpen] = useState(false)
  const [notice, setNotice] = useState<Notice | null>(null)
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false)

  const desktop = useMediaQuery('(min-width: 900px)')
  const [mobileShowDetail, setMobileShowDetail] = useState(false)

  const openInMail = useCallback(
    async (id?: MessageId) => {
      const res = await openNative(id)
      if (res) setNotice((n) => ({ seq: (n?.seq ?? 0) + 1, url: res.url }))
    },
    [openNative],
  )

  const expireToast = useCallback((seq: number) => dispatch({ type: 'toastExpired', seq }), [dispatch])
  const clearNotice = useCallback(() => setNotice(null), [])

  const accounts = useMemo(() => accountsOf(state), [state])
  const counts = useMemo(() => folderCounts(state, state.accountScope), [state])
  const rows = useMemo(() => visibleRows(state), [state])
  const activeIndex = useMemo(() => rows.findIndex((r) => rowId(r) === state.focusId), [rows, state.focusId])
  const activeRow = activeIndex >= 0 ? rows[activeIndex] : undefined
  const activeAccount = useMemo(
    () => accounts.find((a) => a.id === state.accountScope),
    [accounts, state.accountScope],
  )

  const setFolder = useCallback(
    (folder: FolderId) => {
      dispatch({ type: 'folder', folder })
      setMobileShowDetail(false)
    },
    [dispatch],
  )

  const setAccountScope = useCallback(
    (scope: AccountScope) => {
      dispatch({ type: 'accountScope', scope })
      setMobileShowDetail(false)
    },
    [dispatch],
  )

  const selectRow = useCallback(
    (id: MessageId) => {
      dispatch({ type: 'focus', id })
      if (!desktop) setMobileShowDetail(true)
    },
    [dispatch, desktop],
  )

  const rescueFocused = useCallback(() => {
    if (activeRow?.kind === 'handled') void rescue(activeRow.item.id)
  }, [activeRow, rescue])

  const toggleSidebar = useCallback(() => setSidebarCollapsed((c) => !c), [])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const mod = e.metaKey || e.ctrlKey
      if (mod && e.key.toLowerCase() === 'k') {
        e.preventDefault()
        setPaletteOpen((o) => !o)
        return
      }
      if (mod && e.key === '\\') {
        e.preventDefault()
        toggleSidebar()
        return
      }
      if (paletteOpen || mod || e.altKey || isTyping(e.target) || e.isComposing) return

      if (e.key === 'Escape' && !desktop && mobileShowDetail) {
        setMobileShowDetail(false)
        return
      }
      if (e.key === '[') {
        e.preventDefault()
        toggleSidebar()
        return
      }
      if (e.key === 'z' || e.key === 'Z') {
        e.preventDefault()
        undo()
        return
      }

      const key = e.key
      const handled = (() => {
        if (key === 'j' || key === 'ArrowDown') return dispatch({ type: 'moveFocus', delta: 1 }), true
        if (key === 'k' || key === 'ArrowUp') return dispatch({ type: 'moveFocus', delta: -1 }), true
        if (key === '1') return setFolder('inbox'), true
        if (key === '2') return setFolder('archived'), true
        if (key === '3') return setFolder('trashed'), true
        if (key === 'Enter' && activeRow) return void openInMail(rowId(activeRow)), true
        if (activeRow?.kind === 'inbox') {
          if (key === 'K') return actOnCard('keep', activeRow.mail.id), true
          if (key === ' ') return actOnCard('archive', activeRow.mail.id), true
          if (key === 'Backspace' || key === 'Delete') return actOnCard('trash', activeRow.mail.id), true
        } else if (activeRow?.kind === 'handled') {
          if (key === 'r' || key === 'R') return rescueFocused(), true
        }
        return false
      })()
      if (handled) e.preventDefault()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [paletteOpen, desktop, mobileShowDetail, activeRow, dispatch, undo, actOnCard, openInMail, setFolder, rescueFocused, toggleSidebar])

  const hud = useMemo<HudItem[]>(() => {
    const hasRows = rows.length > 0
    const inboxMode = isInboxFolder(state.folder)
    const canActInbox = activeRow?.kind === 'inbox'
    const canRescue = activeRow?.kind === 'handled'

    return [
      { keys: ['J', 'K'], label: '切换', run: () => dispatch({ type: 'moveFocus', delta: 1 }), disabled: !hasRows },
      ...(inboxMode
        ? [
            { keys: ['Space'], label: '归档', run: () => canActInbox && actOnCard('archive', activeRow.mail.id), disabled: !canActInbox },
            { keys: ['⇧K'], label: '保留', run: () => canActInbox && actOnCard('keep', activeRow.mail.id), disabled: !canActInbox },
            { keys: ['⌫'], label: '推广', run: () => canActInbox && actOnCard('trash', activeRow.mail.id), disabled: !canActInbox },
          ]
        : state.folder === 'kept'
          ? []
          : [{ keys: ['R'], label: '拉回待处理', run: rescueFocused, disabled: !canRescue }]),
      { keys: ['↵'], label: 'Mail', run: () => void openInMail(activeRow && rowId(activeRow)), disabled: !activeRow },
      { keys: ['Z'], label: '撤销', run: undo, disabled: state.undo.length === 0 },
      { keys: ['⌘K'], label: '命令', run: () => setPaletteOpen(true) },
    ]
  }, [rows.length, state.folder, state.undo.length, activeRow, dispatch, actOnCard, rescueFocused, openInMail, undo])

  const commands = useMemo<Command[]>(() => {
    const list: Command[] = []
    if (activeRow?.kind === 'inbox') {
      const sub = activeRow.mail.subject
      list.push(
        { id: 'archive', group: '当前邮件', title: '阅毕归档', subtitle: sub, kbd: 'Space', icon: Archive, run: () => actOnCard('archive', activeRow.mail.id) },
        { id: 'keep', group: '当前邮件', title: '重要保留', subtitle: sub, kbd: '⇧K', icon: Flag, run: () => actOnCard('keep', activeRow.mail.id) },
        { id: 'trash', group: '当前邮件', title: '判为推广并清掉', subtitle: sub, kbd: '⌫', icon: Trash2, run: () => actOnCard('trash', activeRow.mail.id) },
        { id: 'native', group: '当前邮件', title: '在 Apple Mail 中打开', kbd: '↵', icon: ArrowUpRight, run: () => void openInMail(activeRow.mail.id) },
      )
    } else if (activeRow?.kind === 'handled') {
      const sub = activeRow.item.subject
      list.push(
        { id: 'rescue', group: '当前邮件', title: '拉回待处理', subtitle: sub, kbd: 'R', icon: Undo2, run: rescueFocused },
        { id: 'native', group: '当前邮件', title: '在 Apple Mail 中打开', kbd: '↵', icon: ArrowUpRight, run: () => void openInMail(activeRow.item.id) },
      )
    } else if (activeRow?.kind === 'kept') {
      const content = rowContent(activeRow)
      list.push({ id: 'native', group: '当前邮件', title: '在 Apple Mail 中打开', subtitle: content.subject, kbd: '↵', icon: ArrowUpRight, run: () => void openInMail(content.id) })
    }

    if (accounts.length > 1) {
      list.push({
        id: 'acc-all',
        group: '邮箱范围',
        title: '查看全部邮箱',
        keywords: 'account all 全部邮箱',
        icon: Inbox,
        run: () => setAccountScope('all'),
      })
      for (const acc of accounts) {
        list.push({
          id: `acc-${acc.id}`,
          group: '邮箱范围',
          title: `只看「${acc.label}」邮箱`,
          subtitle: acc.address,
          keywords: `account ${acc.id} ${acc.label} ${acc.address}`,
          icon: Mail,
          run: () => setAccountScope(acc.id),
        })
      }
    }

    for (const def of FOLDER_DEFS) {
      list.push({
        id: `folder-${def.id}`,
        group: '分拣夹',
        title: `前往：${def.label}`,
        subtitle: `${counts[def.id]} 封`,
        kbd: def.shortcut,
        icon: def.id === 'trashed' ? Trash2 : def.id === 'archived' ? Archive : def.id === 'kept' ? Flag : Inbox,
        run: () => setFolder(def.id),
      })
    }

    for (const m of state.queue) {
      list.push({
        id: `mail-${m.id}`,
        group: '待你处理',
        title: m.subject,
        subtitle: `${m.from.name} · ${m.account.label}`,
        keywords: `${m.from.address} ${m.account.address} ${m.meta.badge} ${m.meta.intent ?? ''} ${m.plainText}`,
        icon: Mail,
        run: () => {
          setAccountScope('all')
          setFolder('inbox')
          dispatch({ type: 'focus', id: m.id })
        },
      })
    }
    for (const h of state.handled) {
      list.push({
        id: `handled-${h.id}`,
        group: '自动处理',
        title: h.subject,
        subtitle: `${h.from.name} · ${h.category} · ${h.account.label}`,
        keywords: `${h.from.address} ${h.account.address} ${h.plainText}`,
        icon: Mail,
        run: () => {
          setAccountScope('all')
          setFolder(h.disposition === 'archived' ? 'archived' : 'trashed')
          dispatch({ type: 'focus', id: h.id })
        },
      })
    }

    if (state.undo.length) list.push({ id: 'undo', group: '系统', title: '撤销上一步', kbd: 'Z', icon: Undo2, run: undo })
    list.push(
      {
        id: 'sidebar',
        group: '系统',
        title: sidebarCollapsed ? '展开左侧边栏' : '收起左侧边栏',
        kbd: '[',
        icon: PanelLeft,
        run: toggleSidebar,
      },
      {
        id: 'theme',
        group: '系统',
        title: theme === 'dark' ? '切换到浅色模式' : '切换到深色模式',
        keywords: 'theme dark light 主题 深色 浅色',
        icon: theme === 'dark' ? Sun : Moon,
        run: toggleTheme,
      },
    )
    if (demo) {
      list.push(
        { id: 'sim', group: '演示', title: '模拟收到 3 封新邮件', keywords: 'demo 模拟收到', icon: Inbox, run: () => void demo.simulateIncoming(3) },
        { id: 'reset', group: '演示', title: '重置演示数据', keywords: 'demo reset 重置演示', icon: RotateCcw, run: () => void demo.reset() },
      )
    }
    return list
  }, [
    activeRow,
    accounts,
    counts,
    state.queue,
    state.handled,
    state.undo.length,
    sidebarCollapsed,
    theme,
    demo,
    actOnCard,
    openInMail,
    rescueFocused,
    setAccountScope,
    setFolder,
    dispatch,
    undo,
    toggleSidebar,
    toggleTheme,
  ])

  const showSidebar = desktop && !sidebarCollapsed
  const showList = desktop || !mobileShowDetail
  const showReading = desktop || mobileShowDetail

  return (
    <MotionConfig reducedMotion="user">
      <div className="flex h-screen w-screen overflow-hidden bg-canvas text-ink">
        {showSidebar && (
          <Sidebar
            folder={state.folder}
            counts={counts}
            accounts={accounts}
            accountScope={state.accountScope}
            handledTotal={state.handled.length}
            theme={theme}
            onSelectFolder={setFolder}
            onSelectAccount={setAccountScope}
            onOpenPalette={() => setPaletteOpen(true)}
            onToggleTheme={toggleTheme}
            onCollapse={() => setSidebarCollapsed(true)}
            onSimulate={demo ? () => void demo.simulateIncoming(3) : undefined}
            onReset={demo ? () => void demo.reset() : undefined}
          />
        )}

        {/* Linear 式内嵌工作台纸页：用材质层次替代彩色分块 */}
        <div
          className={`flex min-w-0 flex-1 overflow-hidden bg-paper md:my-1.5 md:mr-1.5 md:rounded-[10px] md:border md:border-line md:shadow-sheet ${
            showSidebar ? '' : 'md:ml-1.5'
          }`}
        >
          {showList && (
            <MailList
              folder={state.folder}
              rows={rows}
              focusId={state.focusId}
              readIds={state.readIds}
              activeAccount={activeAccount}
              showAccountBadge={accounts.length > 1 && state.accountScope === 'all'}
              sidebarCollapsed={!showSidebar}
              onExpandSidebar={() => setSidebarCollapsed(false)}
              onClearAccount={() => setAccountScope('all')}
              onSelectRow={selectRow}
            />
          )}

          {showReading && (
            <ReadingPane
              folder={state.folder}
              row={activeRow}
              position={activeIndex >= 0 ? { index: activeIndex + 1, total: rows.length } : null}
              canUndo={state.undo.length > 0}
              tally={state.tally}
              handledCount={state.handled.length}
              hud={hud}
              toast={state.toast}
              onExpireToast={expireToast}
              showBackToList={!desktop && mobileShowDetail}
              onBackToList={() => setMobileShowDetail(false)}
              onAction={(a) => activeRow?.kind === 'inbox' && actOnCard(a, activeRow.mail.id)}
              onRescue={rescueFocused}
              onUndo={undo}
              onOpenNative={() => void openInMail(activeRow && rowId(activeRow))}
              onSimulate={demo ? () => demo.simulateIncoming(3).then(() => undefined) : undefined}
              onReset={demo?.reset}
            />
          )}
        </div>

        <NativeNotice notice={notice} onDone={clearNotice} />
        <CommandPalette open={paletteOpen} commands={commands} onClose={() => setPaletteOpen(false)} />
      </div>
    </MotionConfig>
  )
}

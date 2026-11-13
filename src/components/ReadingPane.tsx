import { Archive, ArrowLeft, ArrowUpRight, Flag, Trash2, Undo2 } from 'lucide-react'
import { useEffect, useRef, type ReactNode } from 'react'
import { accountDotColor, avatarTintStyle } from '../lib/accents'
import { evidenceOf } from '../lib/excerpt'
import { formatPercent, formatTime } from '../lib/format'
import {
  isInboxFolder,
  rowContent,
  type CardAction,
  type FolderId,
  type FolderRow,
  type Tally,
  type Toast,
} from '../state/deck'
import { InboxZero } from './InboxZero'
import { KeyboardHUD, type HudItem } from './KeyboardHUD'
import { AttachmentChips, KindBadge, PlainText } from './MailDetail'
import { UndoToast } from './UndoToast'

interface Props {
  folder: FolderId
  row: FolderRow | undefined
  position: { index: number; total: number } | null
  canUndo: boolean
  tally: Tally
  handledCount: number
  hud: HudItem[]
  toast: Toast | null
  onExpireToast: (seq: number) => void
  showBackToList?: boolean
  onBackToList?: () => void
  onAction: (action: CardAction) => void
  onRescue: () => void
  onUndo: () => void
  onOpenNative: () => void
  onSimulate?: () => Promise<void>
  onReset?: () => Promise<void>
}

export function ReadingPane({
  folder,
  row,
  position,
  canUndo,
  tally,
  handledCount,
  hud,
  toast,
  onExpireToast,
  showBackToList,
  onBackToList,
  onAction,
  onRescue,
  onUndo,
  onOpenNative,
  onSimulate,
  onReset,
}: Props) {
  const scroller = useRef<HTMLDivElement>(null)
  const content = row ? rowContent(row) : undefined
  const evidence = row && (row.kind === 'inbox' || row.kind === 'kept') ? evidenceOf(row.mail) : undefined

  useEffect(() => {
    const el = scroller.current
    if (!el) return
    const t = setTimeout(() => {
      const mark = el.querySelector<HTMLElement>('mark[data-evidence]')
      el.scrollTo({ top: mark ? Math.max(0, mark.offsetTop - el.clientHeight / 3) : 0, behavior: 'smooth' })
    }, 120)
    return () => clearTimeout(t)
  }, [content?.id])

  return (
    <main aria-label="邮件正文与操作" className="relative flex h-full min-w-0 flex-1 flex-col bg-paper">
      {/* 顶部克制无彩色工具栏：40px 高，与左侧列表栏顶对齐 */}
      <div className="flex h-10 shrink-0 items-center gap-1 border-b border-line px-4">
        {showBackToList && onBackToList && (
          <button
            type="button"
            onClick={onBackToList}
            className="mr-1 inline-flex items-center gap-1 rounded-md px-2 py-1 text-[12px] text-ink-2 transition-colors hover:bg-sunken hover:text-ink"
          >
            <ArrowLeft className="size-3.5" strokeWidth={1.75} />
            列表
          </button>
        )}

        {position && (
          <span className="num text-[11.5px] text-ink-3">
            {position.index} / {position.total}
          </span>
        )}

        <div className="ml-auto flex items-center gap-0.5">
          {row?.kind === 'inbox' && (
            <>
              <ToolbarButton title="阅毕归档（Space）" onClick={() => onAction('archive')}>
                <Archive className="size-3.5 transition-colors group-hover:text-sage" strokeWidth={1.75} />
                归档
              </ToolbarButton>
              <ToolbarButton title="重要保留（⇧K）" onClick={() => onAction('keep')}>
                <Flag className="size-3.5 transition-colors group-hover:text-amber" strokeWidth={1.75} />
                保留
              </ToolbarButton>
              <ToolbarButton title="判为推广并移入废纸篓（⌫）" onClick={() => onAction('trash')}>
                <Trash2 className="size-3.5 transition-colors group-hover:text-coral" strokeWidth={1.75} />
                推广
              </ToolbarButton>
              <span className="mx-1 h-3.5 w-px bg-line" />
            </>
          )}

          {row?.kind === 'handled' && (
            <>
              <ToolbarButton title="拉回待处理（R）" onClick={onRescue}>
                <Undo2 className="size-3.5" strokeWidth={1.75} />
                拉回待处理
              </ToolbarButton>
              <span className="mx-1 h-3.5 w-px bg-line" />
            </>
          )}

          {row?.kind === 'kept' && (
            <>
              <span className="inline-flex items-center gap-1.5 px-2 py-1 text-[12px] text-ink-2">
                <Flag className="size-3.5 text-amber" strokeWidth={1.75} />
                已标旗保留
              </span>
              <span className="mx-1 h-3.5 w-px bg-line" />
            </>
          )}

          <ToolbarButton title="撤销上一步（Z）" disabled={!canUndo} onClick={onUndo}>
            <Undo2 className="size-3.5" strokeWidth={1.75} />
            撤销
          </ToolbarButton>

          {content && (
            <>
              <span className="mx-1 h-3.5 w-px bg-line" />
              <ToolbarButton title="在 Apple Mail 中打开（↵）" onClick={onOpenNative}>
                Apple Mail
                <ArrowUpRight className="size-3.5 text-ink-3" strokeWidth={1.75} />
              </ToolbarButton>
            </>
          )}
        </div>
      </div>

      {/* 正文阅读区（底部留足余量，避免被快捷键胶囊遮挡） */}
      <div ref={scroller} className="scroll-thin relative min-h-0 flex-1 overflow-y-auto">
        {row && content ? (
          <article key={content.id}>
            <header className="border-b border-line px-8 pt-6 pb-5">
              <div className="max-w-[720px]">
                <h1 className="selectable text-[18.5px] leading-snug font-semibold tracking-[-0.015em] text-ink">
                  {content.subject}
                </h1>

                <div className="mt-3.5 flex items-start gap-3">
                  <span
                    style={avatarTintStyle(content.from.address || content.from.name)}
                    className="mt-0.5 grid size-7 shrink-0 place-items-center rounded-full border text-[12px] font-medium"
                  >
                    {content.from.name.slice(0, 1).toUpperCase()}
                  </span>

                  <div className="min-w-0 flex-1 space-y-1">
                    <div className="flex flex-wrap items-baseline gap-x-2 gap-y-0.5 text-[13px]">
                      <span className="font-semibold text-ink">{content.from.name}</span>
                      <span className="selectable truncate text-[12px] text-ink-3">&lt;{content.from.address}&gt;</span>
                      <span className="num ml-auto shrink-0 text-[11.5px] text-ink-3">
                        {formatTime(content.receivedAt)}
                      </span>
                    </div>

                    <div className="flex flex-wrap items-center gap-x-2.5 gap-y-1.5 text-[12px] text-ink-3">
                      <span className="inline-flex items-center gap-1.5">
                        <span>发至</span>
                        <span className="inline-flex items-center gap-1 rounded-[3px] border border-line px-1.5 py-px text-[11px] text-ink-2">
                          <span
                            aria-hidden="true"
                            className="size-1.5 shrink-0 rounded-full"
                            style={{ backgroundColor: accountDotColor(content.account.id) }}
                          />
                          {content.account.label}
                        </span>
                        <span className="selectable text-ink-2">{content.account.address}</span>
                      </span>

                      <span className="text-line-strong">·</span>

                      {row.kind === 'handled' ? (
                        <span className="inline-flex items-center gap-1.5 rounded-[5px] bg-sunken px-2 py-[3px] text-[11.5px] leading-none text-ink-2">
                          <span>{row.item.disposition === 'archived' ? '自动归档' : '已移入废纸篓'}</span>
                          <span className="text-ink-3">·</span>
                          <span>{row.item.category}</span>
                          {!row.item.manual && (
                            <>
                              <span className="text-ink-3">·</span>
                              <span className="text-ink-3">
                                校准概率 <span className="num">{formatPercent(row.item.probability)}</span>
                              </span>
                            </>
                          )}
                        </span>
                      ) : (
                        <KindBadge mail={row.mail} />
                      )}
                    </div>
                  </div>
                </div>

                {content.attachments.length > 0 && (
                  <div className="mt-3.5 pl-10">
                    <AttachmentChips attachments={content.attachments} />
                  </div>
                )}
              </div>
            </header>

            <div className="max-w-[720px] px-8 pt-6 pb-24">
              <PlainText text={content.plainText} highlight={evidence} />
            </div>
          </article>
        ) : (
          <div className="flex min-h-full items-center justify-center p-8 pb-20">
            {isInboxFolder(folder) ? (
              <div className="w-full max-w-[520px]">
                <InboxZero
                  tally={tally}
                  handledCount={handledCount}
                  canUndo={canUndo}
                  onSimulate={onSimulate}
                  onReset={onReset}
                />
              </div>
            ) : (
              <p className="text-[13px] text-ink-3">该分拣夹当前没有邮件</p>
            )}
          </div>
        )}
      </div>

      <UndoToast toast={toast} onUndo={onUndo} onExpire={onExpireToast} />
      <KeyboardHUD items={hud} />
    </main>
  )
}

function ToolbarButton({
  children,
  title,
  disabled,
  onClick,
}: {
  children: ReactNode
  title?: string
  disabled?: boolean
  onClick: () => void
}) {
  return (
    <button
      type="button"
      title={title}
      disabled={disabled}
      onClick={onClick}
      className="group inline-flex h-7 items-center gap-1.5 rounded-[6px] px-2 text-[12px] text-ink-2 transition-colors hover:bg-sunken hover:text-ink disabled:pointer-events-none disabled:opacity-38"
    >
      {children}
    </button>
  )
}

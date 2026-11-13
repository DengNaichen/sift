import { Flag, PanelLeftOpen, Paperclip, X } from 'lucide-react'
import { useEffect, useRef } from 'react'
import type { MailAccount, MessageId } from '../adapter/mailAdapter'
import { accountDotColor, kindDotColor } from '../lib/accents'
import { evidenceOf, openingLines } from '../lib/excerpt'
import { formatPercent, formatTime } from '../lib/format'
import { FOLDER_DEFS, rowContent, rowId, type FolderId, type FolderRow } from '../state/deck'

interface Props {
  folder: FolderId
  rows: FolderRow[]
  focusId: MessageId | null
  readIds: ReadonlySet<MessageId>
  activeAccount: MailAccount | undefined
  showAccountBadge: boolean
  sidebarCollapsed: boolean
  onExpandSidebar: () => void
  onClearAccount: () => void
  onSelectRow: (id: MessageId) => void
}

export function MailList({
  folder,
  rows,
  focusId,
  readIds,
  activeAccount,
  showAccountBadge,
  sidebarCollapsed,
  onExpandSidebar,
  onClearAccount,
  onSelectRow,
}: Props) {
  const folderTitle = FOLDER_DEFS.find((f) => f.id === folder)?.label ?? '邮件'

  return (
    <section
      aria-label={folderTitle}
      className="flex h-full w-full shrink-0 flex-col border-r border-line bg-paper md:w-[348px]"
    >
      {/* 列表栏顶：40px 与右侧阅读工具栏等高 */}
      <div className="flex h-10 shrink-0 items-center gap-2 border-b border-line px-3.5">
        {sidebarCollapsed && (
          <button
            type="button"
            onClick={onExpandSidebar}
            title="展开侧边栏（[）"
            aria-label="展开侧边栏"
            className="-ml-1 grid size-6 shrink-0 place-items-center rounded-md text-ink-3 transition-colors hover:bg-sunken hover:text-ink"
          >
            <PanelLeftOpen className="size-3.5" strokeWidth={1.75} />
          </button>
        )}
        <h2 className="truncate text-[13px] font-semibold tracking-tight text-ink">{folderTitle}</h2>
        <span className="num text-[11.5px] text-ink-3">{rows.length}</span>

        {activeAccount && (
          <button
            type="button"
            onClick={onClearAccount}
            title="点击恢复全部邮箱"
            className="inline-flex items-center gap-1.5 rounded-[5px] border border-line bg-sunken/70 px-1.5 py-0.5 text-[11px] text-ink-2 transition-colors hover:text-ink"
          >
            <span
              aria-hidden="true"
              className="size-1.5 shrink-0 rounded-full"
              style={{ backgroundColor: accountDotColor(activeAccount.id) }}
            />
            <span>{activeAccount.label}</span>
            <X className="size-2.5 text-ink-3" />
          </button>
        )}
      </div>

      {/* 无彩色高密度等高列表：以字重、灰阶和线型构建层级 */}
      <div className="scroll-thin min-h-0 flex-1 overflow-y-auto">
        {rows.length > 0 ? (
          <ol className="divide-y divide-line">
            {rows.map((row) => {
              const id = rowId(row)
              return (
                <li key={id}>
                  <MailListRow
                    row={row}
                    selected={id === focusId}
                    unread={row.kind !== 'handled' && !readIds.has(id)}
                    showAccountBadge={showAccountBadge}
                    onSelect={() => onSelectRow(id)}
                  />
                </li>
              )
            })}
          </ol>
        ) : (
          <div className="flex h-full flex-col items-center justify-center px-6 text-center text-[12.5px] text-ink-3">
            当前列表为空
          </div>
        )}
      </div>
    </section>
  )
}

function MailListRow({
  row,
  selected,
  unread,
  showAccountBadge,
  onSelect,
}: {
  row: FolderRow
  selected: boolean
  unread: boolean
  showAccountBadge: boolean
  onSelect: () => void
}) {
  const ref = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    if (selected) ref.current?.scrollIntoView({ block: 'nearest' })
  }, [selected])

  const content = rowContent(row)
  const isInboxOrKept = row.kind === 'inbox' || row.kind === 'kept'
  const evidence = isInboxOrKept ? evidenceOf(row.mail) : undefined
  const preview = evidence ?? openingLines(content.plainText, 90)
  const timestamp = row.kind === 'handled' ? row.item.handledAt : content.receivedAt

  return (
    <button
      ref={ref}
      type="button"
      onClick={onSelect}
      aria-current={selected}
      className={`relative flex w-full flex-col gap-0.5 px-3.5 py-2.5 text-left ${
        selected
          ? 'bg-sunken before:absolute before:inset-y-0 before:left-0 before:w-[2px] before:bg-ink'
          : 'hover:bg-sunken/50'
      }`}
    >
      {/* 第 1 行：未读点 + 发件人 + 细线框邮箱微标 + 旗标/附件/时间 */}
      <div className="flex items-center gap-1.5">
        {unread && (
          <span
            aria-label="未读"
            title="未读"
            className="size-1.5 shrink-0 rounded-full bg-cobalt"
          />
        )}
        <span
          className={`truncate text-[13px] leading-snug ${
            unread ? 'font-semibold text-ink' : isInboxOrKept ? 'font-medium text-ink' : 'font-normal text-ink-2'
          }`}
        >
          {content.from.name}
        </span>

        {showAccountBadge && (
          <span
            title={`收件邮箱：${content.account.address}`}
            className="inline-flex shrink-0 items-center gap-1 rounded-[3px] border border-line px-1 py-px text-[10px] leading-tight text-ink-3"
          >
            <span
              aria-hidden="true"
              className="size-1.5 shrink-0 rounded-full"
              style={{ backgroundColor: accountDotColor(content.account.id) }}
            />
            {content.account.label}
          </span>
        )}

        {row.kind === 'kept' && <Flag className="size-3 shrink-0 text-amber" />}

        <span className="ml-auto flex shrink-0 items-center gap-1.5 pl-1">
          {content.attachments.length > 0 && (
            <span className="inline-flex items-center gap-0.5 text-[10.5px] text-ink-3">
              <Paperclip className="size-3" strokeWidth={1.75} />
              {content.attachments.length > 1 && <span className="num">{content.attachments.length}</span>}
            </span>
          )}
          <span className="num text-[11px] text-ink-3">{formatTime(timestamp)}</span>
        </span>
      </div>

      {/* 第 2 行：无彩色意图/类别标（虚线代表低确信度）+ 单行主题 */}
      <div className="flex items-center gap-1.5">
        <RowBadge row={row} selected={selected} />
        <span
          className={`min-w-0 flex-1 truncate text-[12.5px] leading-snug ${
            isInboxOrKept ? 'font-medium text-ink' : 'text-ink-2'
          }`}
        >
          {content.subject}
        </span>
      </div>

      {/* 第 3 行：单行原句证据或正文摘要 */}
      {evidence ? (
        <p className="mt-0.5 truncate border-l-[1.5px] border-line-strong pl-1.5 text-[11.5px] leading-snug text-ink-2">
          {evidence}
        </p>
      ) : (
        <p className="mt-0.5 truncate text-[11.5px] leading-snug text-ink-3">{preview}</p>
      )}
    </button>
  )
}

function RowBadge({ row, selected }: { row: FolderRow; selected: boolean }) {
  if (row.kind === 'handled') {
    const { category, probability, manual } = row.item
    return (
      <span
        className={`shrink-0 rounded-[4px] px-1.5 py-[1px] text-[10.5px] leading-tight text-ink-3 ${
          selected ? 'bg-paper/80' : 'bg-sunken'
        }`}
      >
        {category}
        {!manual && <span className="num ml-1">{formatPercent(probability)}</span>}
      </span>
    )
  }

  const { kind, intent, badge, confidence } = row.mail.meta
  const uncertain = confidence < 0.9
  const label = intent ?? (uncertain ? `${badge} ${formatPercent(confidence)}` : badge)

  return (
    <span
      className={`inline-flex shrink-0 items-center gap-1 rounded-[4px] px-1.5 py-[1px] text-[10.5px] leading-tight ${
        uncertain
          ? 'border border-dashed border-line-strong text-ink-3'
          : selected
            ? 'bg-paper font-medium text-ink-2 shadow-[0_0_0_0.5px_var(--line)]'
            : 'bg-sunken font-medium text-ink-2'
      }`}
    >
      <span
        aria-hidden="true"
        className="size-1.5 shrink-0 rounded-full"
        style={{ backgroundColor: kindDotColor(kind) }}
      />
      {label}
    </span>
  )
}

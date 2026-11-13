import {
  Archive,
  CircleHelp,
  FileText,
  Flag,
  Inbox,
  Mail,
  MailPlus,
  Moon,
  PanelLeftClose,
  RotateCcw,
  Search,
  Sun,
  Trash2,
  User,
} from 'lucide-react'
import type { MailAccount } from '../adapter/mailAdapter'
import { accountDotColor } from '../lib/accents'
import { savedMinutes } from '../lib/format'
import { FOLDER_DEFS, type AccountScope, type FolderDef, type FolderId } from '../state/deck'
import { Kbd } from './Kbd'

interface Props {
  folder: FolderId
  counts: Record<FolderId, number>
  accounts: MailAccount[]
  accountScope: AccountScope
  handledTotal: number
  theme: 'light' | 'dark'
  onSelectFolder: (folder: FolderId) => void
  onSelectAccount: (scope: AccountScope) => void
  onOpenPalette: () => void
  onToggleTheme: () => void
  onCollapse: () => void
  onSimulate?: () => void
  onReset?: () => void
}

function FolderIcon({ def }: { def: FolderDef }) {
  const cls = 'size-3.5 shrink-0'
  switch (def.id) {
    case 'inbox':
      return <Inbox className={cls} strokeWidth={1.8} />
    case 'inbox:human':
      return <User className={cls} strokeWidth={1.75} />
    case 'inbox:stakes':
      return <FileText className={cls} strokeWidth={1.75} />
    case 'inbox:uncertain':
      return <CircleHelp className={cls} strokeWidth={1.75} />
    case 'kept':
      return <Flag className={cls} strokeWidth={1.75} />
    case 'archived':
      return <Archive className={cls} strokeWidth={1.75} />
    case 'trashed':
      return <Trash2 className={cls} strokeWidth={1.75} />
  }
}

export function Sidebar({
  folder,
  counts,
  accounts,
  accountScope,
  handledTotal,
  theme,
  onSelectFolder,
  onSelectAccount,
  onOpenPalette,
  onToggleTheme,
  onCollapse,
  onSimulate,
  onReset,
}: Props) {
  const triageFolders = FOLDER_DEFS.filter((f) => f.group === 'triage')
  const processedFolders = FOLDER_DEFS.filter((f) => f.group === 'processed')
  const activeAccount = accounts.find((a) => a.id === accountScope)

  return (
    <aside
      aria-label="邮箱与分拣导航"
      className="flex h-full w-[206px] shrink-0 flex-col bg-canvas px-2.5 pt-2.5 pb-2 select-none"
    >
      {/* 品牌栏 */}
      <div className="flex h-8 shrink-0 items-center justify-between px-1">
        <div className="flex items-center gap-2">
          <span className="grid size-[18px] place-items-center rounded-[4px] bg-ink text-canvas">
            <Mail className="size-2.5" strokeWidth={2.5} />
          </span>
          <span className="text-[13px] font-semibold tracking-tight text-ink">Mailroom</span>
        </div>
        <button
          type="button"
          onClick={onCollapse}
          title="收起侧边栏（[）"
          aria-label="收起侧边栏"
          className="grid size-6 place-items-center rounded-md text-ink-3 transition-colors hover:bg-[color-mix(in_srgb,var(--ink)_6%,transparent)] hover:text-ink"
        >
          <PanelLeftClose className="size-3.5" strokeWidth={1.75} />
        </button>
      </div>

      {/* 收件邮箱范围滤镜：以 6px 小圆点区分公私身份 */}
      {accounts.length > 1 && (
        <div className="pt-2">
          <div
            role="tablist"
            aria-label="收件邮箱范围"
            className="grid grid-cols-3 gap-0.5 rounded-[7px] bg-[color-mix(in_srgb,var(--ink)_5.5%,transparent)] p-0.5"
          >
            <button
              type="button"
              role="tab"
              aria-selected={accountScope === 'all'}
              onClick={() => onSelectAccount('all')}
              className={`truncate rounded-[5px] px-1.5 py-1 text-[11.5px] ${
                accountScope === 'all'
                  ? 'bg-paper font-medium text-ink shadow-card'
                  : 'text-ink-3 hover:text-ink-2'
              }`}
            >
              全部
            </button>
            {accounts.map((acc) => {
              const active = accountScope === acc.id
              return (
                <button
                  key={acc.id}
                  type="button"
                  role="tab"
                  aria-selected={active}
                  title={acc.address}
                  onClick={() => onSelectAccount(acc.id)}
                  className={`flex items-center justify-center gap-1.5 truncate rounded-[5px] px-1.5 py-1 text-[11.5px] ${
                    active ? 'bg-paper font-medium text-ink shadow-card' : 'text-ink-3 hover:text-ink-2'
                  }`}
                >
                  <span
                    aria-hidden="true"
                    className="size-1.5 shrink-0 rounded-full"
                    style={{ backgroundColor: accountDotColor(acc.id) }}
                  />
                  <span className="truncate">{acc.label}</span>
                </button>
              )
            })}
          </div>
          {activeAccount && (
            <div className="mt-1 flex items-center gap-1.5 truncate px-1 text-[11px] text-ink-3" title={activeAccount.address}>
              <span
                aria-hidden="true"
                className="size-1.5 shrink-0 rounded-full"
                style={{ backgroundColor: accountDotColor(activeAccount.id) }}
              />
              <span className="truncate">{activeAccount.address}</span>
            </div>
          )}
        </div>
      )}

      {/* 搜索与命令入口 */}
      <div className="pt-2">
        <button
          type="button"
          onClick={onOpenPalette}
          className="flex h-7 w-full items-center gap-2 rounded-[6px] border border-line bg-paper/75 px-2 text-[12px] text-ink-3 transition-colors hover:border-line-strong hover:bg-paper hover:text-ink"
        >
          <Search className="size-3.5 shrink-0" strokeWidth={1.75} />
          <span className="flex-1 text-left">搜索与命令</span>
          <Kbd>⌘K</Kbd>
        </button>
      </div>

      {/* 分拣导航树 */}
      <nav className="scroll-thin min-h-0 flex-1 space-y-4 overflow-y-auto py-3.5">
        <div>
          <div className="px-2 pb-1 text-[10.5px] font-medium tracking-[0.04em] text-ink-3">待你拍板</div>
          <ul className="space-y-0.5">
            {triageFolders.map((def) => (
              <FolderItem
                key={def.id}
                def={def}
                count={counts[def.id]}
                active={folder === def.id}
                onClick={() => onSelectFolder(def.id)}
              />
            ))}
          </ul>
        </div>

        <div>
          <div className="px-2 pb-1 text-[10.5px] font-medium tracking-[0.04em] text-ink-3">已分拣</div>
          <ul className="space-y-0.5">
            {processedFolders.map((def) => (
              <FolderItem
                key={def.id}
                def={def}
                count={counts[def.id]}
                active={folder === def.id}
                onClick={() => onSelectFolder(def.id)}
              />
            ))}
          </ul>
        </div>
      </nav>

      {/* 底部极简状态与调试开关 */}
      <div className="flex h-7 shrink-0 items-center gap-1 px-1 text-[11px] text-ink-3">
        <span className="truncate" title={`今天自动处理了 ${handledTotal} 封通知与推广`}>
          已省 {savedMinutes(handledTotal)} 分钟
        </span>
        <div className="ml-auto flex items-center gap-0.5">
          {onSimulate && (
            <button
              type="button"
              onClick={onSimulate}
              title="模拟收到 3 封新邮件"
              aria-label="模拟收到 3 封新邮件"
              className="grid size-6 place-items-center rounded-md text-ink-3 transition-colors hover:bg-[color-mix(in_srgb,var(--ink)_6%,transparent)] hover:text-ink"
            >
              <MailPlus className="size-3.5" strokeWidth={1.75} />
            </button>
          )}
          {onReset && (
            <button
              type="button"
              onClick={onReset}
              title="重置演示数据"
              aria-label="重置演示数据"
              className="grid size-6 place-items-center rounded-md text-ink-3 transition-colors hover:bg-[color-mix(in_srgb,var(--ink)_6%,transparent)] hover:text-ink"
            >
              <RotateCcw className="size-3.5" strokeWidth={1.75} />
            </button>
          )}
          <button
            type="button"
            onClick={onToggleTheme}
            title={theme === 'dark' ? '切换到浅色模式' : '切换到深色模式'}
            aria-label="切换深浅色"
            className="grid size-6 place-items-center rounded-md text-ink-3 transition-colors hover:bg-[color-mix(in_srgb,var(--ink)_6%,transparent)] hover:text-ink"
          >
            {theme === 'dark' ? <Moon className="size-3.5" strokeWidth={1.75} /> : <Sun className="size-3.5" strokeWidth={1.75} />}
          </button>
        </div>
      </div>
    </aside>
  )
}

function FolderItem({
  def,
  count,
  active,
  onClick,
}: {
  def: FolderDef
  count: number
  active: boolean
  onClick: () => void
}) {
  return (
    <li>
      <button
        type="button"
        onClick={onClick}
        aria-current={active ? 'page' : undefined}
        title={def.shortcut ? `${def.label}（${def.shortcut}）` : def.label}
        className={`flex h-7 w-full items-center gap-2 rounded-[6px] pr-2 text-[12.5px] ${
          def.sub ? 'pl-4' : 'pl-2'
        } ${
          active
            ? 'bg-[color-mix(in_srgb,var(--ink)_7.5%,transparent)] font-medium text-ink'
            : 'text-ink-2 hover:bg-[color-mix(in_srgb,var(--ink)_4.5%,transparent)] hover:text-ink'
        }`}
      >
        <span
          className={
            def.id === 'kept' && (count > 0 || active)
              ? 'text-amber'
              : active
                ? 'text-ink'
                : 'text-ink-3'
          }
        >
          <FolderIcon def={def} />
        </span>
        <span className="min-w-0 flex-1 truncate text-left">{def.label}</span>
        <span
          className={`num text-[11px] ${
            count === 0 ? 'text-ink-3/40' : active || def.id === 'inbox' ? 'font-medium text-ink-2' : 'text-ink-3'
          }`}
        >
          {count}
        </span>
      </button>
    </li>
  )
}

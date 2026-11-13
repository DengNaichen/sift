import { Fragment } from 'react'
import { Kbd } from './Kbd'

export interface HudItem {
  keys: string[]
  label: string
  run: () => void
  disabled?: boolean
}

/**
 * 悬浮在阅读区底部中央的快捷键胶囊：
 * 保持全无彩色毛玻璃质感，既提供肌肉记忆提示与点击触发，又绝不遮挡左侧邮件列表。
 */
export function KeyboardHUD({ items }: { items: HudItem[] }) {
  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-4 z-20 hidden justify-center px-4 sm:flex">
      <div
        role="toolbar"
        aria-label="快捷键提示"
        className="pointer-events-auto flex items-center gap-0.5 rounded-full border border-line-strong bg-raised/88 px-2 py-1 shadow-float backdrop-blur-md"
      >
        {items.map((item, i) => (
          <Fragment key={item.label}>
            {i > 0 && <span className="mx-0.5 h-3 w-px bg-line" />}
            <button
              type="button"
              disabled={item.disabled}
              onClick={item.run}
              className="inline-flex items-center gap-1.5 rounded-full px-2 py-1 text-[11.5px] text-ink-2 transition-colors hover:bg-sunken hover:text-ink disabled:pointer-events-none disabled:opacity-38"
            >
              <span className="inline-flex items-center gap-0.5">
                {item.keys.map((k) => (
                  <Kbd key={k}>{k}</Kbd>
                ))}
              </span>
              <span>{item.label}</span>
            </button>
          </Fragment>
        ))}
      </div>
    </div>
  )
}

import { motion } from 'framer-motion'
import { Inbox, RotateCcw } from 'lucide-react'
import { useState } from 'react'
import { softSpring, spring } from '../lib/motion'
import type { Tally } from '../state/deck'
import { Kbd } from './Kbd'

interface Props {
  tally: Tally
  handledCount: number
  canUndo: boolean
  onSimulate?: () => Promise<void>
  onReset?: () => Promise<void>
}

export function InboxZero({ tally, handledCount, canUndo, onSimulate, onReset }: Props) {
  const [busy, setBusy] = useState<'sim' | 'reset' | null>(null)
  const run = (key: 'sim' | 'reset', fn?: () => Promise<void>) => async () => {
    if (!fn || busy) return
    setBusy(key)
    try {
      await fn()
    } finally {
      setBusy(null)
    }
  }
  const handled = tally.archived + tally.kept + tally.trashed
  const stats: Array<[string, number | string]> = [
    ['阅毕归档', tally.archived],
    ['重要保留', tally.kept],
    ['判为推广', tally.trashed],
    ['自动处理', handledCount],
  ]

  return (
    <motion.div
      initial={{ opacity: 0, y: 16, scale: 0.98 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={{ opacity: 0, y: -8, scale: 0.98 }}
      transition={softSpring}
      className="flex flex-col items-center rounded-xl bg-paper px-8 pt-14 pb-10 text-center shadow-card"
    >
      <motion.svg width="56" height="56" viewBox="0 0 56 56" fill="none" className="text-sage">
        <motion.circle
          cx="28"
          cy="28"
          r="26"
          stroke="currentColor"
          strokeOpacity="0.32"
          strokeWidth="1.5"
          initial={{ pathLength: 0 }}
          animate={{ pathLength: 1 }}
          transition={{ duration: 0.5, ease: [0.2, 0, 0, 1] }}
        />
        <motion.path
          d="M18 28.5 L25 35.5 L38.5 21"
          stroke="currentColor"
          strokeWidth="2.25"
          strokeLinecap="round"
          strokeLinejoin="round"
          initial={{ pathLength: 0 }}
          animate={{ pathLength: 1 }}
          transition={{ duration: 0.35, delay: 0.3, ease: [0.2, 0, 0, 1] }}
        />
      </motion.svg>

      <h2 className="mt-6 text-[22px] font-semibold tracking-tight">收件箱已清零</h2>
      <p className="mt-2 max-w-sm text-[13.5px] leading-relaxed text-ink-3">
        {handled > 0 ? (
          <>
            今天你亲自处理了 <span className="num text-ink-2">{handled}</span> 件事，其余的噪音都没有打扰到你。
          </>
        ) : (
          '没有需要你处理的事。去做点更重要的事吧。'
        )}
      </p>

      <dl className="mt-8 grid w-full max-w-md grid-cols-4 overflow-hidden rounded-xl border border-line">
        {stats.map(([label, value], i) => (
          <motion.div
            key={label}
            initial={{ opacity: 0, y: 6 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ ...spring, delay: 0.35 + i * 0.04 }}
            className={`px-3 py-3.5 ${i < stats.length - 1 ? 'border-r border-line' : ''}`}
          >
            <dt className="text-[11.5px] text-ink-3">{label}</dt>
            <dd className="num mt-1 text-[17px] font-medium text-ink">{value}</dd>
          </motion.div>
        ))}
      </dl>

      <div className="mt-8 flex flex-wrap items-center justify-center gap-2">
        {onSimulate && (
          <button
            type="button"
            onClick={run('sim', onSimulate)}
            disabled={busy !== null}
            className="inline-flex items-center gap-2 rounded-lg bg-ink px-3.5 py-2 text-[13px] font-medium text-canvas transition-opacity hover:opacity-90 disabled:opacity-60"
          >
            <Inbox className="size-4" />
            {busy === 'sim' ? '正在投递…' : '模拟收到 3 封新邮件'}
          </button>
        )}
        {onReset && (
          <button
            type="button"
            onClick={run('reset', onReset)}
            disabled={busy !== null}
            className="inline-flex items-center gap-2 rounded-lg border border-line-strong px-3.5 py-2 text-[13px] text-ink-2 transition-colors hover:bg-sunken hover:text-ink disabled:opacity-60"
          >
            <RotateCcw className="size-3.5" />
            {busy === 'reset' ? '正在重置…' : '重置演示数据'}
          </button>
        )}
      </div>
      {canUndo && (
        <p className="mt-5 flex items-center gap-1.5 text-[12px] text-ink-3">
          手滑了？按 <Kbd>Z</Kbd> 把上一张卡片拿回来
        </p>
      )}
    </motion.div>
  )
}

import { AnimatePresence, motion } from 'framer-motion'
import { ArrowUpRight } from 'lucide-react'
import { useEffect } from 'react'
import { quick, spring } from '../lib/motion'

export interface Notice {
  seq: number
  url: string
}

/** 原型中代替系统跳转：展示 `message://` 的调用效果 */
export function NativeNotice({ notice, onDone }: { notice: Notice | null; onDone: () => void }) {
  useEffect(() => {
    if (!notice) return
    const t = setTimeout(onDone, 2600)
    return () => clearTimeout(t)
  }, [notice, onDone])

  return (
    <div className="pointer-events-none fixed inset-x-0 top-4 z-[60] flex justify-center">
      <AnimatePresence>
        {notice && (
          <motion.div
            key={notice.seq}
            initial={{ opacity: 0, y: -14, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -10, transition: quick }}
            transition={spring}
            className="pointer-events-auto flex max-w-[min(640px,calc(100vw-32px))] items-center gap-3 rounded-xl bg-raised/95 py-2.5 pr-4 pl-3 shadow-float backdrop-blur"
          >
            <span className="grid size-7 shrink-0 place-items-center rounded-lg bg-sunken text-ink-2">
              <ArrowUpRight className="size-4" />
            </span>
            <div className="min-w-0">
              <div className="text-[12.5px] font-medium text-ink">正在 Apple Mail 中打开原信</div>
              <div className="num truncate text-[11.5px] text-ink-3">{decodeURIComponent(notice.url)}</div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}

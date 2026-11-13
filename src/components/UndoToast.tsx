import { AnimatePresence, motion } from 'framer-motion'
import { Check, Undo2 } from 'lucide-react'
import { useEffect } from 'react'
import { quick, spring } from '../lib/motion'
import { describeEntry, type Toast } from '../state/deck'
import { Kbd } from './Kbd'

const DONE_MS = 5000
const UNDONE_MS = 1600

export function UndoToast({ toast, onUndo, onExpire }: { toast: Toast | null; onUndo: () => void; onExpire: (seq: number) => void }) {
  useEffect(() => {
    if (!toast) return
    const t = setTimeout(() => onExpire(toast.seq), toast.kind === 'done' ? DONE_MS : UNDONE_MS)
    return () => clearTimeout(t)
  }, [toast, onExpire])

  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-16 z-30 flex justify-center px-4">
      <AnimatePresence mode="popLayout">
        {toast && (
          <motion.div
            key={toast.seq}
            layout
            initial={{ opacity: 0, y: 12, scale: 0.97 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 6, scale: 0.98, transition: quick }}
            transition={spring}
            className="pointer-events-auto relative flex w-[360px] max-w-full items-center gap-3 overflow-hidden rounded-xl border border-line-strong bg-raised/95 py-2 pr-2 pl-3.5 text-[12.5px] text-ink shadow-float backdrop-blur-md"
          >
            {toast.kind === 'done' ? (
              <>
                <span className="min-w-0 flex-1 truncate text-ink-2">{describeEntry(toast.entry)}</span>
                <button
                  type="button"
                  onClick={onUndo}
                  className="flex shrink-0 items-center gap-1.5 rounded-lg px-2 py-1 font-medium text-ink transition-colors hover:bg-sunken"
                >
                  <Undo2 className="size-3.5 text-ink-2" />
                  撤销
                  <Kbd>Z</Kbd>
                </button>
                <motion.span
                  className="absolute bottom-0 left-0 h-[1.5px] bg-ink/20"
                  initial={{ width: '100%' }}
                  animate={{ width: '0%' }}
                  transition={{ duration: DONE_MS / 1000, ease: 'linear' }}
                />
              </>
            ) : (
              <span className="flex items-center gap-2 py-0.5 text-ink-2">
                <Check className="size-3.5 text-ink" strokeWidth={2.4} />
                已撤销，邮件已放回原位
              </span>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  )
}

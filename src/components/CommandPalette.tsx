import { AnimatePresence, motion } from 'framer-motion'
import { CornerDownLeft, Search, type LucideIcon } from 'lucide-react'
import { useEffect, useMemo, useRef, useState } from 'react'
import { quick, spring } from '../lib/motion'
import { Kbd } from './Kbd'

export interface Command {
  id: string
  group: string
  title: string
  subtitle?: string
  keywords?: string
  kbd?: string
  icon: LucideIcon
  run: () => void
}

interface Props {
  open: boolean
  commands: Command[]
  onClose: () => void
}

export function CommandPalette({ open, commands, onClose }: Props) {
  return (
    <AnimatePresence>
      {open && (
        <>
          <motion.div
            key="scrim"
            className="fixed inset-0 z-[70] bg-[rgb(20_19_17/0.22)] backdrop-blur-[3px] dark:bg-black/50"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={quick}
            onClick={onClose}
          />
          <Panel key="panel" commands={commands} onClose={onClose} />
        </>
      )}
    </AnimatePresence>
  )
}

function Panel({ commands, onClose }: Omit<Props, 'open'>) {
  const [query, setQuery] = useState('')
  const [active, setActive] = useState(0)
  const listRef = useRef<HTMLUListElement>(null)

  const results = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return commands
    return commands.filter((c) => `${c.title} ${c.subtitle ?? ''} ${c.keywords ?? ''} ${c.group}`.toLowerCase().includes(q))
  }, [commands, query])

  useEffect(() => setActive(0), [query])

  useEffect(() => {
    listRef.current?.querySelector(`[data-index="${active}"]`)?.scrollIntoView({ block: 'nearest' })
  }, [active])

  const run = (c: Command | undefined) => {
    if (!c) return
    onClose()
    c.run()
  }

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown' || (e.ctrlKey && e.key === 'n')) {
      e.preventDefault()
      setActive((i) => Math.min(results.length - 1, i + 1))
    } else if (e.key === 'ArrowUp' || (e.ctrlKey && e.key === 'p')) {
      e.preventDefault()
      setActive((i) => Math.max(0, i - 1))
    } else if (e.key === 'Enter' && !e.nativeEvent.isComposing) {
      e.preventDefault()
      run(results[active])
    } else if (e.key === 'Escape') {
      e.preventDefault()
      onClose()
    }
  }

  let lastGroup = ''
  return (
    <motion.div
      role="dialog"
      aria-label="命令搜索"
      className="fixed top-[14vh] left-1/2 z-[80] w-[600px] max-w-[calc(100vw-32px)] -translate-x-1/2 overflow-hidden rounded-xl bg-paper shadow-float"
      initial={{ opacity: 0, scale: 0.97, y: -8 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      exit={{ opacity: 0, scale: 0.98, y: -4, transition: quick }}
      transition={spring}
      onKeyDown={onKeyDown}
    >
      <div className="flex items-center gap-3 border-b border-line px-4">
        <Search className="size-4 text-ink-3" />
        <input
          autoFocus
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="搜索邮件或输入命令…"
          className="h-13 flex-1 bg-transparent text-[14.5px] text-ink outline-none placeholder:text-ink-3"
        />
        <Kbd>esc</Kbd>
      </div>
      <ul ref={listRef} className="scroll-thin max-h-[52vh] overflow-y-auto p-1.5">
        {results.map((c, i) => {
          const header = c.group !== lastGroup ? c.group : null
          lastGroup = c.group
          const Icon = c.icon
          return (
            <li key={c.id}>
              {header && <div className="px-2.5 pt-2.5 pb-1 text-[11px] font-medium tracking-[0.04em] text-ink-3">{header}</div>}
              <button
                type="button"
                data-index={i}
                onMouseMove={() => setActive(i)}
                onClick={() => run(c)}
                className={`relative flex w-full items-center gap-3 rounded-lg px-2.5 py-2 text-left text-[13.5px] transition-colors ${
                  i === active ? 'text-ink' : 'text-ink-2'
                }`}
              >
                {i === active && (
                  <motion.span
                    layoutId="palette-active"
                    className="absolute inset-0 rounded-lg bg-sunken"
                    transition={spring}
                  />
                )}
                <Icon className="relative size-4 shrink-0 text-ink-3" />
                <span className="relative min-w-0 flex-1 truncate">
                  {c.title}
                  {c.subtitle && <span className="ml-2 text-[12px] text-ink-3">{c.subtitle}</span>}
                </span>
                {c.kbd && (
                  <span className="relative">
                    <Kbd>{c.kbd}</Kbd>
                  </span>
                )}
                {i === active && !c.kbd && <CornerDownLeft className="relative size-3.5 text-ink-3" />}
              </button>
            </li>
          )
        })}
        {results.length === 0 && <li className="px-3 py-10 text-center text-[13px] text-ink-3">没有匹配「{query}」的邮件或命令</li>}
      </ul>
    </motion.div>
  )
}

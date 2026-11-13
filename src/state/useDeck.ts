import { useCallback, useEffect, useMemo, useReducer, useRef } from 'react'
import { hasDemoControls, type MailAdapter, type MessageId } from '../adapter/mailAdapter'
import { deckReducer, initialDeck, type CardAction } from './deck'

/** 把 reducer（界面状态）和 MailAdapter（数据源）接起来。界面先乐观更新，再同步到 adapter。 */
export function useDeck(adapter: MailAdapter) {
  const [state, dispatch] = useReducer(deckReducer, initialDeck)
  const ref = useRef(state)
  ref.current = state
  const rescuing = useRef(new Set<MessageId>())

  const sync = useCallback((p: Promise<unknown>) => {
    p.catch((err: unknown) => console.error('[MailAdapter]', err))
  }, [])

  const load = useCallback(async () => {
    dispatch({ type: 'loaded', snapshot: await adapter.fetchDeck() })
  }, [adapter])

  useEffect(() => {
    void load()
  }, [load])

  const actOnCard = useCallback(
    (action: CardAction, id = ref.current.focusId) => {
      if (!id || !ref.current.queue.some((m) => m.id === id)) return
      dispatch({ type: 'card', id, action, now: new Date().toISOString() })
      sync(
        action === 'archive'
          ? adapter.archive(id)
          : action === 'keep'
            ? adapter.flagImportant(id)
            : adapter.moveToTrash(id, 'user-promo'),
      )
    },
    [adapter, sync],
  )

  const rescue = useCallback(
    async (id: MessageId) => {
      if (rescuing.current.has(id)) return
      rescuing.current.add(id)
      try {
        dispatch({ type: 'rescued', mail: await adapter.rescue(id) })
      } finally {
        rescuing.current.delete(id)
      }
    },
    [adapter],
  )

  const undo = useCallback(() => {
    const entry = ref.current.undo.at(-1)
    if (!entry) return false
    dispatch({ type: 'undo' })
    if (entry.kind === 'card') sync(adapter.restore(entry.mail.id))
    else if (entry.item.disposition === 'archived') sync(adapter.archive(entry.mail.id))
    else sync(adapter.moveToTrash(entry.mail.id, entry.item.manual ? 'user-promo' : 'auto-promo'))
    return true
  }, [adapter, sync])

  const openNative = useCallback(
    (id = ref.current.focusId) => (id ? adapter.openInNativeMail(id) : Promise.resolve(null)),
    [adapter],
  )

  const demo = useMemo(() => {
    if (!hasDemoControls(adapter)) return null
    return {
      simulateIncoming: async (count: number) => {
        dispatch({ type: 'incoming', mails: await adapter.simulateIncoming(count) })
      },
      reset: async () => {
        await adapter.reset()
        await load()
      },
    }
  }, [adapter, load])

  return { state, dispatch, actOnCard, rescue, undo, openNative, demo }
}

export type Deck = ReturnType<typeof useDeck>

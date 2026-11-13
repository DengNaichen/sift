import type { CSSProperties } from 'react'
import type { DecisionKind } from '../adapter/mailAdapter'

const ACCENT_PALETTE = ['var(--cobalt)', 'var(--sage)', 'var(--amber)', 'var(--coral)'] as const

const hashString = (input: string): number => {
  let h = 0
  for (let i = 0; i < input.length; i += 1) {
    h = (h * 31 + input.charCodeAt(i)) | 0
  }
  return Math.abs(h)
}

const pickTone = (seed: string): string =>
  ACCENT_PALETTE[hashString(seed) % ACCENT_PALETTE.length] ?? 'var(--cobalt)'

/** 邮箱身份小圆点色：工作=钴蓝，个人=鼠尾草绿，其余账户稳定哈希分配 */
export function accountDotColor(accountId: string): string {
  if (accountId === 'work') return 'var(--cobalt)'
  if (accountId === 'personal') return 'var(--sage)'
  return pickTone(accountId)
}

/** 决策类别点缀色：匹配 DecisionKind 语义，保持克制低饱和 */
const KIND_COLOR: Record<DecisionKind, string> = {
  human: 'var(--cobalt)',
  contract: 'var(--amber)',
  policy: 'var(--amber)',
  billing: 'var(--coral)',
  uncertain: 'var(--amber)',
  rescued: 'var(--sage)',
}

export const kindDotColor = (kind: DecisionKind): string => KIND_COLOR[kind]

/** 极克制的纸本浅色调头像底色，自适应浅/深色模式 */
export function avatarTintStyle(seed: string): CSSProperties {
  const tone = pickTone(seed)
  return {
    backgroundColor: `color-mix(in srgb, ${tone} 11%, var(--sunken))`,
    borderColor: `color-mix(in srgb, ${tone} 24%, transparent)`,
    color: `color-mix(in srgb, ${tone} 72%, var(--ink))`,
  }
}

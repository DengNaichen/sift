import type { ReactNode } from 'react'

export function Kbd({ children, tone = 'default' }: { children: ReactNode; tone?: 'default' | 'inverse' }) {
  // 等宽字体里的 O 容易被看成 0，单个字母键改用无衬线
  const letter = typeof children === 'string' && /^[A-Z]$/.test(children)
  return (
    <kbd
      className={`${letter ? 'font-sans' : 'num'} inline-flex h-[18px] min-w-[18px] items-center justify-center rounded-[5px] px-1 text-[10.5px] leading-none font-medium ${
        tone === 'inverse'
          ? 'bg-[color-mix(in_srgb,var(--canvas)_18%,transparent)] text-current opacity-80'
          : 'bg-[color-mix(in_srgb,var(--ink)_6%,transparent)] text-ink-3'
      }`}
    >
      {children}
    </kbd>
  )
}

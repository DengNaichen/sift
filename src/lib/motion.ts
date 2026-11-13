import type { Transition } from 'framer-motion'

/** 统一的物理弹簧：约 180ms 落定，轻微过冲 */
export const spring: Transition = { type: 'spring', stiffness: 560, damping: 42, mass: 0.8 }
export const softSpring: Transition = { type: 'spring', stiffness: 380, damping: 36, mass: 0.9 }
export const quick: Transition = { duration: 0.16, ease: [0.2, 0, 0, 1] }

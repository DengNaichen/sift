
const pad = (n: number) => String(n).padStart(2, '0')
const hm = (d: Date) => `${pad(d.getHours())}:${pad(d.getMinutes())}`
const dayStart = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()

/** 今天 → `08:42`；昨天 → `昨天 22:10`；更早 → `11月9日` */
export function formatTime(iso: string, now = new Date()): string {
  const d = new Date(iso)
  const days = Math.round((dayStart(now) - dayStart(d)) / 86_400_000)
  if (days <= 0) return hm(d)
  if (days === 1) return `昨天 ${hm(d)}`
  return `${d.getMonth() + 1}月${d.getDate()}日`
}

export function formatRelative(iso: string, now = Date.now()): string {
  const min = Math.round((now - new Date(iso).getTime()) / 60_000)
  if (min < 1) return '刚刚'
  if (min < 60) return `${min} 分钟前`
  const h = Math.floor(min / 60)
  return h < 24 ? `${h} 小时前` : formatTime(iso)
}

export function formatDate(iso: string): string {
  const d = new Date(iso)
  return `${d.getMonth() + 1}月${d.getDate()}日`
}

/** 按每封 30 秒的平均处理时长折算的节省时间（演示口径） */
export const savedMinutes = (count: number) => Math.round((count * 30) / 60)

export const formatPercent = (p: number) => `${Math.round(p * 100)}%`

const WEEKDAYS = ['日', '一', '二', '三', '四', '五', '六']

export function briefingHeading(now = new Date()) {
  const h = now.getHours()
  const greeting = h < 5 ? '夜深了' : h < 11 ? '早上好' : h < 13 ? '中午好' : h < 18 ? '下午好' : '晚上好'
  return { greeting, date: `${now.getMonth() + 1}月${now.getDate()}日 · 星期${WEEKDAYS[now.getDay()]}` }
}

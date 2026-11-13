import type { MailItem } from '../adapter/mailAdapter'

/** 只有逐字出现在原文里的 evidence 才算数；否则视为没有 */
export function evidenceOf(mail: MailItem): string | undefined {
  const ev = mail.meta.evidence?.trim()
  return ev && mail.plainText.includes(ev) ? ev : undefined
}

/** 正文开头的原文片段：跳过「您好，」这类称呼行，合并空白，不做任何改写 */
export function openingLines(plainText: string, max = 140): string {
  const lines = plainText.split('\n').map((l) => l.trim()).filter(Boolean)
  const body = lines[0] && lines[0].length <= 8 && /[，,:：]$/.test(lines[0]) ? lines.slice(1) : lines
  const text = body.join(' ').replace(/\s+/g, ' ')
  return text.length > max ? `${text.slice(0, max)}…` : text
}

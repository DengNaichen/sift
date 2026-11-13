import { FileText, Paperclip } from 'lucide-react'
import type { Attachment, MailItem } from '../adapter/mailAdapter'
import { kindDotColor } from '../lib/accents'
import { formatPercent } from '../lib/format'

/**
 * 分类器输出（Linear 风格层级）：
 * 高确信度用实心浅灰底标签，低于 90% 用虚线描边提示「待人拍板」，左侧附 6px 语义小圆点。
 */
export function KindBadge({ mail }: { mail: MailItem }) {
  const { kind, badge, confidence, intent } = mail.meta
  const uncertain = confidence < 0.9
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-[5px] px-2 py-[3px] text-[11.5px] leading-none text-ink-2 ${
        uncertain ? 'border border-dashed border-line-strong' : 'bg-sunken'
      }`}
    >
      <span
        aria-hidden="true"
        className="size-1.5 shrink-0 rounded-full"
        style={{ backgroundColor: kindDotColor(kind) }}
      />
      {intent && <span className="font-medium text-ink">{intent}</span>}
      {intent && <span className="text-ink-3">·</span>}
      <span>{badge}</span>
      {uncertain && (
        <span className="text-ink-3">
          · 确信度 <span className="num">{formatPercent(confidence)}</span>
        </span>
      )}
    </span>
  )
}

export function AttachmentChips({ attachments }: { attachments: Attachment[] }) {
  if (attachments.length === 0) return null
  return (
    <div className="flex flex-wrap gap-1.5">
      {attachments.map((a) => (
        <span
          key={a.name}
          className="inline-flex items-center gap-1.5 rounded-md border border-line bg-sunken/60 px-2.5 py-1 text-[12px] text-ink-2"
        >
          {a.kind === 'pdf' ? <FileText className="size-3.5 text-ink-3" /> : <Paperclip className="size-3.5 text-ink-3" />}
          <span>{a.name}</span>
          <span className="num text-[10.5px] text-ink-3">{a.size}</span>
        </span>
      ))}
    </div>
  )
}

/** 原文。若有触发判定的原句 evidence，用单一克制的纸本暖色荧光标亮 */
export function PlainText({ text, highlight, className = '' }: { text: string; highlight?: string; className?: string }) {
  const at = highlight ? text.indexOf(highlight) : -1
  return (
    <pre className={`selectable font-sans text-[13.5px] leading-[1.8] whitespace-pre-wrap text-ink-2 ${className}`}>
      {at < 0 || !highlight ? (
        text
      ) : (
        <>
          {text.slice(0, at)}
          <mark
            data-evidence
            className="rounded-[3px] bg-[color-mix(in_srgb,var(--amber)_15%,transparent)] px-1 py-0.5 text-ink"
          >
            {highlight}
          </mark>
          {text.slice(at + highlight.length)}
        </>
      )}
    </pre>
  )
}

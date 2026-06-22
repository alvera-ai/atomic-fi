import {
  useState,
  type ButtonHTMLAttributes,
  type InputHTMLAttributes,
  type ReactNode,
} from 'react'
import * as RSelect from '@radix-ui/react-select'
import { Check, ChevronDown, Copy } from 'lucide-react'
import { cn } from '@/lib/cn'

const inputBase =
  'w-full rounded-md border border-line bg-panel/70 px-3 py-2 text-sm text-ink ' +
  'placeholder:text-ink-faint transition-colors hover:border-line-strong ' +
  'focus:border-accent/70 focus:bg-panel focus-visible:outline-none'

/* ── Field wrapper ─────────────────────────────────────────────────────── */
export function Field({
  label,
  hint,
  htmlFor,
  children,
}: {
  label: string
  hint?: string
  htmlFor?: string
  children: ReactNode
}) {
  return (
    <label htmlFor={htmlFor} className="flex flex-col gap-1.5">
      <span className="text-[0.7rem] font-medium uppercase tracking-[0.08em] text-ink-faint">
        {label}
      </span>
      {children}
      {hint ? <span className="text-xs text-ink-faint">{hint}</span> : null}
    </label>
  )
}

/* ── Text / number input ───────────────────────────────────────────────── */
export function TextInput({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return <input className={cn(inputBase, className)} {...props} />
}

/* ── Select (Radix) ────────────────────────────────────────────────────── */
export interface Option {
  value: string
  label: string
}

export function Select({
  value,
  onValueChange,
  options,
  placeholder,
  id,
}: {
  value: string
  onValueChange: (v: string) => void
  options: Option[]
  placeholder?: string
  id?: string
}) {
  return (
    <RSelect.Root value={value || undefined} onValueChange={onValueChange}>
      <RSelect.Trigger
        id={id}
        className={cn(inputBase, 'flex items-center justify-between gap-2 text-left')}
      >
        <RSelect.Value placeholder={placeholder} />
        <RSelect.Icon>
          <ChevronDown className="size-4 text-ink-faint" />
        </RSelect.Icon>
      </RSelect.Trigger>
      <RSelect.Portal>
        <RSelect.Content
          position="popper"
          sideOffset={6}
          className="z-50 overflow-hidden rounded-lg border border-line-strong bg-raised shadow-2xl shadow-black/50"
        >
          <RSelect.Viewport className="p-1">
            {options.map((opt) => (
              <RSelect.Item
                key={opt.value}
                value={opt.value}
                className="flex cursor-pointer items-center justify-between gap-3 rounded-md px-2.5 py-1.5 text-sm text-ink-muted outline-none data-[highlighted]:bg-panel data-[highlighted]:text-ink"
              >
                <RSelect.ItemText>{opt.label}</RSelect.ItemText>
                <RSelect.ItemIndicator>
                  <Check className="size-3.5 text-accent" />
                </RSelect.ItemIndicator>
              </RSelect.Item>
            ))}
          </RSelect.Viewport>
        </RSelect.Content>
      </RSelect.Portal>
    </RSelect.Root>
  )
}

/* ── Segmented control ─────────────────────────────────────────────────── */
export function Segmented({
  value,
  onChange,
  options,
}: {
  value: string
  onChange: (v: string) => void
  options: Option[]
}) {
  return (
    <div className="inline-flex rounded-md border border-line bg-panel/60 p-0.5">
      {options.map((opt) => {
        const active = opt.value === value
        return (
          <button
            key={opt.value}
            type="button"
            onClick={() => onChange(opt.value)}
            className={cn(
              'rounded-[5px] px-3 py-1.5 text-sm font-medium transition-colors',
              active ? 'bg-raised text-ink shadow-sm shadow-black/30' : 'text-ink-faint hover:text-ink-muted',
            )}
          >
            {opt.label}
          </button>
        )
      })}
    </div>
  )
}

/* ── Toggle ────────────────────────────────────────────────────────────── */
export function Toggle({
  checked,
  onChange,
  label,
}: {
  checked: boolean
  onChange: (v: boolean) => void
  label: string
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      className="flex items-center gap-2.5 text-sm text-ink-muted"
    >
      <span
        className={cn(
          'relative h-5 w-9 rounded-full border transition-colors',
          checked ? 'border-accent/50 bg-accent/25' : 'border-line bg-panel',
        )}
      >
        <span
          className={cn(
            'absolute top-0.5 size-3.5 rounded-full transition-all',
            checked ? 'left-[1.1rem] bg-accent' : 'left-0.5 bg-ink-faint',
          )}
        />
      </span>
      {label}
    </button>
  )
}

/* ── Button ────────────────────────────────────────────────────────────── */
type Variant = 'primary' | 'ghost' | 'subtle'
const variants: Record<Variant, string> = {
  primary:
    'bg-ink text-canvas hover:bg-ink/90 disabled:bg-line-strong disabled:text-ink-faint',
  ghost: 'text-ink-muted hover:bg-panel hover:text-ink',
  subtle: 'border border-line bg-panel/60 text-ink-muted hover:border-line-strong hover:text-ink',
}

export function Button({
  variant = 'primary',
  className,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant }) {
  return (
    <button
      className={cn(
        'inline-flex items-center justify-center gap-2 rounded-md px-4 py-2 text-sm font-semibold transition-colors disabled:cursor-not-allowed',
        variants[variant],
        className,
      )}
      {...props}
    />
  )
}

/* ── Disclosure ────────────────────────────────────────────────────────── */
export function Disclosure({ summary, children }: { summary: string; children: ReactNode }) {
  const [open, setOpen] = useState(false)
  return (
    <div className="rounded-md border border-line bg-panel/40">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="flex w-full items-center gap-2 px-3 py-2 text-xs font-medium uppercase tracking-[0.08em] text-ink-faint hover:text-ink-muted"
      >
        <ChevronDown className={cn('size-3.5 transition-transform', open && 'rotate-180')} />
        {summary}
      </button>
      {open ? <div className="border-t border-line p-3">{children}</div> : null}
    </div>
  )
}

/* ── JSON block ────────────────────────────────────────────────────────── */
export function JsonBlock({ value }: { value: unknown }) {
  const text = typeof value === 'string' ? value : JSON.stringify(value, null, 2)
  return (
    <div className="relative">
      <pre className="max-h-80 overflow-auto rounded bg-canvas/60 p-3 font-mono text-xs leading-relaxed text-ink-muted">
        {text}
      </pre>
      <CopyButton text={text} className="absolute right-2.5 top-2.5" />
    </div>
  )
}

/* ── Copy button ───────────────────────────────────────────────────────── */
export function CopyButton({ text, className }: { text: string; className?: string }) {
  const [copied, setCopied] = useState(false)
  return (
    <button
      type="button"
      onClick={() => {
        void navigator.clipboard.writeText(text)
        setCopied(true)
        window.setTimeout(() => setCopied(false), 1200)
      }}
      className={cn(
        'inline-flex items-center gap-1.5 text-xs text-ink-faint transition-colors hover:text-ink-muted',
        className,
      )}
    >
      {copied ? <Check className="size-3.5 text-ok" /> : <Copy className="size-3.5" />}
      {copied ? 'Copied' : 'Copy'}
    </button>
  )
}

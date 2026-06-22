import { Building2, ScanSearch, Settings, UserRound, Users, Wallet, type LucideIcon } from 'lucide-react'
import { cn } from '@/lib/cn'
import { SCREENER_META, type ScreenerId } from '@/lib/screeners'

export type View = ScreenerId | 'settings'

const ICONS: Record<ScreenerId, LucideIcon> = {
  'account-holder': UserRound,
  'beneficial-owner': Users,
  counterparty: Building2,
  'payment-account': Wallet,
}

const ORDER: ScreenerId[] = ['account-holder', 'beneficial-owner', 'counterparty', 'payment-account']

function NavItem({ icon: Icon, label, active, onClick }: { icon: LucideIcon; label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-current={active}
      className={cn(
        'flex w-full items-center gap-3 rounded-lg px-3 py-2 text-sm transition-colors',
        active ? 'bg-panel font-medium text-ink' : 'text-ink-faint hover:bg-panel/50 hover:text-ink-muted',
      )}
    >
      <Icon className={cn('size-4 shrink-0', active && 'text-accent')} strokeWidth={1.75} />
      <span className="truncate">{label}</span>
    </button>
  )
}

export function Sidebar({ view, onSelect }: { view: View; onSelect: (v: View) => void }) {
  return (
    <aside className="flex w-60 shrink-0 flex-col border-r border-line bg-canvas/80">
      <div className="flex items-center gap-2.5 px-5 py-5">
        <ScanSearch className="size-5 text-accent" strokeWidth={1.75} />
        <div className="leading-tight">
          <div className="font-display text-sm font-semibold tracking-tight text-ink">Payments Screening</div>
          <div className="text-[0.7rem] uppercase tracking-[0.12em] text-ink-faint">atomic-fi</div>
        </div>
      </div>

      <nav className="flex flex-1 flex-col gap-1 px-3 pt-2">
        <div className="px-3 pb-1.5 text-[0.65rem] font-semibold uppercase tracking-[0.12em] text-ink-faint">
          Stateless previews
        </div>
        {ORDER.map((id) => (
          <NavItem key={id} icon={ICONS[id]} label={SCREENER_META[id].label} active={view === id} onClick={() => onSelect(id)} />
        ))}
      </nav>

      <div className="px-3 pb-4">
        <NavItem icon={Settings} label="Settings" active={view === 'settings'} onClick={() => onSelect('settings')} />
      </div>
    </aside>
  )
}

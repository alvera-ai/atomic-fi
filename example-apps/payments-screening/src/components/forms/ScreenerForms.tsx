import { useState, type ReactNode } from 'react'
import { ArrowRight, Loader2 } from 'lucide-react'
import { Button, Disclosure, Field, JsonBlock, Segmented, Select, TextInput, Toggle, type Option } from '@/components/ui'
import { ToneDot } from '@/components/status'
import { useConfig } from '@/lib/config'
import { titleCase } from '@/lib/screening'
import {
  ACCOUNT_HOLDER_PRESETS,
  ACCOUNT_HOLDER_TYPES,
  ACCOUNT_TYPES,
  BENEFICIAL_OWNER_PRESETS,
  buildAccountHolder,
  buildBeneficialOwner,
  buildCounterparty,
  buildPaymentAccount,
  CONTROL_TYPES,
  COUNTERPARTY_PRESETS,
  COUNTERPARTY_STATUSES,
  PAYMENT_ACCOUNT_PRESETS,
  RISK_LEVELS,
  newParty,
  type AccountHolderForm,
  type BeneficialOwnerForm,
  type CounterpartyForm,
  type Party,
  type PaymentAccountForm,
  type Preset,
} from '@/lib/screeners'
import type { FormProps } from './types'

const opts = (values: string[]): Option[] => values.map((v) => ({ value: v, label: titleCase(v) }))

/** Tenant id (injected into every payload) plus a reason to block submit. */
function useScreenerGate() {
  const { tenantId, tenantState } = useConfig()
  const blockedReason =
    tenantState === 'resolving'
      ? 'Resolving tenant…'
      : tenantState === 'error'
        ? 'No tenant resolved — set a valid API key in Settings'
        : undefined
  return { tenantId, blockedReason }
}

/* ── Shared scaffolding ────────────────────────────────────────────────── */
function PresetBar<F>({ presets, onApply }: { presets: Preset<F>[]; onApply: (f: F) => void }) {
  return (
    <div className="flex flex-wrap items-center gap-2">
      <span className="mr-1 text-[0.7rem] font-medium uppercase tracking-[0.08em] text-ink-faint">Presets</span>
      {presets.map((p) => (
        <button
          key={p.name}
          type="button"
          onClick={() => onApply(structuredClone(p.form))}
          className="inline-flex items-center gap-1.5 rounded-full border border-line bg-panel/60 px-3 py-1 text-xs text-ink-muted transition-colors hover:border-line-strong hover:text-ink"
        >
          <ToneDot tone={p.tone} />
          {p.name}
        </button>
      ))}
    </div>
  )
}

function FormLayout<F>({
  presets,
  onApply,
  payload,
  onSubmit,
  busy,
  blockedReason,
  children,
}: {
  presets: Preset<F>[]
  onApply: (f: F) => void
  payload: unknown
  onSubmit: () => void
  busy: boolean
  blockedReason?: string
  children: ReactNode
}) {
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        if (!blockedReason) onSubmit()
      }}
      className="flex flex-col gap-6"
    >
      <PresetBar presets={presets} onApply={onApply} />
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">{children}</div>
      <Disclosure summary="Advanced — request payload">
        <JsonBlock value={payload} />
      </Disclosure>
      <div className="flex items-center justify-end gap-3">
        {blockedReason ? <span className="text-xs text-ink-faint">{blockedReason}</span> : null}
        <Button type="submit" disabled={busy || !!blockedReason} className="min-w-44">
          {busy ? (
            <>
              <Loader2 className="size-4 animate-spin" /> Screening…
            </>
          ) : (
            <>
              Run screening <ArrowRight className="size-4" />
            </>
          )}
        </Button>
      </div>
    </form>
  )
}

function PartyFields({ value, onChange }: { value: Party; onChange: (p: Party) => void }) {
  const set = (patch: Partial<Party>) => onChange({ ...value, ...patch })
  return (
    <>
      <div className="sm:col-span-2">
        <Field label="Entity kind">
          <Segmented
            value={value.kind}
            onChange={(k) => onChange(newParty({ ...value, kind: k as Party['kind'] }))}
            options={[
              { value: 'individual', label: 'Individual' },
              { value: 'business', label: 'Business' },
            ]}
          />
        </Field>
      </div>

      {value.kind === 'individual' ? (
        <>
          <Field label="First name">
            <TextInput value={value.firstName} onChange={(e) => set({ firstName: e.target.value })} placeholder="Vladimir" />
          </Field>
          <Field label="Last name">
            <TextInput value={value.lastName} onChange={(e) => set({ lastName: e.target.value })} placeholder="Putin" />
          </Field>
          <Field label="Middle name (optional)">
            <TextInput value={value.middleName} onChange={(e) => set({ middleName: e.target.value })} />
          </Field>
          <Field label="Date of birth">
            <TextInput type="date" value={value.dob} onChange={(e) => set({ dob: e.target.value })} />
          </Field>
          <Field label="Citizenship" hint="ISO 3166-1 alpha-2">
            <TextInput
              list="country-codes"
              value={value.country}
              onChange={(e) => set({ country: e.target.value.toUpperCase().slice(0, 2) })}
              placeholder="RU"
            />
          </Field>
          <div className="flex items-end pb-2">
            <Toggle checked={value.pep} onChange={(pep) => set({ pep })} label="Politically exposed person" />
          </div>
        </>
      ) : (
        <>
          <div className="sm:col-span-2">
            <Field label="Business name">
              <TextInput value={value.businessName} onChange={(e) => set({ businessName: e.target.value })} placeholder="Bank Rossiya" />
            </Field>
          </div>
          <Field label="Country" hint="ISO 3166-1 alpha-2">
            <TextInput
              list="country-codes"
              value={value.country}
              onChange={(e) => set({ country: e.target.value.toUpperCase().slice(0, 2) })}
              placeholder="RU"
            />
          </Field>
        </>
      )}
    </>
  )
}

function AccountHolderIdField({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <div className="sm:col-span-2">
      <Field label="Account holder ID" hint="Stateless preview — any UUID works">
        <TextInput value={value} onChange={(e) => onChange(e.target.value)} className="font-mono text-xs" />
      </Field>
    </div>
  )
}

/* ── The four screener forms ───────────────────────────────────────────── */
export function AccountHolderForm({ onSubmit, busy }: FormProps) {
  const { tenantId, blockedReason } = useScreenerGate()
  const [f, setF] = useState<AccountHolderForm>(() => structuredClone(ACCOUNT_HOLDER_PRESETS[0].form))
  const payload = buildAccountHolder(f, tenantId)
  return (
    <FormLayout presets={ACCOUNT_HOLDER_PRESETS} onApply={setF} payload={payload} busy={busy} blockedReason={blockedReason} onSubmit={() => onSubmit(payload)}>
      <PartyFields value={f.party} onChange={(party) => setF({ ...f, party })} />
      <Field label="Account holder type">
        <Select value={f.accountHolderType} onValueChange={(v) => setF({ ...f, accountHolderType: v })} options={opts(ACCOUNT_HOLDER_TYPES)} />
      </Field>
      <Field label="Risk level">
        <Select value={f.riskLevel} onValueChange={(v) => setF({ ...f, riskLevel: v })} options={opts(RISK_LEVELS)} />
      </Field>
    </FormLayout>
  )
}

export function BeneficialOwnerForm({ onSubmit, busy }: FormProps) {
  const { tenantId, blockedReason } = useScreenerGate()
  const [f, setF] = useState<BeneficialOwnerForm>(() => structuredClone(BENEFICIAL_OWNER_PRESETS[0].form))
  const payload = buildBeneficialOwner(f, tenantId)
  return (
    <FormLayout presets={BENEFICIAL_OWNER_PRESETS} onApply={setF} payload={payload} busy={busy} blockedReason={blockedReason} onSubmit={() => onSubmit(payload)}>
      <PartyFields value={f.party} onChange={(party) => setF({ ...f, party })} />
      <Field label="Ownership %">
        <TextInput type="number" min={0} max={100} value={f.ownershipPct} onChange={(e) => setF({ ...f, ownershipPct: e.target.value })} placeholder="25" />
      </Field>
      <Field label="Control type">
        <Select value={f.controlType} onValueChange={(v) => setF({ ...f, controlType: v })} options={opts(CONTROL_TYPES)} />
      </Field>
      <AccountHolderIdField value={f.accountHolderId} onChange={(v) => setF({ ...f, accountHolderId: v })} />
    </FormLayout>
  )
}

export function CounterpartyForm({ onSubmit, busy }: FormProps) {
  const { tenantId, blockedReason } = useScreenerGate()
  const [f, setF] = useState<CounterpartyForm>(() => structuredClone(COUNTERPARTY_PRESETS[0].form))
  const payload = buildCounterparty(f, tenantId)
  return (
    <FormLayout presets={COUNTERPARTY_PRESETS} onApply={setF} payload={payload} busy={busy} blockedReason={blockedReason} onSubmit={() => onSubmit(payload)}>
      <PartyFields value={f.party} onChange={(party) => setF({ ...f, party })} />
      <Field label="Status">
        <Select value={f.status} onValueChange={(v) => setF({ ...f, status: v })} options={opts(COUNTERPARTY_STATUSES)} />
      </Field>
      <AccountHolderIdField value={f.accountHolderId} onChange={(v) => setF({ ...f, accountHolderId: v })} />
    </FormLayout>
  )
}

export function PaymentAccountForm({ onSubmit, busy }: FormProps) {
  const { tenantId, blockedReason } = useScreenerGate()
  const [f, setF] = useState<PaymentAccountForm>(() => structuredClone(PAYMENT_ACCOUNT_PRESETS[0].form))
  const payload = buildPaymentAccount(f, tenantId)
  const isCrypto = f.accountType === 'crypto_wallet' || f.accountType === 'wallet'
  return (
    <FormLayout presets={PAYMENT_ACCOUNT_PRESETS} onApply={setF} payload={payload} busy={busy} blockedReason={blockedReason} onSubmit={() => onSubmit(payload)}>
      <Field label="Account type">
        <Select value={f.accountType} onValueChange={(v) => setF({ ...f, accountType: v })} options={opts(ACCOUNT_TYPES)} />
      </Field>
      <Field label="Currency">
        <TextInput list="currency-codes" value={f.currency} onChange={(e) => setF({ ...f, currency: e.target.value.toUpperCase() })} placeholder="USD" />
      </Field>
      <div className="sm:col-span-2">
        <Field
          label="Wallet address"
          hint={isCrypto ? 'On-chain OFAC SDN address screen' : 'No on-chain screen for this rail — returns pending'}
        >
          <TextInput
            value={f.walletAddress}
            onChange={(e) => setF({ ...f, walletAddress: e.target.value })}
            placeholder="0x…"
            className="font-mono text-xs"
            disabled={!isCrypto}
          />
        </Field>
      </div>
      <Field label="Wallet chain">
        <TextInput list="chain-codes" value={f.walletChain} onChange={(e) => setF({ ...f, walletChain: e.target.value.toUpperCase() })} placeholder="ETH" disabled={!isCrypto} />
      </Field>
      <Field label="Country" hint="ISO 3166-1 alpha-2">
        <TextInput list="country-codes" value={f.country} onChange={(e) => setF({ ...f, country: e.target.value.toUpperCase().slice(0, 2) })} placeholder="US" />
      </Field>
    </FormLayout>
  )
}

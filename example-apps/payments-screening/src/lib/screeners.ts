import type { Tone } from './screening'

export type ScreenerId = 'account-holder' | 'beneficial-owner' | 'counterparty' | 'payment-account'

/* ── Shared party (inline legal_entity) ────────────────────────────────── */
export interface Party {
  kind: 'individual' | 'business'
  firstName: string
  middleName: string
  lastName: string
  businessName: string
  dob: string
  country: string
  pep: boolean
}

export const newParty = (over: Partial<Party> = {}): Party => ({
  kind: 'individual',
  firstName: '',
  middleName: '',
  lastName: '',
  businessName: '',
  dob: '',
  country: '',
  pep: false,
  ...over,
})

const blank = (v: string): string | undefined => (v.trim() === '' ? undefined : v.trim())

function legalEntity(p: Party, tenantId: string | null): Record<string, unknown> {
  // The nested legal_entity requires tenant_id even on a stateless preview.
  const tenant = tenantId ?? undefined
  if (p.kind === 'business') {
    return { legal_entity_type: 'business', tenant_id: tenant, business_name: blank(p.businessName) }
  }
  return {
    legal_entity_type: 'individual',
    tenant_id: tenant,
    first_name: blank(p.firstName),
    middle_name: blank(p.middleName),
    last_name: blank(p.lastName),
    date_of_birth: blank(p.dob),
    citizenship_country: blank(p.country),
    politically_exposed_person: p.pep,
  }
}

/* ── Per-screener form shapes ──────────────────────────────────────────── */
export interface AccountHolderForm {
  party: Party
  accountHolderType: string
  riskLevel: string
}
export interface BeneficialOwnerForm {
  party: Party
  ownershipPct: string
  controlType: string
  accountHolderId: string
}
export interface CounterpartyForm {
  party: Party
  status: string
  accountHolderId: string
}
export interface PaymentAccountForm {
  accountType: string
  walletAddress: string
  walletChain: string
  currency: string
  country: string
}

/** Stateless preview only screens the inline entity; any well-formed UUID works. */
export const PLACEHOLDER_AH_ID = '00000000-0000-0000-0000-000000000000'

export const buildAccountHolder = (f: AccountHolderForm, tenantId: string | null) => ({
  account_holder_type: f.accountHolderType,
  risk_level: f.riskLevel,
  legal_entity: legalEntity(f.party, tenantId),
})

export const buildBeneficialOwner = (f: BeneficialOwnerForm, tenantId: string | null) => ({
  account_holder_id: blank(f.accountHolderId) ?? PLACEHOLDER_AH_ID,
  control_type: f.controlType,
  ownership_pct: f.ownershipPct.trim() === '' ? undefined : Number(f.ownershipPct),
  legal_entity: legalEntity(f.party, tenantId),
})

export const buildCounterparty = (f: CounterpartyForm, tenantId: string | null) => ({
  account_holder_id: blank(f.accountHolderId) ?? PLACEHOLDER_AH_ID,
  status: f.status,
  legal_entity: legalEntity(f.party, tenantId),
})

export const buildPaymentAccount = (f: PaymentAccountForm, tenantId: string | null) => ({
  account_type: f.accountType,
  tenant_id: tenantId ?? undefined,
  account_holder_id: PLACEHOLDER_AH_ID,
  wallet_address: blank(f.walletAddress),
  wallet_chain: blank(f.walletChain),
  currency: blank(f.currency),
  country: blank(f.country),
})

/* ── Reference data for inputs ─────────────────────────────────────────── */
export const COUNTRIES: { code: string; name: string }[] = [
  { code: 'US', name: 'United States' },
  { code: 'RU', name: 'Russia' },
  { code: 'CN', name: 'China' },
  { code: 'KP', name: 'North Korea' },
  { code: 'IR', name: 'Iran' },
  { code: 'SY', name: 'Syria' },
  { code: 'CU', name: 'Cuba' },
  { code: 'VE', name: 'Venezuela' },
  { code: 'BY', name: 'Belarus' },
  { code: 'MM', name: 'Myanmar' },
  { code: 'CH', name: 'Switzerland' },
  { code: 'GB', name: 'United Kingdom' },
  { code: 'DE', name: 'Germany' },
  { code: 'FR', name: 'France' },
  { code: 'AE', name: 'United Arab Emirates' },
  { code: 'SG', name: 'Singapore' },
  { code: 'IN', name: 'India' },
  { code: 'NG', name: 'Nigeria' },
]

export const ACCOUNT_HOLDER_TYPES = ['individual', 'business', 'trust', 'nonprofit']
export const RISK_LEVELS = ['low', 'medium', 'high', 'very_high', 'prohibited']
export const CONTROL_TYPES = ['shareholder', 'director', 'officer', 'trustee']
export const COUNTERPARTY_STATUSES = ['active', 'suspended', 'blocked']
export const ACCOUNT_TYPES = ['crypto_wallet', 'wallet', 'bank_account', 'card']
export const WALLET_CHAINS = ['ETH', 'BTC', 'XBT', 'TRON', 'SOL', 'BSC']
export const CURRENCIES = ['USD', 'EUR', 'GBP', 'USDC', 'USDT']

/* ── Presets ───────────────────────────────────────────────────────────── */
export interface Preset<F> {
  name: string
  tone: Tone
  form: F
}

// Shared reference parties: a sanctioned and a clean example of each identity
// type, reused across the entity screeners so every combination has a preset.
const putin = newParty({ firstName: 'Vladimir', lastName: 'Putin', dob: '1952-10-07', country: 'RU', pep: true })
const federer = newParty({ firstName: 'Roger', lastName: 'Federer', dob: '1981-08-08', country: 'CH' })
const bankRossiya = newParty({ kind: 'business', businessName: 'Bank Rossiya', country: 'RU' })
const cleanCo = newParty({ kind: 'business', businessName: 'Northwind Trading', country: 'US' })

export const ACCOUNT_HOLDER_PRESETS: Preset<AccountHolderForm>[] = [
  { name: 'Sanctioned person', tone: 'bad', form: { party: putin, accountHolderType: 'individual', riskLevel: 'high' } },
  { name: 'Clean person', tone: 'ok', form: { party: federer, accountHolderType: 'individual', riskLevel: 'low' } },
  { name: 'Sanctioned business', tone: 'bad', form: { party: bankRossiya, accountHolderType: 'business', riskLevel: 'high' } },
  { name: 'Clean business', tone: 'ok', form: { party: cleanCo, accountHolderType: 'business', riskLevel: 'low' } },
]

export const BENEFICIAL_OWNER_PRESETS: Preset<BeneficialOwnerForm>[] = [
  { name: 'Sanctioned person', tone: 'bad', form: { party: putin, ownershipPct: '30', controlType: 'shareholder', accountHolderId: PLACEHOLDER_AH_ID } },
  { name: 'Clean person', tone: 'ok', form: { party: federer, ownershipPct: '25', controlType: 'director', accountHolderId: PLACEHOLDER_AH_ID } },
  { name: 'Sanctioned business', tone: 'bad', form: { party: bankRossiya, ownershipPct: '51', controlType: 'shareholder', accountHolderId: PLACEHOLDER_AH_ID } },
  { name: 'Clean business', tone: 'ok', form: { party: cleanCo, ownershipPct: '40', controlType: 'shareholder', accountHolderId: PLACEHOLDER_AH_ID } },
]

export const COUNTERPARTY_PRESETS: Preset<CounterpartyForm>[] = [
  { name: 'Sanctioned person', tone: 'bad', form: { party: putin, status: 'active', accountHolderId: PLACEHOLDER_AH_ID } },
  { name: 'Clean person', tone: 'ok', form: { party: federer, status: 'active', accountHolderId: PLACEHOLDER_AH_ID } },
  { name: 'Sanctioned business', tone: 'bad', form: { party: bankRossiya, status: 'active', accountHolderId: PLACEHOLDER_AH_ID } },
  { name: 'Clean business', tone: 'ok', form: { party: cleanCo, status: 'active', accountHolderId: PLACEHOLDER_AH_ID } },
]

export const PAYMENT_ACCOUNT_PRESETS: Preset<PaymentAccountForm>[] = [
  {
    name: 'Crypto wallet',
    tone: 'ok',
    form: { accountType: 'crypto_wallet', walletAddress: '0x742d35cc6634c0532925a3b844bc454e4438f44e', walletChain: 'ETH', currency: 'USD', country: '' },
  },
  {
    name: 'Bank account',
    tone: 'pending',
    form: { accountType: 'bank_account', walletAddress: '', walletChain: '', currency: 'USD', country: 'US' },
  },
  {
    name: 'Card',
    tone: 'pending',
    form: { accountType: 'card', walletAddress: '', walletChain: '', currency: 'USD', country: 'US' },
  },
]

/* ── Registry metadata ─────────────────────────────────────────────────── */
export interface ScreenerMeta {
  id: ScreenerId
  label: string
  blurb: string
  endpoint: string
}

export const SCREENER_META: Record<ScreenerId, ScreenerMeta> = {
  'account-holder': {
    id: 'account-holder',
    label: 'Account Holder',
    blurb: 'Screen an internal payer or payee and its legal entity.',
    endpoint: '/api/compliance-screenings/screen-account-holder',
  },
  'beneficial-owner': {
    id: 'beneficial-owner',
    label: 'Beneficial Owner',
    blurb: 'Screen a UBO in an account holder’s ownership chain.',
    endpoint: '/api/compliance-screenings/screen-beneficial-owner',
  },
  counterparty: {
    id: 'counterparty',
    label: 'Counterparty',
    blurb: 'Screen an external party before transacting with it.',
    endpoint: '/api/compliance-screenings/screen-counterparty',
  },
  'payment-account': {
    id: 'payment-account',
    label: 'Payment Account',
    blurb: 'OFAC SDN address screen for a crypto wallet rail.',
    endpoint: '/api/compliance-screenings/screen-payment-account',
  },
}

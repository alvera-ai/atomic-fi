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

function legalEntity(p: Party): Record<string, unknown> {
  if (p.kind === 'business') {
    return { legal_entity_type: 'business', business_name: blank(p.businessName) }
  }
  return {
    legal_entity_type: 'individual',
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

export const buildAccountHolder = (f: AccountHolderForm) => ({
  account_holder_type: f.accountHolderType,
  risk_level: f.riskLevel,
  legal_entity: legalEntity(f.party),
})

export const buildBeneficialOwner = (f: BeneficialOwnerForm) => ({
  account_holder_id: blank(f.accountHolderId) ?? PLACEHOLDER_AH_ID,
  control_type: f.controlType,
  ownership_pct: f.ownershipPct.trim() === '' ? undefined : Number(f.ownershipPct),
  legal_entity: legalEntity(f.party),
})

export const buildCounterparty = (f: CounterpartyForm) => ({
  account_holder_id: blank(f.accountHolderId) ?? PLACEHOLDER_AH_ID,
  status: f.status,
  legal_entity: legalEntity(f.party),
})

export const buildPaymentAccount = (f: PaymentAccountForm) => ({
  account_type: f.accountType,
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

const putin = newParty({ firstName: 'Vladimir', lastName: 'Putin', dob: '1952-10-07', country: 'RU', pep: true })
const federer = newParty({ firstName: 'Roger', lastName: 'Federer', dob: '1981-08-08', country: 'CH' })
const merkel = newParty({ firstName: 'Angela', lastName: 'Merkel', dob: '1954-07-17', country: 'DE', pep: true })

export const ACCOUNT_HOLDER_PRESETS: Preset<AccountHolderForm>[] = [
  { name: 'Sanctions hit', tone: 'bad', form: { party: putin, accountHolderType: 'individual', riskLevel: 'high' } },
  { name: 'Clean pass', tone: 'ok', form: { party: federer, accountHolderType: 'individual', riskLevel: 'low' } },
  { name: 'PEP', tone: 'warn', form: { party: merkel, accountHolderType: 'individual', riskLevel: 'medium' } },
]

export const COUNTERPARTY_PRESETS: Preset<CounterpartyForm>[] = [
  {
    name: 'Sanctioned entity',
    tone: 'bad',
    form: { party: newParty({ kind: 'business', businessName: 'Bank Rossiya', country: 'RU' }), status: 'active', accountHolderId: PLACEHOLDER_AH_ID },
  },
  {
    name: 'Clean vendor',
    tone: 'ok',
    form: { party: newParty({ kind: 'business', businessName: 'Acme Logistics', country: 'US' }), status: 'active', accountHolderId: PLACEHOLDER_AH_ID },
  },
  { name: 'PEP', tone: 'warn', form: { party: merkel, status: 'active', accountHolderId: PLACEHOLDER_AH_ID } },
]

export const BENEFICIAL_OWNER_PRESETS: Preset<BeneficialOwnerForm>[] = [
  { name: 'Sanctioned UBO', tone: 'bad', form: { party: putin, ownershipPct: '30', controlType: 'shareholder', accountHolderId: PLACEHOLDER_AH_ID } },
  { name: 'Clean UBO', tone: 'ok', form: { party: federer, ownershipPct: '25', controlType: 'director', accountHolderId: PLACEHOLDER_AH_ID } },
]

export const PAYMENT_ACCOUNT_PRESETS: Preset<PaymentAccountForm>[] = [
  {
    name: 'OFAC mixer wallet',
    tone: 'bad',
    form: { accountType: 'crypto_wallet', walletAddress: '0x47ce0c6ed5b0ce3d3a51fdb1c52dc66a7c3c2936', walletChain: 'ETH', currency: 'USD', country: '' },
  },
  {
    name: 'Clean wallet',
    tone: 'ok',
    form: { accountType: 'crypto_wallet', walletAddress: '0x742d35cc6634c0532925a3b844bc454e4438f44e', walletChain: 'ETH', currency: 'USD', country: '' },
  },
  {
    name: 'Bank account (no on-chain screen)',
    tone: 'pending',
    form: { accountType: 'bank_account', walletAddress: '', walletChain: '', currency: 'USD', country: 'US' },
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

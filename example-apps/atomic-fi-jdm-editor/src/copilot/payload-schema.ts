// Mirror of .claude/skills/zenrule-author/references/payload-schema.md
// Kept in sync manually. If the Elixir struct AtomicFi.RuleEngine.Payload
// changes, update both this file and the skill reference.

export const RULE_ENGINE_PAYLOAD_SCHEMA = {
  description:
    'Fields available to a JDM `inputs[].field` path. Any branch can be null; rules must tolerate null with explicit checks or default rows.',
  shape: {
    transaction: {
      'transaction.id': { type: 'string', description: 'UUID' },
      'transaction.transaction_type': {
        type: 'enum',
        values: ['credit_transfer', 'direct_debit', 'card_payment', 'refund', 'reversal', 'internal_transfer'],
      },
      'transaction.status': {
        type: 'enum',
        values: ['pending', 'accepted', 'settled', 'rejected', 'reversed', 'cancelled'],
      },
      'transaction.amount': {
        type: 'number',
        description: 'Minor units (cents) — 2500 means $25.00',
      },
      'transaction.currency': { type: 'string', description: 'ISO 4217 (USD, EUR, ...)' },
      'transaction.end_to_end_id': { type: 'string', description: 'ISO 20022 reference' },
      'transaction.uetr': { type: 'string', description: 'SWIFT UETR' },
      'transaction.requested_execution_date': { type: 'string', description: 'YYYY-MM-DD' },
      'transaction.settlement_date': { type: 'string', description: 'YYYY-MM-DD' },
      // Output-only fields conventionally written via outputs[].field.
      'transaction.rule': { type: 'string', description: 'Output: matched rule name' },
      'transaction.max_amount': { type: 'number', description: 'Output: per-txn max (minor units)' },
      'transaction.daily_debit_limit': { type: 'number', description: 'Output' },
      'transaction.weekly_debit_limit': { type: 'number', description: 'Output' },
      'transaction.monthly_debit_limit': { type: 'number', description: 'Output' },
      'transaction.yearly_debit_limit': { type: 'number', description: 'Output' },
      'transaction.daily_credit_limit': { type: 'number', description: 'Output' },
      'transaction.weekly_credit_limit': { type: 'number', description: 'Output' },
      'transaction.monthly_credit_limit': { type: 'number', description: 'Output' },
      'transaction.yearly_credit_limit': { type: 'number', description: 'Output' },
    },
    account_holder: {
      'account_holder.id': { type: 'string', description: 'UUID' },
      'account_holder.external_id': { type: 'string' },
      'account_holder.holder_type': {
        type: 'enum',
        values: ['individual', 'business', 'trust', 'nonprofit'],
      },
      'account_holder.status': {
        type: 'enum',
        values: ['pending', 'active', 'suspended', 'closed', 'flagged'],
      },
      'account_holder.kyc_status': {
        type: 'enum',
        values: ['not_started', 'in_progress', 'approved', 'rejected', 'expired'],
      },
      'account_holder.risk_level': {
        type: 'enum',
        values: ['low', 'medium', 'high', 'very_high'],
      },
      'account_holder.enabled_currencies': {
        type: 'object',
        description: 'string[] — e.g. ["USD","EUR"]',
      },
    },
    debtor_payment_account: {
      'debtor_payment_account.id': { type: 'string', description: 'UUID' },
      'debtor_payment_account.account_type': {
        type: 'enum',
        values: ['bank_account', 'card', 'wallet', 'crypto_wallet'],
      },
      'debtor_payment_account.status': {
        type: 'enum',
        values: ['active', 'suspended', 'blocked'],
      },
      'debtor_payment_account.currency': { type: 'string', description: 'ISO 4217' },
      'debtor_payment_account.bank_name': { type: 'string' },
      'debtor_payment_account.iban': { type: 'string', description: 'sensitive (PCI/PII)' },
      'debtor_payment_account.account_holder.kyc_status': {
        type: 'enum',
        values: ['not_started', 'in_progress', 'approved', 'rejected', 'expired'],
        description: 'Nested KYC of the counterparty payment account holder',
      },
      'debtor_payment_account.account_holder.holder_type': {
        type: 'enum',
        values: ['individual', 'business', 'trust', 'nonprofit'],
      },
      'debtor_payment_account.account_holder.risk_level': {
        type: 'enum',
        values: ['low', 'medium', 'high', 'very_high'],
      },
    },
    creditor_payment_account: {
      'creditor_payment_account.id': { type: 'string', description: 'UUID' },
      'creditor_payment_account.account_type': {
        type: 'enum',
        values: ['bank_account', 'card', 'wallet', 'crypto_wallet'],
      },
      'creditor_payment_account.status': {
        type: 'enum',
        values: ['active', 'suspended', 'blocked'],
      },
      'creditor_payment_account.currency': { type: 'string', description: 'ISO 4217' },
      'creditor_payment_account.bank_name': { type: 'string' },
      'creditor_payment_account.iban': { type: 'string', description: 'sensitive (PCI/PII)' },
      'creditor_payment_account.account_holder.kyc_status': {
        type: 'enum',
        values: ['not_started', 'in_progress', 'approved', 'rejected', 'expired'],
        description: 'Nested KYC of the counterparty payment account holder',
      },
      'creditor_payment_account.account_holder.holder_type': {
        type: 'enum',
        values: ['individual', 'business', 'trust', 'nonprofit'],
      },
      'creditor_payment_account.account_holder.risk_level': {
        type: 'enum',
        values: ['low', 'medium', 'high', 'very_high'],
      },
    },
    debtor_counterparty: {
      'debtor_counterparty.id': { type: 'string', description: 'UUID' },
      'debtor_counterparty.status': {
        type: 'enum',
        values: ['active', 'suspended', 'blocked'],
      },
      'debtor_counterparty.counterparty_number': { type: 'string' },
    },
    creditor_counterparty: {
      'creditor_counterparty.id': { type: 'string', description: 'UUID' },
      'creditor_counterparty.status': {
        type: 'enum',
        values: ['active', 'suspended', 'blocked'],
      },
      'creditor_counterparty.counterparty_number': { type: 'string' },
    },
  },
} as const;

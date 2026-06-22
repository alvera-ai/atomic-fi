import type { FC } from 'react'
import type { ScreenerId } from '@/lib/screeners'
import type { FormProps } from './types'
import { AccountHolderForm, BeneficialOwnerForm, CounterpartyForm, PaymentAccountForm } from './ScreenerForms'

export const SCREENER_FORMS: Record<ScreenerId, FC<FormProps>> = {
  'account-holder': AccountHolderForm,
  'beneficial-owner': BeneficialOwnerForm,
  counterparty: CounterpartyForm,
  'payment-account': PaymentAccountForm,
}

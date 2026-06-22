import { COUNTRIES, CURRENCIES, WALLET_CHAINS } from '@/lib/screeners'

/** Shared <datalist> suggestions for the free-text code inputs. Mounted once. */
export function Datalists() {
  return (
    <>
      <datalist id="country-codes">
        {COUNTRIES.map((c) => (
          <option key={c.code} value={c.code}>
            {c.name}
          </option>
        ))}
      </datalist>
      <datalist id="chain-codes">
        {WALLET_CHAINS.map((c) => (
          <option key={c} value={c} />
        ))}
      </datalist>
      <datalist id="currency-codes">
        {CURRENCIES.map((c) => (
          <option key={c} value={c} />
        ))}
      </datalist>
    </>
  )
}

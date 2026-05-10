// ISO 4217 minor-unit fractional digits for currencies we use in fixtures.
const FRACTION_DIGITS: Record<string, number> = {
  USD: 2, EUR: 2, GBP: 2, CAD: 2, AUD: 2, CHF: 2, SEK: 2, NOK: 2, DKK: 2,
  JPY: 0, KRW: 0, CLP: 0,
  BHD: 3, KWD: 3, JOD: 3, OMR: 3, TND: 3,
};

export function formatAmount(minor: number, currency: string): string {
  const digits = FRACTION_DIGITS[currency.toUpperCase()] ?? 2;
  const major = minor / Math.pow(10, digits);
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: currency.toUpperCase(),
      minimumFractionDigits: digits,
      maximumFractionDigits: digits,
    }).format(major);
  } catch {
    return `${major.toFixed(digits)} ${currency.toUpperCase()}`;
  }
}

export function shortId(id: string, len = 8): string {
  return id.length > len ? `${id.slice(0, len)}…` : id;
}

import axios from 'axios';

// ZenRule agent: unauthenticated, evaluates saved decisions.
// Hits /api/projects/<rule_type>/evaluate/<name> via Vite proxy → :8090.
export const zenruleClient = axios.create();

// atomic-fi Phoenix REST: requires x-api-key.
// Hits /api/rules/* and /api/compliance-screenings/* via Vite proxy → :4000.
export const atomicFiClient = axios.create({
  headers: {
    'x-api-key': import.meta.env.VITE_ATOMIC_FI_API_KEY ?? '',
  },
});

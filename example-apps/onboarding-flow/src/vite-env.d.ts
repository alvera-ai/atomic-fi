/// <reference types="vite/client" />

// No app-specific env vars: the backend API key is entered at the
// ConnectGate at runtime, not baked in at build time. `import.meta.env`
// still carries Vite's own built-ins (BASE_URL, MODE, …).

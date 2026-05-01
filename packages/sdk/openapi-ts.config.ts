import { defineConfig } from '@hey-api/openapi-ts'

export default defineConfig({
  input: './spec/openapi.yaml',
  output: 'generated',
  plugins: [
    '@hey-api/client-fetch',
    '@hey-api/typescript',
    '@hey-api/sdk',
    {
      name: 'valibot',
      // Generate runtime schemas for both request and response shapes so
      // tests can validate API responses against the spec.
      definitions: true,
      requests: true,
      responses: true,
    },
  ],
})

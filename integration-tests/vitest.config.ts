import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    pool: 'forks',
    poolOptions: { forks: { singleFork: true } },
    fileParallelism: false,
    // bootstrap.test.ts sorts first alphabetically; specs that depend on its
    // state should rely on this ordering. If we ever add a spec that needs
    // to run later than 'b…' we'll wire a custom sequencer.
    sequence: { shuffle: false },
    setupFiles: ['./vitest.setup.ts'],
    testTimeout: 30_000,
    hookTimeout: 30_000,
  },
})

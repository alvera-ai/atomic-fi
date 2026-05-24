# syntax=docker/dockerfile:1
#
# @atomic-fi/copilot-runtime — generic CopilotKit v2 runtime sidecar.
#
# CopilotKit ships @copilotkit/runtime as library middleware — not a server,
# and not an official image. This is the thin Hono host plus the Dockerfile
# CopilotKit leaves to you. Built by local-dependencies.yaml alongside
# watchman + zenrule.

FROM oven/bun:1-alpine AS deps
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production

FROM oven/bun:1-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY package.json tsconfig.json ./
COPY src ./src
EXPOSE 4111
# Bun runs the TypeScript entrypoint directly — no build/transpile step.
CMD ["bun", "src/main.ts"]

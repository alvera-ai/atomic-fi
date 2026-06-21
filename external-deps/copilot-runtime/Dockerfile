# syntax=docker/dockerfile:1
#
# @atomic-fi/copilot-runtime — generic CopilotKit v2 runtime sidecar.
#
# CopilotKit ships @copilotkit/runtime as library middleware — not a server,
# and not an official image. This is the thin Hono host plus the Dockerfile
# CopilotKit leaves to you. Built by local-dependencies.yaml alongside
# watchman + zenrule.
#
# Switched from Bun to Node because @modelcontextprotocol/sdk's CJS build
# uses top-level await which Bun's require() can't handle (MCP SDK #213).

FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json bun.lock ./
# Use npm since we're on Node now — bun.lock is ignored
RUN npm install --omit=dev

FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY package.json tsconfig.json ./
COPY src ./src
EXPOSE 4111
# tsx runs TypeScript directly on Node — same DX as bun
CMD ["npx", "tsx", "src/main.ts"]

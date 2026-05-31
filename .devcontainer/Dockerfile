FROM hexpm/elixir:1.18.3-erlang-27.3.3-debian-bookworm-20250428-slim

RUN apt-get update && apt-get install -y \
    git curl build-essential inotify-tools docker.io docker-compose-plugin \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g pnpm@9.15.0 \
    && rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && mix local.rebar --force

WORKDIR /app

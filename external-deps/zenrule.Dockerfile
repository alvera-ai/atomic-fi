# Local build of the GoRules Agent (ZenRule) from the vendored subtree at
# external-deps/zenrule/. GoRules only publishes amd64 images on Docker Hub, so
# arm64 dev machines build it here.
#
# This wrapper keeps the subtree pristine (so `git subtree pull --squash` stays
# clean) and overrides only the release profile: the upstream Cargo.toml sets
# `lto = true` + `codegen-units = 1`, whose single-threaded whole-program link
# step exceeds Docker Desktop's default ~4 GB VM and gets OOM-killed. A local dev
# image does not need that optimisation, so we disable LTO and parallelise codegen.
#
# Build context is external-deps/ (parent of the subtree dir).

FROM rust:1.93 AS builder

WORKDIR /app
COPY zenrule/ .
RUN cargo build --release \
      --config profile.release.lto=false \
      --config profile.release.codegen-units=16

FROM gcr.io/distroless/cc-debian13:nonroot AS runner

WORKDIR /home/nonroot
COPY --from=builder /app/target/release/agent ./app

ARG SERVICE_VERSION=local
ENV SERVICE_VERSION=$SERVICE_VERSION

EXPOSE 8080
CMD ["./app"]

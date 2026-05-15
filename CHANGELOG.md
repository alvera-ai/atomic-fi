# Changelog

## [1.3.0](https://github.com/alvera-ai/atomic-fi/compare/v1.2.0...v1.3.0) (2026-05-13)


### Features

* **atomic-fi-web:** per-node editor, CodeMirror, design pass ([8dd17c4](https://github.com/alvera-ai/atomic-fi/commit/8dd17c4bafbe12b23d40f1025aa73dc85a816e71))
* **atomic-fi-web:** scaffold JDM workflow editor POC ([8a8cc9b](https://github.com/alvera-ai/atomic-fi/commit/8a8cc9b5ec69d14906beb49722bc21088c9f6a91))

## [1.2.0](https://github.com/alvera-ai/atomic-fi/compare/v1.1.0...v1.2.0) (2026-05-01)


### Features

* claude skills added ([520726e](https://github.com/alvera-ai/atomic-fi/commit/520726ec10a6155b2180dea9f76a05fc58861952))
* **integration-tests:** 100% E2E OpenAPI coverage ([5ec096f](https://github.com/alvera-ai/atomic-fi/commit/5ec096f2503a44803f8f872d7538b396c74beeb8))
* **sdk:** add mintSecondaryTenant() for RLS isolation tests ([b4e0b7d](https://github.com/alvera-ai/atomic-fi/commit/b4e0b7d0b1c40992b81bb620d31d2b447c3abd68))
* **seeds:** split platform bootstrap into seed_migrations, fix login deadlock ([cac17e7](https://github.com/alvera-ai/atomic-fi/commit/cac17e76573ab2111fd260eea86ee828e9aa9885))


### Bug Fixes

* **compliance_screening:** persist BO screenings with scope=:beneficial_owner ([be635b5](https://github.com/alvera-ai/atomic-fi/commit/be635b5ec97414734ca545aa8d88ae6ba8a6e5fc))
* **legal_entities:** cascade-delete change events on legal_entity delete ([0f77341](https://github.com/alvera-ai/atomic-fi/commit/0f77341a0449fb02693bebd5db3f7e3f7ff90273))
* **migrations:** bump timestamps to avoid collision with seed migration ([a030dd0](https://github.com/alvera-ai/atomic-fi/commit/a030dd0a635b79434fbfae85fc156762be6064cf))

## [1.1.0](https://github.com/alvera-ai/atomic-fi/compare/v1.0.0...v1.1.0) (2026-04-29)


### Features

* rebrand to AtomicFi, adopt MIT license, prep for open source ([060fdc8](https://github.com/alvera-ai/atomic-fi/commit/060fdc8be0335a82be72ba6c3836b552cb3a1bb0))
* rebrand to AtomicFi, adopt MIT license, prep for open source ([a1c2963](https://github.com/alvera-ai/atomic-fi/commit/a1c2963084dfe82f13d8198bfbdf4cfcba8f877c)), closes [#12](https://github.com/alvera-ai/atomic-fi/issues/12)

## 1.0.0 (2026-04-24)


### Features

* add blocklist system with ETS cache and Quantum scheduler ([3884904](https://github.com/alvera-ai/payments-compliance-platform/commit/388490430962694ad343758a7d1c472b8b652fa2))
* add demo blocklist seed data for all tenants ([49a321a](https://github.com/alvera-ai/payments-compliance-platform/commit/49a321abee8d1bb9b3a34f309b6f4a129cffa1bb))
* add family/relation terms to blocklist exact matches ([f6277b1](https://github.com/alvera-ai/payments-compliance-platform/commit/f6277b1e0b40ab79e75c962b249667d1f6cf81d0))
* add init_blocklist_cache helper to ConnCase ([c90d43d](https://github.com/alvera-ai/payments-compliance-platform/commit/c90d43d9455ed4fda0e61d8d6b167e12d556cede))
* add manual blocklist cache refresh endpoint ([07fde63](https://github.com/alvera-ai/payments-compliance-platform/commit/07fde6336bb3ad245ba938b564c8c9fed3a17b58))
* add onboarding screening API with Watchman integration ([f3577a9](https://github.com/alvera-ai/payments-compliance-platform/commit/f3577a9636a4e983ba68f5f9c1b58a1e3e3f221b))
* add OpenAPI schema for BlocklistEntry list response ([a3bc264](https://github.com/alvera-ai/payments-compliance-platform/commit/a3bc264c6e8dfc925e956ef2140cb1f74cbf1fec))
* add Playwright E2E test infrastructure and blocklist demo ([39b1329](https://github.com/alvera-ai/payments-compliance-platform/commit/39b1329dc9a62644c1061b010b43aa39aa84b7c4))
* add runtime exception for uninitialized blocklist cache ([1bc1549](https://github.com/alvera-ai/payments-compliance-platform/commit/1bc1549572ef0128cdeef052f03b94af1f2a07a0))
* add unique constraint and idempotent seeding for blocklist entries ([56824c4](https://github.com/alvera-ai/payments-compliance-platform/commit/56824c422d38c9b638f04571f7d3b9fc27a55e29))
* add Watchman API client for sanctions screening ([c9e9b5c](https://github.com/alvera-ai/payments-compliance-platform/commit/c9e9b5c4b3be04449df821f536c2702c03ac6483))
* add watchman container dependency ([42d6b9c](https://github.com/alvera-ai/payments-compliance-platform/commit/42d6b9cea42ddd4a88d3e19b5826ce51605fb08f))
* align data model with ISO 20022 (GH-9) ([#10](https://github.com/alvera-ai/payments-compliance-platform/issues/10)) ([8fdcab6](https://github.com/alvera-ai/payments-compliance-platform/commit/8fdcab6977afab1b93f41924a047770104590ef2))
* Blocklist screening feature with E2E demonstration ([0f99ee3](https://github.com/alvera-ai/payments-compliance-platform/commit/0f99ee3ec86c84234fb36f31bcf7cd07fef7fd9e))
* integrate blocklist screening into decision flow with cache refresh ([2c9250e](https://github.com/alvera-ai/payments-compliance-platform/commit/2c9250ea54fe197b143a10c588ea6e48e5c18d01))
* integrate Docker Compose for local dependency management. ([30b24ca](https://github.com/alvera-ai/payments-compliance-platform/commit/30b24ca30098f9eb4cf88409d4620b863b082d91))


### Bug Fixes

* add Phoenix.CodeReloader listener to mix.exs ([d7e525a](https://github.com/alvera-ai/payments-compliance-platform/commit/d7e525a6876032505cfe877ee02e2032c9caaf4a))
* formatting ([fbc756b](https://github.com/alvera-ai/payments-compliance-platform/commit/fbc756bd9a8dba2ed4ef96a8b72ac3743dc90f22))
* properly manage Vault lifecycle in test migrations ([eef5019](https://github.com/alvera-ai/payments-compliance-platform/commit/eef5019ce6bf8002f7b22288eb708cef0a1175df))
* remove non-existent ApiKey.active field check and add tests ([405ea15](https://github.com/alvera-ai/payments-compliance-platform/commit/405ea15c32f43ef5d980d24b6275ff748e5409b4))
* rename project ([73dc0a4](https://github.com/alvera-ai/payments-compliance-platform/commit/73dc0a46f6eb6eb1ea48171b94651c25e6e7e9bd))
* resolve GitHub Actions Vault conflict and add database creation step ([6ba0f49](https://github.com/alvera-ai/payments-compliance-platform/commit/6ba0f49d5ccbfaecf9ffbc914f7572fce99f285d))
* use Alvera AI's Watchman fork in GitHub Actions ([ab63a15](https://github.com/alvera-ai/payments-compliance-platform/commit/ab63a158f9fbdc9e23dd9a30a99feb63bc967c2e))

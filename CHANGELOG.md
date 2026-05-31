# Changelog

## [1.8.0](https://github.com/alvera-ai/atomic-fi/compare/v1.7.0...v1.8.0) (2026-05-31)


### Features

* add .env support for dev secrets ([d1830c4](https://github.com/alvera-ai/atomic-fi/commit/d1830c44712786b4f8ac4e7aa522cb2be6ad4b29))
* add .env support for dev secrets ([1bc391b](https://github.com/alvera-ai/atomic-fi/commit/1bc391bde49d12716b7a72a8011cf332b9a60c4b))

## [1.7.0](https://github.com/alvera-ai/atomic-fi/compare/v1.6.0...v1.7.0) (2026-05-31)


### Features

* **gh-53:** add corpus schema to LotusRepo search_path ([c6579c3](https://github.com/alvera-ai/atomic-fi/commit/c6579c3071dd9287577183582599b24537b23e96))
* **gh-53:** add correctness verification skills + make targets ([9815154](https://github.com/alvera-ai/atomic-fi/commit/98151548a015309792a5ee1d99c0e8303839ab8b)), closes [#53](https://github.com/alvera-ai/atomic-fi/issues/53)
* **gh-53:** add country field to PaymentAccount ([a3c349e](https://github.com/alvera-ai/atomic-fi/commit/a3c349efe3bcd7ff9176e79f1d1050be9b08ae7c))
* **gh-53:** add country-onboarding skill ([a58162b](https://github.com/alvera-ai/atomic-fi/commit/a58162b0b49efd21bf5dd3836ddd30e8b8c4b72e))
* **gh-53:** add Indonesia rules, corpora, and Bruno collections ([2e7602e](https://github.com/alvera-ai/atomic-fi/commit/2e7602ec8f1196ea6d43a47ae3d26b5373a5043f))
* **gh-53:** add institutional due diligence fields to LegalEntity ([02c98b9](https://github.com/alvera-ai/atomic-fi/commit/02c98b94a60ad369a3ca98f10c2538c1a3449450))
* **gh-53:** correctness verification — three skills for the compliance officer ([187421d](https://github.com/alvera-ai/atomic-fi/commit/187421d9e8e8eeb5a836c5e3cd5576b7611f4452))
* **gh-53:** enable Watchman Postgres-backed custom ingest ([613c1b5](https://github.com/alvera-ai/atomic-fi/commit/613c1b5596f9a7d78e628d90aaeff6b645e9ac93))
* **gh-53:** fill guide section 3 — Write the controls ([778170c](https://github.com/alvera-ai/atomic-fi/commit/778170c9e7465addd770d400434580ccb44b6abf))
* **gh-53:** fill guide section 4 — Prove the controls ([7f53e43](https://github.com/alvera-ai/atomic-fi/commit/7f53e4360bd13607c9ae4a98c9bc04cebe5e3b98))
* **gh-53:** fill guide sections 5-7 — Bruno, Lotus, evidence pack ([e7b48b6](https://github.com/alvera-ai/atomic-fi/commit/e7b48b68b20a5ed4a2819da62cb86414ded58821))
* **gh-53:** harden generate-rules with source-specific fetch strategies ([f070d22](https://github.com/alvera-ai/atomic-fi/commit/f070d22cd76895bd315f09b61d04719cfae62a69))
* **gh-53:** harden skills, fix atom safety, add --build for fresh clones ([5268879](https://github.com/alvera-ai/atomic-fi/commit/52688798bcfdbc6ca91ef87e1f7065d13222a92d))
* **gh-53:** improve bruno-generate skill from eval findings ([0c6e3c4](https://github.com/alvera-ai/atomic-fi/commit/0c6e3c40b1caf308f65b03eee9777e51ccb0ecf3))
* **gh-53:** master-suite now generates 100 AH / 1k CP / 10k Txn ([f3a2f34](https://github.com/alvera-ai/atomic-fi/commit/f3a2f34d8ff13ad4804e195094f70815d0da07fd))
* **gh-53:** onboard Indonesia sanctions list via in-memory Senzing pathway ([c2c672a](https://github.com/alvera-ai/atomic-fi/commit/c2c672a27e0b062d51e7d8b86d33fc1a91495061))


### Bug Fixes

* **ci:** override Watchman healthcheck so initial crash doesn't abort job ([717ae4c](https://github.com/alvera-ai/atomic-fi/commit/717ae4cf897cfbf3164781163e6f00e1bc5f66d8))
* **ci:** start Watchman after checkout via docker run, not as a service ([b3ebdd8](https://github.com/alvera-ai/atomic-fi/commit/b3ebdd8a23aef4aaa3950028b98d64e0ce88332c))
* **ci:** strip Watchman Database config in CI to avoid role error ([1139253](https://github.com/alvera-ai/atomic-fi/commit/11392538487e93ca53254613a8f5b9a08cc24741))
* **ci:** upgrade Watchman to v0.62.0 and disable dead us_csl in CI ([5300989](https://github.com/alvera-ai/atomic-fi/commit/530098932a7a3027ec5ff50caa2c98d9a692bea7))
* **gh-53:** add make run, remove Task.async from validate, simplify master-suite ([06a7fed](https://github.com/alvera-ai/atomic-fi/commit/06a7fedd648590fd73e12df7638def41542e9a39))
* **gh-53:** correct guide screenshot paths so images render ([dc5145d](https://github.com/alvera-ai/atomic-fi/commit/dc5145d298deb82af1c4d70104818844dcdfd110))
* **gh-53:** country-onboarding uses API ingest, not file append ([780c6f1](https://github.com/alvera-ai/atomic-fi/commit/780c6f16874ce1645927f641cfa25542fc9c4e12))
* **gh-53:** country-onboarding uses in-memory Senzing pathway ([0c465c1](https://github.com/alvera-ai/atomic-fi/commit/0c465c1f86d3561e176ff62c5d1c58b2fe350ef6))
* **gh-53:** enforce hard stops in skills + require lifecycle & external_id ([a111d70](https://github.com/alvera-ai/atomic-fi/commit/a111d7027603e425107382cada652b1add3bcce7))
* **gh-53:** fix id_dttot_match _expected for rule stacking ([69743af](https://github.com/alvera-ai/atomic-fi/commit/69743afd00f12cdeb41480f978c18f28d8a8076a))
* **gh-53:** fix ofac_sdn_match _expected for rule stacking with id_dttot_match ([d6d1e7d](https://github.com/alvera-ai/atomic-fi/commit/d6d1e7de81e8a5af96f4e19cc2b27046453b501c))
* **gh-53:** fix ofac-sdn Bruno assertion for rule stacking ([8134c37](https://github.com/alvera-ai/atomic-fi/commit/8134c370e4a90d5f7e42c1435885e917baf94795))
* **gh-53:** fix output-contract holder_type + search custom watchlist ([abe5eee](https://github.com/alvera-ai/atomic-fi/commit/abe5eeec6671c05b7f1aaa4cfdb37294314f77d3))
* **gh-53:** fix scenario-author file paths — payload.ex does not exist ([0e588a3](https://github.com/alvera-ai/atomic-fi/commit/0e588a3bd600c40256484ff10a64f0fba2f2889c))
* **gh-53:** improve country-onboarding from eval findings ([e1639d6](https://github.com/alvera-ai/atomic-fi/commit/e1639d6f3f18bef5a00e45ef0a82c19f33d0ba2e))
* **gh-53:** remove dedup + confirmation prompts from generate-rules ([4ce3f09](https://github.com/alvera-ai/atomic-fi/commit/4ce3f0995f71e00166fb3a40323d25cdb09011ef))
* **gh-53:** update country-onboarding skill — Postgres ingest works now ([140fbe9](https://github.com/alvera-ai/atomic-fi/commit/140fbe9e764ec89c9e01af5f6792241fd9e03f5c))
* **gh-53:** use R2 CDN URLs for guide videos ([2518011](https://github.com/alvera-ai/atomic-fi/commit/2518011e1ab927dbe0ff87bc3636f15b2c80232a))
* upgrade Watchman to v0.62.0 and disable dead us_csl list ([34c7c91](https://github.com/alvera-ai/atomic-fi/commit/34c7c91de5a6006c61bbf9d1272d1071ec296183))

## [1.6.0](https://github.com/alvera-ai/atomic-fi/compare/v1.5.0...v1.6.0) (2026-05-24)


### Features

* **compliance-screening:** stateful sync screen-by-id endpoints + Flop-shaped responses ([7a3b878](https://github.com/alvera-ai/atomic-fi/commit/7a3b8781a504bb49194df4945c7d1c59d4e89eb4))
* **copilotkit:** /api/copilotkit CopilotKit Runtime Protocol passthrough ([2f0a6cf](https://github.com/alvera-ai/atomic-fi/commit/2f0a6cf932a5b1dcbfdd9ad2fbfc6ed016e3b7dc))
* **copilotkit:** wire POST /api/copilotkit in router + Ollama config ([ea3754f](https://github.com/alvera-ai/atomic-fi/commit/ea3754fcb77af4cd7bd76220154f8bb851790910))
* **delete:** 422 instead of 5xx on FK :restrict + ControlLimit ExOpenApiUtils ([c241219](https://github.com/alvera-ai/atomic-fi/commit/c241219a1ef00021eb77a893b4c46cb7977f8d4c))
* **demo:** allow Plug.Static to serve priv/static/demo/* ([7d36811](https://github.com/alvera-ai/atomic-fi/commit/7d368114b50ea7ad5e9a4787c4bee7071826a31e))
* **demo:** list example apps on the home page ([9bba945](https://github.com/alvera-ai/atomic-fi/commit/9bba945ef8f78ec32de781a6f00093d126455777))
* **demo:** point example-app builds at priv/static/demo/&lt;app&gt; ([22f530e](https://github.com/alvera-ai/atomic-fi/commit/22f530e15b08a32dc2b52e6c8f35690bdbf03a28))
* **demo:** run vite build --watch per example app from Phoenix ([403ed65](https://github.com/alvera-ai/atomic-fi/commit/403ed65cc8a57647359e34d1f9ca49c020210d5c))
* **gh-49:** copilot-runtime — generic CopilotKit v2 sidecar + Vector telemetry ([42580db](https://github.com/alvera-ai/atomic-fi/commit/42580db9be3eccdbe63d043aca036350825639c1))
* **gh-49:** JDM editor copilot on CopilotKit v2 + harden SSE streaming ([022a69e](https://github.com/alvera-ai/atomic-fi/commit/022a69ee9cb1223a6e2537a5211b845f59728b3e))
* **gh-49:** onboarding API-key gate + Elixir e2e ports + parser fixes ([f425c94](https://github.com/alvera-ai/atomic-fi/commit/f425c94ca04d568e8646a8cb75991404620eeaae))
* **gh-49:** PR-ready — Mockoon replaces WireMock, drop dead Elixir CopilotKit, size ZenRule pool ([bcc47c2](https://github.com/alvera-ai/atomic-fi/commit/bcc47c2351ead6586a24279bcb164a1e85df1933))
* **gh-49:** single-app demo build — JDM editor copilot v2, Mockoon LLM mock, unified Playwright ([003adbc](https://github.com/alvera-ai/atomic-fi/commit/003adbc4e1089a69fdd2b941997163e8abf63bf1))
* **parse:** port app/schemas.py + extractor to Elixir (ReqLLM + poppler) ([22835e8](https://github.com/alvera-ai/atomic-fi/commit/22835e89b7900d4e6e3c1364c36b3ac863d09887))
* **parse:** POST /api/parse — JSON + base64 controller ([f6a0985](https://github.com/alvera-ai/atomic-fi/commit/f6a0985e6efa32ee15aa4a43ef3f93a7284e713d))


### Bug Fixes

* **demo:** green Playwright e2e for onboarding + Lotus demos ([0505faf](https://github.com/alvera-ai/atomic-fi/commit/0505faff96fc4f948d7ec969cf47223fb387e155))
* **gh-49:** CI greens — register Parse* schemas, warm dev _build + atomic_fi_dev ([de8ae3a](https://github.com/alvera-ai/atomic-fi/commit/de8ae3a9ff4b9d4cadb19728ba4c4d3f1b88f42b))
* **gh-49:** corpus checks — bash loop in regression.yml, drop ExUnit wrapper ([ce9f71d](https://github.com/alvera-ai/atomic-fi/commit/ce9f71d2dab02404f823ee5bd82f253c8f23a8a1))
* **gh-49:** corpus.validate inherits parent MIX_ENV — no CI dev-env workaround ([a2d1447](https://github.com/alvera-ai/atomic-fi/commit/a2d14473e8db42e246ddadb0602569da6d09c29f))
* **gh-49:** HITL cards — fix stale Apply-all registry + thread toolCallId for stable ids ([90854be](https://github.com/alvera-ai/atomic-fi/commit/90854be9891507e749b3a0ca7591db0f07884bfc))
* **gh-49:** HITL respond?.() — await it everywhere to avoid AI_MissingToolResultsError ([9c1700b](https://github.com/alvera-ai/atomic-fi/commit/9c1700be27dce06b27b64355f3a3e3283ba2699e))
* **gh-49:** JDM editor robustness — dev-console gate, dirty-on-load, simulator routing, error catch-all ([d573d70](https://github.com/alvera-ai/atomic-fi/commit/d573d708d1d3d12446de69b386534b2d5658e8c6))
* **openapi:** register LinkedLedgerAccount{Request,Response} ([9345d61](https://github.com/alvera-ai/atomic-fi/commit/9345d61bcf420ee36779c11b80ac6cd6f23ec901)), closes [#44](https://github.com/alvera-ai/atomic-fi/issues/44)

## [1.5.0](https://github.com/alvera-ai/atomic-fi/compare/v1.4.0...v1.5.0) (2026-05-18)


### Features

* **account-holder,counterparty:** preload beneficial_owners + expose on OpenAPI response ([995617b](https://github.com/alvera-ai/atomic-fi/commit/995617bb80e7f66864e026f7561c5883a551fb3a))
* **account-holder:** add :prohibited to risk_level enum (scenario [#10](https://github.com/alvera-ai/atomic-fi/issues/10)) ([cee69c5](https://github.com/alvera-ai/atomic-fi/commit/cee69c508b8712376f0bacdca9d62f23133fa77b))
* add document-agent client example app and Makefile delegation ([465eb41](https://github.com/alvera-ai/atomic-fi/commit/465eb41d4207cd82f0f7336bdd819aeedf0a9436))
* add onboarding-flow example app to workspace ([a4c5b2f](https://github.com/alvera-ai/atomic-fi/commit/a4c5b2fe396714a565752ae2117e688a93f0dab2))
* **api:** nested LegalEntity PUT routes on AH/CP/BO controllers ([fbd25d4](https://github.com/alvera-ai/atomic-fi/commit/fbd25d447d7ec74d1d5212529ca6b2cf3c28e264))
* **api:** remove standalone LegalEntity REST surface ([108a9ff](https://github.com/alvera-ai/atomic-fi/commit/108a9ff541d4847b5eaaeca189bd9fc4c64ae1e0))
* **bench:** concurrency sweep — power-of-2 ladder, env fingerprint, GitHub-flavored report ([1e9c550](https://github.com/alvera-ai/atomic-fi/commit/1e9c5506a67d50bbbd6b962342d76e9c83588efb))
* **bench:** k6-shape VU sweep — in-process Tasks, 10 catalog scenarios ([9bfb909](https://github.com/alvera-ai/atomic-fi/commit/9bfb90918e590bc7cf25dba7eae77041faca8c2a))
* **beneficial-owner:** add external_id + corpus loader; ship scenario [#27](https://github.com/alvera-ai/atomic-fi/issues/27) ([d50ba28](https://github.com/alvera-ai/atomic-fi/commit/d50ba280e5ac396d46165e059ff6a756b11d9ddb))
* **contexts:** get_*_by_external_id/2 with same preloads as get_*!/2 ([de4ca48](https://github.com/alvera-ai/atomic-fi/commit/de4ca4880534a131eccda08ce595b5b5259bbad1))
* **corpus-validate:** bootstrap LA unblock + deterministic proof.md report ([b70df0b](https://github.com/alvera-ai/atomic-fi/commit/b70df0b545700070d5f59db275913d1c1a4b3a7f))
* **corpus:** add cip_kyc_gate rule + fixtures ([072c835](https://github.com/alvera-ai/atomic-fi/commit/072c835ffc597ba036d0c81d8d32c53a9910b9ae))
* **corpus:** add ctr_structuring rule + recent-debits payload ([eca281f](https://github.com/alvera-ai/atomic-fi/commit/eca281fa4a68a4f8b2b3807644e634f9b4ca3a71))
* **corpus:** add ofac_sdn_match rule + fixtures ([0fc5793](https://github.com/alvera-ai/atomic-fi/commit/0fc57936b5352ee95ad1b4fa4ed6139013ff61a3))
* **corpus:** commit upstream manifests under corpus/upstream/; add SAML-D + AMLGentex reseed Makefile targets ([87dc349](https://github.com/alvera-ai/atomic-fi/commit/87dc34984ad7bf63fb14c6c780bf6e853eee415c))
* **corpus:** corpus-from-rule skill + mix corpus.validate (Phase 3a) ([0fbe93d](https://github.com/alvera-ai/atomic-fi/commit/0fbe93d26f1a35c8428df07b443305e7b04bec9e))
* **corpus:** de_minimis_stablecoin corpus + B2 validate via production contexts ([05671ba](https://github.com/alvera-ai/atomic-fi/commit/05671ba836ebe5e5aaaab62485b6fecdee82f286))
* **corpus:** end-to-end performance bench (mix corpus.bench) + plain-English benchmark/ ([613379d](https://github.com/alvera-ai/atomic-fi/commit/613379d318a04493641b9c59951f86dc15a3edb6))
* **corpus:** idempotent inserts in mix corpus.validate ([28d4c7b](https://github.com/alvera-ai/atomic-fi/commit/28d4c7bef54e65af05401e4886162dfe67115768))
* **corpus:** isolate mix corpus.validate in its own Postgres schema ([c4a8519](https://github.com/alvera-ai/atomic-fi/commit/c4a8519394cfea3d3f26bcc447784c0e33cfd092))
* **corpus:** sharded bulk-bench pipeline — Shard emitter, SAML-D + AMLGentex mix tasks, sharded corpus.validate ([8a2cb68](https://github.com/alvera-ai/atomic-fi/commit/8a2cb68810ed319e60a995f1c444b847ee9582e7))
* **corpus:** StableAML upstream bootstrap — make reseed + mix generate ([bf0e2a6](https://github.com/alvera-ai/atomic-fi/commit/bf0e2a6f05e964c6e89f948630097865dcfc1f98))
* **issue-31:** scenario rollout ([2760b47](https://github.com/alvera-ai/atomic-fi/commit/2760b47442fe725969e7d916cac5ebb19781583f))
* **jdm-editor:** add api clients for phoenix + zenrule ([b318504](https://github.com/alvera-ai/atomic-fi/commit/b318504cc9ac36ae0eb88e05e11230aef2ae34c4))
* **jdm-editor:** rules index page + rule-type routes ([26dbf86](https://github.com/alvera-ai/atomic-fi/commit/26dbf86973a62c6be65f447d6dbdbe4bfc7d3c76))
* **jdm-editor:** split vite proxy for phoenix + zenrule ([bb82dc6](https://github.com/alvera-ai/atomic-fi/commit/bb82dc672dc7544a46432edaff6c1b1ccc20c2dc))
* **jdm-editor:** wire editor to RuleController + revision-counter dirty state ([962e1e9](https://github.com/alvera-ai/atomic-fi/commit/962e1e948e8f5ed41208f986f029919b6b9c498b))
* **legal-entity:** split BO subject_type into AH-BO and CP-BO ([924e3f8](https://github.com/alvera-ai/atomic-fi/commit/924e3f8f67d480fe6a9bc9f7c60e14efde40dc73))
* **lotus:** add lotus_web dependency and LotusRepo for embedded SQL dashboard ([4696a04](https://github.com/alvera-ai/atomic-fi/commit/4696a04517a85d1b06f8e83add79de4d7d8f4602))
* **lotus:** add React secure embed example app with E2E tests ([db2ce80](https://github.com/alvera-ai/atomic-fi/commit/db2ce804ee92c196a6e84a2d337bf08fa8a282b2))
* **lotus:** add secure iframe embed auth with Phoenix.Token ([793a30f](https://github.com/alvera-ai/atomic-fi/commit/793a30fcf71c078d59077e93997e73f0eb8d36ed))
* **lotus:** secure iframe embed with React POC and E2E tests ([f2a3af4](https://github.com/alvera-ai/atomic-fi/commit/f2a3af4581733769f149534e180002a18a3a2ca8))
* **onboarding-flow:** business onboarding with AI document extraction ([1a2d68f](https://github.com/alvera-ai/atomic-fi/commit/1a2d68f177e574a46d36ce16d1282cc820fd15f1))
* **onboarding-flow:** integrate document-agent-server for AI extraction ([4c80277](https://github.com/alvera-ai/atomic-fi/commit/4c80277e765e4bb842d97c36717dfd58c62a1360))
* **onboarding-flow:** show full entity details on status page after submission ([7bf70e1](https://github.com/alvera-ai/atomic-fi/commit/7bf70e1cadcfa7cd87276cf7b841470f593cb873))
* **onboarding-flow:** wire M1 API integration and Playwright E2E test ([5eeb8a1](https://github.com/alvera-ai/atomic-fi/commit/5eeb8a1f34d4dc7fe3bedc53d965de8d5bed6c90))
* **onboarding:** add refresh endpoint + thin worker + fail-loud schemas ([274b07d](https://github.com/alvera-ai/atomic-fi/commit/274b07db639286d87852a2d631b23e45608cfd49))
* **rule_engine:** synthesize per-PA las[] + compliance_screenings[] in payload ([9c1de34](https://github.com/alvera-ai/atomic-fi/commit/9c1de34bfc03c217aaeb8171ab72984c24faf031))
* **rule-engine:** ofac_sdn_match honors false_positive_qualifier ([9dce797](https://github.com/alvera-ai/atomic-fi/commit/9dce797b265de270fddda6f19313eef6ee427ca9))
* **rule-engine:** project country_of_residence onto party legal_entity (scenario [#15](https://github.com/alvera-ai/atomic-fi/issues/15)) ([0081dd2](https://github.com/alvera-ai/atomic-fi/commit/0081dd2d115782715d62e041f80f685ca2c299ba))
* **rule-engine:** structural LA resolution + effective_control merge + k6 VU fan-out ([c9c14a8](https://github.com/alvera-ai/atomic-fi/commit/c9c14a890663940546723f53c5e482b90d0b9182))
* **rules:** add ah_country_kp_residence rule + corpus + proof (scenario [#15](https://github.com/alvera-ai/atomic-fi/issues/15)) ([a4a7b25](https://github.com/alvera-ai/atomic-fi/commit/a4a7b253da8eab15a2454e5c81c2bfd5d7ba5bf8))
* **rules:** add prohibited_risk_freeze rule + corpus + proof (scenario [#10](https://github.com/alvera-ai/atomic-fi/issues/10)) ([bc120a5](https://github.com/alvera-ai/atomic-fi/commit/bc120a533f703595874d99dabc4b06e008c9c6b3))
* **rules:** ship [#41](https://github.com/alvera-ai/atomic-fi/issues/41) internal_blocklist_lastname + [#20](https://github.com/alvera-ai/atomic-fi/issues/20) smurfing_pattern_sar_eligible — eval 10/10 ([0e6e36c](https://github.com/alvera-ai/atomic-fi/commit/0e6e36c0f0ac7a1387ee30699c20d32fec6eda75))
* **scenario-author:** merge zenrule-author + corpus-from-rule into one skill + eval harness ([a315ba4](https://github.com/alvera-ai/atomic-fi/commit/a315ba43033e367c52c61ebae0797cd978e6a211))
* **zenrule:** de_minimis emits per-LA Control + stablecoin KYC gate (3/3 corpus green) ([7bf143e](https://github.com/alvera-ai/atomic-fi/commit/7bf143e655b61dbc60f0274d9452063dbb371add))
* **zenrule:** permissive onboarding rule replaces SQL unblock shim ([2392644](https://github.com/alvera-ai/atomic-fi/commit/239264420d943f04be7b3081eb06019195a6d124))


### Bug Fixes

* add LotusRepo config to test.exs to fix CI ([9be41f7](https://github.com/alvera-ai/atomic-fi/commit/9be41f7eed734ba2032755ff30765f00567ed475))
* **jdm-editor:** align rules index visual language with editor ([a3a1892](https://github.com/alvera-ai/atomic-fi/commit/a3a18924114a9b0d39ba76079438fad1c1d69c73))
* **jdm-editor:** point phoenix proxy at :4100 (not :4000) ([fe2ef08](https://github.com/alvera-ai/atomic-fi/commit/fe2ef08cea6aaec5caa7323eb69cae40eddf783f))
* **jdm-editor:** swap theme tokens via CSS vars for dark mode ([f78a760](https://github.com/alvera-ai/atomic-fi/commit/f78a7600c455bd70a902140a2cb01524de633819))
* **ledger:** materialise LA tree on AccountHolder update ([69cdfb4](https://github.com/alvera-ai/atomic-fi/commit/69cdfb4975b7acb2b26b3b1258ea7c5c7a51a225))
* **onboarding-flow:** correct FieldProvenance type in processSampleEntries ([cb54203](https://github.com/alvera-ai/atomic-fi/commit/cb54203ecc1cdfa6a4865eeb0c6837a084662088))
* **onboarding-flow:** fix submission bugs and add full E2E test ([ed98e00](https://github.com/alvera-ai/atomic-fi/commit/ed98e00404424e14da47399088631f878fc5873c))
* **onboarding-flow:** lower image dimension threshold to 100x100 ([6ac7cd0](https://github.com/alvera-ai/atomic-fi/commit/6ac7cd065871f2ba612bf5e2bd80c9372cdad575))
* **onboarding-flow:** resolve lint errors in app code ([9504878](https://github.com/alvera-ai/atomic-fi/commit/950487831039e26345da3566ca7a755cce69cd7b))
* resolve RuleEngine infinite recursion and onboarding submission bugs ([bd78551](https://github.com/alvera-ai/atomic-fi/commit/bd78551ae1013e346c73f1b9d6c667cc55af3149))
* **rule_engine:** config pointed :rule_engine at dispatcher → infinite recursion ([4921a44](https://github.com/alvera-ai/atomic-fi/commit/4921a44f363579cbcfc7c887a3c5e9256d204a4b))
* **transactions:** promote pending → accepted when no rule blocks ([d4ad6b1](https://github.com/alvera-ai/atomic-fi/commit/d4ad6b1ce37439d48a3a5697c6aababe434b5504))
* **zenrule:** null-guard de_minimis filter; relocate proof.md to corpus dir ([af9d1c9](https://github.com/alvera-ai/atomic-fi/commit/af9d1c9c5bc7324381d29e2eb3c3d20c28fa0cbc))

## [1.4.0](https://github.com/alvera-ai/atomic-fi/compare/v1.3.0...v1.4.0) (2026-05-15)


### Features

* **api:** add REST RuleController over RulesContext ([f766937](https://github.com/alvera-ai/atomic-fi/commit/f76693775e53460911a9a1f31489b0e9eb06753d))
* **bruno:** add atomic-fi-smoke collection (29 requests, single Run All) ([1e67a5d](https://github.com/alvera-ai/atomic-fi/commit/1e67a5d109d462b9490e3fede43e0ea41fc761b2))
* **counterparties:** cast_assoc(:legal_entity) + get-or-create on counterparty_number ([#27](https://github.com/alvera-ai/atomic-fi/issues/27)) ([e4c806f](https://github.com/alvera-ai/atomic-fi/commit/e4c806f69f9031af3013410319a49709eb911511))
* **jdm-editor:** vendor gorules/editor frontend, wire simulator to ZenRule agent ([29a4db7](https://github.com/alvera-ai/atomic-fi/commit/29a4db76784d94b3bc6afcb905a9a73070c0b338))
* **ledger:** create_entries + create_transaction flow; drop ledger-account side; PA enabled_regimes; worklog ([e76c103](https://github.com/alvera-ai/atomic-fi/commit/e76c1038c8326278700cb0b9654e58ce82469155))
* **ledger:** extend LA tree with AH roots + belt-and-suspenders enforcement ([8d5f320](https://github.com/alvera-ai/atomic-fi/commit/8d5f32006b0be84b6858cb1f71a86332bd011c4f))
* **ledger:** la_type tree + trigger-maintained ancestor/descendant_ids ([8d5cd25](https://github.com/alvera-ai/atomic-fi/commit/8d5cd256b66674ad1b73ae0f95f57c075f336e97))
* **ledger:** PA/CP write lifecycle materialises direct-line LedgerAccounts ([3b90a75](https://github.com/alvera-ai/atomic-fi/commit/3b90a7531bde5fa8d3e726c967c8ca8373b83bfa))
* **ledger:** rule-engine velocity limits — schema layer + RuleEngine behaviour (WIP) ([4a83f6b](https://github.com/alvera-ai/atomic-fi/commit/4a83f6b42003682d84a374b54a3e5f3134d3a547))
* **onboarding:** ControlProtocol + OnboardingWorker + AH ledger fan-out ([1d5c2ac](https://github.com/alvera-ai/atomic-fi/commit/1d5c2ac46a35e9c0fb7b9aa5a7727a088f6361bd))
* **onboarding:** introduce OnboardingContext for synchronous screen+engine+apply ([ecb95b3](https://github.com/alvera-ai/atomic-fi/commit/ecb95b3455ab393fc93233e2dedbdd6549b5c7db))
* **regimes:** hierarchical enabled_regimes (config → Tenant → AH → CP → PA) ([b41e4f1](https://github.com/alvera-ai/atomic-fi/commit/b41e4f1f6b4c276d8a907ddc4dc8e2bf7b2663dc))
* **rules:** add RulesContext fs wrapper + split JDM rules per rule_type ([6cc3bd7](https://github.com/alvera-ai/atomic-fi/commit/6cc3bd7c19db5a2b8dcc28c61e37d869007bbb5b))
* **screening:** facts-only engine + stateless preview endpoints ([82e2d26](https://github.com/alvera-ai/atomic-fi/commit/82e2d26acd739bcf3f93d21be587d33df6328aea))
* **skill:** add zenrule-author for English-to-JDM rule authoring ([4f0bc02](https://github.com/alvera-ai/atomic-fi/commit/4f0bc021d8108eaf933d87942fff7ac9f8b4b721))


### Bug Fixes

* **assets:** convert vendor/topbar.js to ESM ([#24](https://github.com/alvera-ai/atomic-fi/issues/24)) ([3ba817c](https://github.com/alvera-ai/atomic-fi/commit/3ba817ca622d06e4b390156ea9bd9285b981ca6a))
* **jdm-editor:** unblock simulator — agent hot-reload + Graph→Input tab ([d63ec2f](https://github.com/alvera-ai/atomic-fi/commit/d63ec2fbe34cc07603a9a474b600161c99cd3563))
* **make:** unbreak run-backing-services; align compose watchman with upstream ([#27](https://github.com/alvera-ai/atomic-fi/issues/27)) ([77a3678](https://github.com/alvera-ai/atomic-fi/commit/77a367891753a6b45935efa6a7cfc61ad6fa6311))
* **rule_engine:** log when decode_rule_result hits the catch-all ([0825def](https://github.com/alvera-ai/atomic-fi/commit/0825def585ede8d2f283760e3501e5e91c9df9af))
* **test:** wire ExCoveralls into mix.exs test_coverage ([#27](https://github.com/alvera-ai/atomic-fi/issues/27)) ([12ee652](https://github.com/alvera-ai/atomic-fi/commit/12ee6522aafe19588a697d0efc38991ad1241bcd))

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

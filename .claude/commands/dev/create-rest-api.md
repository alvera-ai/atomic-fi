---
name: create-rest-api
description: Create an atomic-fi REST API endpoint end-to-end — schema annotations, controller, route, ApiSpec tag, and schema-validated tests
when_to_use:
  - Exposing an atomic-fi resource (account holder, legal entity, beneficial owner, counterparty, transaction, ledger account, payment account, etc.)
  - Adding CRUD endpoints to an existing context
  - Wiring an endpoint that uses `x-api-key` (M2M) and/or `Authorization: Bearer` (human session) auth via `AtomicFiApi.Plugs.ApiAuthentication`
related_commands:
  - /qa:check-api-quality (verify the result — the checker side of this maker)
  - /qa:quality-checks (run before committing — REQUIRED)
  - /qa:increase-test-coverage (push controller + schema modules to 100%)
---

# Create a REST API Endpoint

One skill, one end-to-end result: OpenApiSpex schema annotations on the
Ecto schema, controller with `OpenApiSpex.ControllerSpecs`, route under
`/api`, tag registered in `ApiSpec`, and a test file with
`assert_schema`-validated assertions.

The canonical example throughout this skill is **Counterparty**, a real,
idiomatic atomic-fi resource. When building your own, swap `Counterparty`
for your resource name everywhere.

## Usage

```
/dev:create-rest-api <ResourceName> <ContextModule> <SchemaModule>
```

`ResourceName` — e.g. `Counterparty`, `AccountHolder`, `BeneficialOwner`
`ContextModule` — e.g. `AtomicFi.CounterpartyContext`
`SchemaModule` — e.g. `AtomicFi.CounterpartyContext.Counterparty`

---

## Auth model

atomic-fi has a **single** auth plug — `AtomicFiApi.Plugs.ApiAuthentication`
— wired through the `:api_authenticated` pipeline in
`lib/atomic_fi_web/router.ex`. It accepts both credential types in one
pass:

| Header | Subject | `conn.assigns` set |
|---|---|---|
| `x-api-key: <key>` | `%ApiKey{}` (M2M / system) | `:current_api_key`, `:api_session`, `:session_id` |
| `Authorization: Bearer <token>` | `%User{}` session (human via `POST /api/sessions`) | `:current_user`, `:api_session`, `:session_id` |

**Either way, `conn.assigns.api_session` is the session struct your
controller pattern-matches.** Authorization (per-action role checks) is
the controller's job, not the plug's.

Atomic-fi is **tenant-only** under `/api` — there is no datalake-scoped
pipeline. Multi-tenancy is enforced via RLS keyed on `session.tenant_id`
(handled by the `def_with_rls_and_logging` macro in the context).

---

## End-to-end walkthrough — Counterparty as the worked example

The files you'll touch (or create) when adding a new endpoint:

| Layer | File | Purpose |
|---|---|---|
| Schema | `lib/atomic_fi/counterparty_context/counterparty.ex` | Ecto schema + `open_api_property` / `open_api_schema` annotations |
| Context | `lib/atomic_fi/counterparty_context.ex` | Public functions, all wrapped in `def_with_rls_and_logging` |
| Controller | `lib/atomic_fi_api/controllers/counterparty_controller.ex` | `use OpenApiSpex.ControllerSpecs`, one `operation :name` per action |
| Routes | `lib/atomic_fi_api/routes.ex` | `get`/`post`/`put`/`delete` paths under `/api` |
| ApiSpec | `lib/atomic_fi_api/api_spec.ex` | `%Tag{name: "Counterparties", description: "..."}` registered |
| Test | `test/atomic_fi_api/controllers/counterparty_controller_test.exs` | `assert_schema`-driven, real DB, real Watchman where applicable |

---

### Step 1: Schema + OpenAPI annotations

`lib/atomic_fi/counterparty_context/counterparty.ex`:

```elixir
defmodule AtomicFi.CounterpartyContext.Counterparty do
  use AtomicFi.Schema    # NOT `use ExOpenApiUtils` — AtomicFi.Schema already does that

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.LegalEntityContext.LegalEntity
  alias AtomicFi.TenantContext.Tenant

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [:id, :tenant_id, :account_holder_id, :status],
    sortable: [:id, :inserted_at, :updated_at, :status],
    default_limit: 20,
    max_limit: 100
  }

  # readOnly fields — appear only in Response, excluded from Request
  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)
  open_api_property(schema: %Schema{type: :string, format: :"date-time", readOnly: true}, key: :inserted_at)
  open_api_property(schema: %Schema{type: :string, format: :"date-time", readOnly: true}, key: :updated_at)
  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :tenant_id)

  # Bidirectional fields — appear in both Request and Response
  open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :account_holder_id)
  open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :legal_entity_id)
  open_api_property(schema: %Schema{type: :string, enum: ["active", "suspended", "blocked"]}, key: :status)

  open_api_schema(
    title: "Counterparty",        # MUST match module name exactly — no spaces
    description: "External payer/payee that an AccountHolder transacts with (ISO 20022 <Dbtr>/<Cdtr>)",
    required: [:account_holder_id, :legal_entity_id, :status],
    properties: [:id, :account_holder_id, :legal_entity_id, :status, :tenant_id, :inserted_at, :updated_at]
  )

  schema "counterparties" do
    belongs_to :account_holder, AccountHolder, type: :binary_id
    belongs_to :legal_entity, LegalEntity, type: :binary_id
    belongs_to :tenant, Tenant, type: :binary_id
    field :status, Ecto.Enum, values: [:active, :suspended, :blocked]
    timestamps()
  end

  def changeset(counterparty, attrs) do
    counterparty
    |> cast(attrs, [:account_holder_id, :legal_entity_id, :status, :tenant_id])
    |> validate_required([:account_holder_id, :legal_entity_id, :status, :tenant_id])
    |> unique_constraint([:account_holder_id, :legal_entity_id])
  end
end
```

Key rules from [CLAUDE.md § OpenAPI Schema Patterns](../../../CLAUDE.md):

- `open_api_schema(title: "Counterparty", ...)` — title must match the
  module name **exactly**, no spaces. This generates
  `AtomicFi.OpenApiSchema.CounterpartyRequest` and
  `AtomicFi.OpenApiSchema.CounterpartyResponse` at compile time.
- `readOnly: true` on `:id`, `:inserted_at`, `:updated_at`, `:tenant_id` —
  server-generated, never in Request schema, always in Response.
- For sensitive input (passwords, tokens), use `writeOnly: true` instead.
- For nested embedded schemas (e.g. arrays of `%InterestedCompany{}`),
  reference auto-generated variants via `$ref`:
  `%OpenApiSpex.Reference{"$ref": "#/components/schemas/InterestedCompanyRequest"}`.

---

### Step 2: Context functions

`lib/atomic_fi/counterparty_context.ex`:

```elixir
defmodule AtomicFi.CounterpartyContext do
  use AtomicFi.LoggerMacro   # provides def_with_rls_and_logging

  import Ecto.Query, warn: false

  alias AtomicFi.OpenApiSchema.CounterpartyRequest
  alias AtomicFi.Repo
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.SessionContext.Session

  def_with_rls_and_logging list_counterparties(session, flop_params \\ %{}),
    log_fields: [] do
    Flop.validate_and_run(Counterparty, flop_params, for: Counterparty)
  end

  def_with_rls_and_logging get_counterparty!(session, id), log_fields: [:id] do
    Repo.get!(Counterparty, id)
  end

  def_with_rls_and_logging create_counterparty(session, %CounterpartyRequest{} = request),
    log_fields: [] do
    %Counterparty{}
    |> Counterparty.changeset(request)
    |> Repo.insert(session: session)
  end

  def_with_rls_and_logging update_counterparty(
                            session,
                            %Counterparty{} = counterparty,
                            %CounterpartyRequest{} = request
                          ),
                          log_fields: [:id] do
    counterparty
    |> Counterparty.changeset(request)
    |> Repo.update(session: session)
  end

  def_with_rls_and_logging delete_counterparty(session, %Counterparty{} = counterparty),
    log_fields: [:id] do
    Repo.delete(counterparty, session: session)
  end
end
```

Critical points (per [CLAUDE.md § Controller / Context Contract](../../../CLAUDE.md)):

- Pattern-match the typed `%CounterpartyRequest{}` struct in the function head.
- Pass the struct directly to `Counterparty.changeset(...)` — the
  `ExOpenApiUtils.Changeset.cast/3` macro (wired in via `use AtomicFi.Schema`)
  handles the struct-to-map conversion internally. **No** `Map.from_struct`.
  **No** `Mapper.to_map`.
- `def_with_rls_and_logging` wraps the function so RLS is scoped from
  `session.tenant_id` automatically, and a structured Logger call is emitted
  with the named `log_fields`.

---

### Step 3: Controller

`lib/atomic_fi_api/controllers/counterparty_controller.ex`:

```elixir
defmodule AtomicFiApi.CounterpartyController do
  use AtomicFiApi, :controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.CounterpartyContext
  alias AtomicFi.OpenApiSchema.CounterpartyRequest
  alias AtomicFiApi.Helpers.ApiHelpers

  tags ["Counterparties"]

  operation :index,
    summary: "List counterparties",
    parameters: [
      page: [in: :query, type: :integer, description: "Page number", example: 1],
      page_size: [in: :query, type: :integer, description: "Page size", example: 20]
    ],
    responses: [
      ok: {"Paginated counterparties", "application/json", AtomicFi.OpenApiSchema.CounterpartyListResponse}
    ]

  def index(%{assigns: %{api_session: session}} = conn, params) do
    with {:ok, {counterparties, meta}} <- CounterpartyContext.list_counterparties(session, params) do
      ApiHelpers.json_paginated_response(conn, counterparties, meta, AtomicFi.OpenApiSchema.CounterpartyResponse)
    end
  end

  operation :create,
    summary: "Create counterparty",
    request_body: {"Counterparty request", "application/json", CounterpartyRequest},
    responses: [
      created: {"Counterparty created", "application/json", AtomicFi.OpenApiSchema.CounterpartyResponse}
    ]

  def create(%{body_params: %CounterpartyRequest{} = request, assigns: %{api_session: session}} = conn, %{}) do
    with {:ok, counterparty} <- CounterpartyContext.create_counterparty(session, request) do
      conn
      |> put_status(:created)
      |> ApiHelpers.json_response(counterparty, AtomicFi.OpenApiSchema.CounterpartyResponse)
    end
  end

  operation :update,
    summary: "Update counterparty",
    parameters: [id: [in: :path, type: :string, format: :uuid, required: true]],
    request_body: {"Counterparty request", "application/json", CounterpartyRequest},
    responses: [
      ok: {"Counterparty updated", "application/json", AtomicFi.OpenApiSchema.CounterpartyResponse}
    ]

  def update(%{body_params: %CounterpartyRequest{} = request, assigns: %{api_session: session}} = conn, %{id: id}) do
    counterparty = CounterpartyContext.get_counterparty!(session, id)

    with {:ok, updated} <- CounterpartyContext.update_counterparty(session, counterparty, request) do
      ApiHelpers.json_response(conn, updated, AtomicFi.OpenApiSchema.CounterpartyResponse)
    end
  end

  # show + delete elided for brevity
end
```

Critical points (per [CLAUDE.md § Controller / Context Contract](../../../CLAUDE.md)):

- **`%{assigns: %{api_session: session}}`** in the handler head — NOT
  `conn.assigns.api_session` inside the body.
- **`%{body_params: %CounterpartyRequest{} = request}`** in the handler head —
  Phoenix already cast the JSON body into the typed struct via the
  `OpenApiSpex.Plug.CastAndValidate` plug. Pass it directly.
- **No `Map.from_struct`, no `Mapper.to_map`**, no `request_to_attrs`. The
  struct goes to the context unchanged.
- **`PUT` for update**, not `PATCH`. atomic-fi disallows `PATCH` outright.
- Use `ApiHelpers.json_response/3` and `ApiHelpers.json_paginated_response/4`
  for responses — never ad-hoc `json(conn, %{data: struct})`.

---

### Step 4: Routes

`lib/atomic_fi_api/routes.ex` — add to the existing tenant-scoped `/api`
scope (note: there is **no** `:datalake_slug` in atomic-fi paths):

```elixir
scope "/api", AtomicFiApi do
  pipe_through [:api, :api_authenticated]

  # ...

  get "/counterparties", CounterpartyController, :index
  get "/counterparties/:id", CounterpartyController, :show
  post "/counterparties", CounterpartyController, :create
  put "/counterparties/:id", CounterpartyController, :update
  delete "/counterparties/:id", CounterpartyController, :delete
end
```

Quality gate: **no `patch` routes anywhere**. If you find one (`grep -nE '^\s+patch\s' lib/atomic_fi_api/routes.ex`), it's a bug — convert to `put`.

---

### Step 5: ApiSpec tag

`lib/atomic_fi_api/api_spec.ex` — add the tag to the `tags:` list (atomic-fi
uses a flat `tags:` list; no `x-tagGroups`):

```elixir
tags: [
  # ... existing tags
  %Tag{
    name: "Counterparties",
    description:
      "External payers/payees (ISO 20022 <Dbtr>/<Cdtr>) that AccountHolders transact with. " <>
        "PII lives in the linked Legal Entity."
  },
  # ...
]
```

Tag names CAN have spaces here (atomic-fi tags include "Account Holders",
"Legal Entities", "Compliance Screening", etc.). What CAN'T have spaces is
the `open_api_schema(title: ...)` from Step 1 — that title is used to
generate the Elixir module name.

Also register the auto-generated schemas in the `components.schemas` map
(usually a few lines up in `api_spec.ex`):

```elixir
"CounterpartyRequest" => OpenApiSchema.CounterpartyRequest.schema(),
"CounterpartyResponse" => OpenApiSchema.CounterpartyResponse.schema(),
"CounterpartyListResponse" => OpenApiSchema.CounterpartyListResponse.schema()
```

---

### Step 6: Controller test

`test/atomic_fi_api/controllers/counterparty_controller_test.exs`:

```elixir
defmodule AtomicFiApi.CounterpartyControllerTest do
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AtomicFi.Factory

  alias AtomicFiApi.ApiSpec

  setup :setup_platform_admin_api

  setup %{platform_tenant: platform_tenant} do
    account_holder = insert(:account_holder, tenant_id: platform_tenant.id)
    legal_entity = insert(:legal_entity, tenant_id: platform_tenant.id)
    %{account_holder: account_holder, legal_entity: legal_entity}
  end

  describe "POST /api/counterparties" do
    test "creates counterparty and returns Response schema",
         %{conn: conn, platform_tenant: t, account_holder: ah, legal_entity: le} do
      attrs = %{
        status: "active",
        account_holder_id: ah.id,
        legal_entity_id: le.id,
        tenant_id: t.id
      }

      conn = post(conn, ~p"/api/counterparties", attrs)
      json = json_response(conn, 201)
      assert_schema(json, "CounterpartyResponse", ApiSpec.spec())
      assert json["status"] == "active"
    end

    test "rejects invalid body with 4xx + schema-validated error",
         %{conn: conn} do
      conn = post(conn, ~p"/api/counterparties", %{status: nil})
      json = json_response(conn, 422)
      assert_schema(json, "ErrorResponse", ApiSpec.spec())
    end
  end

  describe "RLS isolation" do
    test "tenant A cannot see tenant B's counterparty",
         %{conn: conn, platform_tenant: tenant_a} do
      tenant_b = insert(:tenant)
      ah_b = insert(:account_holder, tenant_id: tenant_b.id)
      le_b = insert(:legal_entity, tenant_id: tenant_b.id)
      _hidden = insert(:counterparty, tenant_id: tenant_b.id, account_holder_id: ah_b.id, legal_entity_id: le_b.id)

      conn = get(conn, ~p"/api/counterparties")
      json = json_response(conn, 200)
      assert_schema(json, "CounterpartyListResponse", ApiSpec.spec())
      assert json["data"] == []  # tenant A's session, nothing of tenant B's visible
    end
  end
end
```

Critical points:

- **`use AtomicFiWeb.ConnCase, async: false`** — `async: true` is only safe
  for tests that don't touch Watchman / BlocklistCache shared resources.
- **`setup :setup_platform_admin_api`** — wires the platform tenant + admin
  API key + session into `conn` (see `test/support/conn_case.ex`). The setup
  context yields `:conn`, `:platform_tenant`, `:api_key`, `:session`.
- **Every `json_response(conn, 200|201)` is followed by an `assert_schema(...)` call.**
  No assertion is allowed to pass without verifying the response matches
  the OpenAPI spec.
- **At least one RLS isolation test** — insert in tenant B, then assert the
  tenant-A session does not see it. This protects against future RLS
  regressions.
- **At least one negative test** — invalid body returns 4xx + a
  schema-validated `ErrorResponse`.

---

## Common gotchas

### 1. `open_api_schema(title: ...)` with a space

```elixir
# ❌ wrong — generates "Account Holder"Request which is invalid
open_api_schema(title: "Account Holder", ...)

# ✅ correct — generates AccountHolderRequest / AccountHolderResponse
open_api_schema(title: "AccountHolder", ...)
```

The tag in `api_spec.ex` can be `"Account Holders"` (with spaces, for the
human-readable Scalar UI). The schema `title:` cannot.

### 2. Forgetting `readOnly: true` on server-generated fields

If `inserted_at` doesn't have `readOnly: true`, it leaks into the Request
schema. Tests that send a Request body without `inserted_at` will then fail
spec validation. Add `readOnly: true` to anything the server generates
(`id`, `inserted_at`, `updated_at`, `tenant_id`, generated UUIDs).

### 3. `oneOf` / `allOf` / `anyOf` with bare module references

```elixir
# ❌ wrong — module ref is a compile-time alias, not a schema struct
oneOf: [AccountHolder, BeneficialOwner]

# ✅ correct — use $ref
oneOf: [
  %OpenApiSpex.Reference{"$ref": "#/components/schemas/AccountHolderResponse"},
  %OpenApiSpex.Reference{"$ref": "#/components/schemas/BeneficialOwnerResponse"}
]
```

### 4. `Map.from_struct` slipping into the controller

Symptom: the controller does

```elixir
def create(conn, params) do
  request = struct(CounterpartyRequest, params)
  attrs = Map.from_struct(request)            # ❌ wrong
  CounterpartyContext.create_counterparty(session, attrs)
end
```

Fix per [CLAUDE.md](../../../CLAUDE.md): pattern-match the struct in the
handler head, pass the struct unchanged to the context:

```elixir
def create(%{body_params: %CounterpartyRequest{} = request, assigns: %{api_session: session}} = conn, %{}) do
  with {:ok, cp} <- CounterpartyContext.create_counterparty(session, request) do
    # ...
  end
end
```

[`/qa:check-api-quality`](../qa/check-api-quality.md) flags this
automatically — run it before opening a PR.

### 5. Adding a PATCH route

atomic-fi disallows `PATCH` outright. If you find yourself reaching for it,
use `PUT` with a full resource body instead. The `resources/4` macro
generates both `PUT` and `PATCH` when you include `:update` in `only:` —
use explicit `put "/path/:id"` route declarations to keep things tight.

---

## After you're done

Run the full quality gate before opening a PR:

```bash
mix compile --warnings-as-errors
mix quality                       # format + sobelow + credo
mix test                          # full suite green
mix coveralls 2>&1 | tail -10     # ≥ baseline, target 95%
```

Then verify structural compliance:

```
/qa:check-api-quality lib/atomic_fi_api/controllers/counterparty_controller.ex
```

The checker is the maker's mirror — it greps for every invariant this skill
documents. Both must agree.

Finally:

```bash
git commit -S -m "feat(counterparties): add /api/counterparties CRUD endpoints

- Schema: CounterpartyContext.Counterparty with open_api_schema/property
- Context: list/get/create/update/delete wrapped in def_with_rls_and_logging
- Controller: typed CounterpartyRequest in handler head; no Mapper.to_map
- Routes: GET/POST/PUT/DELETE under /api/counterparties (tenant-scoped, RLS)
- ApiSpec: 'Counterparties' tag + 3 schemas registered
- Tests: assert_schema-validated, includes RLS isolation + negative case

Refs: #<issue>"
```

---

## Related Commands

- [/qa:check-api-quality](../qa/check-api-quality.md) — the structural checker that mirrors this maker
- [/qa:quality-checks](../qa/quality-checks.md) — pre-commit gate (REQUIRED before commit)
- [/qa:fix-failing-tests](../qa/fix-failing-tests.md) — iterate on failing tests via `mix test --failed`
- [/qa:increase-test-coverage](../qa/increase-test-coverage.md) — push the new controller + schema toward 100%
- [/qa:review](../qa/review.md) — multi-agent code review for pre-PR

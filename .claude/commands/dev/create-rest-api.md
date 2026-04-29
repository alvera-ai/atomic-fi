---
name: create-rest-api
description: Create a Management REST API endpoint end-to-end — schemas, controller, routes, ApiSpec tag, and schema-validated tests
when_to_use:
  - Building a new tenant/datalake-scoped Management API endpoint
  - Exposing a platform resource (workflows, DACs, agents, tools, datasets)
  - Wiring ingestion-only (M2M) or delegated (Bearer) auth
related_guides:
  - guides/core-infra/access_control.md
  - guides/howtos/howto_manage_tenants.md
  - guides/cheatsheet/quality_gates.cheatmd
related_commands:
  - /qa:check-api-quality (verify the result)
  - /qa:quality-checks (run before committing — REQUIRED)
  - /qa:increase-test-coverage (push controller + schema modules to 100%)
---

# Create Management REST API

One skill, one end-to-end result: schemas, controller, routes, `ApiSpec`
tag, and a full test file with 3-layer schema-validated assertions.

## Usage

```
/dev:create-rest-api <resource_name> <context_module> <schema_module>
```

`resource_name` — e.g. `DataActivationClient`, `AiAgent`
`context_module` — e.g. `AtomicFi.DataActivationClients`
`schema_module` — e.g. `AtomicFi.DataActivationClients.DataActivationClient`

---

## Auth model — pick the right lane

Management APIs run on **one pipeline** but two credential types; the
allowed reach depends on which credential authenticated the request:

| Lane | Header | Backing subject | Typical use | PHI / regulated reach |
|---|---|---|---|---|
| **M2M** | `x-api-key` | `AtomicFi.ApiKeys` (role `:api`) | Ingestion endpoints (DAC push, workflow trigger), system integrations | **No** — narrow role scope |
| **Bearer / Connected App** | `Authorization: Bearer …` | Delegated human session via a Connected App | Humans reading/writing tenant data | **Yes** — gated by user role + RLS |
| **Bearer / AI agent** | `Authorization: Bearer …` | AI agent session | Agents executing inside DAC / Workflow runtimes | **No** — agent `data_access` pins it to tokenized/unregulated lanes |

The `fetch_api_key` plug accepts `x-api-key` first, then
`Authorization: Bearer`; both land a `current_session` in `conn.assigns`.
The endpoint itself doesn't choose between them — it publishes a
capability; whichever credential holder has the right role + agent
`data_access` gets through.

---

## Substrate

- `AtomicFi.Schema` — includes `ExOpenApiUtils`. **Never** also
  `use ExOpenApiUtils` (duplicate module definition).
- `ExOpenApiUtils` — `open_api_property/1` + `open_api_schema/1` generate
  `*Request` (POST/PUT body) + `*Response` (GET output) schemas at
  compile time.
- `OpenApiSpex.ControllerSpecs` — `operation :action, …` blocks bind
  request/response schemas to controller actions.
- `AtomicFiApi.ApiSpec` — assembled from the schemas in
  `lib/atomic_fi_api/schemas/`; consumed at runtime by the
  `OpenApiSpex.Plug.PutApiSpec` plug and at test time by
  `assert_schema/3`.
- `AtomicFi.Api.Helpers` — response builders
  (`ApiHelpers.json_response/3`, `list_resources_as_map/3`) that call
  `ExOpenApiUtils.Mapper.to_map/1` on each row.
- `AtomicFi.Test.ApiHelpers` — `setup_api_context/2`, `put_api_key/2`,
  path builders. Use these from tests; don't reinvent fixtures.

---

## Critical gotchas

### 1. `oneOf` / `allOf` / `anyOf` with module references won't resolve

```elixir
# ❌ wrong — module ref is a compile-time alias, not a schema struct
open_api_property(
  schema: %OASchema{oneOf: [AtomicFi.Some.Schema, %OASchema{type: :string}]},
  key: :value
)

# ✅ right — call .schema() to get the resolved struct
open_api_property(
  schema: %OASchema{
    nullable: true,
    allOf: [AtomicFi.OpenApiSchema.DatalakeResponse.schema()]
  },
  key: :datalake
)

# ✅ $ref only for genuine circular refs (A → B → A); register in ApiSpec
@datalake_ref %OpenApiSpex.Reference{"$ref": "#/components/schemas/DatalakeResponse"}
```

### 2. Pass the OpenAPI request struct *directly* to the context

`AtomicFi.Schema`'s generated changeset uses
`ExOpenApiUtils.Changeset.cast/4` which accepts the `%FooRequest{}`
struct. Do **not** `Map.from_struct/1` in the controller.

```elixir
# ❌ wrong
def create(conn, %{body_params: %ClientRequest{} = req}) do
  attrs = Map.from_struct(req)
  DataActivationClients.create_client(attrs)
end

# ✅ right
def create(%{body_params: %ClientRequest{} = req} = conn, _) do
  with {:ok, client} <- DataActivationClients.create_client(session(conn), req) do
    conn
    |> put_status(:created)
    |> ApiHelpers.json_response(client, ClientResponse)
  end
end
```

### 3. PUT for updates — **never PATCH**

Platform invariant (CLAUDE.md, [quality_gates](../../../guides/cheatsheet/quality_gates.cheatmd)).
Routes use `put/4` only.

---

## Step 1 — Annotate the Ecto schema

```elixir
defmodule AtomicFi.DataActivationClients.DataActivationClient do
  use AtomicFi.Schema

  open_api_property(schema: %OASchema{type: :string, format: :uuid}, key: :id, readOnly: true)
  open_api_property(schema: %OASchema{type: :string}, key: :name, description: "Client name")
  open_api_property(
    schema: %OASchema{type: :string, enum: ["api", "webhook", "cron"]},
    key: :source_type
  )

  open_api_schema(
    title: "DataActivationClient",
    description: "External data source configuration",
    required: [:name, :source_type],
    properties: [:id, :name, :source_type, :config, :inserted_at, :updated_at]
  )

  typed_schema "data_activation_clients" do
    field :name, :string
    field :source_type, Ecto.Enum, values: [:api, :webhook, :cron]
    field :config, :map
    belongs_to :datalake, Datalake

    timestamps(type: :utc_datetime_usec)
  end
end
```

At compile time this generates
`AtomicFi.OpenApiSchema.DataActivationClientRequest` (write) and
`AtomicFi.OpenApiSchema.DataActivationClientResponse` (read).

---

## Step 2 — Controller

`lib/atomic_fi_api/controllers/<resource>_controller.ex`:

```elixir
defmodule AtomicFiApi.DataActivationClientsController do
  use AtomicFiApi, :controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.Api.Helpers, as: ApiHelpers
  alias AtomicFi.DataActivationClients
  alias AtomicFi.OpenApiSchema.DataActivationClientRequest
  alias AtomicFi.OpenApiSchema.DataActivationClientResponse
  alias AtomicFi.OpenApiSchema.DataActivationClientListResponse

  action_fallback AtomicFiApi.FallbackController

  tags ["Data Activation Clients"]

  operation :index,
    summary: "List data activation clients",
    responses: [ok: {"OK", "application/json", DataActivationClientListResponse}]

  def index(%{assigns: %{current_session: session}} = conn, params) do
    clients = DataActivationClients.list_clients(session, params)
    ApiHelpers.list_response(conn, clients, DataActivationClientResponse, params)
  end

  operation :create,
    summary: "Create data activation client",
    request_body: {"Body", "application/json", DataActivationClientRequest},
    responses: [
      created: {"Created", "application/json", DataActivationClientResponse},
      unprocessable_entity: {"Errors", "application/json", %OASchema{type: :object}}
    ]

  def create(
        %{assigns: %{current_session: session}, body_params: %DataActivationClientRequest{} = req} = conn,
        _params
      ) do
    with {:ok, client} <- DataActivationClients.create_client(session, req) do
      conn
      |> put_status(:created)
      |> ApiHelpers.json_response(client, DataActivationClientResponse)
    end
  end

  # show/2, update/2 (PUT only), delete/2 follow the same shape
end
```

---

## Step 3 — Routes (tenant + datalake scoped)

`lib/atomic_fi_api/router.ex`:

```elixir
pipeline :api_authenticated do
  plug :accepts, ["json"]
  plug :fetch_api_key                     # X-API-Key OR Authorization: Bearer
  plug OpenApiSpex.Plug.PutApiSpec, module: AtomicFiApi.ApiSpec
end

scope "/api/v1/tenants/:tenant_slug/datalakes/:datalake_slug", AtomicFiApi do
  pipe_through :api_authenticated

  get    "/data-activation-clients",      DataActivationClientsController, :index
  get    "/data-activation-clients/:id",  DataActivationClientsController, :show
  post   "/data-activation-clients",      DataActivationClientsController, :create
  put    "/data-activation-clients/:id",  DataActivationClientsController, :update   # never patch
  delete "/data-activation-clients/:id",  DataActivationClientsController, :delete
end
```

---

## Step 4 — Register tag in `ApiSpec`

Tags are **1:1 with controllers** (client generators emit one class per tag).
`x-tagGroups` organise tags by capability area (maps to the how-to guides).

```elixir
# lib/atomic_fi_api/api_spec.ex
tags: [
  …,
  %OpenApiSpex.Tag{name: "Data Activation Clients", description: "DAC CRUD"}
]

extensions: %{
  "x-tagGroups" => [
    %{"name" => "Data Activation", "tags" => ["Data Activation Clients", …]}
  ]
}
```

Use the **tag name** (not group name) in the controller's `tags [...]`.

---

## Step 5 — Tests (3-layer schema validation)

`test/atomic_fi_api/controllers/<resource>_controller_test.exs`:

```elixir
defmodule AtomicFiApi.DataActivationClientsControllerTest do
  use AtomicFiWeb.ConnCase, async: true

  import OpenApiSpex.TestAssertions
  import AtomicFi.Test.ApiHelpers

  alias AtomicFi.OpenApiSchema.DatalakeResponse
  alias AtomicFi.OpenApiSchema.DataActivationClientResponse
  alias AtomicFi.OpenApiSchema.DataActivationClientListResponse
  alias AtomicFi.OpenApiSchema.PaginationMeta
  alias AtomicFi.OpenApiSchema.TenantResponse
  alias AtomicFiApi.ApiSpec

  setup %{conn: conn} do
    ctx = setup_api_context(conn, data_domain: :healthcare)
    client = insert(:data_activation_client, datalake_id: ctx.datalake.id)
    {:ok, Map.put(ctx, :client, client) |> Map.to_list()}
  end

  describe "GET index" do
    test "schema + pagination + row match", %{
      conn: conn, tenant: t, datalake: d, api_key_token: tok, client: c
    } do
      response =
        conn
        |> put_api_key(tok)
        |> get(~p"/api/v1/tenants/#{t.slug}/datalakes/#{d.slug}/data-activation-clients")
        |> json_response(200)

      client_id = c.id
      tenant_id = t.id
      datalake_id = d.id

      # Layer 1 — schema cast (OpenApiSpex.Cast.cast)
      assert %DataActivationClientListResponse{
               data: list,
               meta: %PaginationMeta{total_count: total}
             } = assert_schema(response, "DataActivationClientListResponse", ApiSpec.spec())

      # Layer 2 — typed struct destructure + pin-matched nested IDs
      assert Enum.any?(list, fn
               %DataActivationClientResponse{
                 id: ^client_id,
                 tenant: %TenantResponse{id: ^tenant_id},
                 datalake: %DatalakeResponse{id: ^datalake_id}
               } ->
                 true

               _ ->
                 false
             end)

      assert is_integer(total) and total >= 1
    end
  end

  describe "POST create" do
    test "schema + struct destructure + DB round-trip", %{
      conn: conn, tenant: t, datalake: d, session: session, api_key_token: tok
    } do
      response =
        conn
        |> put_api_key(tok)
        |> post(
          ~p"/api/v1/tenants/#{t.slug}/datalakes/#{d.slug}/data-activation-clients",
          %{"name" => "New", "source_type" => "api"}
        )
        |> json_response(201)

      tenant_id = t.id
      datalake_id = d.id

      assert %DataActivationClientResponse{id: id, name: "New", source_type: "api"} =
               cast = assert_schema(response, "DataActivationClientResponse", ApiSpec.spec())

      # Layer 3 — the DB row actually matches the response
      assert %AtomicFi.DataActivationClients.DataActivationClient{
               name: "New",
               source_type: :api,
               tenant_id: ^tenant_id,
               datalake_id: ^datalake_id
             } = AtomicFi.DataActivationClients.get_client!(session, cast.id)
    end
  end

  describe "PUT update (never PATCH)" do
    test "updates and returns fresh schema-valid response", %{
      conn: conn, tenant: t, datalake: d, api_key_token: tok, client: c
    } do
      response =
        conn
        |> put_api_key(tok)
        |> put(
          ~p"/api/v1/tenants/#{t.slug}/datalakes/#{d.slug}/data-activation-clients/#{c.id}",
          %{"name" => "Renamed"}
        )
        |> json_response(200)

      client_id = c.id

      assert %DataActivationClientResponse{id: ^client_id, name: "Renamed"} =
               assert_schema(response, "DataActivationClientResponse", ApiSpec.spec())
    end
  end

  describe "auth + isolation" do
    test "401 without credential", %{conn: conn, tenant: t, datalake: d} do
      conn = get(conn, ~p"/api/v1/tenants/#{t.slug}/datalakes/#{d.slug}/data-activation-clients")
      assert response(conn, 401)
    end

    test "other tenant's key — no cross-tenant leak", %{conn: conn, client: c} do
      other = setup_api_context(build_conn())
      conn =
        conn
        |> put_api_key(other.api_key_token)
        |> get(
          ~p"/api/v1/tenants/#{other.tenant.slug}/datalakes/#{other.datalake.slug}/data-activation-clients/#{c.id}"
        )

      assert json_response(conn, 404)
    end
  end
end
```

Cover: 5+ success, 5+ auth, 5+ validation (422 on missing required, 404
on unknown id).

---

## Step 6 — Generate spec YAML

```bash
zsh -l -c 'source ~/.zshrc && mix openapi.spec.yaml --spec AtomicFiApi.ApiSpec'
```

Output: `priv/static/openapi.yaml`. Check `git diff` to review the
generated shape before committing.

---

## Step 7 — Verify

```bash
zsh -l -c 'source ~/.zshrc && mix test test/atomic_fi_api/controllers/data_activation_clients_controller_test.exs --color 2>&1 | tee /tmp/test.txt'
```

Then hand off:

```
/qa:check-api-quality lib/atomic_fi_api/controllers/data_activation_clients_controller.ex
```

---

## Checklist

- [ ] Schema uses `use AtomicFi.Schema` (NOT also `use ExOpenApiUtils`)
- [ ] All fields have `open_api_property`
- [ ] `open_api_schema` block emits Request + Response
- [ ] No `oneOf`/`allOf` with bare module references — `.schema()` calls or `$ref`
- [ ] Controller uses `use OpenApiSpex.ControllerSpecs` with `operation` blocks per action
- [ ] Body-params destructured as `%FooRequest{}` and passed straight to context
- [ ] Responses built via `ApiHelpers.json_response/3` (calls `ExOpenApiUtils.Mapper.to_map/1`)
- [ ] Routes are tenant+datalake scoped and use `put/4` (never `patch/4`)
- [ ] Pipeline uses `:fetch_api_key` (M2M + Bearer both accepted)
- [ ] Tag registered in `ApiSpec` and added to the right `x-tagGroup`
- [ ] Tests import `AtomicFi.Test.ApiHelpers` + `OpenApiSpex.TestAssertions`
- [ ] Every 2xx response goes through `assert_schema/3`
- [ ] Create/update tests cross-check DB via context function
- [ ] `mix openapi.spec.yaml` regenerated
- [ ] `/qa:check-api-quality` green
- [ ] `/qa:quality-checks` green

---

## Related

- [test/support/api_helpers/api_helpers.ex](../../../test/support/api_helpers/api_helpers.ex) — shared test setup
- [lib/atomic_fi_api/api_spec.ex](../../../lib/atomic_fi_api/api_spec.ex) — `ApiSpec.spec()`
- [lib/atomic_fi_api/helpers/api_helpers.ex](../../../lib/atomic_fi_api/helpers/api_helpers.ex) — response builders
- [guides/core-infra/access_control.md](../../../guides/core-infra/access_control.md) — role + RLS model
- [guides/cheatsheet/quality_gates.cheatmd](../../../guides/cheatsheet/quality_gates.cheatmd) — commit gate

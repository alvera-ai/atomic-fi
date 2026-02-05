# Code Generators

The Alvera Phoenix Template includes custom Mix tasks for scaffolding common patterns.

## Available Generators

| Generator | Purpose | Output |
|-----------|---------|--------|
| `alvera.gen.context` | Ecto context + schema | Context, schema, migration, tests |
| `alvera.gen.live` | LiveView UI | Index, Edit, Form components |
| `alvera.gen.api` | REST API | Controller, JSON view, tests |

## alvera.gen.context

Generate an Ecto context with schema, migration, and tests.

### Usage

```bash
mix alvera.gen.context <Context> <Schema> <plural> [fields]
```

### Example

```bash
mix alvera.gen.context Blog Post posts \
  title:string:required \
  slug:string:unique \
  content:text \
  published_at:utc_datetime \
  status:string
```

### Generated Files

- `lib/alvera_phoenix_template_server/blog/post.ex` - Schema with TypedEctoSchema
- `lib/alvera_phoenix_template_server/blog.ex` - Context with CRUD functions
- `priv/repo/migrations/TIMESTAMP_create_posts.exs` - Migration
- `test/alvera_phoenix_template_server/blog_test.exs` - Context tests
- `test/support/fixtures/blog_fixtures.ex` - Test fixtures

### Field Types

| Type | Ecto Type | Example |
|------|-----------|---------|
| `string` | `:string` | `name:string` |
| `text` | `:text` | `content:text` |
| `integer` | `:integer` | `age:integer` |
| `float` | `:float` | `rating:float` |
| `decimal` | `:decimal` | `price:decimal` |
| `boolean` | `:boolean` | `active:boolean` |
| `date` | `:date` | `birthdate:date` |
| `time` | `:time` | `starts_at:time` |
| `datetime` | `:naive_datetime` | `published_at:datetime` |
| `utc_datetime` | `:utc_datetime` | `confirmed_at:utc_datetime` |
| `uuid` | `:binary_id` | `external_id:uuid` |
| `references` | `references/2` | `user_id:references:users` |

### Modifiers

- `:required` - Add NOT NULL constraint and validation
- `:unique` - Add unique index and constraint

Example: `email:string:unique:required`

## alvera.gen.live

Generate LiveView UI with Petal Components.

### Usage

```bash
mix alvera.gen.live <Context> <Schema> <plural> [fields] [options]
```

### Options

- `--data_table` - Include Flop data table (recommended)
- `--route_root <path>` - Custom route prefix (default: "/")
- `--no-context` - Skip context generation (if exists)

### Example

```bash
mix alvera.gen.live Blog Post posts \
  title:string \
  content:text \
  --data_table \
  --route_root "/admin"
```

### Generated Files

- `lib/alvera_phoenix_template_server_web/live/post_live/index.ex`
- `lib/alvera_phoenix_template_server_web/live/post_live/edit.ex`
- `lib/alvera_phoenix_template_server_web/live/post_live/form_component.ex`
- `lib/alvera_phoenix_template_server_web/live/post_live/index.html.heex`
- `lib/alvera_phoenix_template_server_web/live/post_live/edit.html.heex`
- `lib/alvera_phoenix_template_server_web/live/post_live/form_component.html.heex`
- `test/alvera_phoenix_template_server_web/live/post_live_test.exs`

### After Generation

1. **Add routes** to `router.ex`:

```elixir
scope "/admin", AlveraPhoenixTemplateServerWeb do
  pipe_through [:browser, :require_authenticated_user]

  live "/posts", PostLive.Index, :index
  live "/posts/new", PostLive.Index, :new
  live "/posts/:id/edit", PostLive.Edit, :edit
end
```

2. **Run tests**:

```bash
mix test test/alvera_phoenix_template_server_web/live/post_live_test.exs
```

## alvera.gen.api

Generate REST API controller with OpenAPI.

### Usage

```bash
mix alvera.gen.api <Context> <Schema> <plural> [fields]
```

### Options

- `--no-context` - Skip context generation
- `--no-schema` - Skip schema generation

### Example

```bash
mix alvera.gen.api Blog Post posts \
  title:string \
  content:text
```

### Generated Files

- `lib/alvera_phoenix_template_server_api/controllers/post_controller.ex`
- `lib/alvera_phoenix_template_server_api/controllers/post_json.ex`
- `test/alvera_phoenix_template_server_api/controllers/post_controller_test.exs`

### After Generation

1. **Add API routes** to `router.ex`:

```elixir
scope "/api", AlveraPhoenixTemplateServerApi do
  pipe_through :api

  scope "/" do
    pipe_through :api_auth

    resources "/posts", PostController, except: [:new, :edit]
  end
end
```

2. **Generate OpenAPI spec**:

```bash
mix openapi.spec.yaml
```

3. **Run tests**:

```bash
mix test test/alvera_phoenix_template_server_api/controllers/post_controller_test.exs
```

4. **View API docs**: http://localhost:4000/api/openapi

## Full Stack Example

Generate a complete CRUD resource with context, LiveView, and API:

```bash
# 1. Generate context
mix alvera.gen.context Accounts User users \
  email:string:unique:required \
  first_name:string \
  last_name:string \
  status:string

# 2. Generate LiveView (skip context)
mix alvera.gen.live Accounts User users \
  --no-context \
  --data_table \
  --route_root "/admin"

# 3. Generate API (skip context)
mix alvera.gen.api Accounts User users --no-context

# 4. Add routes (manually)
# 5. Run migrations
mix ecto.migrate

# 6. Run tests
mix test
```

## Multi-Tenancy Pattern

All generators automatically include multi-tenancy support:

- Schemas include `owner_id` field
- Migrations add `owner_id` references to `tenants`
- Context functions scope queries by `owner_id`
- Composite unique indexes: `[:field, :owner_id]`

Example generated schema:

```elixir
typed_schema "posts" do
  field :title, :string
  field :content, :text

  # Multi-tenancy
  belongs_to :owner, AlveraPhoenixTemplateServer.TenantContext.Tenant

  timestamps()
end
```

## Customizing Templates

Generator templates are in `priv/templates/mix/alvera.gen.*`:

```
priv/templates/mix/
├── alvera.gen.context/
│   ├── context.ex
│   ├── schema.ex
│   ├── context_test.exs
│   └── fixtures.ex
├── alvera.gen.live/
│   ├── index.ex
│   ├── edit.ex
│   ├── form_component.ex
│   └── live_test.exs
└── alvera.gen.api/
    ├── controller.ex
    ├── json.ex
    └── controller_test.exs
```

Modify these templates to change generator output.

## Best Practices

### Naming Conventions

- **Context**: Plural noun (e.g., `Accounts`, `Blog`)
- **Schema**: Singular noun (e.g., `User`, `Post`)
- **Table**: Plural snake_case (e.g., `users`, `posts`)

### Field Naming

- Use snake_case: `first_name`, `created_at`
- Boolean fields: `is_active`, `has_permission`
- Timestamps: Use `_at` suffix (`published_at`, `confirmed_at`)

### Multi-Step Generation

When generating multiple resources:

1. Generate context first
2. Generate LiveView with `--no-context`
3. Generate API with `--no-context`
4. This avoids duplicate context/schema files

### Testing After Generation

Always run tests immediately after generation:

```bash
mix test --only <context_name>
```

Fix any failing tests before proceeding.

## Troubleshooting

### "Module already defined"

Context or schema already exists. Use `--no-context` or `--no-schema`.

### "Table already exists"

Run `mix ecto.rollback` before regenerating.

### Routes not found

Add generated routes to `router.ex` manually. Generators provide route examples in output.

### Tests failing

- Check test fixtures in `test/support/fixtures/`
- Verify factory data is valid
- Ensure migrations ran: `mix ecto.migrate`

## Related Commands

- `mix phx.gen.schema` - Phoenix built-in schema generator
- `mix phx.gen.live` - Phoenix built-in LiveView generator
- `mix phx.gen.json` - Phoenix built-in JSON API generator

Alvera generators extend these with:
- TypedEctoSchema support
- OpenAPI annotations
- Multi-tenancy patterns
- Flop data tables
- Comprehensive tests

## Next Steps

- [Testing Guide](testing.md) - Write tests for generated code
- [API Development](api-development.md) - Work with REST APIs
- [Multi-Tenancy](multi-tenancy.md) - Understand tenant scoping

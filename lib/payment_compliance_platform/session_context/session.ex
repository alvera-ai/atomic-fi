defmodule PaymentCompliancePlatform.SessionContext.Session do
  @moduledoc """
  Session tracks authenticated sessions with assumed roles.

  Each session links a user (or API key) to a specific role they've assumed.
  The `type` field determines whether this is a :user or :api session.
  The `active` field allows for session invalidation and tracking history.
  """
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.ApiKeyContext.ApiKey
  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.RoleContext.{Role, RoleConstants}
  alias PaymentCompliancePlatform.TenantContext.Tenant
  alias PaymentCompliancePlatform.UserContext.User
  alias PaymentCompliancePlatform.UserContext.UserToken

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :tenant_id,
      :customer_id,
      :type,
      :active,
      :expires_at,
      :user_id,
      :api_key_id,
      :role_id
    ],
    sortable: [:id, :inserted_at, :updated_at, :type, :expires_at],
    default_limit: 20,
    max_limit: 100
  }

  @typedoc """
  Represents an active authentication session for users and API keys with role-based access.

  Sessions track authenticated access to the system. Each session is associated with
  either a user or an API key (determined by type), and assigns a specific role for
  the duration of that session. Sessions can be invalidated by setting active to false.

  ## Attributes

  * `id` - UUID of the session
  * `type` - Session type: 'user' for user sessions or 'api' for API key sessions
  * `active` - Whether this session is currently active and valid
  * `session_token` - Cryptographic session token hash for authentication
  * `expires_at` - Expiration timestamp for the session (null for non-expiring sessions)
  * `metadata` - Additional session data (IP address, user agent, device info)
  * `user_id` - FK to user (required when type='user', null when type='api')
  * `user` - Belongs to association with User (polymorphic)
  * `api_key_id` - FK to API key (required when type='api', null when type='user')
  * `api_key` - Belongs to association with ApiKey (polymorphic)
  * `role_id` - FK to role determining permissions for this session
  * `role` - Belongs to association with Role
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `tenant` - Belongs to association with Tenant
  * `customer_id` - Optional FK to customer for customer-scoped RLS (nullable)
  * `customer` - Optional belongs to association with Customer
  * `inserted_at` - Timestamp when session was created
  * `updated_at` - Timestamp when session was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # OpenAPI annotations
  # Server-resolved fields — readOnly so they appear in SessionResponse only,
  # never expected on a SessionRequest body.
  open_api_property(
    schema: %Schema{type: :string, format: :uuid, readOnly: true},
    key: :id
  )

  open_api_property(
    schema: %Schema{type: :string, enum: ["user", "api"], readOnly: true},
    key: :type
  )

  open_api_property(
    schema: %Schema{type: :boolean, default: true, readOnly: true},
    key: :active
  )

  open_api_property(
    schema: %Schema{type: :string, format: :binary, readOnly: true},
    key: :session_token
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true, nullable: true},
    key: :expires_at
  )

  open_api_property(
    schema: %Schema{
      type: :object,
      readOnly: true,
      additionalProperties: true,
      description: "Session metadata (IP, user agent, Cloudflare headers)"
    },
    key: :metadata
  )

  # Plaintext Bearer token — returned ONCE by POST /api/sessions. readOnly;
  # never accepted on a request body. When absent (e.g. on GET /verify) the
  # field is stripped from the Response by ExOpenApiUtils.Mapper.
  open_api_property(
    schema: %Schema{
      type: :string,
      readOnly: true,
      nullable: true,
      description: "Plaintext Bearer token. Returned ONCE on POST /api/sessions."
    },
    key: :bearer
  )

  # Preloaded association projections — Mapper.to_map serializes each via its
  # own Response schema. `$ref`-to-*Response is auto-detected as readOnly by
  # ExOpenApiUtils (is_readOnly?/1 on a Reference checks the ref suffix).
  open_api_property(
    schema: %OpenApiSpex.Reference{"$ref": "#/components/schemas/TenantResponse"},
    key: :tenant
  )

  open_api_property(
    schema: %OpenApiSpex.Reference{"$ref": "#/components/schemas/RoleResponse"},
    key: :role
  )

  open_api_property(
    schema: %OpenApiSpex.Reference{"$ref": "#/components/schemas/UserResponse"},
    key: :user
  )

  open_api_property(
    schema: %OpenApiSpex.Reference{"$ref": "#/components/schemas/ApiKeyResponse"},
    key: :api_key
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, readOnly: true, nullable: true},
    key: :user_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, readOnly: true, nullable: true},
    key: :api_key_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, readOnly: true},
    key: :role_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, readOnly: true},
    key: :tenant_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :inserted_at
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :updated_at
  )

  # Auth-only writeOnly fields — appear in SessionRequest, excluded from SessionResponse.
  # Populated by POST /api/sessions body to exchange credentials for a Bearer token.
  open_api_property(
    schema: %Schema{type: :string, format: :email, writeOnly: true},
    key: :email
  )

  open_api_property(
    schema: %Schema{type: :string, format: :password, writeOnly: true, minLength: 1},
    key: :password
  )

  open_api_property(
    schema: %Schema{type: :string, writeOnly: true},
    key: :tenant_slug
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      writeOnly: true,
      nullable: true,
      minimum: 60,
      maximum: 2_592_000,
      description: "Bearer session duration in seconds. Default 86400 (24h)."
    },
    key: :expires_in
  )

  open_api_schema(
    title: "Session",
    description:
      "Authentication session. Request fields (writeOnly) carry credentials for " <>
        "POST /api/sessions. Response fields (readOnly) describe the resolved session.",
    required: [:email, :password, :tenant_slug],
    properties: [
      # readOnly DB fields — appear in Response only
      :id,
      :type,
      :active,
      :expires_at,
      :metadata,
      :user_id,
      :api_key_id,
      :role_id,
      :tenant_id,
      :inserted_at,
      :updated_at,
      # readOnly plaintext Bearer token (virtual, returned once on create)
      :bearer,
      # readOnly preloaded associations — serialized via their Response schemas
      :tenant,
      :role,
      :user,
      :api_key,
      # writeOnly — appear in Request only (POST /api/sessions body)
      :email,
      :password,
      :tenant_slug,
      :expires_in
    ]
  )

  typed_schema "sessions" do
    field :type, Ecto.Enum, values: [:user, :api]
    field :active, :boolean, default: true
    field :session_token, :binary
    field :expires_at, :utc_datetime
    field :metadata, :map, default: %{}

    # Virtual auth-input fields — present only on SessionRequest (writeOnly).
    # POST /api/sessions reads these from the request body; never persisted.
    field :email, :string, virtual: true
    field :password, :string, virtual: true
    field :tenant_slug, :string, virtual: true
    field :expires_in, :integer, virtual: true

    # Virtual response field — plaintext Bearer token returned ONCE by
    # POST /api/sessions. Not persisted; the DB stores only the hashed
    # UserToken linked via user_token_id.
    field :bearer, :string, virtual: true

    # Polymorphic association: either user or api_key
    belongs_to :user, User
    belongs_to :api_key, ApiKey

    # Non-null only for Bearer user-session API tokens
    # (POST /api/sessions). NULL for X-API-Key sessions.
    belongs_to :user_token, UserToken

    # The assumed role (required)
    belongs_to :role, Role

    # Multi-tenancy: tenant_id for RLS
    belongs_to :tenant, Tenant

    # Customer context for RLS (optional, nullable)
    belongs_to :customer, PaymentCompliancePlatform.CustomerContext.Customer

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :type,
      :active,
      :session_token,
      :expires_at,
      :metadata,
      :user_id,
      :api_key_id,
      :user_token_id,
      :role_id,
      :tenant_id,
      :customer_id
    ])
    |> validate_required([:type, :active, :session_token, :role_id, :tenant_id])
    |> validate_conditional_foreign_keys()
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:api_key_id)
    |> foreign_key_constraint(:user_token_id)
    |> foreign_key_constraint(:role_id)
    |> foreign_key_constraint(:tenant_id)
    |> foreign_key_constraint(:customer_id)
    |> unique_constraint(:session_token)
    |> validate_role_assumption()
  end

  # Validates that user_id or api_key_id is present based on type
  defp validate_conditional_foreign_keys(changeset) do
    type = get_field(changeset, :type)
    user_id = get_field(changeset, :user_id)
    api_key_id = get_field(changeset, :api_key_id)

    case {type, user_id, api_key_id} do
      {:user, nil, _} ->
        add_error(changeset, :user_id, "must be present when type is :user")

      {:user, _, api_key_id} when not is_nil(api_key_id) ->
        add_error(changeset, :api_key_id, "must be null when type is :user")

      {:api, _, nil} ->
        add_error(changeset, :api_key_id, "must be present when type is :api")

      {:api, user_id, _} when not is_nil(user_id) ->
        add_error(changeset, :user_id, "must be null when type is :api")

      _ ->
        changeset
    end
  end

  # Validate role assumption (CRITICAL SECURITY - runs last, can't be bypassed)
  # Ensures actor (user/api_key) is authorized to assume the target role
  defp validate_role_assumption(changeset) do
    user_id = get_field(changeset, :user_id)
    api_key_id = get_field(changeset, :api_key_id)
    role_id = get_field(changeset, :role_id)

    # Skip validation if no role or no actor (earlier validations will catch this)
    if is_nil(role_id) or (is_nil(user_id) and is_nil(api_key_id)) do
      changeset
    else
      # Use changeset.repo for testability (falls back to Repo if not set)
      repo = changeset.repo || Repo

      # Get actor (user or api_key) with preloaded roles
      actor =
        if user_id do
          repo.get(User, user_id, skip_multi_tenancy_check: true)
          |> repo.preload(:roles, skip_multi_tenancy_check: true)
        else
          repo.get(ApiKey, api_key_id, skip_multi_tenancy_check: true)
          |> repo.preload(:role, skip_multi_tenancy_check: true)
        end

      # Get target role
      target_role = repo.get(Role, role_id, skip_multi_tenancy_check: true)

      # Validate assumption
      case can_assume_role?(actor, target_role) do
        true -> changeset
        false -> add_error(changeset, :role_id, "unauthorized to assume role")
      end
    end
  end

  # Check if actor can assume target role
  defp can_assume_role?(actor, target_role) do
    # Get actor's roles (User has many roles, ApiKey has one role)
    actor_roles =
      case actor do
        %User{roles: roles} -> roles
        %ApiKey{role: role} when not is_nil(role) -> [role]
        _ -> []
      end

    cond do
      # Platform admin can assume any role
      Enum.any?(actor_roles, &RoleConstants.reserved?(&1.name)) ->
        true

      # Customer admin can assume employee role in same customer
      is_customer_admin?(actor_roles, target_role) and
          target_role.name == RoleConstants.employee() ->
        same_customer?(actor_roles, target_role.customer_id)

      # Otherwise, actor must already have this exact role
      Enum.any?(actor_roles, &(&1.id == target_role.id)) ->
        true

      true ->
        false
    end
  end

  # Check if actor has customer_admin role for target role's customer
  defp is_customer_admin?(actor_roles, target_role) do
    Enum.any?(actor_roles, fn role ->
      role.name == RoleConstants.customer_admin() and
        role.customer_id == target_role.customer_id
    end)
  end

  # Check if actor has any role in the same customer
  defp same_customer?(actor_roles, customer_id) do
    Enum.any?(actor_roles, &(&1.customer_id == customer_id))
  end
end

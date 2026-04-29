defmodule AtomicFi.UserContext.User do
  use AtomicFi.Schema

  alias AtomicFi.RoleContext.UserRoleMapping
  alias AtomicFi.TenantContext.Tenant

  @derive {
    Flop.Schema,
    filterable: [:id, :email, :confirmed_at, :tenant_id],
    sortable: [:id, :email, :confirmed_at, :inserted_at, :updated_at],
    default_limit: 20,
    max_limit: 100
  }

  @typedoc """
  Represents a user account with email authentication and tenant association.

  Users authenticate via email and password. Each user belongs to a tenant and can
  be assigned multiple roles through UserRoleMapping. The current_role field is set
  at runtime during authentication to determine session permissions.

  ## Attributes

  * `id` - UUID of the user
  * `email` - User email address (unique within tenant)
  * `hashed_password` - Bcrypt-hashed password for authentication
  * `confirmed_at` - Timestamp when user confirmed their email address
  * `current_role` - Virtual field for current role (set at runtime during authentication)
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `tenant` - Belongs to association with Tenant
  * `roles` - Many-to-many association with roles via user_role_mappings
  * `user_role_mappings` - Direct access to join table for cast_assoc operations
  * `inserted_at` - Timestamp when user was created
  * `updated_at` - Timestamp when user was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)
  open_api_property(schema: %Schema{type: :string}, key: :email)
  open_api_property(schema: %Schema{type: :string, writeOnly: true}, key: :hashed_password)

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", nullable: true},
    key: :confirmed_at
  )

  open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :tenant_id)

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :inserted_at
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :updated_at
  )

  open_api_schema(
    title: "User",
    description: "User schema",
    required: [:email, :tenant_id],
    properties: [
      :id,
      :email,
      :hashed_password,
      :confirmed_at,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "users" do
    field :email, :string
    field :hashed_password, :string
    field :confirmed_at, :utc_datetime_usec

    # Virtual field for current role (set at runtime during authentication)
    field :current_role, :map, virtual: true

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    # Many-to-many relationship with roles
    many_to_many :roles, AtomicFi.RoleContext.Role,
      join_through: UserRoleMapping,
      on_replace: :delete

    # Direct access to join table for cast_assoc operations
    has_many :user_role_mappings, UserRoleMapping, on_replace: :delete

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :hashed_password, :confirmed_at, :tenant_id])
    |> validate_required([:email, :hashed_password, :confirmed_at, :tenant_id])
    |> unique_constraint(:email)
  end

  @doc """
  Verifies the password against the user's `hashed_password` using Bcrypt.

  Runs a no-op hash when `user` is nil or `hashed_password` is nil so the
  function is constant-time against email-existence enumeration.
  """
  @spec valid_password?(t() | nil, String.t()) :: boolean()
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end

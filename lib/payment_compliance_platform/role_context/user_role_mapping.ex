defmodule PaymentCompliancePlatform.RoleContext.UserRoleMapping do
  @moduledoc """
  Join table schema linking users to roles for role-based access control (RBAC).

  This is a mapping table without id or timestamps, using composite primary key.
  Allows use of cast_assoc for managing user-role relationships.
  """
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.RoleContext.Role
  alias PaymentCompliancePlatform.UserContext.User

  @typedoc """
  Represents the many-to-many mapping between users and roles for authorization.

  This join table enables users to have multiple roles within their tenant.
  Uses composite primary key (user_id, role_id) for uniqueness enforcement.

  ## Attributes

  * `user_id` - FK to user being assigned the role (composite primary key)
  * `user` - Belongs to association with User
  * `role_id` - FK to role being assigned to the user (composite primary key)
  * `role` - Belongs to association with Role
  """

  @primary_key false
  @foreign_key_type :binary_id

  typed_schema "user_roles" do
    belongs_to :user, User, primary_key: true
    belongs_to :role, Role, primary_key: true
  end

  @doc """
  Changeset for creating a user_role_mapping association.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(user_role_mapping, attrs) do
    user_role_mapping
    |> cast(attrs, [:user_id, :role_id])
    |> validate_required([:user_id, :role_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:role_id)
    |> unique_constraint([:user_id, :role_id], name: :user_roles_user_id_role_id_index)
  end
end

defmodule AtomicFi.Factory.UserRoleMappingFactory do
  @moduledoc """
  Factory for UserRoleMapping join table schema.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.RoleContext.UserRoleMapping

      def user_role_mapping_factory(attrs \\ %{}) do
        # Only create user if neither :user nor :user_id is provided
        user =
          if Map.has_key?(attrs, :user) or Map.has_key?(attrs, :user_id) do
            Map.get(attrs, :user)
          else
            insert(:user)
          end

        user_id = Map.get(attrs, :user_id, user && user.id)

        # Only create role if neither :role nor :role_id is provided
        role =
          if Map.has_key?(attrs, :role) or Map.has_key?(attrs, :role_id) do
            Map.get(attrs, :role)
          else
            tenant_id = if user, do: user.tenant_id
            insert(:role, tenant_id: tenant_id)
          end

        role_id = Map.get(attrs, :role_id, role && role.id)

        %UserRoleMapping{
          user_id: user_id,
          role_id: role_id
        }
      end
    end
  end
end

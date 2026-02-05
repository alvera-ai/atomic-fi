defmodule PaymentCompliancePlatform.Factory.SessionFactory do
  @moduledoc """
  Factory for Session context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias PaymentCompliancePlatform.SessionContext.Session

      def session_factory(attrs \\ %{}) do
        alias PaymentCompliancePlatform.RoleContext.UserRoleMapping
        alias PaymentCompliancePlatform.Repo

        # Determine type - default to :user
        type = Map.get(attrs, :type, :user)

        # Get or create tenant_id
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        # Type-specific foreign keys and role assignment
        {user_id, api_key_id, role_id} =
          case type do
            :user ->
              # Get or create user
              user_id =
                Map.get_lazy(attrs, :user_id, fn ->
                  insert(:user, tenant_id: tenant_id).id
                end)

              # Get or create role for user session
              role_id =
                Map.get_lazy(attrs, :role_id, fn ->
                  insert(:role, tenant_id: tenant_id).id
                end)

              # Assign role to user via user_role_mappings
              # Only create mapping if both user_id and role_id are present (not nil)
              if user_id != nil and role_id != nil and
                   not (Map.has_key?(attrs, :user_id) and Map.has_key?(attrs, :role_id)) do
                Repo.insert!(
                  %UserRoleMapping{user_id: user_id, role_id: role_id},
                  skip_multi_tenancy_check: true
                )
              end

              {user_id, nil, role_id}

            :api ->
              # Get or create api_key (has its own role_id)
              api_key =
                Map.get_lazy(attrs, :api_key_id, fn ->
                  insert(:api_key, tenant_id: tenant_id)
                end)

              # For API sessions, use the API key's role_id
              api_key_id = if is_struct(api_key), do: api_key.id, else: api_key

              role_id =
                if api_key_id == nil do
                  # If api_key_id is nil (testing invalid session), don't fetch role
                  Map.get(attrs, :role_id, nil)
                else
                  Map.get_lazy(attrs, :role_id, fn ->
                    if is_struct(api_key) do
                      api_key.role_id
                    else
                      # If api_key_id was passed directly, fetch the api_key
                      Repo.get!(PaymentCompliancePlatform.ApiKeyContext.ApiKey, api_key_id,
                        skip_multi_tenancy_check: true
                      ).role_id
                    end
                  end)
                end

              {nil, api_key_id, role_id}
          end

        customer_id = Map.get(attrs, :customer_id, nil)

        %Session{
          type: type,
          active: Map.get(attrs, :active, true),
          session_token: Map.get(attrs, :session_token, :crypto.strong_rand_bytes(32)),
          expires_at:
            Map.get(
              attrs,
              :expires_at,
              DateTime.add(DateTime.utc_now(), 60, :day) |> DateTime.truncate(:second)
            ),
          metadata: Map.get(attrs, :metadata, %{}),
          user_id: user_id,
          api_key_id: api_key_id,
          role_id: role_id,
          tenant_id: tenant_id,
          customer_id: customer_id
        }
      end
    end
  end
end

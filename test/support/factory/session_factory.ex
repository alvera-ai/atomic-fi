defmodule AtomicFi.Factory.SessionFactory do
  @moduledoc """
  Factory for Session context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.SessionContext.Session

      def session_factory(attrs \\ %{}) do
        alias AtomicFi.RoleContext.UserRoleMapping
        alias AtomicFi.Repo

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

              role_id = resolve_api_role_id(attrs, api_key, api_key_id)

              {nil, api_key_id, role_id}
          end

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
          tenant_id: tenant_id
        }
      end

      # If api_key_id is nil (testing invalid session) → no role lookup.
      # Otherwise prefer attrs[:role_id]; fall back to the api_key's role_id
      # (re-fetching from the repo if only the id was passed).
      defp resolve_api_role_id(attrs, _api_key, nil),
        do: Map.get(attrs, :role_id, nil)

      defp resolve_api_role_id(attrs, api_key, _api_key_id) when is_struct(api_key),
        do: Map.get_lazy(attrs, :role_id, fn -> api_key.role_id end)

      defp resolve_api_role_id(attrs, _api_key, api_key_id) do
        Map.get_lazy(attrs, :role_id, fn ->
          AtomicFi.Repo.get!(AtomicFi.ApiKeyContext.ApiKey, api_key_id,
            skip_multi_tenancy_check: true
          ).role_id
        end)
      end
    end
  end
end

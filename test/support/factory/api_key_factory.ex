defmodule AtomicFi.Factory.ApiKeyFactory do
  @moduledoc """
  Factory for ApiKey context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.ApiKeyContext.ApiKey
      alias AtomicFi.Vault

      def api_key_factory(attrs \\ %{}) do
        unique_suffix = String.slice(Ecto.UUID.generate(), 0, 8)
        raw_key = "api-key-#{unique_suffix}"

        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        role_id =
          Map.get_lazy(attrs, :role_id, fn ->
            insert(:role, tenant_id: tenant_id).id
          end)

        # Generate both hash (for validation) and encrypted value (for UI display)
        key_hash = :crypto.hash(:sha256, raw_key) |> Base.encode16(case: :lower)
        key_value = Vault.encrypt!(raw_key)

        %ApiKey{
          name: "API Key #{unique_suffix}",
          key_hash: key_hash,
          key_value: key_value,
          last_used_at: nil,
          tenant_id: tenant_id,
          role_id: role_id
        }
      end

      @doc """
      Helper to build an API key with current_role populated.

      The current_role represents the ACTIVE role for this API authentication session.
      Useful for testing API authentication scenarios with role-based access.

      ## Examples

          # With a specific role
          api_key = build(:api_key_with_role, current_role: %{id: "123", name: "service"})

          # With a built role
          service_role = build(:role, name: "service")
          api_key = build(:api_key_with_role, current_role: service_role)
      """
      def api_key_with_role_factory(attrs) do
        current_role = Map.get(attrs, :current_role, build(:role))

        build(:api_key)
        |> Map.put(:current_role, current_role)
      end
    end
  end
end

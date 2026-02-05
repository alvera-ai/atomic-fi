defmodule PaymentCompliancePlatform.Factory.UserFactory do
  @moduledoc """
  Factory for User context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias PaymentCompliancePlatform.UserContext.User

      def user_factory(attrs \\ %{}) do
        unique_suffix = String.slice(Ecto.UUID.generate(), 0, 8)

        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        %User{
          email: "user-#{unique_suffix}@example.com",
          hashed_password: Bcrypt.hash_pwd_salt("password123"),
          confirmed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
          tenant_id: tenant_id
        }
      end

      @doc """
      Helper to build a user with current_role populated.

      The current_role represents the ACTIVE role for this authentication session.
      Useful for testing authenticated user scenarios with role-based access.

      ## Examples

          # With a specific role
          user = build(:user_with_role, current_role: %{id: "123", name: "admin"})

          # With a built role
          admin_role = build(:role, name: "admin")
          user = build(:user_with_role, current_role: admin_role)
      """
      def user_with_role_factory(attrs) do
        current_role = Map.get(attrs, :current_role, build(:role))

        build(:user)
        |> Map.put(:current_role, current_role)
      end
    end
  end
end

defmodule AtomicFi.UserContext.UserTokenTest do
  use AtomicFi.DataCase

  alias AtomicFi.UserContext.UserToken

  describe "user_session_api_token_context/0" do
    test "returns the canonical context string" do
      assert UserToken.user_session_api_token_context() == "user-session-api-token"
    end
  end

  describe "build_user_session_api_token/1" do
    test "returns {plaintext, struct} with hashed token and sent_to == email", %{tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id, email: "ut-#{System.unique_integer([:positive])}@example.com")

      {plaintext, %UserToken{} = ut} = UserToken.build_user_session_api_token(user)

      assert is_binary(plaintext)
      assert byte_size(plaintext) > 30
      assert ut.context == UserToken.user_session_api_token_context()
      assert ut.sent_to == user.email
      assert ut.user_id == user.id

      decoded = Base.url_decode64!(plaintext, padding: false)
      assert ut.token == :crypto.hash(:sha256, decoded)
    end

    test "yields a different plaintext on each call" do
      user = insert(:user)
      {p1, _} = UserToken.build_user_session_api_token(user)
      {p2, _} = UserToken.build_user_session_api_token(user)
      refute p1 == p2
    end
  end

  describe "verify_user_session_api_token_query/1" do
    test "{:ok, query} for a valid base64url token, query selects the matching row", %{tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id)
      {plaintext, ut_attrs} = UserToken.build_user_session_api_token(user)

      {:ok, inserted} =
        ut_attrs
        |> Map.from_struct()
        |> Map.drop([:__meta__, :user])
        |> then(&Repo.insert(struct(UserToken, &1), skip_multi_tenancy_check: true))

      assert {:ok, query} = UserToken.verify_user_session_api_token_query(plaintext)
      found = Repo.one(query, skip_multi_tenancy_check: true)
      assert found.id == inserted.id
    end

    test "returns :error for non-base64url input" do
      assert UserToken.verify_user_session_api_token_query("!!!not_base64!!!") == :error
    end
  end

  describe "token_and_context_query/2" do
    test "returns a query filtered by token + context", %{tenant: tenant} do
      user = insert(:user, tenant_id: tenant.id)
      {_plaintext, %UserToken{token: token, context: ctx} = ut_attrs} =
        UserToken.build_user_session_api_token(user)

      {:ok, _inserted} =
        ut_attrs
        |> Map.from_struct()
        |> Map.drop([:__meta__, :user])
        |> then(&Repo.insert(struct(UserToken, &1), skip_multi_tenancy_check: true))

      results = UserToken.token_and_context_query(token, ctx) |> Repo.all(skip_multi_tenancy_check: true)
      assert length(results) == 1
    end
  end
end

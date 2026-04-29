defmodule AtomicFi.ApiKeyContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.ApiKeyContext

  describe "api_keys" do
    alias AtomicFi.ApiKeyContext.ApiKey

    import AtomicFi.Factory

    @invalid_attrs %{name: nil, key_hash: nil, last_used_at: nil}

    test "list_api_keys/2 returns all api_keys", %{session: session} do
      api_key = insert(:api_key, tenant_id: session.tenant_id)
      {:ok, {api_keys, _meta}} = ApiKeyContext.list_api_keys(session)
      # Verify the inserted API key is in the list (System tenant may have root API key from seed)
      assert Enum.any?(api_keys, fn k -> k.id == api_key.id end)
    end

    test "get_api_key!/2 returns the api_key with given id", %{session: session} do
      api_key = insert(:api_key, tenant_id: session.tenant_id)
      assert ApiKeyContext.get_api_key!(session, api_key.id).id == api_key.id
    end

    test "create_api_key/2 with valid data creates a api_key", %{session: session} do
      role = insert(:role, tenant_id: session.tenant_id)
      raw_key = "test-api-key-#{Ecto.UUID.generate()}"
      key_hash = :crypto.hash(:sha256, raw_key) |> Base.encode16(case: :lower)
      key_value = AtomicFi.Vault.encrypt!(raw_key)

      valid_attrs = %{
        name: "some name",
        key_hash: key_hash,
        key_value: key_value,
        last_used_at: ~U[2026-02-03 20:47:00.000000Z],
        tenant_id: session.tenant_id,
        role_id: role.id
      }

      assert {:ok, %ApiKey{} = api_key} = ApiKeyContext.create_api_key(session, valid_attrs)
      assert api_key.name == "some name"
      assert api_key.key_hash == key_hash
      assert api_key.last_used_at == ~U[2026-02-03 20:47:00.000000Z]
      assert api_key.role_id == role.id
    end

    test "create_api_key/2 with invalid data returns error changeset", %{session: session} do
      assert {:error, %Ecto.Changeset{}} = ApiKeyContext.create_api_key(session, @invalid_attrs)
    end

    test "update_api_key/3 with valid data updates the api_key", %{session: session} do
      api_key = insert(:api_key, tenant_id: session.tenant_id)

      update_attrs = %{
        name: "some updated name",
        key_hash: "some updated key_hash",
        last_used_at: ~U[2026-02-04 20:47:00.000000Z]
      }

      assert {:ok, %ApiKey{} = api_key} =
               ApiKeyContext.update_api_key(session, api_key, update_attrs)

      assert api_key.name == "some updated name"
      assert api_key.key_hash == "some updated key_hash"
      assert api_key.last_used_at == ~U[2026-02-04 20:47:00.000000Z]
    end

    test "update_api_key/3 with invalid data returns error changeset", %{session: session} do
      api_key = insert(:api_key, tenant_id: session.tenant_id)

      assert {:error, %Ecto.Changeset{}} =
               ApiKeyContext.update_api_key(session, api_key, @invalid_attrs)

      assert ApiKeyContext.get_api_key!(session, api_key.id).id == api_key.id
    end

    test "delete_api_key/2 deletes the api_key", %{session: session} do
      api_key = insert(:api_key, tenant_id: session.tenant_id)
      assert {:ok, %ApiKey{}} = ApiKeyContext.delete_api_key(session, api_key)

      assert_raise Ecto.NoResultsError, fn ->
        ApiKeyContext.get_api_key!(session, api_key.id)
      end
    end

    test "change_api_key/1 returns a api_key changeset" do
      api_key = insert(:api_key)
      assert %Ecto.Changeset{} = ApiKeyContext.change_api_key(api_key)
    end
  end
end

defmodule AtomicFi.BlocklistContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.BlocklistContext
  alias AtomicFi.BlocklistContext.BlocklistEntry

  describe "blocklist_entries" do
    @invalid_attrs %{active: nil, reason: nil, scope: nil, term: nil, entry_type: nil}

    test "list_blocklist_entries/2 returns all blocklist_entries", %{session: session} do
      blocklist_entry = insert(:blocklist_entry, tenant_id: session.tenant_id)
      {:ok, {[result], _meta}} = BlocklistContext.list_blocklist_entries(session)
      assert result.id == blocklist_entry.id
    end

    test "get_blocklist_entry!/2 returns the blocklist_entry with given id", %{session: session} do
      blocklist_entry = insert(:blocklist_entry, tenant_id: session.tenant_id)
      result = BlocklistContext.get_blocklist_entry!(session, blocklist_entry.id)
      assert result.id == blocklist_entry.id
    end

    test "create_blocklist_entry/2 with valid data creates a blocklist_entry", %{
      session: session,
      tenant: tenant
    } do
      valid_attrs = %{
        active: true,
        reason: "Test reason",
        scope: :first_name,
        term: "blocked",
        entry_type: :exact,
        tenant_id: tenant.id
      }

      assert {:ok, %BlocklistEntry{} = blocklist_entry} =
               BlocklistContext.create_blocklist_entry(session, valid_attrs)

      assert blocklist_entry.active == true
      assert blocklist_entry.reason == "Test reason"
      assert blocklist_entry.scope == :first_name
      assert blocklist_entry.term == "blocked"
      assert blocklist_entry.entry_type == :exact
    end

    test "create_blocklist_entry/2 with invalid data returns error changeset", %{session: session} do
      assert {:error, %Ecto.Changeset{}} =
               BlocklistContext.create_blocklist_entry(session, @invalid_attrs)
    end

    test "update_blocklist_entry/3 with valid data updates the blocklist_entry", %{
      session: session
    } do
      blocklist_entry = insert(:blocklist_entry, tenant_id: session.tenant_id)

      update_attrs = %{
        active: false,
        reason: "Updated reason",
        scope: :last_name,
        term: "updated_term",
        entry_type: :regex
      }

      assert {:ok, %BlocklistEntry{} = updated_entry} =
               BlocklistContext.update_blocklist_entry(session, blocklist_entry, update_attrs)

      assert updated_entry.active == false
      assert updated_entry.reason == "Updated reason"
      assert updated_entry.scope == :last_name
      assert updated_entry.term == "updated_term"
      assert updated_entry.entry_type == :regex
    end

    test "update_blocklist_entry/3 with invalid data returns error changeset", %{
      session: session
    } do
      blocklist_entry = insert(:blocklist_entry, tenant_id: session.tenant_id)

      assert {:error, %Ecto.Changeset{}} =
               BlocklistContext.update_blocklist_entry(session, blocklist_entry, @invalid_attrs)

      result = BlocklistContext.get_blocklist_entry!(session, blocklist_entry.id)
      assert result.id == blocklist_entry.id
    end

    test "delete_blocklist_entry/2 deletes the blocklist_entry", %{session: session} do
      blocklist_entry = insert(:blocklist_entry, tenant_id: session.tenant_id)

      assert {:ok, %BlocklistEntry{}} =
               BlocklistContext.delete_blocklist_entry(session, blocklist_entry)

      assert_raise Ecto.NoResultsError, fn ->
        BlocklistContext.get_blocklist_entry!(session, blocklist_entry.id)
      end
    end

    test "change_blocklist_entry/1 returns a blocklist_entry changeset", %{session: session} do
      blocklist_entry = insert(:blocklist_entry, tenant_id: session.tenant_id)
      assert %Ecto.Changeset{} = BlocklistContext.change_blocklist_entry(blocklist_entry)
    end
  end
end

defmodule AtomicFi.LedgerAccountContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.LedgerAccountContext.LedgerAccount
  alias AtomicFi.OpenApiSchema.LedgerAccountRequest
  import AtomicFi.Factory

  # Helper: build a valid LedgerAccountRequest for the given session/ledger
  defp ledger_account_request(session, ledger, overrides \\ %{}) do
    %LedgerAccountRequest{
      account_holder_id: Map.get(overrides, :account_holder_id, ledger.account_holder_id),
      ledger_id: Map.get(overrides, :ledger_id, ledger.id),
      currency: Map.get(overrides, :currency, "USD"),
      account_type: Map.get(overrides, :account_type, :asset),
      status: Map.get(overrides, :status, :active),
      parent_ledger_account_id: Map.get(overrides, :parent_ledger_account_id, nil),
      tenant_id: Map.get(overrides, :tenant_id, session.tenant_id)
    }
  end

  describe "ledger_accounts CRUD" do
    test "list_ledger_accounts/1 returns all accounts for tenant", %{session: session} do
      insert(:ledger_account, tenant_id: session.tenant_id)
      {:ok, {accounts, _meta}} = LedgerAccountContext.list_ledger_accounts(session)
      assert accounts != []
    end

    test "get_ledger_account!/2 returns the account with given id", %{session: session} do
      account = insert(:ledger_account, tenant_id: session.tenant_id)

      assert %LedgerAccount{id: id} =
               LedgerAccountContext.get_ledger_account!(session, account.id)

      assert id == account.id
    end

    test "create_ledger_account/2 with valid data creates a root account", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      request = ledger_account_request(session, ledger)

      assert {:ok, %LedgerAccount{} = account} =
               LedgerAccountContext.create_ledger_account(session, request)

      assert account.ledger_id == ledger.id
      assert account.currency == "USD"
      assert account.account_type == :asset
      assert account.status == :active
      assert account.balance == 0
      assert account.ancestor_ids == []
      assert is_nil(account.parent_ledger_account_id)
      assert account.tenant_id == session.tenant_id
    end

    test "create_ledger_account/2 with missing required fields returns error", %{session: session} do
      request = %LedgerAccountRequest{
        account_holder_id: nil,
        ledger_id: nil,
        currency: nil,
        tenant_id: session.tenant_id
      }

      assert {:error, changeset} = LedgerAccountContext.create_ledger_account(session, request)
      assert errors_on(changeset).account_holder_id != []
      assert errors_on(changeset).ledger_id != []
      assert errors_on(changeset).currency != []
    end

    test "update_ledger_account/3 updates mutable fields", %{session: session} do
      account = insert(:ledger_account, tenant_id: session.tenant_id, status: :active)

      request = %LedgerAccountRequest{
        account_holder_id: account.account_holder_id,
        ledger_id: account.ledger_id,
        currency: account.currency,
        account_type: account.account_type,
        status: :closed,
        tenant_id: session.tenant_id
      }

      assert {:ok, updated} =
               LedgerAccountContext.update_ledger_account(session, account, request)

      assert updated.status == :closed
    end

    test "delete_ledger_account/2 deletes the account", %{session: session} do
      account = insert(:ledger_account, tenant_id: session.tenant_id)

      assert {:ok, %LedgerAccount{}} =
               LedgerAccountContext.delete_ledger_account(session, account)

      assert_raise Ecto.NoResultsError, fn ->
        LedgerAccountContext.get_ledger_account!(session, account.id)
      end
    end

    test "change_ledger_account/1 returns a changeset", %{session: session} do
      account = insert(:ledger_account, tenant_id: session.tenant_id)
      assert %Ecto.Changeset{} = LedgerAccountContext.change_ledger_account(account)
    end
  end

  describe "ledger_accounts hierarchy — ancestor_ids materialized path" do
    test "root account has empty ancestor_ids", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      request = ledger_account_request(session, ledger)

      assert {:ok, root} = LedgerAccountContext.create_ledger_account(session, request)
      assert root.ancestor_ids == []
      assert is_nil(root.parent_ledger_account_id)
    end

    test "child account has parent id in ancestor_ids", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)

      root_request = ledger_account_request(session, ledger)
      assert {:ok, root} = LedgerAccountContext.create_ledger_account(session, root_request)

      child_request =
        ledger_account_request(session, ledger, %{
          parent_ledger_account_id: root.id,
          account_type: :liability
        })

      assert {:ok, child} = LedgerAccountContext.create_ledger_account(session, child_request)
      assert child.parent_ledger_account_id == root.id
      assert child.ancestor_ids == [root.id]
    end

    test "grandchild has both grandparent and parent in ancestor_ids in order", %{
      session: session
    } do
      ledger = insert(:ledger, tenant_id: session.tenant_id)

      root_request = ledger_account_request(session, ledger)
      assert {:ok, root} = LedgerAccountContext.create_ledger_account(session, root_request)

      child_request =
        ledger_account_request(session, ledger, %{
          parent_ledger_account_id: root.id,
          account_type: :liability
        })

      assert {:ok, child} = LedgerAccountContext.create_ledger_account(session, child_request)

      grandchild_request =
        ledger_account_request(session, ledger, %{
          parent_ledger_account_id: child.id,
          account_type: :equity
        })

      assert {:ok, grandchild} =
               LedgerAccountContext.create_ledger_account(session, grandchild_request)

      assert grandchild.parent_ledger_account_id == child.id
      # ancestor_ids = parent's ancestors ++ [parent_id] = [root.id, child.id]
      assert grandchild.ancestor_ids == [root.id, child.id]
    end

    test "updating parent_ledger_account_id recomputes ancestor_ids", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)

      root_request = ledger_account_request(session, ledger)
      assert {:ok, root_a} = LedgerAccountContext.create_ledger_account(session, root_request)

      # root_b is an independent root
      root_b_request = ledger_account_request(session, ledger, %{account_type: :liability})
      assert {:ok, root_b} = LedgerAccountContext.create_ledger_account(session, root_b_request)

      # account starts under root_a
      child_request =
        ledger_account_request(session, ledger, %{
          parent_ledger_account_id: root_a.id,
          account_type: :equity
        })

      assert {:ok, child} = LedgerAccountContext.create_ledger_account(session, child_request)
      assert child.ancestor_ids == [root_a.id]

      # reparent to root_b
      update_request = %LedgerAccountRequest{
        account_holder_id: child.account_holder_id,
        ledger_id: child.ledger_id,
        currency: child.currency,
        account_type: child.account_type,
        status: child.status,
        parent_ledger_account_id: root_b.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, reparented} =
               LedgerAccountContext.update_ledger_account(session, child, update_request)

      assert reparented.parent_ledger_account_id == root_b.id
      assert reparented.ancestor_ids == [root_b.id]
    end

    test "updating without changing parent retains ancestor_ids", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)

      root_request = ledger_account_request(session, ledger)
      assert {:ok, root} = LedgerAccountContext.create_ledger_account(session, root_request)

      child_request =
        ledger_account_request(session, ledger, %{
          parent_ledger_account_id: root.id,
          account_type: :liability
        })

      assert {:ok, child} = LedgerAccountContext.create_ledger_account(session, child_request)
      assert child.ancestor_ids == [root.id]

      # Update status only — parent unchanged
      update_request = %LedgerAccountRequest{
        account_holder_id: child.account_holder_id,
        ledger_id: child.ledger_id,
        currency: child.currency,
        account_type: child.account_type,
        status: :closed,
        parent_ledger_account_id: child.parent_ledger_account_id,
        tenant_id: session.tenant_id
      }

      assert {:ok, updated} =
               LedgerAccountContext.update_ledger_account(session, child, update_request)

      assert updated.status == :closed
      assert updated.ancestor_ids == [root.id]
    end
  end

  describe "ledger_accounts no-cycle validation" do
    test "setting ancestor_ids that includes own id is rejected", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)

      root_request = ledger_account_request(session, ledger)
      assert {:ok, root} = LedgerAccountContext.create_ledger_account(session, root_request)

      child_request =
        ledger_account_request(session, ledger, %{
          parent_ledger_account_id: root.id,
          account_type: :liability
        })

      assert {:ok, child} = LedgerAccountContext.create_ledger_account(session, child_request)
      assert child.ancestor_ids == [root.id]

      # Attempt to make root a child of child (would create cycle: root → child → root)
      # This is detected by validate_no_ancestor_cycle because root.id would be in ancestor_ids
      # when we try to set parent = child (child's ancestors ++ [child.id] = [root.id, child.id])
      # and root.id is in that list
      cycle_request = %LedgerAccountRequest{
        account_holder_id: root.account_holder_id,
        ledger_id: root.ledger_id,
        currency: root.currency,
        account_type: root.account_type,
        status: root.status,
        parent_ledger_account_id: child.id,
        tenant_id: session.tenant_id
      }

      assert {:error, changeset} =
               LedgerAccountContext.update_ledger_account(session, root, cycle_request)

      assert errors_on(changeset).ancestor_ids != []
    end
  end
end

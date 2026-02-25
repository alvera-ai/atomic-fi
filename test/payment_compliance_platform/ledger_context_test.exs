defmodule PaymentCompliancePlatform.LedgerContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.LedgerContext
  alias PaymentCompliancePlatform.LedgerContext.Ledger
  alias PaymentCompliancePlatform.OpenApiSchema.LedgerRequest
  import PaymentCompliancePlatform.Factory

  describe "ledgers" do
    test "list_ledgers/1 returns all ledgers for tenant", %{session: session} do
      insert(:ledger, tenant_id: session.tenant_id)
      {:ok, {ledgers, _meta}} = LedgerContext.list_ledgers(session)
      assert ledgers != []
    end

    test "get_ledger!/2 returns the ledger with given id", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      assert %Ledger{id: id} = LedgerContext.get_ledger!(session, ledger.id)
      assert id == ledger.id
    end

    test "create_ledger/2 with valid data creates a ledger", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %LedgerRequest{
        account_holder_id: account_holder.id,
        currency: "USD",
        status: :active,
        tenant_id: session.tenant_id
      }

      assert {:ok, %Ledger{} = ledger} = LedgerContext.create_ledger(session, request)
      assert ledger.account_holder_id == account_holder.id
      assert ledger.currency == "USD"
      assert ledger.status == :active
      assert ledger.tenant_id == session.tenant_id
    end

    test "create_ledger/2 enforces unique account_holder + currency constraint", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %LedgerRequest{
        account_holder_id: account_holder.id,
        currency: "USD",
        status: :active,
        tenant_id: session.tenant_id
      }

      assert {:ok, _} = LedgerContext.create_ledger(session, request)
      assert {:error, changeset} = LedgerContext.create_ledger(session, request)
      errors = errors_on(changeset)

      assert Map.get(errors, :currency) == ["has already been taken"] or
               Map.get(errors, :account_holder_id) == ["has already been taken"]
    end

    test "create_ledger/2 rejects currency code not exactly 3 chars", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %LedgerRequest{
        account_holder_id: account_holder.id,
        currency: "US",
        tenant_id: session.tenant_id
      }

      assert {:error, changeset} = LedgerContext.create_ledger(session, request)
      assert errors_on(changeset).currency != []
    end

    test "create_ledger/2 with missing required fields returns error changeset", %{
      session: session
    } do
      request = %LedgerRequest{
        account_holder_id: nil,
        currency: nil,
        tenant_id: session.tenant_id
      }

      assert {:error, changeset} = LedgerContext.create_ledger(session, request)
      assert errors_on(changeset).account_holder_id != []
      assert errors_on(changeset).currency != []
    end

    test "update_ledger/3 with valid data updates the ledger", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)

      request = %LedgerRequest{
        account_holder_id: ledger.account_holder_id,
        currency: ledger.currency,
        status: :closed,
        tenant_id: session.tenant_id
      }

      assert {:ok, %Ledger{} = updated} = LedgerContext.update_ledger(session, ledger, request)
      assert updated.status == :closed
    end

    test "update_ledger/3 with invalid data returns error changeset", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)

      request = %LedgerRequest{
        account_holder_id: nil,
        currency: nil,
        tenant_id: session.tenant_id
      }

      assert {:error, changeset} = LedgerContext.update_ledger(session, ledger, request)
      assert errors_on(changeset).account_holder_id != []
    end

    test "delete_ledger/2 deletes the ledger", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      assert {:ok, %Ledger{}} = LedgerContext.delete_ledger(session, ledger)

      assert_raise Ecto.NoResultsError, fn ->
        LedgerContext.get_ledger!(session, ledger.id)
      end
    end

    test "change_ledger/1 returns a ledger changeset", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      assert %Ecto.Changeset{} = LedgerContext.change_ledger(ledger)
    end
  end
end

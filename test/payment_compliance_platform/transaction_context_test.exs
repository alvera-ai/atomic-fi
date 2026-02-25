defmodule PaymentCompliancePlatform.TransactionContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.OpenApiSchema.TransactionRequest
  alias PaymentCompliancePlatform.TransactionContext
  alias PaymentCompliancePlatform.TransactionContext.Transaction
  import PaymentCompliancePlatform.Factory

  describe "transactions" do
    test "list_transactions/1 returns all transactions for tenant", %{session: session} do
      insert(:transaction, tenant_id: session.tenant_id)
      {:ok, {transactions, _meta}} = TransactionContext.list_transactions(session)
      assert transactions != []
    end

    test "list_transactions/1 returns own tenant records", %{session: session} do
      own = insert(:transaction, tenant_id: session.tenant_id)

      {:ok, {transactions, _meta}} = TransactionContext.list_transactions(session)
      ids = Enum.map(transactions, & &1.id)
      assert own.id in ids
    end

    test "get_transaction!/2 returns the transaction with given id", %{session: session} do
      transaction = insert(:transaction, tenant_id: session.tenant_id)

      assert %Transaction{id: id} =
               TransactionContext.get_transaction!(session, transaction.id)

      assert id == transaction.id
    end

    test "create_transaction/2 with valid data creates a transaction", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %TransactionRequest{
        transaction_type: :credit_transfer,
        amount: 5000,
        currency: "USD",
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %Transaction{} = transaction} =
               TransactionContext.create_transaction(session, request)

      assert transaction.transaction_type == :credit_transfer
      assert transaction.status == :pending
      assert transaction.amount == 5000
      assert transaction.currency == "USD"
      assert transaction.account_holder_id == account_holder.id
      assert transaction.tenant_id == session.tenant_id
    end

    test "create_transaction/2 with optional fields", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %TransactionRequest{
        transaction_type: :credit_transfer,
        status: :accepted,
        amount: 100_000,
        currency: "EUR",
        end_to_end_id: "E2E-REF-001",
        uetr: "550e8400-e29b-41d4-a716-446655440000",
        instruction_id: "INSTR-001",
        status_reason_code: "ACCP",
        requested_execution_date: ~D[2026-03-01],
        settlement_date: ~D[2026-03-02],
        transaction_external_id: "ext-txn-001",
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %Transaction{} = transaction} =
               TransactionContext.create_transaction(session, request)

      assert transaction.status == :accepted
      assert transaction.amount == 100_000
      assert transaction.currency == "EUR"
      assert transaction.end_to_end_id == "E2E-REF-001"
      assert transaction.uetr == "550e8400-e29b-41d4-a716-446655440000"
      assert transaction.instruction_id == "INSTR-001"
      assert transaction.status_reason_code == "ACCP"
      assert transaction.requested_execution_date == ~D[2026-03-01]
      assert transaction.settlement_date == ~D[2026-03-02]
      assert transaction.transaction_external_id == "ext-txn-001"
    end

    test "create_transaction/2 with payment account links", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      debtor_account =
        insert(:payment_account,
          tenant_id: session.tenant_id,
          account_holder_id: account_holder.id
        )

      creditor_account =
        insert(:payment_account,
          tenant_id: session.tenant_id,
          account_holder_id: account_holder.id
        )

      request = %TransactionRequest{
        transaction_type: :internal_transfer,
        amount: 25_000,
        currency: "USD",
        debtor_payment_account_id: debtor_account.id,
        creditor_payment_account_id: creditor_account.id,
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %Transaction{} = transaction} =
               TransactionContext.create_transaction(session, request)

      assert transaction.debtor_payment_account_id == debtor_account.id
      assert transaction.creditor_payment_account_id == creditor_account.id
    end

    test "create_transaction/2 defaults status to :pending when not provided", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %TransactionRequest{
        transaction_type: :direct_debit,
        amount: 1000,
        currency: "GBP",
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %Transaction{} = transaction} =
               TransactionContext.create_transaction(session, request)

      assert transaction.status == :pending
    end

    test "create_transaction/2 with invalid data returns error changeset", %{session: session} do
      request = %TransactionRequest{
        transaction_type: nil,
        amount: nil,
        currency: nil,
        account_holder_id: nil,
        tenant_id: session.tenant_id
      }

      assert {:error, %Ecto.Changeset{}} =
               TransactionContext.create_transaction(session, request)
    end

    test "create_transaction/2 rejects amount <= 0", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %TransactionRequest{
        transaction_type: :credit_transfer,
        amount: 0,
        currency: "USD",
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:error, %Ecto.Changeset{} = changeset} =
               TransactionContext.create_transaction(session, request)

      errors = errors_on(changeset)
      assert errors[:amount] != nil
    end

    test "create_transaction/2 enforces unique transaction_external_id per tenant", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %TransactionRequest{
        transaction_type: :credit_transfer,
        amount: 1000,
        currency: "USD",
        transaction_external_id: "ext-unique-001",
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, _} = TransactionContext.create_transaction(session, request)
      assert {:error, changeset} = TransactionContext.create_transaction(session, request)

      errors = errors_on(changeset)

      assert Map.get(errors, :transaction_external_id) == ["has already been taken"] or
               Map.get(errors, :tenant_id) == ["has already been taken"]
    end

    test "create_transaction/2 enforces unique uetr globally", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      make_request = fn uetr ->
        %TransactionRequest{
          transaction_type: :credit_transfer,
          amount: 1000,
          currency: "USD",
          uetr: uetr,
          account_holder_id: account_holder.id,
          tenant_id: session.tenant_id
        }
      end

      uetr = Ecto.UUID.generate()
      assert {:ok, _} = TransactionContext.create_transaction(session, make_request.(uetr))

      assert {:error, changeset} =
               TransactionContext.create_transaction(session, make_request.(uetr))

      errors = errors_on(changeset)
      assert Map.get(errors, :uetr) == ["has already been taken"]
    end

    test "create_transaction/2 allows nil external_id for multiple transactions", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      make_request = fn ->
        %TransactionRequest{
          transaction_type: :credit_transfer,
          amount: 1000,
          currency: "USD",
          account_holder_id: account_holder.id,
          tenant_id: session.tenant_id
        }
      end

      assert {:ok, _} = TransactionContext.create_transaction(session, make_request.())
      assert {:ok, _} = TransactionContext.create_transaction(session, make_request.())
    end

    test "update_transaction/3 with valid data updates the transaction", %{session: session} do
      transaction = insert(:transaction, tenant_id: session.tenant_id)

      request = %TransactionRequest{
        transaction_type: transaction.transaction_type,
        status: :settled,
        amount: transaction.amount,
        currency: transaction.currency,
        account_holder_id: transaction.account_holder_id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %Transaction{} = updated} =
               TransactionContext.update_transaction(session, transaction, request)

      assert updated.status == :settled
    end

    test "update_transaction/3 with invalid data returns error changeset", %{session: session} do
      transaction = insert(:transaction, tenant_id: session.tenant_id)

      request = %TransactionRequest{
        transaction_type: nil,
        amount: nil,
        currency: nil,
        account_holder_id: nil,
        tenant_id: nil
      }

      assert {:error, %Ecto.Changeset{}} =
               TransactionContext.update_transaction(session, transaction, request)
    end

    test "delete_transaction/2 deletes the transaction", %{session: session} do
      transaction = insert(:transaction, tenant_id: session.tenant_id)

      assert {:ok, %Transaction{}} =
               TransactionContext.delete_transaction(session, transaction)

      assert_raise Ecto.NoResultsError, fn ->
        TransactionContext.get_transaction!(session, transaction.id)
      end
    end

    test "change_transaction/1 returns a transaction changeset", %{session: session} do
      transaction = insert(:transaction, tenant_id: session.tenant_id)

      assert %Ecto.Changeset{} = TransactionContext.change_transaction(transaction)
    end
  end
end

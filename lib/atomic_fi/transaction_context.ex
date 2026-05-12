defmodule AtomicFi.TransactionContext do
  @moduledoc """
  Transaction context — manages payment transactions linked to AccountHolders.

  One row per payment instruction or transfer event, covering the full ISO 20022
  payment lifecycle across message families:

  - `pain:001` — CustomerCreditTransferInitiation
  - `pacs:008` — FIToFICustomerCreditTransfer (interbank settlement)
  - `pacs:002` — FIToFIPaymentStatusReport (status / rejection)
  - `pacs:004` — PaymentReturn (reversal / refund)
  - `camt:054` — BankToCustomerDebitCreditNotification (booking confirmation)

  ## FATF Recommendation 16 — Wire Transfer Rule

  Transactions gate FATF R16 wire transfer compliance. Every payment instruction
  must reference verified debtor and creditor PaymentAccounts linked to verified
  AccountHolders. The orchestration layer is responsible for enforcing this before
  creating a transaction.

  ## PCI-DSS 4.0

  Raw PAN data must never appear in transaction fields. Use tokenised references
  via the linked PaymentAccount only.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.LedgerEntryContext
  alias AtomicFi.OpenApiSchema.TransactionRequest
  alias AtomicFi.Repo
  alias AtomicFi.RuleEngine
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.TransactionContext.Transaction

  # Associations preloaded before handing the transaction to the rule engine, so it
  # can evaluate the full entity tree (debtor/creditor payment accounts + counterparties
  # + the account holder) and resolve the leaf ledger accounts in play.
  @rule_engine_preloads [
    :account_holder,
    :debtor_payment_account,
    :creditor_payment_account,
    :debtor_counterparty,
    :creditor_counterparty
  ]

  @doc """
  Returns the list of transactions with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_transactions(session, %{page: 1, page_size: 20})
      {:ok, {[%Transaction{}, ...], %Flop.Meta{}}}

  """
  @spec list_transactions(Session.t(), map()) ::
          {:ok, {list(Transaction.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_transactions(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    Transaction
    |> Flop.validate_and_run(flop_params,
      for: Transaction,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single transaction.

  Raises `Ecto.NoResultsError` if the Transaction does not exist.

  ## Examples

      iex> get_transaction!(session, "123")
      %Transaction{}

      iex> get_transaction!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_transaction!(Session.t(), Ecto.UUID.t()) :: Transaction.t()
  def_with_rls_and_logging get_transaction!(session, id), log_fields: [:id] do
    Repo.get!(Transaction, id, session: session)
  end

  @doc """
  Creates a transaction.

  Flow:

  1. Insert the transaction `:pending`.
  2. Preload the entity tree (`#{inspect(@rule_engine_preloads)}`).
  3. `RuleEngine.get_limits(transaction)` → `%{ledger_account_id => [VelocityLimit.t()]}`
     (the rule engine maps `transaction_type → regime` and returns limits for the leaf
     ledger accounts in play, plus their ancestors).
  4. `LedgerEntryContext.create_entries/3` posts the balanced debit/credit pair, carrying
     those limits; the BEFORE-INSERT trigger fans them up the ancestor chain and the
     `ledger_account_balances` CHECK constraints enforce them. If a limit is breached, the
     entries come back `:voided` with `rejected_*` and nothing posts.
  5. Update the transaction: `:rejected` + `rejected_*` (from the voided entry) if any leg
     was voided, otherwise `:accepted`.

  ## Examples

      iex> create_transaction(session, %{field: value})
      {:ok, %Transaction{status: :accepted}}

      iex> create_transaction(session, %{...amount over a velocity limit...})
      {:ok, %Transaction{status: :rejected, rejected_rule: "...", ...}}

  """
  @spec create_transaction(Session.t(), TransactionRequest.t()) ::
          {:ok, Transaction.t()} | {:error, Ecto.Changeset.t() | term()}
  def_with_rls_and_logging create_transaction(
                             session,
                             %TransactionRequest{} = request
                           ),
                           log_fields: [] do
    with {:ok, transaction} <-
           %Transaction{} |> Transaction.changeset(request) |> Repo.insert(session: session),
         transaction <-
           Repo.preload(transaction, @rule_engine_preloads, skip_multi_tenancy_check: true),
         {:ok, limits} <- RuleEngine.impl().get_limits(transaction),
         {:ok, entries} <- LedgerEntryContext.create_entries(session, transaction, limits) do
      transaction
      |> Transaction.changeset(transaction_outcome(entries))
      |> Repo.update(session: session)
    end
  end

  # Maps the posted/voided ledger-entry pair to the transaction's resulting status
  # (+ denormalised rejection metadata when a velocity limit was hit).
  defp transaction_outcome(entries) do
    case Enum.find(entries, &(&1.status == :voided)) do
      nil ->
        %{status: :accepted}

      voided ->
        %{
          status: :rejected,
          rejected_ledger_account_id: voided.rejected_ledger_account_id,
          rejected_period: voided.rejected_period,
          rejected_direction: voided.rejected_direction,
          rejected_rule: voided.rejected_rule,
          rejected_code: voided.rejected_code
        }
    end
  end

  @doc """
  Updates a transaction.

  ## Examples

      iex> update_transaction(session, transaction, %{field: new_value})
      {:ok, %Transaction{}}

      iex> update_transaction(session, transaction, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_transaction(Session.t(), Transaction.t(), TransactionRequest.t()) ::
          {:ok, Transaction.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_transaction(
                             session,
                             %Transaction{} = transaction,
                             %TransactionRequest{} = request
                           ),
                           log_fields: [:transaction] do
    transaction
    |> Transaction.changeset(request)
    |> Repo.update(session: session)
  end

  @doc """
  Deletes a transaction.

  ## Examples

      iex> delete_transaction(session, transaction)
      {:ok, %Transaction{}}

      iex> delete_transaction(session, transaction)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_transaction(Session.t(), Transaction.t()) ::
          {:ok, Transaction.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_transaction(session, %Transaction{} = transaction),
    log_fields: [:transaction] do
    Repo.delete(transaction, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking transaction changes.

  ## Examples

      iex> change_transaction(transaction)
      %Ecto.Changeset{data: %Transaction{}}

  """
  def change_transaction(%Transaction{} = transaction, attrs \\ %{}) do
    Transaction.changeset(transaction, attrs)
  end
end

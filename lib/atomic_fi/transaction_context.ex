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
  #
  # LegalEntity + its addresses are preloaded on every party — rules over residency
  # / geo-sanctions (scenario #15 etc.) read `<party>.legal_entity.country_of_residence`,
  # which `AtomicFi.RuleEngine.build_payload/2` carries onto the party via
  # `legal_entity.addresses[]` (the rule walks the array directly).
  #
  # `beneficial_owners` is preloaded on every party that can carry UBOs (AH +
  # CP) — rules over corporate-AH UBO disclosure (FinCEN CDD §1010.230, scenario
  # #27 etc.) read `account_holder.beneficial_owners[]` (or the CP-side mirror).
  # The has_many on AH/CP walks the BO-LE rows via the split subject_type, so
  # AH-BOs never bleed into the CP-BO list and vice versa.
  @rule_engine_preloads [
    account_holder: [legal_entity: [:addresses], beneficial_owners: [legal_entity: [:addresses]]],
    debtor_counterparty: [
      legal_entity: [:addresses],
      beneficial_owners: [legal_entity: [:addresses]]
    ],
    creditor_counterparty: [
      legal_entity: [:addresses],
      beneficial_owners: [legal_entity: [:addresses]]
    ],
    debtor_payment_account: [
      account_holder: [
        legal_entity: [:addresses],
        beneficial_owners: [legal_entity: [:addresses]]
      ]
    ],
    creditor_payment_account: [
      account_holder: [
        legal_entity: [:addresses],
        beneficial_owners: [legal_entity: [:addresses]]
      ]
    ]
  ]

  @doc """
  Returns transactions originated by `account_holder` (i.e. the AH was the
  payer / debtor side) inserted within the last 24 hours. Excludes
  rejected transactions — rejected attempts don't move money and so
  don't count toward structuring/velocity aggregates.

  Used by `AtomicFi.RuleEngine.build_payload/2` to surface
  a recent-debit projection that BSA §5324 (anti-structuring) rules
  can window over. `exclude_id` skips a specific transaction — the
  payload builder passes the current transaction's id so the row
  being evaluated never counts itself as a prior debit.
  """
  @spec list_recent_debits_for_account_holder(Session.t(), Ecto.UUID.t(), Ecto.UUID.t() | nil) ::
          [Transaction.t()]
  def_with_rls_and_logging list_recent_debits_for_account_holder(
                             session,
                             account_holder_id,
                             exclude_id
                           ),
                           log_fields: [] do
    since = DateTime.add(DateTime.utc_now(), -24 * 60 * 60, :second)

    base =
      from(t in Transaction,
        where:
          t.account_holder_id == ^account_holder_id and
            t.inserted_at >= ^since and
            t.status != :rejected,
        order_by: [desc: t.inserted_at]
      )

    query =
      case exclude_id do
        nil -> base
        id -> from(t in base, where: t.id != ^id)
      end

    Repo.all(query, session: session)
  end

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
  Fetches a transaction by caller-supplied SoE handle. Returns the
  struct or `nil`.
  """
  @spec get_transaction_by_external_id(Session.t(), String.t()) :: Transaction.t() | nil
  def_with_rls_and_logging get_transaction_by_external_id(session, external_id),
    log_fields: [:external_id] do
    Repo.get_by(Transaction, [external_id: external_id], session: session)
  end

  @doc """
  Creates a transaction.

  Flow:

  1. Insert the transaction `:pending`.
  2. Preload the entity tree (`#{inspect(@rule_engine_preloads)}`).
  3. `RuleEngine.get_limits(transaction)` → `%{ledger_account_id => [ControlLimit.t()]}`
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

      iex> create_transaction(session, %{...amount over a control limit...})
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
           Repo.preload(transaction, @rule_engine_preloads, skip_multi_tenancy_check: true) do
      case RuleEngine.apply_rules(session, :transaction_screening, transaction) do
        {:ok, :no_limits} ->
          # No rule emitted controls — the catalog's PASS path. If both PAs
          # are wired, post un-capped entries; the txn flips to :accepted
          # (`guides/use-cases.md` result vocabulary: "transaction proceeds;
          # ledger commits; no compliance event opened"). If the txn is
          # malformed (missing a PA), keep :pending — engine has nothing
          # to score against and there are no leaf LAs to post into.
          if has_payment_accounts?(transaction) do
            post_entries(session, transaction, %{})
          else
            {:ok, transaction}
          end

        {:ok, %{controls: controls}} ->
          # next_screening_at is meaningful only for onboarding; transactions
          # are one-shot, so we ignore it here.
          post_entries(session, transaction, controls)

        {:error, _} = err ->
          err
      end
    end
  end

  defp post_entries(session, %Transaction{} = transaction, controls) do
    with {:ok, entries} <-
           LedgerEntryContext.create_entries(session, transaction, controls) do
      transaction
      |> Transaction.changeset(transaction_outcome(entries))
      |> Repo.update(session: session)
    end
  end

  defp has_payment_accounts?(%Transaction{
         debtor_payment_account_id: debtor,
         creditor_payment_account_id: creditor
       }),
       do: is_binary(debtor) and is_binary(creditor)

  # Maps the posted/voided ledger-entry pair to the transaction's resulting status
  # (+ denormalised rejection metadata when a control limit was hit).
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

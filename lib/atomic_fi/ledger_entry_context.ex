defmodule AtomicFi.LedgerEntryContext do
  @moduledoc """
  LedgerEntry context — manages individual debit/credit line items (ISO 20022 CdtDbtInd).

  Balance propagation is handled by the `ledger_entry_propagate_to_balances`
  PostgreSQL trigger (BEFORE INSERT OR UPDATE OF status ON ledger_entries):

  - INSERT (non-voided): walks `ledger_account.ancestor_ids || self`, increments
    `ledger_accounts.balance` (credit = +, debit = –) and upserts
    `ledger_account_balances` rows for the leaf + every ancestor, fanning the entry's
    `limits_at_entry` (`control_limit[]`) into the flat `last_*_limit` columns. If a
    control-limit CHECK constraint fires, the trigger persists the entry `:voided`
    and records `rejected_*` (which account / period / direction / rule).
  - INSERT (already `:voided`): no-op (used by `create_entries/3` to re-record a
    rejected pair without moving balances).
  - UPDATE status → voided: reverses the balance delta on the leaf + every ancestor.

  This context does NOT perform manual balance increments — the trigger does it all.
  """

  import Ecto.Query, warn: false
  require Logger
  use AtomicFi.LoggerMacro

  alias AtomicFi.LedgerAccountContext.LedgerAccount
  alias AtomicFi.LedgerAccountContext.ControlLimit
  alias AtomicFi.LedgerEntryContext.LedgerEntry
  alias AtomicFi.OpenApiSchema.LedgerEntryRequest
  alias AtomicFi.Repo
  alias AtomicFi.RuleEngine.Control
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.TransactionContext.Transaction

  @doc """
  Returns the list of ledger_entries with pagination and filtering.

  ## Examples

      iex> list_ledger_entries(session, %{page: 1, page_size: 20})
      {:ok, {[%LedgerEntry{}, ...], %Flop.Meta{}}}

  """
  @spec list_ledger_entries(Session.t(), map()) ::
          {:ok, {list(LedgerEntry.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_ledger_entries(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    LedgerEntry
    |> Flop.validate_and_run(flop_params,
      for: LedgerEntry,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single ledger_entry.

  Raises `Ecto.NoResultsError` if the LedgerEntry does not exist.

  ## Examples

      iex> get_ledger_entry!(session, "123")
      %LedgerEntry{}

      iex> get_ledger_entry!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_ledger_entry!(Session.t(), Ecto.UUID.t()) :: LedgerEntry.t()
  def_with_rls_and_logging get_ledger_entry!(session, id), log_fields: [:id] do
    Repo.get!(LedgerEntry, id, session: session)
  end

  @doc """
  Creates a ledger_entry.

  The DB trigger `ledger_entry_propagate_to_balances` fires after the INSERT and:
  - Updates ledger_accounts.balance (credit = +, debit = –)
  - Upserts ledger_account_balances rows for the direct account and all ancestors
  - Copies *_limit_at_entry to last_*_limit on balance rows (for CHECK constraint enforcement)

  Control limit snapshots (*_limit_at_entry) must be set on the request by the
  orchestration layer from the risk engine before calling this function. NULL = unconstrained.

  ## Examples

      iex> create_ledger_entry(session, %{entry_type: :credit, amount: 5000, ...})
      {:ok, %LedgerEntry{}}

  """
  @spec create_ledger_entry(Session.t(), LedgerEntryRequest.t()) ::
          {:ok, LedgerEntry.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_ledger_entry(session, %LedgerEntryRequest{} = request),
    log_fields: [] do
    %LedgerEntry{}
    |> LedgerEntry.changeset(request)
    |> Repo.insert(session: session)
  end

  @doc """
  Creates the balanced ledger-entry pair for a transaction.

  Posts a debit on the debtor's leaf LedgerAccount and a credit on the creditor's
  leaf, each carrying the per-LA `%Control{}` returned by the rule engine. `controls`
  is the `%{ledger_account_id => Control.t()}` map; the leaf for each side is
  whichever id in `controls` belongs to that side's PaymentAccount and is a regime
  leaf. `Σ debits = Σ credits` by construction.

  Internally we fan each `Control` into 0–8 `ControlLimit{}` structs (one per
  non-nil cap slot) and write them to `LedgerEntry.limits_at_entry` — the
  ledger-storage shape the trigger already understands.

  The BEFORE-INSERT trigger fans each entry's limits up its ancestor chain; if a
  control-limit CHECK fires the trigger persists *that* entry `:voided` with
  `rejected_*`. If either of the pair comes back `:voided`, the whole pair is
  re-recorded `:voided` (carrying the same `rejected_*`) — nothing posts, so the
  ledger stays balanced.

  Returns `{:ok, [debit_entry, credit_entry]}` — both `:posted`, or both `:voided`.
  """
  @spec create_entries(Session.t(), Transaction.t(), map()) ::
          {:ok, [LedgerEntry.t()]} | {:error, term()}
  def_with_rls_and_logging create_entries(session, %Transaction{} = transaction, controls),
    log_fields: [] do
    {debit_la_id, credit_la_id} = resolve_leaf_accounts(transaction, controls)

    debit_cs =
      build_changeset(transaction, debit_la_id, :debit, Map.get(controls, debit_la_id))

    credit_cs =
      build_changeset(transaction, credit_la_id, :credit, Map.get(controls, credit_la_id))

    # The transaction is load-bearing for the case where the debit posts
    # (debtor ancestor balances move) but the credit insert's trigger flips
    # status to :voided (creditor side unchanged) — without the wrapper the
    # ledger would be left unbalanced. When the debit itself comes back :voided,
    # the trigger's own EXCEPTION block already rolled its partial balance
    # changes back, but we keep a single shape across both paths.
    first_attempt =
      Repo.transaction(fn ->
        with {:ok, debit} <- insert_entry(session, debit_cs),
             {:ok, credit} <- insert_entry(session, credit_cs) do
          if debit.status == :voided or credit.status == :voided do
            Repo.rollback({:rejected, rejection_from(debit, credit)})
          else
            [debit, credit]
          end
        else
          {:error, %Ecto.Changeset{} = cs} ->
            Logger.warning("create_entries: changeset invalid — errors=#{inspect(cs.errors)}")

            Repo.rollback(cs)
        end
      end)

    case first_attempt do
      {:ok, entries} ->
        {:ok, entries}

      {:error, {:rejected, rejection}} ->
        # Re-record both legs :voided (trigger skips voided inserts ⇒ no balance moves).
        Repo.transaction(fn ->
          with {:ok, debit} <- insert_entry(session, put_voided(debit_cs, rejection)),
               {:ok, credit} <- insert_entry(session, put_voided(credit_cs, rejection)) do
            [debit, credit]
          else
            # coveralls-ignore-start — first attempt's insert succeeded at the
            # DB level (changeset was valid; trigger merely flipped status to
            # :voided), so the SAME attrs with put_change(:status, :voided)
            # would only fail here if the FK target was concurrently deleted
            # between the two transactions. Real but un-testable in single-
            # process tests.
            {:error, %Ecto.Changeset{} = cs} ->
              Logger.warning(
                "create_entries: void re-record invalid — errors=#{inspect(cs.errors)}"
              )

              Repo.rollback(cs)
              # coveralls-ignore-stop
          end
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The leaf LedgerAccount for each side = the id in `limits` that belongs to
  # that side's PaymentAccount and is a regime leaf (one of the *_regime_root
  # la_types — not an aggregation-root row).
  @regime_leaf_la_types [
    :account_holder_payment_account_regime_root,
    :counter_party_payment_account_regime_root
  ]

  defp resolve_leaf_accounts(%Transaction{} = txn, limits) do
    ids = Map.keys(limits)

    leaves =
      Repo.all(
        from(la in LedgerAccount,
          where: la.id in ^ids and la.la_type in ^@regime_leaf_la_types,
          select: {la.id, la.payment_account_id}
        ),
        skip_multi_tenancy_check: true
      )

    {find_leaf(leaves, txn.debtor_payment_account_id),
     find_leaf(leaves, txn.creditor_payment_account_id)}
  end

  defp find_leaf(leaves, payment_account_id) do
    Enum.find_value(leaves, fn {id, pa_id} -> pa_id == payment_account_id && id end)
  end

  # Translation boundary: RuleEngine speaks Control (one struct per LA with
  # 8 named caps + reason); the ledger speaks ControlLimit (one struct per
  # period/direction/cap with the rule string). Fan a Control into 0–8
  # ControlLimits — one per non-nil slot.
  defp controls_to_limits(nil), do: []

  defp controls_to_limits(%Control{} = c) do
    [
      {"daily", "debit", c.daily_debit_cap},
      {"daily", "credit", c.daily_credit_cap},
      {"weekly", "debit", c.weekly_debit_cap},
      {"weekly", "credit", c.weekly_credit_cap},
      {"monthly", "debit", c.monthly_debit_cap},
      {"monthly", "credit", c.monthly_credit_cap},
      {"yearly", "debit", c.yearly_debit_cap},
      {"yearly", "credit", c.yearly_credit_cap}
    ]
    |> Enum.reject(fn {_, _, cap} -> is_nil(cap) end)
    |> Enum.map(fn {period, direction, cap} ->
      %ControlLimit{
        period: period,
        direction: direction,
        cap: cap,
        rule: c.reason
      }
    end)
  end

  defp build_changeset(%Transaction{} = txn, ledger_account_id, entry_type, control) do
    LedgerEntry.changeset(%LedgerEntry{}, %{
      account_holder_id: txn.account_holder_id,
      ledger_account_id: ledger_account_id,
      currency: txn.currency,
      amount: txn.amount,
      entry_type: entry_type,
      status: :posted,
      limits_at_entry: controls_to_limits(control),
      tenant_id: txn.tenant_id
    })
  end

  # `returning: true` brings the trigger-mutated row back in a single round-trip —
  # status/rejected_* reflect any BEFORE-INSERT trigger changes without a reload.
  defp insert_entry(session, %Ecto.Changeset{} = cs) do
    Repo.insert(cs, session: session, returning: true)
  end

  defp rejection_from(debit, credit) do
    if debit.status == :voided, do: debit, else: credit
  end

  # Re-record both legs of a rejected pair as :voided. Carries the trigger's
  # rejected_* diagnostics forward so the audit pair tells the same story.
  defp put_voided(%Ecto.Changeset{} = cs, %LedgerEntry{} = rejected) do
    cs
    |> Ecto.Changeset.put_change(:status, :voided)
    |> Ecto.Changeset.put_change(:rejected_ledger_account_id, rejected.rejected_ledger_account_id)
    |> Ecto.Changeset.put_change(:rejected_period, rejected.rejected_period)
    |> Ecto.Changeset.put_change(:rejected_direction, rejected.rejected_direction)
    |> Ecto.Changeset.put_change(:rejected_rule, rejected.rejected_rule)
    |> Ecto.Changeset.put_change(:rejected_code, rejected.rejected_code)
  end

  @doc """
  Updates a ledger_entry.

  Transitioning `status` to `:voided` causes the DB trigger to reverse the balance
  delta on the parent LedgerAccount and all ancestor accounts. Other status transitions
  (e.g. pending → posted) do not affect balances.

  ## Examples

      iex> update_ledger_entry(session, entry, %{status: :posted})
      {:ok, %LedgerEntry{}}

      iex> update_ledger_entry(session, entry, %{status: :voided})
      {:ok, %LedgerEntry{}}  # trigger reverses balance on account + all ancestors

  """
  @spec update_ledger_entry(Session.t(), LedgerEntry.t(), LedgerEntryRequest.t()) ::
          {:ok, LedgerEntry.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_ledger_entry(
                             session,
                             %LedgerEntry{} = ledger_entry,
                             %LedgerEntryRequest{} = request
                           ),
                           log_fields: [:ledger_entry] do
    ledger_entry
    |> LedgerEntry.changeset(request)
    |> Repo.update(session: session)
  end

  @doc """
  Deletes a ledger_entry.

  NOTE: Deleting a posted entry does NOT reverse the balance. Transition status to
  `:voided` first to reverse the balance, then delete if needed.

  ## Examples

      iex> delete_ledger_entry(session, ledger_entry)
      {:ok, %LedgerEntry{}}

  """
  @spec delete_ledger_entry(Session.t(), LedgerEntry.t()) ::
          {:ok, LedgerEntry.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_ledger_entry(session, %LedgerEntry{} = ledger_entry),
    log_fields: [:ledger_entry] do
    Repo.delete(ledger_entry, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking ledger_entry changes.

  ## Examples

      iex> change_ledger_entry(ledger_entry)
      %Ecto.Changeset{data: %LedgerEntry{}}

  """
  def change_ledger_entry(%LedgerEntry{} = ledger_entry, attrs \\ %{}) do
    LedgerEntry.changeset(ledger_entry, attrs)
  end
end

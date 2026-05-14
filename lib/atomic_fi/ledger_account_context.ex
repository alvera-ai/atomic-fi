defmodule AtomicFi.LedgerAccountContext do
  @moduledoc """
  LedgerAccount context — manages chart-of-accounts line items within a Ledger.

  LedgerAccount.balance is a running total in minor currency units (e.g. cents for USD).
  It is updated atomically by the `ledger_entry_propagate_to_balances` PostgreSQL trigger
  whenever a LedgerEntry is inserted or voided.

  LedgerAccounts are hierarchical. The `ancestor_ids` array is a flat
  root-first path of ancestor UUIDs — the single source of truth for
  hierarchy traversal (no separate parent_id column). Callers set
  `ancestor_ids` explicitly on insert/update via the changeset.

  The `ledger_entry_propagate_to_balances` trigger walks `ancestor_ids` so
  cumulative balances roll up through the account hierarchy automatically.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.LedgerAccountContext.LedgerAccount
  alias AtomicFi.LedgerContext.Ledger
  alias AtomicFi.OpenApiSchema.LedgerAccountRequest
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.Repo
  alias AtomicFi.RuleEngine.Control
  alias AtomicFi.SessionContext.Session
  alias Ecto.Multi

  # LAs are materialised block-by-default. The onboarding RuleEngine call
  # (run after `ensure_linked_ledger_accounts/2`) unblocks them and sets the
  # max_* hard caps. If the engine returns `:no_limits`, LAs stay blocked —
  # fail-closed by design.
  @initial_block_reason "pending onboarding screening"

  # Default preload set — the linked_ledger_accounts edge list (with each edge's
  # target LA hydrated) is the read-side ergonomic for tree traversal. Single
  # source of truth: callers never reach into Repo / Ecto.Query themselves.
  @preloads [linked_ledger_accounts: :to]

  @doc """
  Returns the list of ledger_accounts with pagination and filtering.

  ## Examples

      iex> list_ledger_accounts(session, %{page: 1, page_size: 20})
      {:ok, {[%LedgerAccount{}, ...], %Flop.Meta{}}}

  """
  @spec list_ledger_accounts(Session.t(), map()) ::
          {:ok, {list(LedgerAccount.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_ledger_accounts(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    with {:ok, {accounts, meta}} <-
           LedgerAccount
           |> Flop.validate_and_run(flop_params,
             for: LedgerAccount,
             repo: Repo,
             query_opts: [session: session]
           ) do
      {:ok, {Repo.preload(accounts, @preloads, session: session), meta}}
    end
  end

  @doc """
  Gets a single ledger_account.

  Raises `Ecto.NoResultsError` if the LedgerAccount does not exist.

  ## Examples

      iex> get_ledger_account!(session, "123")
      %LedgerAccount{}

      iex> get_ledger_account!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_ledger_account!(Session.t(), Ecto.UUID.t()) :: LedgerAccount.t()
  def_with_rls_and_logging get_ledger_account!(session, id), log_fields: [:id] do
    LedgerAccount
    |> Repo.get!(id, session: session)
    |> Repo.preload(@preloads, session: session)
  end

  @doc """
  Creates a ledger_account.

  Callers supply `ancestor_ids` directly on the request (root-first list of
  parent LA UUIDs). Root LAs use `ancestor_ids: []`.

  ## Examples

      iex> create_ledger_account(session, %{field: value})
      {:ok, %LedgerAccount{}}

      iex> create_ledger_account(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_ledger_account(Session.t(), LedgerAccountRequest.t()) ::
          {:ok, LedgerAccount.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_ledger_account(session, %LedgerAccountRequest{} = request),
    log_fields: [] do
    with {:ok, ledger_account} <-
           %LedgerAccount{}
           |> LedgerAccount.changeset(request)
           |> Repo.insert(session: session) do
      {:ok, Repo.preload(ledger_account, @preloads, session: session)}
    end
  end

  @doc """
  Updates a ledger_account.

  NOTE: balance is never updated directly through this function.
  LedgerEntry inserts and voids update balances via the DB trigger.

  ## Examples

      iex> update_ledger_account(session, ledger_account, %{field: new_value})
      {:ok, %LedgerAccount{}}

      iex> update_ledger_account(session, ledger_account, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_ledger_account(Session.t(), LedgerAccount.t(), LedgerAccountRequest.t()) ::
          {:ok, LedgerAccount.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_ledger_account(
                             session,
                             %LedgerAccount{} = ledger_account,
                             %LedgerAccountRequest{} = request
                           ),
                           log_fields: [:ledger_account] do
    with {:ok, updated} <-
           ledger_account
           |> LedgerAccount.changeset(request)
           |> Repo.update(session: session) do
      {:ok, Repo.preload(updated, @preloads, session: session)}
    end
  end

  @doc """
  Deletes a ledger_account.

  ## Examples

      iex> delete_ledger_account(session, ledger_account)
      {:ok, %LedgerAccount{}}

      iex> delete_ledger_account(session, ledger_account)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_ledger_account(Session.t(), LedgerAccount.t()) ::
          {:ok, LedgerAccount.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_ledger_account(session, %LedgerAccount{} = ledger_account),
    log_fields: [:ledger_account] do
    Repo.delete(ledger_account, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking ledger_account changes.

  ## Examples

      iex> change_ledger_account(ledger_account)
      %Ecto.Changeset{data: %LedgerAccount{}}

  """
  def change_ledger_account(%LedgerAccount{} = ledger_account, attrs \\ %{}) do
    LedgerAccount.changeset(ledger_account, attrs)
  end

  @doc """
  Idempotently materialises the LedgerAccount rows implied by a
  `%PaymentAccount{}` or `%Counterparty{}` write. Hooked at every write
  boundary that can change which (ledger, regime, pa, cp) tuples need to
  exist:

    * `PaymentAccountContext.create/update_payment_account/3`
    * `CounterpartyContext.create/update_counterparty/3`
    * `TransactionContext.create_transaction/2` (defensive backstop)

  Dispatches on struct type:

    * `%PaymentAccount{}` — for the AH's ledger matching `pa.currency`, upserts
      the AH-PA root + every AH-PA regime-root for `pa.enabled_regimes`. When
      the PA carries a `counterparty_id` (CP-owned PA), upserts the CP-PA
      root + per-regime CP-PA regime-roots instead. The CP root + CP regime
      roots are assumed to already exist (created by the CP write hook).

    * `%Counterparty{}` — for every ledger of the CP's linked AccountHolder,
      upserts the CP root + every CP regime-root for `cp.enabled_regimes`.

  Each ancestor LA must exist before its descendant — order is enforced
  inside this helper. The BEFORE-INSERT trigger
  `ledger_accounts_resolve_ancestor_ids` fails fast (changeset error) if a
  descendant is attempted before its `*_root` sibling — this helper
  guarantees the correct order so that error path stays unreachable on the
  happy path.

  Idempotent: each upsert looks up the LA by its natural identity tuple
  (`ledger_id, la_type, regime, payment_account_id, counterparty_id`) and
  inserts only when missing. Re-running for the same entity is a no-op.
  """
  @spec ensure_linked_ledger_accounts(
          Session.t(),
          AccountHolder.t() | PaymentAccount.t() | Counterparty.t()
        ) :: :ok | {:error, term()}
  def_with_rls_and_logging ensure_linked_ledger_accounts(session, %AccountHolder{} = ah),
    log_fields: [:ah] do
    ah.id
    |> ah_ledgers(session)
    |> Enum.reduce(Multi.new(), fn ledger, multi ->
      base = la_base(ah.id, ledger.id, ledger.currency, ah.tenant_id)

      multi
      |> upsert_step({:ah_root, ledger.id}, session, base, :account_holder_root, "root", nil, nil)
      |> upsert_regime_steps(
        session,
        :account_holder_regime_root,
        ah.enabled_regimes,
        nil,
        nil,
        ledger.id
      )
    end)
    |> run_multi(session)
  end

  def_with_rls_and_logging ensure_linked_ledger_accounts(session, %PaymentAccount{} = pa),
    log_fields: [:pa] do
    ledger = ah_ledger!(session, pa.account_holder_id, pa.currency)
    base = la_base(pa.account_holder_id, ledger.id, pa.currency, pa.tenant_id)

    {root_la_type, regime_la_type} =
      case pa.counterparty_id do
        nil ->
          {:account_holder_payment_account_root, :account_holder_payment_account_regime_root}

        _cp_id ->
          {:counter_party_payment_account_root, :counter_party_payment_account_regime_root}
      end

    Multi.new()
    |> upsert_step(:root, session, base, root_la_type, "root", pa.id, pa.counterparty_id)
    |> upsert_regime_steps(session, regime_la_type, pa.enabled_regimes, pa.id, pa.counterparty_id)
    |> run_multi(session)
  end

  def_with_rls_and_logging ensure_linked_ledger_accounts(session, %Counterparty{} = cp),
    log_fields: [:cp] do
    cp.account_holder_id
    |> ah_ledgers(session)
    |> Enum.reduce(Multi.new(), fn ledger, multi ->
      base = la_base(cp.account_holder_id, ledger.id, ledger.currency, cp.tenant_id)

      multi
      |> upsert_step({:root, ledger.id}, session, base, :counter_party_root, "root", nil, cp.id)
      |> upsert_regime_steps(
        session,
        :counter_party_regime_root,
        cp.enabled_regimes,
        nil,
        cp.id,
        ledger.id
      )
    end)
    |> run_multi(session)
  end

  # ── private helpers ────────────────────────────────────────────────────────

  defp la_base(account_holder_id, ledger_id, currency, tenant_id) do
    %{
      account_holder_id: account_holder_id,
      ledger_id: ledger_id,
      currency: currency,
      tenant_id: tenant_id
    }
  end

  defp ah_ledger!(session, account_holder_id, currency) do
    Repo.one!(
      from(l in Ledger,
        where: l.account_holder_id == ^account_holder_id and l.currency == ^currency
      ),
      session: session
    )
  end

  defp ah_ledgers(account_holder_id, session) do
    Repo.all(
      from(l in Ledger, where: l.account_holder_id == ^account_holder_id),
      session: session
    )
  end

  # Multi.run step: idempotent upsert for a single LedgerAccount row.
  defp upsert_step(
         multi,
         name,
         session,
         base,
         la_type,
         regime,
         payment_account_id,
         counterparty_id
       ) do
    Multi.run(multi, name, fn _repo, _changes ->
      upsert_la(session, base, la_type, regime, payment_account_id, counterparty_id)
    end)
  end

  # Adds one regime-root step per enabled regime. Each runs after the root
  # row above so the BEFORE-INSERT trigger can resolve its ancestor.
  defp upsert_regime_steps(
         multi,
         session,
         la_type,
         regimes,
         pa_id,
         cp_id,
         scope \\ nil
       )

  defp upsert_regime_steps(multi, _session, _la_type, [], _pa_id, _cp_id, _scope), do: multi

  defp upsert_regime_steps(multi, session, la_type, [regime | rest], pa_id, cp_id, scope) do
    name = if scope, do: {:regime, scope, regime}, else: {:regime, regime}

    multi
    |> Multi.run(name, fn _repo, %{} = changes ->
      base = la_base_for(changes, scope)
      upsert_la(session, base, la_type, regime, pa_id, cp_id)
    end)
    |> upsert_regime_steps(session, la_type, rest, pa_id, cp_id, scope)
  end

  # The `base` map travels via the first :root step's changes — we re-extract
  # the ledger / tenant context from there so subsequent regime steps stay
  # parameter-free.
  defp la_base_for(changes, nil) do
    %LedgerAccount{} = root = Map.fetch!(changes, :root)
    la_base(root.account_holder_id, root.ledger_id, root.currency, root.tenant_id)
  end

  defp la_base_for(changes, ledger_id) do
    %LedgerAccount{} = root = Map.fetch!(changes, {:root, ledger_id})
    la_base(root.account_holder_id, root.ledger_id, root.currency, root.tenant_id)
  end

  defp run_multi(multi, session) do
    case Repo.transaction(multi, session: session) do
      {:ok, _changes} -> :ok
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  # Looks the LA up by its natural identity tuple (manual `is_nil/1` query —
  # `Repo.get_by` rejects nil values). Inserts via the public
  # `create_ledger_account/2` so `@preloads` apply and validation runs.
  defp upsert_la(session, base, la_type, regime, payment_account_id, counterparty_id) do
    query =
      from(la in LedgerAccount,
        where:
          la.ledger_id == ^base.ledger_id and
            la.regime == ^regime and
            la.la_type == ^la_type
      )

    query =
      case payment_account_id do
        nil -> from(la in query, where: is_nil(la.payment_account_id))
        id -> from(la in query, where: la.payment_account_id == ^id)
      end

    query =
      case counterparty_id do
        nil -> from(la in query, where: is_nil(la.counterparty_id))
        id -> from(la in query, where: la.counterparty_id == ^id)
      end

    case Repo.one(query, session: session) do
      %LedgerAccount{} = existing ->
        {:ok, existing}

      nil ->
        # Internal materialisation — bypass the public LedgerAccountRequest
        # struct (which intentionally omits the internal-only is_blocked /
        # block_reason / max_* fields) and call the schema changeset directly.
        attrs = %{
          account_holder_id: base.account_holder_id,
          ledger_id: base.ledger_id,
          currency: base.currency,
          tenant_id: base.tenant_id,
          la_type: la_type,
          regime: regime,
          payment_account_id: payment_account_id,
          counterparty_id: counterparty_id,
          status: :active,
          is_blocked: true,
          block_reason: @initial_block_reason
        }

        %LedgerAccount{}
        |> LedgerAccount.changeset(attrs)
        |> Repo.insert(session: session)
    end
  end

  @doc """
  Lists the LedgerAccount rows owned by `entity`. Used by onboarding so a
  context can apply the engine's per-LA controls to its own LAs (and
  reset any LAs the engine did NOT emit a Control for back to blocked).

    * `%PaymentAccount{}` — every LA with `payment_account_id == pa.id`.
    * `%AccountHolder{}` — AH-root + AH-regime-root rows: LAs with
      `account_holder_id == ah.id AND payment_account_id IS NULL AND
      counterparty_id IS NULL`.
    * `%Counterparty{}` — CP-root + CP-regime-root rows: LAs with
      `counterparty_id == cp.id AND payment_account_id IS NULL`.
  """
  @spec list_for_entity(Session.t(), AccountHolder.t() | Counterparty.t() | PaymentAccount.t()) ::
          [LedgerAccount.t()]
  def_with_rls_and_logging list_for_entity(session, %PaymentAccount{} = pa), log_fields: [] do
    Repo.all(
      from(la in LedgerAccount, where: la.payment_account_id == ^pa.id),
      session: session
    )
  end

  def_with_rls_and_logging list_for_entity(session, %AccountHolder{} = ah), log_fields: [] do
    Repo.all(
      from(la in LedgerAccount,
        where:
          la.account_holder_id == ^ah.id and is_nil(la.payment_account_id) and
            is_nil(la.counterparty_id)
      ),
      session: session
    )
  end

  def_with_rls_and_logging list_for_entity(session, %Counterparty{} = cp), log_fields: [] do
    Repo.all(
      from(la in LedgerAccount,
        where: la.counterparty_id == ^cp.id and is_nil(la.payment_account_id)
      ),
      session: session
    )
  end

  @doc """
  Applies the engine's per-LA controls to a caller-supplied list of
  LedgerAccounts.

  Semantics (fail-closed): for every LA in `ledger_accounts`, if the
  controls map has an entry for that LA's id, the Control's
  is_blocked / block_reason / max_* fields are written; otherwise the
  LA is reset to the block-by-default state. Entries in `controls` for
  LAs not in `ledger_accounts` are ignored — each entity's onboarding
  flow is responsible for its own LAs only.

  The caller resolves the LA list (via `list_for_entity/2` or a
  preloaded association) so this function stays a pure write step.

  All updates run inside one transaction so a single failure rolls
  them all back.
  """
  @spec apply_controls(
          Session.t(),
          [LedgerAccount.t()],
          %{optional(Ecto.UUID.t()) => Control.t()}
        ) :: :ok | {:error, term()}
  def_with_rls_and_logging apply_controls(session, ledger_accounts, controls), log_fields: [] do
    ledger_accounts
    |> Enum.reduce(Multi.new(), fn %LedgerAccount{} = la, multi ->
      attrs =
        case Map.get(controls, la.id) do
          %Control{} = control -> control_to_la_attrs(control)
          nil -> block_by_default_attrs()
        end

      Multi.update(multi, {:apply, la.id}, LedgerAccount.changeset(la, attrs))
    end)
    |> run_multi(session)
  end

  # Reset attrs for LAs the engine did NOT emit a Control for — the
  # same shape used on initial materialisation in `upsert_la/6`.
  defp block_by_default_attrs do
    %{
      is_blocked: true,
      block_reason: @initial_block_reason,
      max_daily_debit: nil,
      max_daily_credit: nil,
      max_weekly_debit: nil,
      max_weekly_credit: nil,
      max_monthly_debit: nil,
      max_monthly_credit: nil,
      max_yearly_debit: nil,
      max_yearly_credit: nil
    }
  end

  # Maps the Control struct's slot names (daily_debit_cap, …) onto the
  # LedgerAccount column names (max_daily_debit, …). is_blocked /
  # block_reason pass through unchanged.
  defp control_to_la_attrs(%Control{} = c) do
    %{
      max_daily_debit: c.daily_debit_cap,
      max_daily_credit: c.daily_credit_cap,
      max_weekly_debit: c.weekly_debit_cap,
      max_weekly_credit: c.weekly_credit_cap,
      max_monthly_debit: c.monthly_debit_cap,
      max_monthly_credit: c.monthly_credit_cap,
      max_yearly_debit: c.yearly_debit_cap,
      max_yearly_credit: c.yearly_credit_cap,
      is_blocked: c.is_blocked,
      block_reason: c.block_reason
    }
  end
end

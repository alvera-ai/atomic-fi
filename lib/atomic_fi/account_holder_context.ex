defmodule AtomicFi.AccountHolderContext do
  @moduledoc """
  Account holder context — manages the MDM subjects that control accounts.

  AccountHolder records represent the operational state (status, KYC, risk level)
  while all PII lives in the linked LegalEntity.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.LedgerContext.Ledger
  alias AtomicFi.OnboardingContext
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  alias AtomicFi.Repo
  alias AtomicFi.SessionContext.Session
  alias Ecto.Multi

  @preloads [
    legal_entity: [:addresses, :phone_numbers, :identifications],
    beneficial_owners: [legal_entity: [:addresses, :phone_numbers, :identifications]]
  ]

  @doc """
  Returns the list of account_holders with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_account_holders(session, %{page: 1, page_size: 20})
      {:ok, {[%AccountHolder{}, ...], %Flop.Meta{}}}

  """
  @spec list_account_holders(Session.t(), map()) ::
          {:ok, {list(AccountHolder.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_account_holders(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    AccountHolder
    |> preload_query()
    |> Flop.validate_and_run(flop_params,
      for: AccountHolder,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single account_holder.

  Raises `Ecto.NoResultsError` if the Account holder does not exist.

  ## Examples

      iex> get_account_holder!(session, "123")
      %AccountHolder{}

      iex> get_account_holder!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_account_holder!(Session.t(), Ecto.UUID.t()) :: AccountHolder.t()
  def_with_rls_and_logging get_account_holder!(session, id), log_fields: [:id] do
    AccountHolder
    |> preload_query()
    |> Repo.get!(id, session: session)
  end

  @doc """
  Fetches an account holder by caller-supplied SoE handle. Returns the
  fully-preloaded struct or `nil`. Used for idempotent upserts where the
  caller wants to distinguish create vs. update by their own key.
  """
  @spec get_account_holder_by_external_id(Session.t(), String.t()) :: AccountHolder.t() | nil
  def_with_rls_and_logging get_account_holder_by_external_id(session, external_id),
    log_fields: [:external_id] do
    AccountHolder
    |> preload_query()
    |> Repo.get_by([external_id: external_id], session: session)
  end

  @doc """
  Creates a account_holder.

  ## Examples

      iex> create_account_holder(session, %{field: value})
      {:ok, %AccountHolder{}}

      iex> create_account_holder(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_account_holder(Session.t(), AccountHolderRequest.t()) ::
          {:ok, AccountHolder.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_account_holder(
                             session,
                             %AccountHolderRequest{} = request
                           ),
                           log_fields: [] do
    with {:ok, account_holder} <- write_ah_with_ledgers_and_las(session, request),
         {:ok, account_holder} <- OnboardingContext.onboard(session, account_holder) do
      {:ok, account_holder}
    end
  end

  @doc """
  Updates a account_holder.

  ## Examples

      iex> update_account_holder(session, account_holder, %{field: new_value})
      {:ok, %AccountHolder{}}

      iex> update_account_holder(session, account_holder, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_account_holder(Session.t(), AccountHolder.t(), AccountHolderRequest.t()) ::
          {:ok, AccountHolder.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_account_holder(
                             session,
                             %AccountHolder{} = account_holder,
                             %AccountHolderRequest{} = request
                           ),
                           log_fields: [:account_holder] do
    with {:ok, updated} <- write_ah_update_with_ledgers_and_las(session, account_holder, request),
         {:ok, updated} <- OnboardingContext.onboard(session, updated) do
      {:ok, updated}
    end
  end

  @doc """
  `AtomicFi.ControlProtocol` callback for `%AccountHolder{}`. Resolves
  the AH's own LedgerAccounts (AH-root + AH-regime-roots), applies the
  engine's controls, enqueues + links the next `OnboardingWorker`.
  """
  @spec process_controls(AccountHolder.t(), Session.t(), OnboardingContext.result()) ::
          {:ok, AccountHolder.t()} | {:error, term()}
  def process_controls(%AccountHolder{} = account_holder, session, %{
        controls: controls,
        next_screening_at: next_screening_at
      }) do
    require Logger

    Logger.info(
      "[ah.process_controls] start ah=#{account_holder.id} controls=#{map_size(controls)} next=#{inspect(next_screening_at)}"
    )

    ledger_accounts = LedgerAccountContext.list_for_entity(session, account_holder)
    Logger.info("[ah.process_controls] LAs loaded count=#{length(ledger_accounts)}")

    with :ok <- LedgerAccountContext.apply_controls(session, ledger_accounts, controls),
         _ = Logger.info("[ah.process_controls] apply_controls done → enqueue_next"),
         {:ok, job_id} <- OnboardingContext.enqueue_next(account_holder, next_screening_at),
         _ =
           Logger.info(
             "[ah.process_controls] enqueue_next done job=#{inspect(job_id)} → update rescreen_job_id"
           ),
         {:ok, account_holder} <-
           account_holder
           |> Ecto.Changeset.change(%{rescreen_job_id: job_id})
           |> Repo.update(session: session) do
      Logger.info("[ah.process_controls] done")
      {:ok, account_holder}
    end
  end

  # Inserts the AH, fans out one Ledger per `enabled_currencies` entry,
  # and materialises the AH-root + AH-regime-root LedgerAccounts in a
  # single transaction. Empty `enabled_currencies` means no Ledgers and
  # no AH LAs — onboarding still runs (the engine just gets nothing to
  # cap).
  defp write_ah_with_ledgers_and_las(session, %AccountHolderRequest{} = request) do
    Multi.new()
    |> Multi.insert(:account_holder, AccountHolder.changeset(%AccountHolder{}, request))
    |> Multi.run(:ledgers, fn _repo, %{account_holder: account_holder} ->
      ensure_ledgers(session, account_holder)
    end)
    |> Multi.run(:las, fn _repo, %{account_holder: account_holder} ->
      with :ok <- LedgerAccountContext.ensure_linked_ledger_accounts(session, account_holder) do
        {:ok, :ok}
      end
    end)
    |> Repo.transaction(session: session)
    |> case do
      {:ok, %{account_holder: account_holder}} ->
        preload_after_write({:ok, account_holder})

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  # Update sibling of `write_ah_with_ledgers_and_las`. Wraps AH update +
  # ledger ensure + LA ensure in one transaction so growing
  # `enabled_currencies` (adds Ledger + AH-tree per new currency) and
  # growing `enabled_regimes` (adds AH-regime-root LAs per existing ledger)
  # are picked up atomically. Both ensure helpers are idempotent — a
  # no-op update leaves the tree unchanged.
  defp write_ah_update_with_ledgers_and_las(
         session,
         %AccountHolder{} = account_holder,
         %AccountHolderRequest{} = request
       ) do
    Multi.new()
    |> Multi.update(:account_holder, AccountHolder.changeset(account_holder, request))
    |> Multi.run(:ledgers, fn _repo, %{account_holder: updated} ->
      ensure_ledgers(session, updated)
    end)
    |> Multi.run(:las, fn _repo, %{account_holder: updated} ->
      with :ok <- LedgerAccountContext.ensure_linked_ledger_accounts(session, updated) do
        {:ok, :ok}
      end
    end)
    |> Repo.transaction(session: session)
    |> case do
      {:ok, %{account_holder: account_holder}} ->
        preload_after_write({:ok, account_holder})

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  # Idempotent: inserts a Ledger row for each entry in `enabled_currencies`
  # that doesn't already exist for (account_holder_id, currency). Used by
  # both create and update paths.
  defp ensure_ledgers(session, %AccountHolder{enabled_currencies: currencies} = ah)
       when is_list(currencies) do
    existing =
      Repo.all(
        from(l in Ledger,
          where: l.account_holder_id == ^ah.id,
          select: l.currency
        ),
        session: session
      )

    missing = currencies -- existing

    Enum.reduce_while(missing, {:ok, []}, fn currency, {:ok, acc} ->
      attrs = %{
        account_holder_id: ah.id,
        currency: currency,
        tenant_id: ah.tenant_id
      }

      %Ledger{}
      |> Ledger.changeset(attrs)
      |> Repo.insert(session: session)
      |> case do
        {:ok, ledger} -> {:cont, {:ok, [ledger | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  @doc """
  Deletes a account_holder.

  ## Examples

      iex> delete_account_holder(session, account_holder)
      {:ok, %AccountHolder{}}

      iex> delete_account_holder(session, account_holder)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_account_holder(Session.t(), AccountHolder.t()) ::
          {:ok, AccountHolder.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_account_holder(session, %AccountHolder{} = account_holder),
    log_fields: [:account_holder] do
    Repo.delete(account_holder, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking account_holder changes.

  ## Examples

      iex> change_account_holder(account_holder)
      %Ecto.Changeset{data: %AccountHolder{}}

  """
  def change_account_holder(%AccountHolder{} = account_holder, attrs \\ %{}) do
    AccountHolder.changeset(account_holder, attrs)
  end

  # Pipes the preload into the query so Flop and Repo.get! always load associations.
  defp preload_query(query) do
    preload(query, ^@preloads)
  end

  # Preloads associations after successful write operations.
  # Uses skip_multi_tenancy_check since the record was just written and we need the full struct.
  defp preload_after_write({:ok, %AccountHolder{} = account_holder}) do
    {:ok, Repo.preload(account_holder, @preloads, skip_multi_tenancy_check: true)}
  end
end

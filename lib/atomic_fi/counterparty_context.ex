defmodule AtomicFi.CounterpartyContext do
  @moduledoc """
  The CounterpartyContext context.

  Manages external payer/payee relationships for account holders per ISO 20022.
  A counterparty is any external party (<Dbtr>/<Cdtr>) that an internal AccountHolder
  transacts with. All PII lives in the linked LegalEntity — this context manages
  the relationship lifecycle (status) only.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.OnboardingContext
  alias AtomicFi.OpenApiSchema.CounterpartyRequest
  alias AtomicFi.Repo
  alias AtomicFi.SessionContext.Session

  @preloads [legal_entity: [:addresses, :phone_numbers, :identifications]]

  @doc """
  Returns the list of counterparties with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_counterparties(session, %{page: 1, page_size: 20})
      {:ok, {[%Counterparty{}, ...], %Flop.Meta{}}}

  """
  @spec list_counterparties(Session.t(), map()) ::
          {:ok, {list(Counterparty.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_counterparties(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    Counterparty
    |> preload_query()
    |> Flop.validate_and_run(flop_params,
      for: Counterparty,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single counterparty.

  Raises `Ecto.NoResultsError` if the Counterparty does not exist.

  ## Examples

      iex> get_counterparty!(session, "123")
      %Counterparty{}

      iex> get_counterparty!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_counterparty!(Session.t(), Ecto.UUID.t()) :: Counterparty.t()
  def_with_rls_and_logging get_counterparty!(session, id), log_fields: [:id] do
    Counterparty
    |> preload_query()
    |> Repo.get!(id, session: session)
  end

  @doc """
  Creates a counterparty.

  ## Examples

      iex> create_counterparty(session, %{field: value})
      {:ok, %Counterparty{}}

      iex> create_counterparty(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_counterparty(Session.t(), CounterpartyRequest.t()) ::
          {:ok, Counterparty.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_counterparty(
                             session,
                             %CounterpartyRequest{} = request
                           ),
                           log_fields: [] do
    case maybe_get_by_external_id(session, request) do
      %Counterparty{} = existing ->
        {:ok, existing}

      nil ->
        after_cp_changed(session, Counterparty.changeset(%Counterparty{}, request))
    end
  end

  # Get-or-create: the SoE-supplied external_id is the external idempotency key.
  # When the client repeats a POST with the same external_id, return the existing
  # record (RLS scopes to the calling tenant via session). When no external_id is
  # given, fall through to normal insert (the (account_holder_id, legal_entity_id) unique
  # constraint still prevents accidental duplicates).
  defp maybe_get_by_external_id(_session, %CounterpartyRequest{external_id: nil}),
    do: nil

  defp maybe_get_by_external_id(session, %CounterpartyRequest{external_id: number})
       when is_binary(number) and number != "" do
    Counterparty
    |> preload_query()
    |> Ecto.Query.where(external_id: ^number)
    |> Repo.one(session: session)
  end

  defp maybe_get_by_external_id(_session, _request), do: nil

  # Pipes the preload into the query so Flop and Repo.get! always load associations.
  defp preload_query(query) do
    preload(query, ^@preloads)
  end

  @doc """
  Updates a counterparty.

  ## Examples

      iex> update_counterparty(session, counterparty, %{field: new_value})
      {:ok, %Counterparty{}}

      iex> update_counterparty(session, counterparty, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_counterparty(Session.t(), Counterparty.t(), CounterpartyRequest.t()) ::
          {:ok, Counterparty.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_counterparty(
                             session,
                             %Counterparty{} = counterparty,
                             %CounterpartyRequest{} = request
                           ),
                           log_fields: [:counterparty] do
    after_cp_changed(session, Counterparty.changeset(counterparty, request))
  end

  # Lifecycle hook shared by create + update.
  #
  # Three-step flow (see `PaymentAccountContext.after_pa_changed/2` for the
  # PA equivalent):
  #
  #   txn 1 — CP insert/update + CP-tree ensure (block-by-default LAs).
  #   txn 2 — HTTP call to the RuleEngine.
  #   txn 3 — applies the engine's per-LA controls (unblock + max_*).
  defp after_cp_changed(session, %Ecto.Changeset{} = changeset) do
    with {:ok, counterparty} <- write_cp_and_ensure_las(session, changeset),
         {:ok, counterparty} <- OnboardingContext.onboard(session, counterparty) do
      {:ok, counterparty}
    end
  end

  @doc """
  `AtomicFi.ControlProtocol` callback for `%Counterparty{}`. See
  `AtomicFi.PaymentAccountContext.process_controls/3` for the shared
  shape — resolves the CP's own LAs, applies the engine's controls,
  enqueues + links the next `OnboardingWorker`.
  """
  @spec process_controls(Counterparty.t(), Session.t(), OnboardingContext.result()) ::
          {:ok, Counterparty.t()} | {:error, term()}
  def process_controls(%Counterparty{} = counterparty, session, %{
        controls: controls,
        next_screening_at: next_screening_at
      }) do
    ledger_accounts = LedgerAccountContext.list_for_entity(session, counterparty)

    with :ok <- LedgerAccountContext.apply_controls(session, ledger_accounts, controls),
         {:ok, job_id} <- OnboardingContext.enqueue_next(counterparty, next_screening_at),
         {:ok, counterparty} <-
           counterparty
           |> Ecto.Changeset.change(%{rescreen_job_id: job_id})
           |> Repo.update(session: session) do
      {:ok, counterparty}
    end
  end

  defp write_cp_and_ensure_las(session, %Ecto.Changeset{} = changeset) do
    Repo.transaction(
      fn ->
        with {:ok, counterparty} <- Repo.insert_or_update(changeset, session: session),
             :ok <- LedgerAccountContext.ensure_linked_ledger_accounts(session, counterparty) do
          Repo.preload(counterparty, @preloads, skip_multi_tenancy_check: true)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      session: session
    )
  end

  @doc """
  Deletes a counterparty.

  ## Examples

      iex> delete_counterparty(session, counterparty)
      {:ok, %Counterparty{}}

      iex> delete_counterparty(session, counterparty)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_counterparty(Session.t(), Counterparty.t()) ::
          {:ok, Counterparty.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_counterparty(session, %Counterparty{} = counterparty),
    log_fields: [:counterparty] do
    Repo.delete(counterparty, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking counterparty changes.

  ## Examples

      iex> change_counterparty(counterparty)
      %Ecto.Changeset{data: %Counterparty{}}

  """
  def change_counterparty(%Counterparty{} = counterparty, attrs \\ %{}) do
    Counterparty.changeset(counterparty, attrs)
  end
end

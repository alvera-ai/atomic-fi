defmodule AtomicFi.LedgerContext do
  @moduledoc """
  Ledger context — manages ISO 20022 camt:052/camt:053 chart-of-accounts containers.

  One Ledger per AccountHolder per currency. Balance is derived on-read by
  summing child LedgerAccount.balance values. No stored balance on Ledger itself.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.OpenApiSchema.LedgerRequest
  alias AtomicFi.Repo
  alias AtomicFi.LedgerContext.Ledger
  alias AtomicFi.SessionContext.Session

  @doc """
  Returns the list of ledgers with pagination and filtering.

  ## Examples

      iex> list_ledgers(session, %{page: 1, page_size: 20})
      {:ok, {[%Ledger{}, ...], %Flop.Meta{}}}

  """
  @spec list_ledgers(Session.t(), map()) ::
          {:ok, {list(Ledger.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_ledgers(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    Ledger
    |> Flop.validate_and_run(flop_params,
      for: Ledger,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single ledger.

  Raises `Ecto.NoResultsError` if the Ledger does not exist.

  ## Examples

      iex> get_ledger!(session, "123")
      %Ledger{}

      iex> get_ledger!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_ledger!(Session.t(), Ecto.UUID.t()) :: Ledger.t()
  def_with_rls_and_logging get_ledger!(session, id), log_fields: [:id] do
    Repo.get!(Ledger, id, session: session)
  end

  @doc """
  Creates a ledger.

  ## Examples

      iex> create_ledger(session, %{field: value})
      {:ok, %Ledger{}}

      iex> create_ledger(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_ledger(Session.t(), LedgerRequest.t()) ::
          {:ok, Ledger.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_ledger(session, %LedgerRequest{} = request),
    log_fields: [] do
    %Ledger{}
    |> Ledger.changeset(request)
    |> Repo.insert(session: session)
  end

  @doc """
  Updates a ledger.

  ## Examples

      iex> update_ledger(session, ledger, %{field: new_value})
      {:ok, %Ledger{}}

      iex> update_ledger(session, ledger, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_ledger(Session.t(), Ledger.t(), LedgerRequest.t()) ::
          {:ok, Ledger.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_ledger(
                             session,
                             %Ledger{} = ledger,
                             %LedgerRequest{} = request
                           ),
                           log_fields: [:ledger] do
    ledger
    |> Ledger.changeset(request)
    |> Repo.update(session: session)
  end

  @doc """
  Deletes a ledger.

  ## Examples

      iex> delete_ledger(session, ledger)
      {:ok, %Ledger{}}

      iex> delete_ledger(session, ledger)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_ledger(Session.t(), Ledger.t()) ::
          {:ok, Ledger.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_ledger(session, %Ledger{} = ledger),
    log_fields: [:ledger] do
    Repo.delete(ledger, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking ledger changes.

  ## Examples

      iex> change_ledger(ledger)
      %Ecto.Changeset{data: %Ledger{}}

  """
  def change_ledger(%Ledger{} = ledger, attrs \\ %{}) do
    Ledger.changeset(ledger, attrs)
  end
end

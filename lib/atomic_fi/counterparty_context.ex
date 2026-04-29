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

  alias AtomicFi.ComplianceScreeningContext.ScreeningWorker
  alias AtomicFi.OpenApiSchema.CounterpartyRequest
  alias AtomicFi.Repo
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.SessionContext.Session

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
    Repo.get!(Counterparty, id, session: session)
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
    with {:ok, counterparty} <-
           %Counterparty{}
           |> Counterparty.changeset(request)
           |> Repo.insert(session: session) do
      if request.chain_screening do
        %{
          subject: "counterparty",
          account_holder_id: counterparty.account_holder_id,
          counterparty_id: counterparty.id,
          tenant_id: counterparty.tenant_id
        }
        |> ScreeningWorker.new()
        |> Oban.insert!()
      end

      {:ok, counterparty}
    end
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
    counterparty
    |> Counterparty.changeset(request)
    |> Repo.update(session: session)
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

defmodule AtomicFi.PaymentAccountContext do
  @moduledoc """
  PaymentAccount context — manages payment accounts linked to AccountHolders.

  One row per payment instrument, with the AccountHolder as the MDM subject.
  Maps to ISO 20022 `pain:001 <DbtrAcct>/<CdtrAcct>` — the specific account
  involved in a payment instruction.

  ## FATF Recommendation 16

  Payment accounts gate wire-transfer compliance. Every payment instruction must
  reference a known, verified payment account linked to a verified AccountHolder.

  ## PCI-DSS 4.0

  `account_number`, `iban`, and `card_pan` are PCI-DSS sensitive fields. The
  calling orchestration layer must tokenise raw values before invoking this context.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.OpenApiSchema.PaymentAccountRequest
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.Repo
  alias AtomicFi.SessionContext.Session

  @doc """
  Returns the list of payment accounts with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_payment_accounts(session, %{page: 1, page_size: 20})
      {:ok, {[%PaymentAccount{}, ...], %Flop.Meta{}}}

  """
  @spec list_payment_accounts(Session.t(), map()) ::
          {:ok, {list(PaymentAccount.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_payment_accounts(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    PaymentAccount
    |> Flop.validate_and_run(flop_params,
      for: PaymentAccount,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single payment account.

  Raises `Ecto.NoResultsError` if the PaymentAccount does not exist.

  ## Examples

      iex> get_payment_account!(session, "123")
      %PaymentAccount{}

      iex> get_payment_account!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_payment_account!(Session.t(), Ecto.UUID.t()) :: PaymentAccount.t()
  def_with_rls_and_logging get_payment_account!(session, id), log_fields: [:id] do
    Repo.get!(PaymentAccount, id, session: session)
  end

  @doc """
  Creates a payment account.

  ## Examples

      iex> create_payment_account(session, %{field: value})
      {:ok, %PaymentAccount{}}

      iex> create_payment_account(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_payment_account(Session.t(), PaymentAccountRequest.t()) ::
          {:ok, PaymentAccount.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_payment_account(
                             session,
                             %PaymentAccountRequest{} = request
                           ),
                           log_fields: [] do
    after_pa_changed(session, PaymentAccount.changeset(%PaymentAccount{}, request))
  end

  @doc """
  Updates a payment account.

  ## Examples

      iex> update_payment_account(session, payment_account, %{field: new_value})
      {:ok, %PaymentAccount{}}

      iex> update_payment_account(session, payment_account, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_payment_account(Session.t(), PaymentAccount.t(), PaymentAccountRequest.t()) ::
          {:ok, PaymentAccount.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_payment_account(
                             session,
                             %PaymentAccount{} = payment_account,
                             %PaymentAccountRequest{} = request
                           ),
                           log_fields: [:payment_account] do
    after_pa_changed(session, PaymentAccount.changeset(payment_account, request))
  end

  # Lifecycle hook shared by create + update. Wraps the PA insert-or-update
  # and the direct-line LedgerAccount fan-out (`AH-PA root` + per-regime
  # regime-roots, or `CP-PA` variants if `pa.counterparty_id` is set) in one
  # transaction so a trigger-side failure (e.g. missing CP root) rolls the
  # PA write back.
  defp after_pa_changed(session, %Ecto.Changeset{} = changeset) do
    Repo.transaction(
      fn ->
        with {:ok, pa} <- Repo.insert_or_update(changeset, session: session),
             :ok <- LedgerAccountContext.ensure_linked_ledger_accounts(session, pa) do
          pa
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      session: session
    )
  end

  @doc """
  Deletes a payment account.

  ## Examples

      iex> delete_payment_account(session, payment_account)
      {:ok, %PaymentAccount{}}

      iex> delete_payment_account(session, payment_account)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_payment_account(Session.t(), PaymentAccount.t()) ::
          {:ok, PaymentAccount.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_payment_account(session, %PaymentAccount{} = payment_account),
    log_fields: [:payment_account] do
    Repo.delete(payment_account, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking payment account changes.

  ## Examples

      iex> change_payment_account(payment_account)
      %Ecto.Changeset{data: %PaymentAccount{}}

  """
  def change_payment_account(%PaymentAccount{} = payment_account, attrs \\ %{}) do
    PaymentAccount.changeset(payment_account, attrs)
  end
end

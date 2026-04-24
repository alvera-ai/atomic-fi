defmodule PaymentCompliancePlatform.RiskClassificationContext do
  @moduledoc """
  RiskClassification context — formal risk-level records for AccountHolders.

  Drives the LedgerAccount limit cascade: the MASTER LedgerAccount velocity
  limit is a function of the currently active RiskClassification.risk_level.

  ## Active-classification invariant

  Exactly one `is_active = true` record exists per (account_holder_id, tenant_id).

  - DB: enforced by a partial unique index (`WHERE is_active = true`).
  - Application: `create_risk_classification/2` wraps the insert in a transaction
    that deactivates any prior active record for the same holder when the new
    record is `is_active: true`.

  ## Regulatory Alignment

  - ISO 20022 auth:018 — CustomerRiskAssessment
  - FATF Recommendation 10 — risk-based CDD
  """

  import Ecto.Query, warn: false
  use PaymentCompliancePlatform.LoggerMacro

  alias PaymentCompliancePlatform.OpenApiSchema.RiskClassificationRequest
  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.RiskClassificationContext.RiskClassification
  alias PaymentCompliancePlatform.SessionContext.Session

  @doc """
  Returns the list of risk classifications with pagination and filtering.
  """
  @spec list_risk_classifications(Session.t(), map()) ::
          {:ok, {list(RiskClassification.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_risk_classifications(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    RiskClassification
    |> Flop.validate_and_run(flop_params,
      for: RiskClassification,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single risk classification.

  Raises `Ecto.NoResultsError` if the RiskClassification does not exist.
  """
  @spec get_risk_classification!(Session.t(), Ecto.UUID.t()) :: RiskClassification.t()
  def_with_rls_and_logging get_risk_classification!(session, id), log_fields: [:id] do
    Repo.get!(RiskClassification, id, session: session)
  end

  @doc """
  Returns the currently active RiskClassification for an account holder, or
  nil if none is active.
  """
  @spec get_active_classification_for_account_holder(Session.t(), Ecto.UUID.t()) ::
          RiskClassification.t() | nil
  def_with_rls_and_logging get_active_classification_for_account_holder(
                             session,
                             account_holder_id
                           ),
                           log_fields: [:account_holder_id] do
    RiskClassification
    |> where([r], r.account_holder_id == ^account_holder_id and r.is_active == true)
    |> Repo.one(session: session)
  end

  @doc """
  Creates a risk classification.

  When `is_active: true` (the default), deactivates any previously active
  classification for the same `(account_holder_id, tenant_id)` in the same
  transaction before inserting the new row — preserving the single-active
  invariant enforced by the partial unique index.
  """
  @spec create_risk_classification(Session.t(), RiskClassificationRequest.t()) ::
          {:ok, RiskClassification.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_risk_classification(
                             session,
                             %RiskClassificationRequest{} = request
                           ),
                           log_fields: [] do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:deactivate_previous, fn repo, _changes ->
      case request.is_active do
        false ->
          {:ok, 0}

        _ ->
          {count, _} =
            repo.update_all(
              from(r in RiskClassification,
                where: r.account_holder_id == ^request.account_holder_id and r.is_active == true
              ),
              [set: [is_active: false, updated_at: DateTime.utc_now()]],
              session: session
            )

          {:ok, count}
      end
    end)
    |> Ecto.Multi.insert(
      :classification,
      RiskClassification.changeset(%RiskClassification{}, request)
    )
    |> Repo.transaction(session: session)
    |> case do
      {:ok, %{classification: classification}} -> {:ok, classification}
      {:error, :classification, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Updates a risk classification.

  When activating a previously inactive record (`is_active: false → true`),
  deactivates any other active classification for the same holder in the
  same transaction.
  """
  @spec update_risk_classification(
          Session.t(),
          RiskClassification.t(),
          RiskClassificationRequest.t()
        ) :: {:ok, RiskClassification.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_risk_classification(
                             session,
                             %RiskClassification{} = classification,
                             %RiskClassificationRequest{} = request
                           ),
                           log_fields: [:classification] do
    activating? = request.is_active == true and classification.is_active == false

    Ecto.Multi.new()
    |> Ecto.Multi.run(:deactivate_previous, fn repo, _changes ->
      if activating? do
        {count, _} =
          repo.update_all(
            from(r in RiskClassification,
              where:
                r.account_holder_id == ^classification.account_holder_id and
                  r.is_active == true and r.id != ^classification.id
            ),
            [set: [is_active: false, updated_at: DateTime.utc_now()]],
            session: session
          )

        {:ok, count}
      else
        {:ok, 0}
      end
    end)
    |> Ecto.Multi.update(:classification, RiskClassification.changeset(classification, request))
    |> Repo.transaction(session: session)
    |> case do
      {:ok, %{classification: updated}} -> {:ok, updated}
      {:error, :classification, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Deletes a risk classification.
  """
  @spec delete_risk_classification(Session.t(), RiskClassification.t()) ::
          {:ok, RiskClassification.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_risk_classification(
                             session,
                             %RiskClassification{} = classification
                           ),
                           log_fields: [:classification] do
    Repo.delete(classification, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking risk classification changes.
  """
  def change_risk_classification(%RiskClassification{} = classification, attrs \\ %{}) do
    RiskClassification.changeset(classification, attrs)
  end
end

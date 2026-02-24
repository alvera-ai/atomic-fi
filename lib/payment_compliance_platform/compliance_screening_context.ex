defmodule PaymentCompliancePlatform.ComplianceScreeningContext do
  @moduledoc """
  ISO 20022 compliance screening context (auth:018 / camt:998).

  Canonical entry point for all screening operations. Delegates screening logic
  to `ScreeningEngine` and persists results to the normalized
  `compliance_screenings`, `sanctions_matches`, and `blocklist_matches` tables.

  ## Screening Flow

  1. `ScreeningEngine.get_watchman_list_info/0` — fetch list metadata
  2. Query `sanctions_matches` for suppressed source IDs (auto-dedup)
  3. For each entity: `ScreeningEngine.screen_individual/3` or `screen_company/3`
  4. Build one `ComplianceScreening` per entity + child match rows
  5. Insert via `cast_assoc` in a single Repo transaction

  ## False Positive Deduplication

  Before Watchman scoring, the context queries:

      SELECT source_id FROM sanctions_matches
      WHERE tenant_id = $tenant_id
        AND source_id = ANY($source_ids)
        AND false_positive_qualifier IN ('manual_override', 'auto_suppressed')

  The resulting `MapSet` is passed to `ScreeningEngine` as `suppressed_source_ids`.
  Matches found in the set are written with `false_positive_qualifier: :auto_suppressed`
  and excluded from `screening_score` calculation.
  """

  import Ecto.Query, warn: false
  use PaymentCompliancePlatform.LoggerMacro

  alias PaymentCompliancePlatform.ComplianceScreeningContext.BlocklistMatch
  alias PaymentCompliancePlatform.ComplianceScreeningContext.ComplianceScreening
  alias PaymentCompliancePlatform.ComplianceScreeningContext.SanctionsMatch
  alias PaymentCompliancePlatform.DecisionContext.ScreeningEngine
  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.SessionContext.Session

  # ---------------------------------------------------------------------------
  # CRUD — ComplianceScreening
  # ---------------------------------------------------------------------------

  @doc """
  Returns the list of compliance screenings with pagination and filtering.

  ## Examples

      iex> list_compliance_screenings(session, %{page: 1, page_size: 20})
      {:ok, {[%ComplianceScreening{}, ...], %Flop.Meta{}}}

  """
  @spec list_compliance_screenings(Session.t(), map()) ::
          {:ok, {list(ComplianceScreening.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_compliance_screenings(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    ComplianceScreening
    |> Flop.validate_and_run(flop_params,
      for: ComplianceScreening,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single compliance screening.

  Raises `Ecto.NoResultsError` if the ComplianceScreening does not exist.

  ## Examples

      iex> get_compliance_screening!(session, "123")
      %ComplianceScreening{}

      iex> get_compliance_screening!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_compliance_screening!(Session.t(), Ecto.UUID.t()) :: ComplianceScreening.t()
  def_with_rls_and_logging get_compliance_screening!(session, id), log_fields: [:id] do
    Repo.get!(ComplianceScreening, id, session: session)
  end

  @doc """
  Creates a compliance screening.

  ## Examples

      iex> create_compliance_screening(session, %{field: value})
      {:ok, %ComplianceScreening{}}

      iex> create_compliance_screening(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_compliance_screening(Session.t(), map()) ::
          {:ok, ComplianceScreening.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_compliance_screening(session, attrs), log_fields: [] do
    %ComplianceScreening{}
    |> ComplianceScreening.changeset(attrs)
    |> Repo.insert(session: session)
  end

  @doc """
  Updates a compliance screening.

  ## Examples

      iex> update_compliance_screening(session, compliance_screening, %{field: new_value})
      {:ok, %ComplianceScreening{}}

      iex> update_compliance_screening(session, compliance_screening, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_compliance_screening(Session.t(), ComplianceScreening.t(), map()) ::
          {:ok, ComplianceScreening.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_compliance_screening(
                             session,
                             %ComplianceScreening{} = compliance_screening,
                             attrs
                           ),
                           log_fields: [:compliance_screening] do
    compliance_screening
    |> ComplianceScreening.changeset(attrs)
    |> Repo.update(session: session)
  end

  @doc """
  Deletes a compliance screening.

  ## Examples

      iex> delete_compliance_screening(session, compliance_screening)
      {:ok, %ComplianceScreening{}}

      iex> delete_compliance_screening(session, compliance_screening)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_compliance_screening(Session.t(), ComplianceScreening.t()) ::
          {:ok, ComplianceScreening.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_compliance_screening(
                             session,
                             %ComplianceScreening{} = compliance_screening
                           ),
                           log_fields: [:compliance_screening] do
    Repo.delete(compliance_screening, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking compliance_screening changes.

  ## Examples

      iex> change_compliance_screening(compliance_screening)
      %Ecto.Changeset{data: %ComplianceScreening{}}

  """
  def change_compliance_screening(%ComplianceScreening{} = compliance_screening, attrs \\ %{}) do
    ComplianceScreening.changeset(compliance_screening, attrs)
  end

  # ---------------------------------------------------------------------------
  # CRUD — SanctionsMatch
  # ---------------------------------------------------------------------------

  @doc """
  Returns the list of sanctions matches for a compliance screening.
  """
  @spec list_sanctions_matches(Session.t(), Ecto.UUID.t(), map()) ::
          {:ok, {list(SanctionsMatch.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_sanctions_matches(
                             session,
                             compliance_screening_id,
                             flop_params \\ %{}
                           ),
                           log_fields: [:compliance_screening_id] do
    SanctionsMatch
    |> where([sm], sm.compliance_screening_id == ^compliance_screening_id)
    |> Flop.validate_and_run(flop_params,
      for: SanctionsMatch,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Updates a sanctions match (e.g. to set false_positive_qualifier or review notes).

  ## Examples

      iex> update_sanctions_match(session, sanctions_match, %{false_positive_qualifier: :manual_override, review_notes: "Known entity"})
      {:ok, %SanctionsMatch{}}

  """
  @spec update_sanctions_match(Session.t(), SanctionsMatch.t(), map()) ::
          {:ok, SanctionsMatch.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_sanctions_match(
                             session,
                             %SanctionsMatch{} = sanctions_match,
                             attrs
                           ),
                           log_fields: [:sanctions_match] do
    sanctions_match
    |> SanctionsMatch.changeset(attrs)
    |> Repo.update(session: session)
  end

  # ---------------------------------------------------------------------------
  # CRUD — BlocklistMatch
  # ---------------------------------------------------------------------------

  @doc """
  Returns the list of blocklist matches for a compliance screening.
  """
  @spec list_blocklist_matches(Session.t(), Ecto.UUID.t(), map()) ::
          {:ok, {list(BlocklistMatch.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_blocklist_matches(
                             session,
                             compliance_screening_id,
                             flop_params \\ %{}
                           ),
                           log_fields: [:compliance_screening_id] do
    BlocklistMatch
    |> where([bm], bm.compliance_screening_id == ^compliance_screening_id)
    |> Flop.validate_and_run(flop_params,
      for: BlocklistMatch,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Updates a blocklist match (e.g. to set false_positive_qualifier or review notes).

  ## Examples

      iex> update_blocklist_match(session, blocklist_match, %{false_positive_qualifier: :manual_override, review_notes: "Confirmed not a match"})
      {:ok, %BlocklistMatch{}}

  """
  @spec update_blocklist_match(Session.t(), BlocklistMatch.t(), map()) ::
          {:ok, BlocklistMatch.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_blocklist_match(
                             session,
                             %BlocklistMatch{} = blocklist_match,
                             attrs
                           ),
                           log_fields: [:blocklist_match] do
    blocklist_match
    |> BlocklistMatch.changeset(attrs)
    |> Repo.update(session: session)
  end

  # ---------------------------------------------------------------------------
  # Screening — ISO 20022 entry point
  # ---------------------------------------------------------------------------

  @doc """
  Screen an account holder for compliance (ISO 20022 auth:018 / camt:998).

  Screens all associated individuals and companies against the internal blocklist
  (fail-fast) and Watchman sanctions lists. Persists one `ComplianceScreening`
  row per entity plus child `SanctionsMatch` / `BlocklistMatch` rows.

  `request` must include:
  - `account_holder_id` — references an existing AccountHolder in the same tenant
  - `interested_individuals` — list of `%{first_name:, last_name:, birth_date:, gender:}`
  - `interested_companies` — list of `%{name:, created:, dissolved:}`

  Returns `{:ok, [%ComplianceScreening{}]}` — one per screened entity.
  """
  @spec screen_account_holder(Session.t(), map()) ::
          {:ok, [ComplianceScreening.t()]} | {:error, term()}
  def_with_rls_and_logging screen_account_holder(session, request), log_fields: [] do
    tenant_id = session.tenant_id
    account_holder_id = request[:account_holder_id] || request["account_holder_id"]

    with {:ok, list_info} <- ScreeningEngine.get_watchman_list_info(),
         suppressed_ids <- fetch_suppressed_source_ids(tenant_id),
         {:ok, screenings} <-
           screen_all_entities_for_account_holder(
             session,
             account_holder_id,
             tenant_id,
             list_info,
             suppressed_ids,
             request
           ) do
      {:ok, screenings}
    end
  end

  @doc """
  Screen a beneficial owner for compliance (FinCEN CDD Rule 31 CFR §1010.230).

  Screens all listed individuals and companies under the `account_holder` scope —
  beneficial owners are part of account holder CDD per FinCEN CDD Rule.

  `request` must include:
  - `account_holder_id` — references the owning AccountHolder in the same tenant
  - `interested_individuals` / `interested_companies` — entities to screen

  Returns `{:ok, [%ComplianceScreening{}]}` — one per screened entity.
  """
  @spec screen_beneficial_owner(Session.t(), map()) ::
          {:ok, [ComplianceScreening.t()]} | {:error, term()}
  def_with_rls_and_logging screen_beneficial_owner(session, request), log_fields: [] do
    tenant_id = session.tenant_id
    account_holder_id = request[:account_holder_id] || request["account_holder_id"]

    with {:ok, list_info} <- ScreeningEngine.get_watchman_list_info(),
         suppressed_ids <- fetch_suppressed_source_ids(tenant_id),
         {:ok, screenings} <-
           screen_all_entities_for_account_holder(
             session,
             account_holder_id,
             tenant_id,
             list_info,
             suppressed_ids,
             request
           ) do
      {:ok, screenings}
    end
  end

  @doc """
  Screen a counterparty for compliance (ISO 20022 <Dbtr>/<Cdtr>).

  Screens all listed individuals and companies under the `counterparty` scope.
  Results are linked to both the account_holder and the counterparty.

  `request` must include:
  - `account_holder_id` — references the internal AccountHolder
  - `counterparty_id` — references the Counterparty being screened
  - `interested_individuals` / `interested_companies` — entities to screen

  Returns `{:ok, [%ComplianceScreening{}]}` — one per screened entity.
  """
  @spec screen_counterparty(Session.t(), map()) ::
          {:ok, [ComplianceScreening.t()]} | {:error, term()}
  def_with_rls_and_logging screen_counterparty(session, request), log_fields: [] do
    tenant_id = session.tenant_id
    account_holder_id = request[:account_holder_id] || request["account_holder_id"]
    counterparty_id = request[:counterparty_id] || request["counterparty_id"]

    with {:ok, list_info} <- ScreeningEngine.get_watchman_list_info(),
         suppressed_ids <- fetch_suppressed_source_ids(tenant_id),
         {:ok, screenings} <-
           screen_all_entities_for_counterparty(
             session,
             account_holder_id,
             counterparty_id,
             tenant_id,
             list_info,
             suppressed_ids,
             request
           ) do
      {:ok, screenings}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp fetch_suppressed_source_ids(tenant_id) do
    SanctionsMatch
    |> where(
      [sm],
      sm.tenant_id == ^tenant_id and
        sm.false_positive_qualifier in [:manual_override, :auto_suppressed]
    )
    |> select([sm], sm.source_id)
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp screen_all_entities_for_account_holder(
         session,
         account_holder_id,
         tenant_id,
         list_info,
         suppressed_ids,
         request
       ) do
    individuals = request[:interested_individuals] || request["interested_individuals"] || []
    companies = request[:interested_companies] || request["interested_companies"] || []

    individual_results =
      Enum.map(individuals, fn individual ->
        with {:ok, result} <-
               ScreeningEngine.screen_individual(tenant_id, individual, suppressed_ids) do
          persist_account_holder_screening(
            session,
            account_holder_id,
            tenant_id,
            list_info,
            result,
            :sanctions
          )
        end
      end)

    company_results =
      Enum.map(companies, fn company ->
        with {:ok, result} <- ScreeningEngine.screen_company(tenant_id, company, suppressed_ids) do
          persist_account_holder_screening(
            session,
            account_holder_id,
            tenant_id,
            list_info,
            result,
            :sanctions
          )
        end
      end)

    collect_results(individual_results ++ company_results)
  end

  defp screen_all_entities_for_counterparty(
         session,
         account_holder_id,
         counterparty_id,
         tenant_id,
         list_info,
         suppressed_ids,
         request
       ) do
    individuals = request[:interested_individuals] || request["interested_individuals"] || []
    companies = request[:interested_companies] || request["interested_companies"] || []

    individual_results =
      Enum.map(individuals, fn individual ->
        with {:ok, result} <-
               ScreeningEngine.screen_individual(tenant_id, individual, suppressed_ids) do
          persist_counterparty_screening(
            session,
            account_holder_id,
            counterparty_id,
            tenant_id,
            list_info,
            result,
            :sanctions
          )
        end
      end)

    company_results =
      Enum.map(companies, fn company ->
        with {:ok, result} <- ScreeningEngine.screen_company(tenant_id, company, suppressed_ids) do
          persist_counterparty_screening(
            session,
            account_holder_id,
            counterparty_id,
            tenant_id,
            list_info,
            result,
            :sanctions
          )
        end
      end)

    collect_results(individual_results ++ company_results)
  end

  defp persist_account_holder_screening(
         session,
         account_holder_id,
         tenant_id,
         list_info,
         screening_result,
         screening_type
       ) do
    attrs =
      build_screening_attrs(
        :account_holder,
        screening_result,
        screening_type,
        list_info,
        tenant_id
      )
      |> Map.put(:account_holder_id, account_holder_id)

    insert_screening(session, attrs)
  end

  defp persist_counterparty_screening(
         session,
         account_holder_id,
         counterparty_id,
         tenant_id,
         list_info,
         screening_result,
         screening_type
       ) do
    attrs =
      build_screening_attrs(:counterparty, screening_result, screening_type, list_info, tenant_id)
      |> Map.merge(%{account_holder_id: account_holder_id, counterparty_id: counterparty_id})

    insert_screening(session, attrs)
  end

  defp build_screening_attrs(scope, screening_result, screening_type, list_info, tenant_id) do
    overall_status = screening_result.screening_status

    sanctions_match_attrs =
      Enum.map(screening_result.sanctions_matches, fn sm ->
        qualifier = if sm.suppressed, do: :auto_suppressed, else: :none

        sm
        |> Map.merge(%{tenant_id: tenant_id, false_positive_qualifier: qualifier})
        |> Map.delete(:suppressed)
      end)

    blocklist_match_attrs =
      Enum.map(screening_result.blocklist_matches, fn bm ->
        Map.put(bm, :tenant_id, tenant_id)
      end)

    screening_score =
      case overall_status do
        :blocked ->
          Decimal.new("100.0")

        _ ->
          if screening_result.screening_score do
            Decimal.from_float(screening_result.screening_score * 100)
          end
      end

    %{
      scope: scope,
      screening_type: screening_type,
      screening_status: map_status(overall_status),
      screening_score: screening_score,
      screened_entity_type: screening_result.entity_type,
      screened_entity_name: screening_result.entity_name,
      match_count: screening_result.match_count,
      screened_at: screening_result.screened_at,
      list_synced_at: list_info.started_at,
      list_sources: %{lists: list_info.lists, version: list_info.version},
      tenant_id: tenant_id,
      sanctions_matches: sanctions_match_attrs,
      blocklist_matches: blocklist_match_attrs
    }
  end

  defp insert_screening(session, attrs) do
    sanctions_match_attrs = Map.get(attrs, :sanctions_matches, [])
    blocklist_match_attrs = Map.get(attrs, :blocklist_matches, [])

    %ComplianceScreening{}
    |> ComplianceScreening.changeset(attrs)
    |> Ecto.Changeset.put_assoc(
      :sanctions_matches,
      build_match_changesets(sanctions_match_attrs, SanctionsMatch)
    )
    |> Ecto.Changeset.put_assoc(
      :blocklist_matches,
      build_match_changesets(blocklist_match_attrs, BlocklistMatch)
    )
    |> Repo.insert(session: session)
  end

  defp collect_results(results) do
    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(results, fn {:ok, screening} -> screening end)}
    else
      Enum.find(results, &match?({:error, _}, &1))
    end
  end

  defp build_match_changesets(attrs_list, schema_module) do
    Enum.map(attrs_list, fn attrs ->
      schema_module.changeset(struct(schema_module), attrs)
    end)
  end

  defp map_status(:pass), do: :pass
  defp map_status(:potential_match), do: :potential_match
  defp map_status(:blocked), do: :blocked
  defp map_status(other), do: other
end

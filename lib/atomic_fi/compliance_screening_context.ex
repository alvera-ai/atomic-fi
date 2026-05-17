defmodule AtomicFi.ComplianceScreeningContext do
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
  use AtomicFi.LoggerMacro

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.BeneficialOwnerContext.BeneficialOwner
  alias AtomicFi.ComplianceScreeningContext.BlocklistMatch
  alias AtomicFi.ComplianceScreeningContext.ComplianceScreening
  alias AtomicFi.ComplianceScreeningContext.SanctionsMatch
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.LegalEntityContext.LegalEntity
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  alias AtomicFi.OpenApiSchema.BeneficialOwnerRequest
  alias AtomicFi.OpenApiSchema.CounterpartyRequest
  alias AtomicFi.OpenApiSchema.PaymentAccountRequest
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.ScreeningEngine
  alias AtomicFi.Repo
  alias AtomicFi.SessionContext.Session

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
  All screenings attached to a target. Polymorphic on the target struct:

    - `%LegalEntity{}`    — party screenings (PII subject) where
                            `legal_entity_id = target.id`.
    - `%PaymentAccount{}` — instrument screenings (wallet / IBAN) where
                            `payment_account_id = target.id`.

  Used by the rule-engine payload composer to assemble the flat per-PA-side
  `compliance_screenings[]` view, calling this multiple times (the PA itself,
  the AH's identity LE, each BO LE, the CP LE) and concatenating.
  """
  @spec get_screenings_for_target(Session.t(), LegalEntity.t() | PaymentAccount.t()) ::
          [ComplianceScreening.t()]
  def_with_rls_and_logging get_screenings_for_target(session, %LegalEntity{id: le_id}),
    log_fields: [] do
    from(cs in ComplianceScreening, where: cs.legal_entity_id == ^le_id)
    |> Repo.all(session: session)
  end

  def_with_rls_and_logging get_screenings_for_target(session, %PaymentAccount{id: pa_id}),
    log_fields: [] do
    from(cs in ComplianceScreening, where: cs.payment_account_id == ^pa_id)
    |> Repo.all(session: session)
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
  # Stateless preview screening — pure: no DB writes, no rule engine, no caps.
  #
  # Builds the entity (and its LegalEntity for parties) in-memory from the
  # *Request struct, runs ScreeningEngine, returns the unsaved
  # `%ComplianceScreening{}` struct as-is. Useful for rule authoring and
  # pre-flight previews. Onboarding does NOT go through these — it talks
  # to ScreeningEngine directly and persists via `record_screening/3`.
  # ---------------------------------------------------------------------------

  @doc """
  Preview-screen an account holder request (stateless). Returns the unsaved
  `%ComplianceScreening{}` struct with nested matches.
  """
  @spec screen_account_holder(Session.t(), AccountHolderRequest.t()) ::
          {:ok, ComplianceScreening.t()} | {:error, term()}
  def_with_rls_and_logging screen_account_holder(session, %AccountHolderRequest{} = request),
    log_fields: [] do
    ScreeningEngine.screen_account_holder(
      session,
      account_holder_from_request(request, session.tenant_id)
    )
  end

  @doc """
  Preview-screen a beneficial owner request (stateless).
  """
  @spec screen_beneficial_owner(Session.t(), BeneficialOwnerRequest.t()) ::
          {:ok, ComplianceScreening.t()} | {:error, term()}
  def_with_rls_and_logging screen_beneficial_owner(session, %BeneficialOwnerRequest{} = request),
    log_fields: [] do
    ScreeningEngine.screen_beneficial_owner(
      session,
      beneficial_owner_from_request(request, session.tenant_id)
    )
  end

  @doc """
  Preview-screen a counterparty request (stateless).
  """
  @spec screen_counterparty(Session.t(), CounterpartyRequest.t()) ::
          {:ok, ComplianceScreening.t()} | {:error, term()}
  def_with_rls_and_logging screen_counterparty(session, %CounterpartyRequest{} = request),
    log_fields: [] do
    ScreeningEngine.screen_counterparty(
      session,
      counterparty_from_request(request, session.tenant_id)
    )
  end

  @doc """
  Preview-screen a payment account request (stateless). Only meaningful for
  `account_type: :crypto_wallet`; other rails return a `:pending` no-screen.
  """
  @spec screen_payment_account(Session.t(), PaymentAccountRequest.t()) ::
          {:ok, ComplianceScreening.t()} | {:error, term()}
  def_with_rls_and_logging screen_payment_account(session, %PaymentAccountRequest{} = request),
    log_fields: [] do
    ScreeningEngine.screen_payment_account(
      session,
      payment_account_from_request(request, session.tenant_id)
    )
  end

  # ---------------------------------------------------------------------------
  # Persistence — called by OnboardingContext after ScreeningEngine returns.
  # ---------------------------------------------------------------------------

  @doc """
  Persists an unsaved `%ComplianceScreening{}` returned by `ScreeningEngine`.
  `fks` carries the primary anchor (`legal_entity_id` for party screenings,
  `payment_account_id` for instrument screenings). Exactly one anchor must be
  set per DB CHECK. Tenant id is taken from `session`. Child matches inherit
  the tenant id automatically.
  """
  @spec record_screening(Session.t(), ComplianceScreening.t(), map()) ::
          {:ok, ComplianceScreening.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging record_screening(session, %ComplianceScreening{} = screening, fks),
    log_fields: [] do
    tenant_id = session.tenant_id
    attrs = screening |> screening_struct_to_attrs(tenant_id) |> Map.merge(fks)

    sanctions_match_attrs = attrs.sanctions_matches
    blocklist_match_attrs = attrs.blocklist_matches

    parent_attrs = Map.drop(attrs, [:sanctions_matches, :blocklist_matches])

    %ComplianceScreening{}
    |> ComplianceScreening.changeset(parent_attrs)
    |> Ecto.Changeset.put_assoc(
      :sanctions_matches,
      Enum.map(sanctions_match_attrs, &SanctionsMatch.changeset(%SanctionsMatch{}, &1))
    )
    |> Ecto.Changeset.put_assoc(
      :blocklist_matches,
      Enum.map(blocklist_match_attrs, &BlocklistMatch.changeset(%BlocklistMatch{}, &1))
    )
    |> Repo.insert(session: session)
  end

  # ── private: *Request → in-memory entity ──────────────────────────────────

  defp account_holder_from_request(%AccountHolderRequest{} = req, tenant_id) do
    %AccountHolder{
      tenant_id: tenant_id,
      legal_entity: legal_entity_from_request(req.legal_entity, tenant_id)
    }
  end

  defp beneficial_owner_from_request(%BeneficialOwnerRequest{} = req, tenant_id) do
    %BeneficialOwner{
      tenant_id: tenant_id,
      account_holder_id: req.account_holder_id,
      legal_entity: legal_entity_from_request(req.legal_entity, tenant_id)
    }
  end

  defp counterparty_from_request(%CounterpartyRequest{} = req, tenant_id) do
    %Counterparty{
      tenant_id: tenant_id,
      account_holder_id: req.account_holder_id,
      legal_entity: legal_entity_from_request(req.legal_entity, tenant_id)
    }
  end

  defp payment_account_from_request(%PaymentAccountRequest{} = req, tenant_id) do
    %PaymentAccount{
      tenant_id: tenant_id,
      account_type: req.account_type,
      currency: req.currency,
      wallet_address: Map.get(req, :wallet_address),
      wallet_chain: Map.get(req, :wallet_chain),
      account_number: Map.get(req, :account_number),
      routing_number: Map.get(req, :routing_number),
      iban: Map.get(req, :iban),
      swift_bic: Map.get(req, :swift_bic),
      card_pan: Map.get(req, :card_pan),
      account_holder_id: Map.get(req, :account_holder_id),
      counterparty_id: Map.get(req, :counterparty_id)
    }
  end

  defp legal_entity_from_request(%{} = le, tenant_id) do
    %LegalEntity{
      tenant_id: tenant_id,
      legal_entity_type: le |> map_get(:legal_entity_type) |> to_legal_entity_type(),
      first_name: map_get(le, :first_name),
      last_name: map_get(le, :last_name),
      date_of_birth: map_get(le, :date_of_birth),
      business_name: map_get(le, :business_name),
      date_formed: map_get(le, :date_formed)
    }
  end

  # Request may arrive with atom or string key (struct vs raw map); cast values
  # back to the Ecto.Enum atoms the schema expects.
  defp map_get(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))

  defp to_legal_entity_type("individual"), do: :individual
  defp to_legal_entity_type("business"), do: :business
  defp to_legal_entity_type(other), do: other

  # ── private: %ComplianceScreening{} struct → cast_assoc-ready attrs map ──

  defp screening_struct_to_attrs(%ComplianceScreening{} = cs, tenant_id) do
    %{
      scope: cs.scope,
      screening_type: cs.screening_type,
      screening_status: cs.screening_status,
      screening_score: cs.screening_score,
      screened_entity_type: cs.screened_entity_type,
      screened_entity_name: cs.screened_entity_name,
      match_count: cs.match_count,
      screened_at: cs.screened_at,
      tenant_id: tenant_id,
      sanctions_matches:
        Enum.map(cs.sanctions_matches || [], &sanctions_match_struct_to_attrs(&1, tenant_id)),
      blocklist_matches:
        Enum.map(cs.blocklist_matches || [], &blocklist_match_struct_to_attrs(&1, tenant_id))
    }
  end

  defp sanctions_match_struct_to_attrs(%SanctionsMatch{} = sm, tenant_id) do
    %{
      matched_name: sm.matched_name,
      matched_entity_type: sm.matched_entity_type,
      match_score: sm.match_score,
      source_list: sm.source_list,
      source_id: sm.source_id,
      source_data: sm.source_data,
      addresses: Enum.map(sm.addresses || [], &Map.from_struct/1),
      business_data: sm.business_data && Map.from_struct(sm.business_data),
      person_data: sm.person_data && Map.from_struct(sm.person_data),
      contact_data: sm.contact_data && Map.from_struct(sm.contact_data),
      false_positive_qualifier: sm.false_positive_qualifier,
      list_synced_at: sm.list_synced_at,
      list_sources: sm.list_sources,
      tenant_id: tenant_id
    }
  end

  defp blocklist_match_struct_to_attrs(%BlocklistMatch{} = bm, tenant_id) do
    %{
      matched_term: bm.matched_term,
      match_type: bm.match_type,
      scope: bm.scope,
      reason: bm.reason,
      blocklist_updated_at: bm.blocklist_updated_at,
      tenant_id: tenant_id
    }
  end
end

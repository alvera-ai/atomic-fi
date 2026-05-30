defmodule AtomicFi.ScreeningEngine.Default do
  @moduledoc """
  Default screening engine implementation — orchestrates blocklist +
  Watchman sanctions screening for atomic-fi's domain entities.

  Wired in via `AtomicFi.ScreeningEngine` (the public
  dispatcher). Pure of persistence — every callback returns an unsaved
  `%ComplianceScreening{}` struct (id, tenant_id, FKs all nil). Persistence
  is the caller's job: preview controllers return the struct as-is, the
  onboarding flow sets the entity FKs + tenant_id and calls
  `ComplianceScreeningContext.record_screening/3` to insert.

  All public methods take a fully-preloaded domain struct (AccountHolder,
  BeneficialOwner, Counterparty, PaymentAccount) and return
  a normalized `%ComplianceScreening{}` carrying nested `%SanctionsMatch{}`
  + `%BlocklistMatch{}` rows. Watchman-shaped internals stop at this
  module's gate.

  ## False Positive Deduplication

  Reads the tenant's suppressed Watchman `source_id`s from prior
  `SanctionsMatch` rows tagged `:manual_override` or `:auto_suppressed`.
  Matches against those IDs are included with
  `false_positive_qualifier: :auto_suppressed` and excluded from
  `screening_score` calculation.
  """

  @behaviour AtomicFi.ScreeningEngine.Behaviour

  import Ecto.Query, warn: false

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.BeneficialOwnerContext.BeneficialOwner
  alias AtomicFi.ComplianceScreeningContext.BlocklistMatch
  alias AtomicFi.ComplianceScreeningContext.ComplianceScreening
  alias AtomicFi.ComplianceScreeningContext.SanctionsMatch
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.BlocklistContext.{BlocklistCache, BlocklistValidator}
  alias AtomicFi.LegalEntityContext.LegalEntity
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.Repo
  alias AtomicFi.Watchman.Client

  @type list_info :: %{started_at: DateTime.t(), lists: term(), version: term()}

  # ── behaviour callbacks ───────────────────────────────────────────────────

  @impl true
  def get_watchman_list_info do
    case Client.v2_listinfo_get() do
      {:ok, response} ->
        {:ok,
         %{
           started_at: parse_datetime(response.startedAt),
           lists: response.lists,
           version: response.version
         }}

      # coveralls-ignore-start
      {:error, _} = error ->
        error

      :error ->
        {:error, :watchman_listinfo_unavailable}
        # coveralls-ignore-stop
    end
  end

  @impl true
  def screen_account_holder(session, %AccountHolder{} = ah, _opts \\ []) do
    screen_party(session, ah.legal_entity, :account_holder)
  end

  @impl true
  def screen_beneficial_owner(session, %BeneficialOwner{} = bo, _opts \\ []) do
    screen_party(session, bo.legal_entity, :beneficial_owner)
  end

  @impl true
  def screen_counterparty(session, %Counterparty{} = cp, _opts \\ []) do
    screen_party(session, cp.legal_entity, :counterparty)
  end

  @impl true
  def screen_payment_account(session, %PaymentAccount{} = pa, _opts \\ []) do
    screen_pa(session, pa)
  end

  # ── private: party (AH / BO / CP) screening via LegalEntity ───────────────

  defp screen_party(%{tenant_id: tenant_id}, %LegalEntity{} = legal_entity, scope) do
    with {:ok, list_info} <- AtomicFi.ScreeningEngine.get_watchman_list_info() do
      suppressed_ids = fetch_suppressed_source_ids(tenant_id)

      case legal_entity_to_watchman_entity(legal_entity) do
        {:individual, attrs} ->
          screen_individual(scope, tenant_id, attrs, suppressed_ids, list_info)

        {:company, attrs} ->
          screen_company(scope, tenant_id, attrs, suppressed_ids, list_info)
      end
    end
  end

  defp legal_entity_to_watchman_entity(%LegalEntity{legal_entity_type: :individual} = le) do
    {:individual,
     %{
       first_name: le.first_name,
       last_name: le.last_name,
       birth_date: le.date_of_birth && Date.to_string(le.date_of_birth),
       gender: nil
     }}
  end

  defp legal_entity_to_watchman_entity(%LegalEntity{legal_entity_type: :business} = le) do
    {:company,
     %{
       name: le.business_name,
       created: le.date_formed && Date.to_string(le.date_formed),
       dissolved: nil
     }}
  end

  defp fetch_suppressed_source_ids(tenant_id) do
    SanctionsMatch
    |> where(
      [sm],
      sm.tenant_id == ^tenant_id and
        sm.false_positive_qualifier in [:manual_override, :auto_suppressed]
    )
    |> select([sm], sm.source_id)
    |> Repo.all(skip_multi_tenancy_check: true)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  # ── private: individual / company / crypto Watchman screen ────────────────

  defp screen_individual(
         scope,
         tenant_id,
         %{first_name: first_name, last_name: last_name} = individual,
         suppressed_source_ids,
         list_info
       ) do
    entity_name = "#{first_name} #{last_name}"
    blocklist_matches = check_individual_blocklist(tenant_id, first_name, last_name)

    if blocklist_matches != [] do
      {:ok,
       build_blocklist_screening(scope, :individual, entity_name, blocklist_matches, list_info)}
    else
      search_params =
        [name: entity_name, minMatch: 0.7, type: "person"]
        |> maybe_add(:birthDate, individual[:birth_date])
        |> maybe_add(:gender, individual[:gender])

      perform_watchman_search(
        scope,
        :individual,
        entity_name,
        search_params,
        suppressed_source_ids,
        list_info
      )
    end
  end

  defp screen_company(
         scope,
         tenant_id,
         %{name: name} = company,
         suppressed_source_ids,
         list_info
       ) do
    blocklist_matches = check_company_blocklist(tenant_id, name)

    if blocklist_matches != [] do
      {:ok, build_blocklist_screening(scope, :company, name, blocklist_matches, list_info)}
    else
      search_params =
        [name: name, minMatch: 0.7, type: "business"]
        |> maybe_add(:created, company[:created])
        |> maybe_add(:dissolved, company[:dissolved])

      perform_watchman_search(
        scope,
        :company,
        name,
        search_params,
        suppressed_source_ids,
        list_info
      )
    end
  end

  # ── private: PaymentAccount → on-chain Watchman screen ────────────────────

  # The party (AH/CP) tied to the PA is screened during onboarding; the only
  # PA-level Watchman surface we have is the on-chain wallet address. Non-
  # crypto rails return a no-screen :pass — they're not screenable at the
  # instrument level.
  defp screen_pa(_session, %PaymentAccount{
         account_type: :crypto_wallet,
         wallet_address: wallet_address,
         wallet_chain: wallet_chain,
         tenant_id: tenant_id
       })
       when is_binary(wallet_address) and wallet_address != "" do
    with {:ok, list_info} <- AtomicFi.ScreeningEngine.get_watchman_list_info() do
      suppressed_ids = fetch_suppressed_source_ids(tenant_id)
      screen_crypto_address(wallet_address, wallet_chain, suppressed_ids, list_info)
    end
  end

  defp screen_pa(_session, %PaymentAccount{}), do: {:ok, no_screen_pa()}

  defp screen_crypto_address(wallet_address, wallet_chain, suppressed_source_ids, list_info) do
    params =
      [cryptoAddress: wallet_address, minMatch: 0.7]
      |> maybe_add(:name, wallet_chain)

    case Client.v2_search_get(params) do
      {:ok, %{entities: entities}} ->
        all_match_attrs =
          (entities || [])
          |> filter_crypto_entities(wallet_address, wallet_chain)
          |> build_sanctions_match_attrs(suppressed_source_ids)

        active = Enum.reject(all_match_attrs, & &1.suppressed)

        {:ok,
         build_sanctions_screening(
           :payment_account,
           :crypto_address,
           wallet_address,
           all_match_attrs,
           active,
           list_info
         )}

      # coveralls-ignore-start
      {:error, _} = error ->
        error

      :error ->
        {:error, :watchman_search_unavailable}
        # coveralls-ignore-stop
    end
  end

  # coveralls-ignore-start
  # Watchman returns sanctioned entities whose record references the queried
  # `cryptoAddress`. Confirm the address + (optional) chain actually appear in
  # the entity's `cryptoAddresses` list before counting it as a hit — same
  # address string can collide across chains (USDT on ETH vs TRON).
  defp filter_crypto_entities(entities, wallet_address, wallet_chain) do
    Enum.filter(entities, fn entity ->
      addrs = entity.cryptoAddresses || []

      Enum.any?(addrs, fn ca ->
        address_match?(ca, wallet_address) and chain_match?(ca, wallet_chain)
      end)
    end)
  end

  defp address_match?(%{address: address}, target) when is_binary(address) and is_binary(target),
    do: String.downcase(address) == String.downcase(target)

  defp address_match?(_ca, _target), do: false

  defp chain_match?(_ca, nil), do: true
  defp chain_match?(_ca, ""), do: true

  defp chain_match?(%{currency: currency}, chain) when is_binary(currency) and is_binary(chain),
    do: String.downcase(currency) == String.downcase(chain)

  defp chain_match?(_ca, _chain), do: false
  # coveralls-ignore-stop

  defp no_screen_pa do
    %ComplianceScreening{
      scope: :payment_account,
      screening_type: :sanctions,
      screening_status: :pending,
      screening_score: nil,
      screened_entity_type: :payment_account,
      screened_entity_name: "non-crypto-payment-account-bypass",
      match_count: 0,
      screened_at: DateTime.utc_now(),
      sanctions_matches: [],
      blocklist_matches: []
    }
  end

  # ── private: blocklist helpers ────────────────────────────────────────────

  defp check_individual_blocklist(tenant_id, first_name, last_name) do
    matches = []

    matches =
      case BlocklistValidator.validate_first_name(tenant_id, first_name) do
        {:error, :blocklisted, match_type, matched_term, reason} ->
          matches ++
            [
              build_blocklist_match_attrs(
                tenant_id,
                :first_name,
                match_type,
                matched_term,
                reason
              )
            ]

        {:ok, _} ->
          matches
      end

    case BlocklistValidator.validate_last_name(tenant_id, last_name) do
      {:error, :blocklisted, match_type, matched_term, reason} ->
        matches ++
          [build_blocklist_match_attrs(tenant_id, :last_name, match_type, matched_term, reason)]

      {:ok, _} ->
        matches
    end
  end

  defp check_company_blocklist(tenant_id, company_name) do
    case BlocklistValidator.validate_company_name(tenant_id, company_name) do
      {:error, :blocklisted, match_type, matched_term, reason} ->
        [build_blocklist_match_attrs(tenant_id, :company_name, match_type, matched_term, reason)]

      {:ok, _} ->
        []
    end
  end

  defp build_blocklist_match_attrs(tenant_id, scope, match_type, matched_term, reason) do
    %{
      matched_term: matched_term,
      match_type: match_type,
      scope: scope,
      reason: reason,
      blocklist_updated_at: BlocklistCache.get_last_updated(tenant_id)
    }
  end

  # ── private: result builders → %ComplianceScreening{} ─────────────────────

  defp build_blocklist_screening(
         scope,
         entity_type,
         entity_name,
         blocklist_match_attrs,
         list_info
       ) do
    %ComplianceScreening{
      scope: scope,
      screening_type: :sanctions,
      screening_status: :pending,
      screening_score: nil,
      screened_entity_type: entity_type,
      screened_entity_name: entity_name,
      match_count: length(blocklist_match_attrs),
      screened_at: DateTime.utc_now(),
      sanctions_matches: [],
      blocklist_matches:
        Enum.map(blocklist_match_attrs, &to_blocklist_match_struct(&1, list_info))
    }
  end

  defp perform_watchman_search(
         scope,
         entity_type,
         entity_name,
         search_params,
         suppressed_source_ids,
         list_info
       ) do
    broad_entities = search_watchman(search_params)
    custom_entities = search_watchman(Keyword.put(search_params, :source, "custom_watchlist"))

    case {broad_entities, custom_entities} do
      {{:ok, broad}, {:ok, custom}} ->
        entities = Enum.uniq_by(broad ++ custom, & &1.sourceID)
        all_match_attrs = build_sanctions_match_attrs(entities, suppressed_source_ids)
        active = Enum.reject(all_match_attrs, & &1.suppressed)

        {:ok,
         build_sanctions_screening(
           scope,
           entity_type,
           entity_name,
           all_match_attrs,
           active,
           list_info
         )}

      # coveralls-ignore-start
      {{:error, _} = error, _} ->
        error

      {_, {:error, _} = error} ->
        error

      _ ->
        {:error, :watchman_search_unavailable}
        # coveralls-ignore-stop
    end
  end

  # coveralls-ignore-start
  defp search_watchman(params) do
    case Client.v2_search_get(params) do
      {:ok, %{entities: entities}} -> {:ok, entities || []}
      {:error, _} = error -> error
      :error -> {:error, :watchman_search_unavailable}
    end
  end

  # coveralls-ignore-stop

  defp build_sanctions_match_attrs(entities, suppressed_source_ids) do
    Enum.map(entities, fn entity ->
      suppressed = MapSet.member?(suppressed_source_ids, entity.sourceID)

      %{
        matched_name: entity.name,
        matched_entity_type: entity.entityType,
        match_score: entity.match,
        source_list: entity.sourceList,
        source_id: entity.sourceID,
        addresses: normalize_addresses(entity.addresses),
        business_data: normalize_business(entity.business),
        person_data: normalize_person(entity.person),
        contact_data: normalize_contact(entity.contact),
        source_data: to_map(entity.sourceData),
        suppressed: suppressed
      }
    end)
  end

  defp build_sanctions_screening(
         scope,
         entity_type,
         entity_name,
         all_match_attrs,
         active_match_attrs,
         list_info
       ) do
    match_count = length(active_match_attrs)

    score_float =
      if match_count > 0 do
        active_match_attrs |> Enum.map(& &1.match_score) |> Enum.max()
      end

    %ComplianceScreening{
      scope: scope,
      screening_type: :sanctions,
      screening_status: :pending,
      screening_score: score_to_decimal(score_float),
      screened_entity_type: entity_type,
      screened_entity_name: entity_name,
      match_count: match_count,
      screened_at: DateTime.utc_now(),
      sanctions_matches: Enum.map(all_match_attrs, &to_sanctions_match_struct(&1, list_info)),
      blocklist_matches: []
    }
  end

  # Raw max match score scaled to a 0..100 Decimal — a fact, not a verdict.
  defp score_to_decimal(nil), do: nil
  defp score_to_decimal(float) when is_float(float), do: Decimal.from_float(float * 100)

  defp to_sanctions_match_struct(attrs, list_info) do
    qualifier = if attrs.suppressed, do: :auto_suppressed, else: :none

    %SanctionsMatch{
      matched_name: attrs.matched_name,
      matched_entity_type: attrs.matched_entity_type,
      match_score: attrs.match_score,
      source_list: attrs.source_list,
      source_id: attrs.source_id,
      source_data: attrs.source_data,
      addresses: Enum.map(attrs.addresses || [], &struct(SanctionsMatch.WatchmanAddress, &1)),
      business_data:
        attrs.business_data && struct(SanctionsMatch.WatchmanBusiness, attrs.business_data),
      person_data: attrs.person_data && struct(SanctionsMatch.WatchmanPerson, attrs.person_data),
      contact_data:
        attrs.contact_data && struct(SanctionsMatch.WatchmanContact, attrs.contact_data),
      false_positive_qualifier: qualifier,
      list_synced_at: list_info.started_at,
      list_sources: %{lists: list_info.lists, version: list_info.version}
    }
  end

  defp to_blocklist_match_struct(attrs, _list_info) do
    %BlocklistMatch{
      matched_term: attrs.matched_term,
      match_type: attrs.match_type,
      scope: attrs.scope,
      reason: attrs.reason,
      blocklist_updated_at: attrs.blocklist_updated_at
    }
  end

  # ── private: Watchman struct → plain-map normalizers ──────────────────────

  defp normalize_addresses(nil), do: []

  defp normalize_addresses(addresses) do
    Enum.map(addresses, fn addr ->
      %{
        line1: get_field(addr, :address1),
        line2: get_field(addr, :address2),
        city: get_field(addr, :city),
        region: get_field(addr, :state),
        postal_code: get_field(addr, :postalCode),
        country: get_field(addr, :country),
        type: get_field(addr, :type)
      }
    end)
  end

  defp normalize_business(nil), do: nil

  defp normalize_business(business) do
    %{
      name: get_field(business, :name),
      registration_number: get_field(business, :identifier),
      incorporation_date: get_field(business, :created),
      dissolved_date: get_field(business, :dissolved)
    }
  end

  defp normalize_person(nil), do: nil

  defp normalize_person(person) do
    %{
      given_name: get_field(person, :firstName),
      family_name: get_field(person, :lastName),
      dob: get_field(person, :birthDate),
      gender: get_field(person, :gender),
      nationalities: get_field(person, :nationality) |> List.wrap() |> Enum.reject(&is_nil/1)
    }
  end

  # coveralls-ignore-next-line
  defp normalize_contact(nil), do: nil

  defp normalize_contact(contact) do
    %{
      emails: get_field(contact, :emailAddresses) || [],
      phones: get_field(contact, :phoneNumbers) || [],
      websites: get_field(contact, :websites) || []
    }
  end

  defp get_field(struct_or_map, key) when is_struct(struct_or_map) do
    Map.get(struct_or_map, key)
  end

  # coveralls-ignore-start
  defp get_field(map, key) when is_map(map), do: Map.get(map, key)
  defp get_field(nil, _key), do: nil

  defp to_map(nil), do: nil
  # coveralls-ignore-stop

  defp to_map(map) when is_map(map), do: map

  defp maybe_add(params, _key, nil), do: params
  # coveralls-ignore-next-line
  defp maybe_add(params, _key, ""), do: params
  defp maybe_add(params, key, value), do: Keyword.put(params, key, value)

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> datetime
      # coveralls-ignore-next-line
      _ -> DateTime.utc_now()
    end
  end

  # coveralls-ignore-next-line
  defp parse_datetime(_), do: DateTime.utc_now()
end

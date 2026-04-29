defmodule AtomicFi.DecisionContext.ScreeningEngine do
  @moduledoc """
  Public screening engine — blocklist + Watchman API integration.

  Provides the core screening logic used by both `DecisionContext` (legacy)
  and `ComplianceScreeningContext` (ISO 20022 aligned). All `Watchman.*` structs
  are normalized to plain maps before returning — callers never handle Watchman DTOs.

  ## Responsibilities

  - Fetch Watchman list metadata
  - Screen individuals and companies against the internal blocklist (fail-fast)
  - Screen against Watchman sanctions lists if blocklist passes
  - Return typed result maps with no external API types leaking to callers

  ## False Positive Deduplication

  Callers may pass `suppressed_source_ids` (a `MapSet` of Watchman source IDs
  previously tagged as `manual_override` or `auto_suppressed` for the tenant).
  Matches with a `source_id` in that set will still be included in the result
  but flagged with `suppressed: true` so the persistence layer can write them
  with `false_positive_qualifier: :auto_suppressed` and exclude them from scoring.
  """

  alias AtomicFi.DecisionContext.{BlocklistCache, BlocklistValidator}
  alias AtomicFi.Watchman.Operations

  @type individual_attrs :: %{
          first_name: String.t(),
          last_name: String.t(),
          birth_date: String.t() | nil,
          gender: String.t() | nil
        }

  @type company_attrs :: %{
          name: String.t(),
          created: String.t() | nil,
          dissolved: String.t() | nil
        }

  @type watchman_address :: %{
          line1: String.t() | nil,
          line2: String.t() | nil,
          city: String.t() | nil,
          region: String.t() | nil,
          postal_code: String.t() | nil,
          country: String.t() | nil,
          type: String.t() | nil
        }

  @type watchman_business :: %{
          name: String.t() | nil,
          registration_number: String.t() | nil,
          incorporation_date: String.t() | nil,
          dissolved_date: String.t() | nil
        }

  @type watchman_person :: %{
          given_name: String.t() | nil,
          family_name: String.t() | nil,
          dob: String.t() | nil,
          gender: String.t() | nil,
          nationalities: [String.t()]
        }

  @type watchman_contact :: %{
          emails: [String.t()],
          phones: [String.t()],
          websites: [String.t()]
        }

  @type sanctions_match_result :: %{
          matched_name: String.t(),
          matched_entity_type: String.t() | nil,
          match_score: float(),
          sanctions_match_type: :exact | :fuzzy | :ubo | :entity,
          source_list: String.t(),
          source_id: String.t() | nil,
          addresses: [watchman_address()],
          business_data: watchman_business() | nil,
          person_data: watchman_person() | nil,
          contact_data: watchman_contact() | nil,
          source_data: map() | nil,
          suppressed: boolean()
        }

  @type blocklist_match_result :: %{
          matched_term: String.t(),
          match_type: :exact | :regex,
          scope: :first_name | :last_name | :company_name,
          reason: String.t(),
          blocklist_updated_at: DateTime.t() | nil
        }

  @type screening_result :: %{
          entity_type: :individual | :company,
          entity_name: String.t(),
          screening_status: :pass | :potential_match | :blocked,
          match_count: non_neg_integer(),
          screening_score: float() | nil,
          screened_at: DateTime.t(),
          sanctions_matches: [sanctions_match_result()],
          blocklist_matches: [blocklist_match_result()]
        }

  @type list_info :: %{started_at: DateTime.t(), lists: term(), version: term()}

  @doc """
  Fetch Watchman list metadata (sync timestamp, list sources, version).

  Returns `{:ok, list_info()}` or `{:error, term()}`.
  """
  @spec get_watchman_list_info() :: {:ok, list_info()} | {:error, term()}
  def get_watchman_list_info do
    case Operations.v2_listinfo_get() do
      {:ok, response} ->
        {:ok,
         %{
           started_at: parse_datetime(response.startedAt),
           lists: response.lists,
           version: response.version
         }}

      {:error, _} = error ->
        error

      :error ->
        {:error, :watchman_listinfo_unavailable}
    end
  end

  @doc """
  Screen an individual against the blocklist and Watchman sanctions lists.

  Blocklist is checked first (fail-fast). Watchman is only called if the
  individual passes the blocklist.

  `suppressed_source_ids` is a `MapSet` of Watchman source IDs already reviewed
  as false positives for this tenant. Matches found in this set are included in
  results but flagged `suppressed: true`.
  """
  @spec screen_individual(String.t(), individual_attrs(), MapSet.t()) ::
          {:ok, screening_result()} | {:error, term()}
  def screen_individual(
        tenant_id,
        %{first_name: first_name, last_name: last_name} = individual,
        suppressed_source_ids \\ MapSet.new()
      ) do
    entity_name = "#{first_name} #{last_name}"
    blocklist_matches = check_individual_blocklist(tenant_id, first_name, last_name)

    if blocklist_matches != [] do
      result = build_blocklist_screening_result(:individual, entity_name, blocklist_matches)
      {:ok, result}
    else
      search_params =
        [name: entity_name, minMatch: 0.7, type: "person"]
        |> maybe_add(:birthDate, individual[:birth_date])
        |> maybe_add(:gender, individual[:gender])

      perform_watchman_search(:individual, entity_name, search_params, suppressed_source_ids)
    end
  end

  @doc """
  Screen a company against the blocklist and Watchman sanctions lists.

  Blocklist is checked first (fail-fast). Watchman is only called if the
  company passes the blocklist.

  `suppressed_source_ids` is a `MapSet` of Watchman source IDs already reviewed
  as false positives for this tenant.
  """
  @spec screen_company(String.t(), company_attrs(), MapSet.t()) ::
          {:ok, screening_result()} | {:error, term()}
  def screen_company(tenant_id, %{name: name} = company, suppressed_source_ids \\ MapSet.new()) do
    blocklist_matches = check_company_blocklist(tenant_id, name)

    if blocklist_matches != [] do
      result = build_blocklist_screening_result(:company, name, blocklist_matches)
      {:ok, result}
    else
      search_params =
        [name: name, minMatch: 0.7, type: "business"]
        |> maybe_add(:created, company[:created])
        |> maybe_add(:dissolved, company[:dissolved])

      perform_watchman_search(:company, name, search_params, suppressed_source_ids)
    end
  end

  @doc """
  Determine the overall screening status from a list of screening results.

  Precedence: `blocked` > `potential_match` > `pass`.
  """
  @spec determine_overall_status([screening_result()]) :: :pass | :potential_match | :blocked
  def determine_overall_status(results) do
    cond do
      Enum.any?(results, &(&1.screening_status == :blocked)) -> :blocked
      Enum.any?(results, &(&1.screening_status == :potential_match)) -> :potential_match
      true -> :pass
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp check_individual_blocklist(tenant_id, first_name, last_name) do
    matches = []

    matches =
      case BlocklistValidator.validate_first_name(tenant_id, first_name) do
        {:error, :blocklisted, match_type, matched_term, reason} ->
          matches ++
            [build_blocklist_match(tenant_id, :first_name, match_type, matched_term, reason)]

        {:ok, _} ->
          matches
      end

    case BlocklistValidator.validate_last_name(tenant_id, last_name) do
      {:error, :blocklisted, match_type, matched_term, reason} ->
        matches ++
          [build_blocklist_match(tenant_id, :last_name, match_type, matched_term, reason)]

      {:ok, _} ->
        matches
    end
  end

  defp check_company_blocklist(tenant_id, company_name) do
    case BlocklistValidator.validate_company_name(tenant_id, company_name) do
      {:error, :blocklisted, match_type, matched_term, reason} ->
        [build_blocklist_match(tenant_id, :company_name, match_type, matched_term, reason)]

      {:ok, _} ->
        []
    end
  end

  defp build_blocklist_match(tenant_id, scope, match_type, matched_term, reason) do
    %{
      matched_term: matched_term,
      match_type: match_type,
      scope: scope,
      reason: reason,
      blocklist_updated_at: BlocklistCache.get_last_updated(tenant_id)
    }
  end

  defp build_blocklist_screening_result(entity_type, entity_name, blocklist_matches) do
    %{
      entity_type: entity_type,
      entity_name: entity_name,
      screening_status: :blocked,
      match_count: 0,
      screening_score: nil,
      screened_at: DateTime.utc_now(),
      sanctions_matches: [],
      blocklist_matches: blocklist_matches
    }
  end

  defp perform_watchman_search(entity_type, entity_name, search_params, suppressed_source_ids) do
    case Operations.v2_search_get(search_params) do
      {:ok, %{entities: entities}} ->
        sanctions_matches = build_sanctions_matches(entities || [], suppressed_source_ids)
        active_matches = Enum.reject(sanctions_matches, & &1.suppressed)

        result =
          build_sanctions_screening_result(
            entity_type,
            entity_name,
            sanctions_matches,
            active_matches
          )

        {:ok, result}

      {:error, _} = error ->
        error

      :error ->
        {:error, :watchman_search_unavailable}
    end
  end

  defp build_sanctions_matches(entities, suppressed_source_ids) do
    Enum.map(entities, fn entity ->
      suppressed = MapSet.member?(suppressed_source_ids, entity.sourceID)

      %{
        matched_name: entity.name,
        matched_entity_type: entity.entityType,
        match_score: entity.match,
        sanctions_match_type: classify_match_type(entity.match),
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

  defp classify_match_type(score) when score >= 0.95, do: :exact
  defp classify_match_type(_score), do: :fuzzy

  defp build_sanctions_screening_result(entity_type, entity_name, all_matches, active_matches) do
    match_count = length(active_matches)

    screening_score =
      if match_count > 0 do
        active_matches |> Enum.map(& &1.match_score) |> Enum.max()
      end

    screening_status =
      cond do
        match_count == 0 -> :pass
        screening_score && screening_score >= 0.95 -> :blocked
        true -> :potential_match
      end

    %{
      entity_type: entity_type,
      entity_name: entity_name,
      screening_status: screening_status,
      match_count: match_count,
      screening_score: screening_score,
      screened_at: DateTime.utc_now(),
      sanctions_matches: all_matches,
      blocklist_matches: []
    }
  end

  # Normalize Watchman Address struct → plain map (no Watchman types escape this module)
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

  defp get_field(map, key) when is_map(map), do: Map.get(map, key)
  defp get_field(nil, _key), do: nil

  defp to_map(nil), do: nil

  defp to_map(struct) when is_struct(struct) do
    struct |> Map.from_struct() |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new()
  end

  defp to_map(map) when is_map(map), do: map

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, _key, ""), do: params
  defp maybe_add(params, key, value), do: Keyword.put(params, key, value)

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> datetime
      _ -> DateTime.utc_now()
    end
  end

  defp parse_datetime(_), do: DateTime.utc_now()
end

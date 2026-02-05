defmodule PaymentCompliancePlatform.DecisionContext do
  @moduledoc """
  The DecisionContext context.
  """

  import Ecto.Query, warn: false
  alias PaymentCompliancePlatform.Repo

  alias PaymentCompliancePlatform.DecisionContext.Decision
  alias PaymentCompliancePlatform.Watchman.Operations

  @doc """
  Returns the list of decisions.

  ## Examples

      iex> list_decisions()
      [%Decision{}, ...]

  """
  def list_decisions do
    Repo.all(Decision)
  end

  @doc """
  Gets a single decision.

  Raises `Ecto.NoResultsError` if the Decision does not exist.

  ## Examples

      iex> get_decision!(123)
      %Decision{}

      iex> get_decision!(456)
      ** (Ecto.NoResultsError)

  """
  def get_decision!(id), do: Repo.get!(Decision, id)

  @doc """
  Creates a decision.

  ## Examples

      iex> create_decision(%{field: value})
      {:ok, %Decision{}}

      iex> create_decision(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_decision(attrs) do
    %Decision{}
    |> Decision.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a decision.

  ## Examples

      iex> update_decision(decision, %{field: new_value})
      {:ok, %Decision{}}

      iex> update_decision(decision, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_decision(%Decision{} = decision, attrs) do
    decision
    |> Decision.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a decision.

  ## Examples

      iex> delete_decision(decision)
      {:ok, %Decision{}}

      iex> delete_decision(decision)
      {:error, %Ecto.Changeset{}}

  """
  def delete_decision(%Decision{} = decision) do
    Repo.delete(decision)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking decision changes.

  ## Examples

      iex> change_decision(decision)
      %Ecto.Changeset{data: %Decision{}}

  """
  def change_decision(%Decision{} = decision, attrs \\ %{}) do
    Decision.changeset(decision, attrs)
  end

  @doc """
  Screen an account holder for onboarding.

  Screens all interested individuals/companies against Watchman sanctions lists.
  Returns an in-memory Decision struct with screening results (no database persistence).
  """
  @spec screen_account_holder(
          Session.t(),
          PaymentCompliancePlatform.OpenApiSchema.AccountHolderRequest.t()
        ) ::
          {:ok, Decision.t()} | {:error, term()}
  def screen_account_holder(session, request) do
    with {:ok, list_info} <- get_watchman_list_info(),
         {:ok, entity_decisions} <- screen_all_entities(request) do
      decision = build_decision(session, list_info, entity_decisions, request)
      {:ok, decision}
    end
  end

  # Private helpers

  defp get_watchman_list_info do
    case Operations.v2_listinfo_get() do
      {:ok, response} -> {:ok, response}
      {:error, _} = error -> error
      :error -> {:error, :watchman_listinfo_unavailable}
    end
  end

  defp screen_all_entities(%{
         interested_individuals: individuals,
         interested_companies: companies
       }) do
    individuals = individuals || []
    companies = companies || []

    individual_results = Enum.map(individuals, &screen_individual/1)
    company_results = Enum.map(companies, &screen_company/1)

    all_results = individual_results ++ company_results

    if Enum.all?(all_results, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(all_results, fn {:ok, result} -> result end)}
    else
      Enum.find(all_results, &match?({:error, _}, &1))
    end
  end

  defp screen_individual(%{first_name: first_name, last_name: last_name} = individual) do
    entity_name = "#{first_name} #{last_name}"

    search_params =
      [name: entity_name, minMatch: 0.7, type: "person"]
      |> maybe_add(:birthDate, individual.birth_date)
      |> maybe_add(:gender, individual.gender)

    perform_watchman_search(:interested_individual, entity_name, search_params)
  end

  defp screen_company(%{name: name} = company) do
    search_params =
      [name: name, minMatch: 0.7, type: "business"]
      |> maybe_add(:created, company.created)
      |> maybe_add(:dissolved, company.dissolved)

    perform_watchman_search(:interested_company, name, search_params)
  end

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, _key, ""), do: params
  defp maybe_add(params, key, value), do: Keyword.put(params, key, value)

  defp perform_watchman_search(entity_type, entity_name, search_params) do
    case Operations.v2_search_get(search_params) do
      {:ok, %{entities: entities}} ->
        sanctions_matches = build_sanctions_matches(entities || [])
        entity_decision = build_entity_decision(entity_type, entity_name, sanctions_matches)
        {:ok, entity_decision}

      {:error, _} = error ->
        error

      :error ->
        {:error, :watchman_search_unavailable}
    end
  end

  defp build_sanctions_matches(entities) do
    Enum.map(entities, fn entity ->
      %{
        matched_name: entity.name,
        matched_entity_type: entity.entityType,
        match_score: entity.match,
        source_list: entity.sourceList,
        source_id: entity.sourceID,
        addresses: serialize_addresses(entity.addresses),
        business_data: to_map(entity.business),
        person_data: to_map(entity.person),
        contact_data: to_map(entity.contact),
        source_data: entity.sourceData
      }
    end)
  end

  defp serialize_addresses(nil), do: []
  defp serialize_addresses(addresses), do: Enum.map(addresses, &to_map/1)

  defp to_map(nil), do: nil

  defp to_map(struct) when is_struct(struct) do
    struct |> Map.from_struct() |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new()
  end

  defp to_map(map) when is_map(map), do: map

  defp build_entity_decision(entity_type, entity_name, sanctions_matches) do
    match_count = length(sanctions_matches)

    highest_match_score =
      if match_count > 0 do
        sanctions_matches |> Enum.map(& &1.match_score) |> Enum.max()
      end

    screening_result =
      cond do
        match_count == 0 -> :pass
        highest_match_score && highest_match_score >= 0.95 -> :blocked
        true -> :potential_match
      end

    %{
      entity_type: entity_type,
      entity_name: entity_name,
      screening_result: screening_result,
      match_count: match_count,
      highest_match_score: highest_match_score,
      screened_at: DateTime.utc_now(),
      sanctions_matches: sanctions_matches
    }
  end

  defp build_decision(session, list_info, entity_decisions, request) do
    total_entities_screened = length(entity_decisions)
    entities_with_matches = Enum.count(entity_decisions, &(&1.match_count > 0))
    overall_status = determine_overall_status(entity_decisions)

    decision_with_metadata = %Decision{
      id: Ecto.UUID.generate(),
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    attrs = %{
      account_holder_id: Ecto.UUID.generate(),
      tenant_id: session.tenant_id,
      overall_status: Atom.to_string(overall_status),
      total_entities_screened: total_entities_screened,
      entities_with_matches: entities_with_matches,
      list_synced_at: parse_datetime(list_info.startedAt),
      list_sources: %{lists: list_info.lists, version: list_info.version},
      raw_request: if(is_struct(request), do: Map.from_struct(request), else: request),
      entity_decisions: entity_decisions
    }

    case Decision.changeset(decision_with_metadata, attrs)
         |> Ecto.Changeset.apply_action(:insert) do
      {:ok, decision} -> decision
      {:error, changeset} -> raise "Failed to build decision: #{inspect(changeset.errors)}"
    end
  end

  defp determine_overall_status(entity_decisions) do
    cond do
      Enum.any?(entity_decisions, &(&1.screening_result == :blocked)) -> :blocked
      Enum.any?(entity_decisions, &(&1.screening_result == :potential_match)) -> :potential_match
      true -> :pass
    end
  end

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> datetime
      _ -> DateTime.utc_now()
    end
  end

  defp parse_datetime(_), do: DateTime.utc_now()
end

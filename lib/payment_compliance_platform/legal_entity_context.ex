defmodule PaymentCompliancePlatform.LegalEntityContext do
  @moduledoc """
  The LegalEntityContext context.

  Manages shared identity records for individuals and businesses per ISO 20022 acmt:007 + FATF CDD.
  LegalEntity is the foundational identity layer — domain-specific overlays (KYC status, risk level)
  belong on the MDM subject (AccountHolder, etc.).
  """

  import Ecto.Query, warn: false
  use PaymentCompliancePlatform.LoggerMacro

  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.LegalEntityContext.LegalEntity
  alias PaymentCompliancePlatform.LegalEntityChangeEventContext.LegalEntityChangeEvent
  alias PaymentCompliancePlatform.SessionContext.Session

  @legal_entity_preloads [:addresses, :phone_numbers, :identifications]

  @doc """
  Returns the list of legal_entities with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_legal_entities(session, %{page: 1, page_size: 20})
      {:ok, {[%LegalEntity{}, ...], %Flop.Meta{}}}

  """
  @spec list_legal_entities(Session.t(), map()) ::
          {:ok, {list(LegalEntity.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_legal_entities(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    LegalEntity
    |> preload(^@legal_entity_preloads)
    |> Flop.validate_and_run(flop_params,
      for: LegalEntity,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single legal_entity with preloaded associations.

  Raises `Ecto.NoResultsError` if the Legal entity does not exist.

  ## Examples

      iex> get_legal_entity!(session, "123")
      %LegalEntity{}

      iex> get_legal_entity!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_legal_entity!(Session.t(), Ecto.UUID.t()) :: LegalEntity.t()
  def_with_rls_and_logging get_legal_entity!(session, id), log_fields: [:id] do
    LegalEntity
    |> preload(^@legal_entity_preloads)
    |> Repo.get!(id, session: session)
  end

  @doc """
  Creates a legal_entity.

  Supports nested associations: addresses, phone_numbers, identifications can be
  provided as lists in attrs and will be created via cast_assoc.

  ## Examples

      iex> create_legal_entity(session, %{legal_entity_type: :individual, first_name: "John"})
      {:ok, %LegalEntity{}}

      iex> create_legal_entity(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_legal_entity(Session.t(), map()) ::
          {:ok, LegalEntity.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_legal_entity(session, attrs), log_fields: [] do
    %LegalEntity{}
    |> LegalEntity.changeset(attrs)
    |> Repo.insert(session: session)
    |> preload_after_write()
  end

  @doc """
  Updates a legal_entity.

  ## Examples

      iex> update_legal_entity(session, legal_entity, %{first_name: "Jane"})
      {:ok, %LegalEntity{}}

      iex> update_legal_entity(session, legal_entity, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_legal_entity(Session.t(), LegalEntity.t(), map()) ::
          {:ok, LegalEntity.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_legal_entity(
                             session,
                             %LegalEntity{} = legal_entity,
                             attrs
                           ),
                           log_fields: [:legal_entity] do
    legal_entity
    |> Repo.preload(@legal_entity_preloads, session: session)
    |> LegalEntity.changeset(attrs)
    |> record_change_event(session)
    |> Repo.update(session: session)
    |> preload_after_write()
  end

  @doc """
  Deletes a legal_entity.

  ## Examples

      iex> delete_legal_entity(session, legal_entity)
      {:ok, %LegalEntity{}}

      iex> delete_legal_entity(session, legal_entity)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_legal_entity(Session.t(), LegalEntity.t()) ::
          {:ok, LegalEntity.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_legal_entity(session, %LegalEntity{} = legal_entity),
    log_fields: [:legal_entity] do
    Repo.delete(legal_entity, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking legal_entity changes.

  ## Examples

      iex> change_legal_entity(legal_entity)
      %Ecto.Changeset{data: %LegalEntity{}}

  """
  def change_legal_entity(%LegalEntity{} = legal_entity, attrs \\ %{}) do
    LegalEntity.changeset(legal_entity, attrs)
  end

  # Private: Preload associations after writes.
  # Also reloads the struct from DB to pick up any trigger-updated fields
  # (e.g. latest_change_event_id set by the legal_entity_change_event_after_insert trigger).
  defp preload_after_write({:ok, %LegalEntity{} = legal_entity}) do
    reloaded = Repo.reload!(legal_entity, skip_multi_tenancy_check: true)
    {:ok, Repo.preload(reloaded, @legal_entity_preloads, skip_multi_tenancy_check: true)}
  end

  defp preload_after_write({:error, changeset}), do: {:error, changeset}

  # ── Change event recording ────────────────────────────────────────────────────

  # Wraps the changeset in prepare_changes/2 to auto-create a LegalEntityChangeEvent
  # inside the same DB transaction whenever there are actual field changes.
  # Only fires when the changeset is valid (Ecto guarantee for prepare_changes/2).
  defp record_change_event(changeset, session) do
    Ecto.Changeset.prepare_changes(changeset, &insert_change_event(&1, session))
  end

  defp insert_change_event(%{changes: changes} = prepared_cs, _session) when changes == %{} do
    prepared_cs
  end

  defp insert_change_event(prepared_cs, session) do
    legal_entity = prepared_cs.data
    tenant_id = Ecto.Changeset.get_field(prepared_cs, :tenant_id)

    previous_state = build_previous_state(legal_entity)
    changes_diff = build_changes_diff(prepared_cs.changes, previous_state)
    event_type = infer_event_type(Map.keys(prepared_cs.changes))

    change_event_attrs = %{
      legal_entity_id: legal_entity.id,
      event_type: event_type,
      change_channel: :api,
      event_status: :pending,
      changes: changes_diff,
      previous_state: previous_state,
      tenant_id: tenant_id
    }

    change_event_cs =
      LegalEntityChangeEvent.changeset(%LegalEntityChangeEvent{}, change_event_attrs)

    # Insert in the same transaction — non-fatal if it fails (entity update proceeds)
    case prepared_cs.repo.insert(change_event_cs, session: session) do
      {:ok, _event} -> prepared_cs
      {:error, _} -> prepared_cs
    end
  end

  # Build a JSON-safe map of the LegalEntity state before the update.
  defp build_previous_state(%LegalEntity{} = legal_entity) do
    legal_entity
    |> Map.from_struct()
    |> Map.drop([
      :__meta__,
      :addresses,
      :phone_numbers,
      :identifications,
      :tenant,
      :latest_change_event_id
    ])
    |> Enum.map(fn {k, v} -> {to_string(k), serialize_value(v)} end)
    |> Enum.into(%{})
  end

  # Association fields (addresses, phone_numbers, identifications) appear in
  # prepared_cs.changes as lists of Ecto.Changesets — not JSON-serializable.
  # They are handled by infer_event_type/1 so we skip them here.
  @association_fields [:addresses, :phone_numbers, :identifications]

  # Build a diff map: %{"field_name" => [previous_value, new_value]}
  # Association changes are excluded — they are not JSON-serializable and
  # are already captured by event_type via infer_event_type/1.
  defp build_changes_diff(changes, previous_state) do
    changes
    |> Enum.reject(fn {field, _} -> field in @association_fields end)
    |> Enum.map(fn {field, new_val} ->
      prev_val = Map.get(previous_state, to_string(field))
      {to_string(field), [prev_val, serialize_value(new_val)]}
    end)
    |> Enum.into(%{})
  end

  # Infer the event_type from the set of changed Ecto fields.
  defp infer_event_type(changed_keys) do
    cond do
      :phone_numbers in changed_keys -> :phone_change
      :addresses in changed_keys -> :address_change
      :identifications in changed_keys -> :contact_info_change
      :first_name in changed_keys or :last_name in changed_keys -> :contact_info_change
      true -> :contact_info_change
    end
  end

  # Serialize Ecto/Elixir values to JSON-safe primitives.
  defp serialize_value(nil), do: nil
  defp serialize_value(%Date{} = d), do: Date.to_iso8601(d)
  defp serialize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp serialize_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp serialize_value(v) when is_atom(v), do: to_string(v)
  defp serialize_value(v), do: v
end

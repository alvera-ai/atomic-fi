defmodule AtomicFi.LegalEntityChangeEventContext do
  @moduledoc """
  LegalEntityChangeEventContext — manages the audit log of identity lifecycle changes.

  LegalEntityChangeEvents are primarily created automatically by `update_legal_entity/3`
  via `Ecto.Changeset.prepare_changes/2` — they capture a full JSONB diff of every
  identity change and are inserted in the same DB transaction as the entity update.

  Events can also be created directly via the REST API (POST /legal-entity-change-events)
  to record externally received acmt:006 messages.

  ## ISO 20022 Alignment

  - `acmt:006` — AccountModificationInstruction (customer-initiated change request)
  - `acmt:002` — AccountDetailsConfirmation (institution-side confirmation)

  ## AML Signals

  Primary signal source for **account takeover** detection:
  - SIM swap: rapid `phone_change` events
  - Address control: multiple `address_change` events in a short window
  - Pre-transfer grooming: `beneficiary_added` or `authorised_signer_change` before
    a large outgoing payment

  ## Mutable Fields (PUT)

  Only non-system fields are mutable: `event_status`, `change_channel`,
  `acmt_instruction_id`, `acmt_confirmation_id`, `account_holder_id`, `beneficial_owner_id`.
  System-generated fields (`changes`, `previous_state`, `legal_entity_id`) are immutable.
  """

  import Ecto.Query, warn: false
  use AtomicFi.LoggerMacro

  alias AtomicFi.LegalEntityChangeEventContext.LegalEntityChangeEvent
  alias AtomicFi.OpenApiSchema.LegalEntityChangeEventRequest
  alias AtomicFi.Repo
  alias AtomicFi.SessionContext.Session

  @doc """
  Returns the list of legal entity change events with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_legal_entity_change_events(session, %{page: 1, page_size: 20})
      {:ok, {[%LegalEntityChangeEvent{}, ...], %Flop.Meta{}}}

  """
  @spec list_legal_entity_change_events(Session.t(), map()) ::
          {:ok, {list(LegalEntityChangeEvent.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_legal_entity_change_events(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    LegalEntityChangeEvent
    |> Flop.validate_and_run(flop_params,
      for: LegalEntityChangeEvent,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single legal entity change event.

  Raises `Ecto.NoResultsError` if the LegalEntityChangeEvent does not exist.

  ## Examples

      iex> get_legal_entity_change_event!(session, "123")
      %LegalEntityChangeEvent{}

      iex> get_legal_entity_change_event!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_legal_entity_change_event!(Session.t(), Ecto.UUID.t()) :: LegalEntityChangeEvent.t()
  def_with_rls_and_logging get_legal_entity_change_event!(session, id), log_fields: [:id] do
    Repo.get!(LegalEntityChangeEvent, id, session: session)
  end

  @doc """
  Creates a legal entity change event.

  Used for recording externally received acmt:006 messages. Events auto-created by
  `update_legal_entity/3` use the internal `LegalEntityChangeEvent.changeset/2` directly.

  ## Examples

      iex> create_legal_entity_change_event(session, %LegalEntityChangeEventRequest{...})
      {:ok, %LegalEntityChangeEvent{}}

      iex> create_legal_entity_change_event(session, %LegalEntityChangeEventRequest{...})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_legal_entity_change_event(Session.t(), LegalEntityChangeEventRequest.t()) ::
          {:ok, LegalEntityChangeEvent.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_legal_entity_change_event(
                             session,
                             %LegalEntityChangeEventRequest{} = request
                           ),
                           log_fields: [] do
    %LegalEntityChangeEvent{}
    |> LegalEntityChangeEvent.changeset(request)
    |> Repo.insert(session: session)
  end

  @doc """
  Updates a legal entity change event.

  Only mutable fields are allowed: `event_status`, `change_channel`,
  `acmt_instruction_id`, `acmt_confirmation_id`, `account_holder_id`, `beneficial_owner_id`.
  System-generated fields (`changes`, `previous_state`, `legal_entity_id`) are immutable.

  ## Examples

      iex> update_legal_entity_change_event(session, event, %LegalEntityChangeEventRequest{...})
      {:ok, %LegalEntityChangeEvent{}}

      iex> update_legal_entity_change_event(session, event, %LegalEntityChangeEventRequest{...})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_legal_entity_change_event(
          Session.t(),
          LegalEntityChangeEvent.t(),
          LegalEntityChangeEventRequest.t()
        ) :: {:ok, LegalEntityChangeEvent.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_legal_entity_change_event(
                             session,
                             %LegalEntityChangeEvent{} = event,
                             %LegalEntityChangeEventRequest{} = request
                           ),
                           log_fields: [:event] do
    event
    |> LegalEntityChangeEvent.update_changeset(request)
    |> Repo.update(session: session)
  end

  @doc """
  Deletes a legal entity change event.

  ## Examples

      iex> delete_legal_entity_change_event(session, event)
      {:ok, %LegalEntityChangeEvent{}}

      iex> delete_legal_entity_change_event(session, event)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_legal_entity_change_event(Session.t(), LegalEntityChangeEvent.t()) ::
          {:ok, LegalEntityChangeEvent.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_legal_entity_change_event(
                             session,
                             %LegalEntityChangeEvent{} = event
                           ),
                           log_fields: [:event] do
    Repo.delete(event, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking legal entity change event changes.

  ## Examples

      iex> change_legal_entity_change_event(event)
      %Ecto.Changeset{data: %LegalEntityChangeEvent{}}

  """
  def change_legal_entity_change_event(
        %LegalEntityChangeEvent{} = event,
        attrs \\ %{}
      ) do
    LegalEntityChangeEvent.changeset(event, attrs)
  end
end

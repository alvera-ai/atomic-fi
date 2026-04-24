defmodule PaymentCompliancePlatform.LegalEntityChangeEventContext.LegalEntityChangeEvent do
  use PaymentCompliancePlatform.Schema

  alias PaymentCompliancePlatform.AccountHolderContext.AccountHolder
  alias PaymentCompliancePlatform.BeneficialOwnerContext.BeneficialOwner
  alias PaymentCompliancePlatform.LegalEntityContext.LegalEntity
  alias PaymentCompliancePlatform.TenantContext.Tenant

  @typedoc """
  LegalEntityChangeEvent — audit log of non-financial lifecycle changes to an identity record.

  ## ISO 20022 Alignment

  Maps to two acmt (Account Management) message families:

  - `acmt:006` — AccountModificationInstruction (customer-initiated change request)
  - `acmt:002` — AccountDetailsConfirmation (institution-side confirmation)

  ## Lifecycle

  Events created automatically by `update_legal_entity/3` (via `Ecto.Changeset.prepare_changes/2`)
  start with `event_status: :pending`. A DB trigger immediately flips this to `:recorded` and
  updates `legal_entities.latest_change_event_id` in the same transaction.

  Events can also be created directly via the API (POST /legal-entity-change-events) for
  manually recording external acmt:006 messages.

  Non-system fields are mutable via PUT:
  `event_status`, `change_channel`, `acmt_instruction_id`, `acmt_confirmation_id`,
  `account_holder_id`, `beneficial_owner_id`.

  ## AML Signals

  Primary signal source for **account takeover** detection:
  - SIM swap attacks: rapid `phone_change` events
  - Address velocity: multiple `address_change` events in a short window
  - Pre-transfer grooming: `beneficiary_added` or `authorised_signer_change` before
    a large outgoing payment

  ## Attributes

  * `id` - UUID primary key
  * `legal_entity_id` - FK to LegalEntity (identity subject, required, immutable after creation)
  * `account_holder_id` - FK to AccountHolder (nullable context link)
  * `beneficial_owner_id` - FK to BeneficialOwner (nullable context link)
  * `event_type` - Type of identity change
  * `change_channel` - Channel through which the change was requested
  * `event_status` - Lifecycle status (`:pending` | `:confirmed` | `:rejected` | `:recorded`)
  * `acmt_instruction_id` - acmt:006 MsgId (dedup key, unique per tenant when set)
  * `acmt_confirmation_id` - acmt:002 MsgId (populated once confirmed)
  * `changes` - JSONB diff of changed fields: `%{"field" => [prev_val, new_val]}`
  * `previous_state` - Full JSONB snapshot of LegalEntity before this change
  * `tenant_id` - FK to Tenant for multi-tenancy isolation (RLS)
  * `inserted_at` / `updated_at` - Timestamps
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :tenant_id,
      :legal_entity_id,
      :account_holder_id,
      :beneficial_owner_id,
      :event_type,
      :change_channel,
      :event_status
    ],
    sortable: [
      :id,
      :inserted_at,
      :updated_at,
      :event_type,
      :event_status,
      :change_channel
    ],
    default_limit: 20,
    max_limit: 100
  }

  # ── OpenAPI annotations ──────────────────────────────────────────────────────

  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: [
        "address_change",
        "phone_change",
        "email_change",
        "beneficiary_added",
        "beneficiary_removed",
        "beneficiary_modified",
        "account_inquiry",
        "contact_info_change",
        "authorised_signer_change"
      ],
      description:
        "Type of identity change — maps to acmt:006 MdcnCd (Modification Code). " <>
          "Primary AML signals: phone_change (SIM swap), address_change (address velocity), " <>
          "beneficiary_added / authorised_signer_change (pre-transfer grooming)"
    },
    key: :event_type
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: ["web", "mobile", "branch", "api", "phone_banking"],
      description: "Channel through which the modification request was received"
    },
    key: :change_channel
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["pending", "confirmed", "rejected", "recorded"],
      description:
        "Lifecycle status — pending (change requested), confirmed (verified and applied), " <>
          "rejected (denied by compliance / KYC check), " <>
          "recorded (automatically set by DB trigger for system-generated events)"
    },
    key: :event_status
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description:
        "acmt:006 MsgId — upsert deduplication key. " <>
          "Unique per tenant when set (sparse unique index)"
    },
    key: :acmt_instruction_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "acmt:002 MsgId — confirmation message reference, populated once confirmed"
    },
    key: :acmt_confirmation_id
  )

  open_api_property(
    schema: %Schema{
      type: :object,
      nullable: true,
      readOnly: true,
      description:
        "JSONB diff of changed fields: keys are field names, values are [previous_value, new_value]. " <>
          "System-generated from Ecto changeset on update_legal_entity — not user-supplied."
    },
    key: :changes
  )

  open_api_property(
    schema: %Schema{
      type: :object,
      nullable: true,
      readOnly: true,
      description:
        "Full JSONB snapshot of the LegalEntity state before this change was applied. " <>
          "System-generated on update_legal_entity — not user-supplied."
    },
    key: :previous_state
  )

  open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :legal_entity_id)

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description: "AccountHolder context link (nullable — event may affect both threads)"
    },
    key: :account_holder_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      format: :uuid,
      nullable: true,
      description: "BeneficialOwner context link (nullable — event may affect both threads)"
    },
    key: :beneficial_owner_id
  )

  open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :tenant_id)

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :inserted_at
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :updated_at
  )

  open_api_schema(
    title: "LegalEntityChangeEvent",
    description:
      "Audit log of non-financial identity lifecycle changes to a LegalEntity. " <>
        "Maps to ISO 20022 acmt:006 (AccountModificationInstruction) and " <>
        "acmt:002 (AccountDetailsConfirmation). " <>
        "Auto-created by update_legal_entity via prepare_changes — not returned in the update " <>
        "response (requires a separate GET /legal-entity-change-events). " <>
        "Primary AML signal source for account takeover detection.",
    required: [
      :event_type,
      :change_channel,
      :legal_entity_id,
      :tenant_id
    ],
    properties: [
      :id,
      :event_type,
      :change_channel,
      :event_status,
      :acmt_instruction_id,
      :acmt_confirmation_id,
      :changes,
      :previous_state,
      :legal_entity_id,
      :account_holder_id,
      :beneficial_owner_id,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "legal_entity_change_events" do
    field :event_type, Ecto.Enum,
      values: [
        :address_change,
        :phone_change,
        :email_change,
        :beneficiary_added,
        :beneficiary_removed,
        :beneficiary_modified,
        :account_inquiry,
        :contact_info_change,
        :authorised_signer_change
      ]

    field :change_channel, Ecto.Enum, values: [:web, :mobile, :branch, :api, :phone_banking]

    field :event_status, Ecto.Enum,
      values: [:pending, :confirmed, :rejected, :recorded],
      default: :pending

    field :acmt_instruction_id, :string
    field :acmt_confirmation_id, :string

    # JSONB diff and snapshot — system-generated via prepare_changes on update_legal_entity
    field :changes, :map
    field :previous_state, :map

    # Relationships
    belongs_to :legal_entity, LegalEntity
    belongs_to :account_holder, AccountHolder
    belongs_to :beneficial_owner, BeneficialOwner

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new LegalEntityChangeEvent.

  Used by:
  - `create_legal_entity_change_event/2` (API POST)
  - `record_change_event/3` in LegalEntityContext (prepare_changes callback)

  Casts all fields including `:changes` and `:previous_state` (safe from trusted context).
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :event_type,
      :change_channel,
      :acmt_instruction_id,
      :acmt_confirmation_id,
      :changes,
      :previous_state,
      :legal_entity_id,
      :account_holder_id,
      :beneficial_owner_id,
      :tenant_id
    ])
    |> maybe_cast_event_status(attrs)
    |> validate_required([
      :event_type,
      :change_channel,
      :legal_entity_id,
      :tenant_id
    ])
    |> foreign_key_constraint(:legal_entity_id)
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:beneficial_owner_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:acmt_instruction_id, :tenant_id],
      name: :legal_entity_change_events_acmt_instruction_tenant_unique,
      message: "has already been taken"
    )
  end

  @doc """
  Changeset for updating an existing LegalEntityChangeEvent.

  Used by `update_legal_entity_change_event/3` (API PUT).

  Only mutable fields are castable — `legal_entity_id`, `changes`, and `previous_state`
  are immutable after creation and are excluded from this changeset.
  """
  def update_changeset(event, attrs) do
    event
    |> cast(attrs, [
      :change_channel,
      :acmt_instruction_id,
      :acmt_confirmation_id,
      :account_holder_id,
      :beneficial_owner_id
    ])
    |> maybe_cast_event_status(attrs)
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:beneficial_owner_id)
    |> unique_constraint([:acmt_instruction_id, :tenant_id],
      name: :legal_entity_change_events_acmt_instruction_tenant_unique,
      message: "has already been taken"
    )
  end

  # Only cast event_status when explicitly provided and non-nil.
  # ExOpenApiUtils.Changeset.cast/3 calls Mapper.to_map internally, which includes all struct
  # fields even when nil. Casting nil event_status would override the Ecto/DB default of :pending.
  defp maybe_cast_event_status(changeset, attrs) do
    status = Map.get(attrs, :event_status)

    if is_nil(status) do
      changeset
    else
      Ecto.Changeset.cast(changeset, %{event_status: status}, [:event_status])
    end
  end
end

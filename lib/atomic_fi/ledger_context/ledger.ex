defmodule AtomicFi.LedgerContext.Ledger do
  use AtomicFi.Schema

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.TenantContext.Tenant

  @typedoc """
  Ledger — ISO 20022 camt:052/camt:053 chart-of-accounts container.

  One per AccountHolder per currency. Balance is derived on-read by summing
  child LedgerAccount.balance values. No stored balance on Ledger itself.

  ## Attributes

  * `id` - UUID primary key
  * `account_holder_id` - FK to AccountHolder (MDM subject)
  * `currency` - ISO 4217 three-letter code (e.g. "USD") — authoritative for the entire ledger hierarchy
  * `status` - Ledger lifecycle: `active` | `closed`
  * `ledger_number` - Opaque external SoE ID (nullable; upsert identity)
  * `tenant_id` - FK to tenant for RLS
  * `inserted_at`, `updated_at` - Timestamps
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {Flop.Schema,
           filterable: [:id, :tenant_id, :account_holder_id, :currency, :status],
           sortable: [:id, :inserted_at, :updated_at, :currency, :status],
           default_limit: 20,
           max_limit: 100}

  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :account_holder_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      description:
        "ISO 4217 three-letter currency code (e.g. USD). Authoritative for the entire ledger hierarchy."
    },
    key: :currency
  )

  open_api_property(
    schema: %Schema{type: :string, nullable: true, enum: ["active", "closed"]},
    key: :status
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "Opaque external SoE identifier (upsert identity)"
    },
    key: :ledger_number
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid},
    key: :tenant_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :inserted_at
  )

  open_api_property(
    schema: %Schema{type: :string, format: :"date-time", readOnly: true},
    key: :updated_at
  )

  open_api_schema(
    title: "Ledger",
    description:
      "ISO 20022 camt:052/camt:053 chart-of-accounts container — one per AccountHolder per currency. " <>
        "Balance is derived on-read by summing child LedgerAccount.balance values.",
    required: [:account_holder_id, :currency],
    properties: [
      :id,
      :account_holder_id,
      :currency,
      :status,
      :ledger_number,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "ledgers" do
    belongs_to :account_holder, AccountHolder

    field :currency, :string

    field :status, Ecto.Enum,
      values: [:active, :closed],
      default: :active

    field :ledger_number, :string

    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(ledger, attrs) do
    ledger
    |> cast(attrs, [:account_holder_id, :currency, :status, :ledger_number, :tenant_id])
    |> validate_required([:account_holder_id, :currency, :tenant_id])
    |> validate_length(:currency, is: 3)
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:account_holder_id, :currency],
      name: :ledgers_account_holder_id_currency_index
    )
    |> unique_constraint(:ledger_number, name: :ledgers_ledger_number_unique)
  end
end

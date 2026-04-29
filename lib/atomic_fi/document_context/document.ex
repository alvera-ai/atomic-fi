defmodule AtomicFi.DocumentContext.Document do
  use AtomicFi.Schema

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.TenantContext.Tenant

  @typedoc """
  Compliance document — one row per supporting document for an AccountHolder.

  ## ISO 20022 Alignment

  Maps to `acmt:007 SupportingDocument` — documents submitted as part of
  account opening (KYC identity documents, proof of address, UBO declarations, etc.).
  Also supports `acmt:008` Additional Info Request responses.

  ## Subject Anchor

  `account_holder_id` is always the MDM subject (compliance entity).
  One AccountHolder may have many documents of different `document_type`/`name` combinations.

  ## Primary Document Rule

  At most one document may be `primary = true` per `(account_holder_id, name)` combination.
  A secondary document (`primary = false`) may not be inserted until a primary exists
  for the same combination — enforced by a BEFORE INSERT/UPDATE trigger.

  ## File Storage

  Physical files are stored out-of-band (S3/R2 or equivalent). This record stores only
  the storage reference (`file_key`, `file_name`, `content_type`, `file_size`). The
  SoE never holds raw bytes — file upload/download is handled by the calling orchestration layer.

  ## Attributes

  * `id` - UUID primary key
  * `document_type` - Type of document (`:identity_document` | `:proof_of_address` | `:source_of_funds` | `:business_registration` | `:ubo_declaration` | `:pep_declaration` | `:other`)
  * `name` - Form/template name identifying the document slot (e.g. `"kyc_passport"`, `"proof_of_address"`)
  * `description` - Optional human-readable description
  * `status` - Lifecycle state (`:draft` | `:submitted` | `:under_review` | `:accepted` | `:rejected` | `:expired`)
  * `primary` - Whether this is the canonical document for `(account_holder_id, name)`
  * `file_key` - Storage object key (S3/R2 path)
  * `file_name` - Original file name as uploaded
  * `file_size` - File size in bytes
  * `content_type` - MIME type (e.g. `"application/pdf"`, `"image/jpeg"`)
  * `document_number` - Optional opaque external SoE document ID (unique per tenant when set)
  * `metadata` - Arbitrary key-value pairs for caller-specific fields
  * `account_holder_id` - FK to AccountHolder (MDM subject)
  * `tenant_id` - FK to tenant for multi-tenancy isolation (RLS)
  * `inserted_at` - Timestamp when record was created
  * `updated_at` - Timestamp when record was last updated
  """

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @derive {
    Flop.Schema,
    filterable: [
      :id,
      :tenant_id,
      :account_holder_id,
      :document_type,
      :status,
      :primary,
      :name
    ],
    sortable: [:id, :inserted_at, :updated_at, :document_type, :status, :name],
    default_limit: 20,
    max_limit: 100
  }

  # OpenAPI annotations
  open_api_property(schema: %Schema{type: :string, format: :uuid, readOnly: true}, key: :id)

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: [
        "identity_document",
        "proof_of_address",
        "source_of_funds",
        "business_registration",
        "ubo_declaration",
        "pep_declaration",
        "other"
      ]
    },
    key: :document_type
  )

  open_api_property(schema: %Schema{type: :string}, key: :name)

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :description)

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      enum: ["draft", "submitted", "under_review", "accepted", "rejected", "expired"]
    },
    key: :status
  )

  open_api_property(schema: %Schema{type: :boolean}, key: :primary)

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :file_key)

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :file_name)

  open_api_property(schema: %Schema{type: :integer, nullable: true}, key: :file_size)

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :content_type)

  open_api_property(schema: %Schema{type: :string, nullable: true}, key: :document_number)

  open_api_property(schema: %Schema{type: :object, nullable: true}, key: :metadata)

  open_api_property(schema: %Schema{type: :string, format: :uuid}, key: :account_holder_id)

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
    title: "Document",
    description:
      "Compliance document — one row per supporting document for an AccountHolder (ISO 20022 acmt:007 SupportingDocument). " <>
        "Physical files are stored out-of-band; this record holds only the storage reference. " <>
        "At most one document may be primary per (account_holder_id, name) combination.",
    required: [:document_type, :name, :primary, :account_holder_id, :tenant_id],
    properties: [
      :id,
      :document_type,
      :name,
      :description,
      :status,
      :primary,
      :file_key,
      :file_name,
      :file_size,
      :content_type,
      :document_number,
      :metadata,
      :account_holder_id,
      :tenant_id,
      :inserted_at,
      :updated_at
    ]
  )

  typed_schema "documents" do
    field :document_type, Ecto.Enum,
      values: [
        :identity_document,
        :proof_of_address,
        :source_of_funds,
        :business_registration,
        :ubo_declaration,
        :pep_declaration,
        :other
      ]

    field :name, :string

    field :description, :string

    field :status, Ecto.Enum,
      values: [:draft, :submitted, :under_review, :accepted, :rejected, :expired],
      default: :draft

    field :primary, :boolean, default: false

    field :file_key, :string
    field :file_name, :string
    field :file_size, :integer
    field :content_type, :string

    field :document_number, :string

    field :metadata, :map, default: %{}

    belongs_to :account_holder, AccountHolder

    # Multi-tenancy: tenant_id references tenants for RLS
    belongs_to :tenant, Tenant

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(document, attrs) do
    document
    |> cast(attrs, [
      :document_type,
      :name,
      :description,
      :primary,
      :file_key,
      :file_name,
      :file_size,
      :content_type,
      :document_number,
      :metadata,
      :account_holder_id,
      :tenant_id
    ])
    |> maybe_cast_status(attrs)
    |> validate_required([:document_type, :name, :primary, :account_holder_id, :tenant_id])
    |> foreign_key_constraint(:account_holder_id)
    |> foreign_key_constraint(:tenant_id)
    |> unique_constraint([:account_holder_id, :name],
      name: :documents_account_holder_name_primary_unique,
      message: "a primary document already exists for this account holder and name"
    )
    |> unique_constraint(:document_number,
      name: :documents_number_unique,
      message: "has already been taken"
    )
    |> check_constraint(:primary,
      name: :documents_primary_required_before_secondary,
      message: "a primary document must exist before adding a secondary"
    )
  end

  # Only cast status when explicitly provided and non-nil.
  # ExOpenApiUtils.Changeset.cast/3 calls Mapper.to_map internally, which includes all struct
  # fields even when nil. Casting nil status would override the Ecto/DB default of :draft.
  defp maybe_cast_status(changeset, attrs) do
    status = Map.get(attrs, :status)

    if is_nil(status) do
      changeset
    else
      # Use raw Ecto.Changeset.cast to properly coerce through Ecto.Enum
      Ecto.Changeset.cast(changeset, %{status: status}, [:status])
    end
  end
end

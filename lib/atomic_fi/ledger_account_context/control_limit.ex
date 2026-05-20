defmodule AtomicFi.LedgerAccountContext.ControlLimit do
  @moduledoc """
  One control-limit line: a cap for a `{period, direction}` pair, plus the
  rule that set it. The application-side representation of the PostgreSQL
  `control_limit` composite type — see `AtomicFi.Extensions.Ecto.ControlLimitType` /
  `ControlLimitArrayType`.

  Modeled as a `typed_embedded_schema` so untrusted inputs (today: ZenRule's
  JDM decision result over HTTP) can be cast + validated with a real
  changeset rather than blind struct construction. Uses `AtomicFi.Schema` so
  the ExOpenApiUtils `Mapper` protocol can convert it to a plain map on the
  way out — without that, parents like `LedgerEntry.limits_at_entry[]` crash
  on JSON encode with `Protocol.UndefinedError (Jason.Encoder)`.

  ## Fields

    * `period`    — `"daily" | "weekly" | "monthly" | "yearly"`
    * `direction` — `"debit" | "credit"`
    * `cap`       — cap in minor currency units; `nil` = unconstrained
    * `rule`      — name of the rule (engine) that set this cap; `nil` if unset
  """

  use AtomicFi.Schema

  @periods ~w(daily weekly monthly yearly)
  @directions ~w(debit credit)

  open_api_property(
    schema: %Schema{type: :string, enum: ~w(daily weekly monthly yearly)},
    key: :period
  )

  open_api_property(
    schema: %Schema{type: :string, enum: ~w(debit credit)},
    key: :direction
  )

  open_api_property(
    schema: %Schema{
      type: :integer,
      nullable: true,
      description: "Cap in minor currency units; null = unconstrained."
    },
    key: :cap
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      nullable: true,
      description: "Name of the rule (engine) that set this cap; null if unset."
    },
    key: :rule
  )

  open_api_schema(
    title: "ControlLimit",
    description:
      "One control-limit line: a cap for a `{period, direction}` pair plus " <>
        "the rule that set it. Embedded inside `limits_at_entry[]` on " <>
        "LedgerEntry / LedgerAccountBalance responses.",
    required: [:period, :direction],
    properties: [:period, :direction, :cap, :rule]
  )

  @primary_key false
  typed_embedded_schema do
    field :period, :string
    field :direction, :string
    field :cap, :integer
    field :rule, :string
  end

  @doc """
  Casts and validates an untrusted attrs map (string-or-atom keys) into a
  `%ControlLimit{}` changeset. Use `Ecto.Changeset.apply_action(:cast)` to
  realise the struct or surface a `%Changeset{}` error.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(line \\ %__MODULE__{}, attrs) do
    line
    |> cast(attrs, [:period, :direction, :cap, :rule])
    |> validate_required([:period, :direction])
    |> validate_inclusion(:period, @periods)
    |> validate_inclusion(:direction, @directions)
    |> validate_number(:cap, greater_than_or_equal_to: 0)
  end
end

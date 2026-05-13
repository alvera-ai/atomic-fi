defmodule AtomicFi.LedgerAccountContext.VelocityLimit do
  @moduledoc """
  One velocity-limit line: a cap for a `{period, direction}` pair, plus the
  rule that set it. The application-side representation of the PostgreSQL
  `velocity_limit` composite type — see `AtomicFi.Extensions.Ecto.VelocityLimitType` /
  `VelocityLimitArrayType`.

  Modeled as an `embedded_schema` so untrusted inputs (today: ZenRule's JDM
  decision result over HTTP) can be cast + validated with a real changeset
  rather than blind struct construction.

  ## Fields

    * `period`    — `"daily" | "weekly" | "monthly" | "yearly"`
    * `direction` — `"debit" | "credit"`
    * `cap`       — cap in minor currency units; `nil` = unconstrained
    * `rule`      — name of the rule (engine) that set this cap; `nil` if unset
  """

  use Ecto.Schema

  import Ecto.Changeset

  @periods ~w(daily weekly monthly yearly)
  @directions ~w(debit credit)

  @primary_key false
  embedded_schema do
    field :period, :string
    field :direction, :string
    field :cap, :integer
    field :rule, :string
  end

  @type t :: %__MODULE__{
          period: String.t(),
          direction: String.t(),
          cap: non_neg_integer() | nil,
          rule: String.t() | nil
        }

  @doc """
  Casts and validates an untrusted attrs map (string-or-atom keys) into a
  `%VelocityLimit{}` changeset. Use `Ecto.Changeset.apply_action(:cast)` to
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

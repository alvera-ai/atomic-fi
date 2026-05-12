defmodule AtomicFi.LedgerAccountContext.VelocityLimit do
  @moduledoc """
  One velocity-limit line: a cap for a `{period, direction}` pair, plus the rule
  that set it. The application-side representation of the PostgreSQL `velocity_limit`
  composite type — see `AtomicFi.Extensions.Ecto.VelocityLimitType` /
  `VelocityLimitArrayType`.

  ## Fields

    * `period`    — `"daily" | "weekly" | "monthly" | "yearly"`
    * `direction` — `"debit" | "credit"`
    * `cap`       — cap in minor currency units; `nil` = unconstrained
    * `rule`      — name of the rule (engine) that set this cap; `nil` if unset
  """

  @enforce_keys [:period, :direction]
  defstruct [:period, :direction, :cap, :rule]

  @type t :: %__MODULE__{
          period: String.t(),
          direction: String.t(),
          cap: non_neg_integer() | nil,
          rule: String.t() | nil
        }
end

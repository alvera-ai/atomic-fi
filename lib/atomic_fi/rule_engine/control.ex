defmodule AtomicFi.RuleEngine.Control do
  @moduledoc """
  One control — the rule engine's output per LedgerAccount.

  A Control names the eight period × direction caps the rule engine
  has decided apply to a single LedgerAccount, plus the `reason` (which
  rule emitted them). The runtime trigger fans each non-nil cap into
  `ledger_account_balances.last_*_limit`; `CHECK` constraints enforce
  on subsequent entries.

  `nil` for any slot means **unconstrained** in that direction × period.

  Modeled as an `embedded_schema` so untrusted inputs (ZenRule JDM
  results decoded from HTTP) can be cast + validated rather than
  blind struct construction.

  ## Fields

    * `daily_debit_cap`    — minor currency units; daily rolling debit cap
    * `daily_credit_cap`
    * `weekly_debit_cap`
    * `weekly_credit_cap`
    * `monthly_debit_cap`
    * `monthly_credit_cap`
    * `yearly_debit_cap`
    * `yearly_credit_cap`
    * `reason` — which rule emitted these caps
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :daily_debit_cap, :integer
    field :daily_credit_cap, :integer
    field :weekly_debit_cap, :integer
    field :weekly_credit_cap, :integer
    field :monthly_debit_cap, :integer
    field :monthly_credit_cap, :integer
    field :yearly_debit_cap, :integer
    field :yearly_credit_cap, :integer
    field :reason, :string
  end

  @type t :: %__MODULE__{
          daily_debit_cap: non_neg_integer() | nil,
          daily_credit_cap: non_neg_integer() | nil,
          weekly_debit_cap: non_neg_integer() | nil,
          weekly_credit_cap: non_neg_integer() | nil,
          monthly_debit_cap: non_neg_integer() | nil,
          monthly_credit_cap: non_neg_integer() | nil,
          yearly_debit_cap: non_neg_integer() | nil,
          yearly_credit_cap: non_neg_integer() | nil,
          reason: String.t() | nil
        }

  @cap_fields ~w(daily_debit_cap daily_credit_cap weekly_debit_cap weekly_credit_cap
                 monthly_debit_cap monthly_credit_cap yearly_debit_cap yearly_credit_cap)a

  @doc """
  Casts and validates an untrusted attrs map (string-or-atom keys) into
  a `%Control{}` changeset. Use `Ecto.Changeset.apply_action(:cast)` to
  realise the struct or surface a `%Changeset{}` error.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(control \\ %__MODULE__{}, attrs) do
    control
    |> cast(attrs, @cap_fields ++ [:reason])
    |> validate_caps_non_negative()
  end

  @doc """
  Merge two Controls on the same LedgerAccount — slot-by-slot, picking
  the tighter (smaller) cap. `nil` means unconstrained, so any concrete
  cap wins. Reasons concatenate with `; ` so the trigger records every
  rule that contributed.
  """
  @spec tighter(t(), t()) :: t()
  def tighter(%__MODULE__{} = a, %__MODULE__{} = b) do
    %__MODULE__{
      daily_debit_cap: min_cap(a.daily_debit_cap, b.daily_debit_cap),
      daily_credit_cap: min_cap(a.daily_credit_cap, b.daily_credit_cap),
      weekly_debit_cap: min_cap(a.weekly_debit_cap, b.weekly_debit_cap),
      weekly_credit_cap: min_cap(a.weekly_credit_cap, b.weekly_credit_cap),
      monthly_debit_cap: min_cap(a.monthly_debit_cap, b.monthly_debit_cap),
      monthly_credit_cap: min_cap(a.monthly_credit_cap, b.monthly_credit_cap),
      yearly_debit_cap: min_cap(a.yearly_debit_cap, b.yearly_debit_cap),
      yearly_credit_cap: min_cap(a.yearly_credit_cap, b.yearly_credit_cap),
      reason: merge_reasons(a.reason, b.reason)
    }
  end

  defp min_cap(nil, b), do: b
  defp min_cap(a, nil), do: a
  defp min_cap(a, b), do: min(a, b)

  defp merge_reasons(nil, b), do: b
  defp merge_reasons(a, nil), do: a
  defp merge_reasons(a, a), do: a
  defp merge_reasons(a, b), do: "#{a}; #{b}"

  defp validate_caps_non_negative(changeset) do
    Enum.reduce(@cap_fields, changeset, fn field, cs ->
      validate_number(cs, field, greater_than_or_equal_to: 0)
    end)
  end
end

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
    # Hard ceilings — fan out to ledger_accounts.max_*. NULL = infinite.
    field :daily_debit_cap, :integer
    field :daily_credit_cap, :integer
    field :weekly_debit_cap, :integer
    field :weekly_credit_cap, :integer
    field :monthly_debit_cap, :integer
    field :monthly_credit_cap, :integer
    field :yearly_debit_cap, :integer
    field :yearly_credit_cap, :integer

    # Block state — fans out to ledger_accounts.is_blocked / block_reason.
    # is_blocked = true + reason recorded → entry-propagation trigger voids
    # any entry whose ancestor chain touches this LA.
    field :is_blocked, :boolean, default: false
    field :block_reason, :string

    # Which rule emitted this Control (audit + diagnostic).
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
          is_blocked: boolean(),
          block_reason: String.t() | nil,
          reason: String.t() | nil
        }

  @cap_fields ~w(daily_debit_cap daily_credit_cap weekly_debit_cap weekly_credit_cap
                 monthly_debit_cap monthly_credit_cap yearly_debit_cap yearly_credit_cap)a

  @other_fields ~w(is_blocked block_reason reason)a

  @doc """
  Casts and validates an untrusted attrs map (string-or-atom keys) into
  a `%Control{}` changeset. Use `Ecto.Changeset.apply_action(:cast)` to
  realise the struct or surface a `%Changeset{}` error.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(control \\ %__MODULE__{}, attrs) do
    control
    |> cast(attrs, @cap_fields ++ @other_fields)
    |> validate_caps_non_negative()
    |> validate_block_reason_when_blocked()
  end

  defp validate_block_reason_when_blocked(changeset) do
    case {get_field(changeset, :is_blocked), get_field(changeset, :block_reason)} do
      {true, nil} -> add_error(changeset, :block_reason, "is required when is_blocked is true")
      _ -> changeset
    end
  end

  defp validate_caps_non_negative(changeset) do
    Enum.reduce(@cap_fields, changeset, fn field, cs ->
      validate_number(cs, field, greater_than_or_equal_to: 0)
    end)
  end
end

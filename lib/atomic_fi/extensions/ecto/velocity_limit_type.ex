defmodule AtomicFi.Extensions.Ecto.VelocityLimitType do
  @moduledoc """
  Ecto type for the PostgreSQL `velocity_limit` composite type
  `(period varchar, direction varchar, cap bigint, rule varchar)`.

  Maps between `%AtomicFi.LedgerAccountContext.VelocityLimit{}` (app) and the
  4-tuple Postgrex returns/expects for a composite type (db). Modeled on
  `Platform.Extensions.Ecto.TokenizedDataType`.

      field :limits_at_entry, AtomicFi.Extensions.Ecto.VelocityLimitArrayType
  """

  use Ecto.Type

  alias AtomicFi.LedgerAccountContext.VelocityLimit

  @doc false
  @spec type() :: atom()
  def type, do: :velocity_limit

  @doc false
  @spec cast(term()) :: {:ok, VelocityLimit.t() | nil} | :error
  def cast(nil), do: {:ok, nil}
  def cast(%VelocityLimit{} = v), do: {:ok, v}

  def cast(%{} = m) do
    {:ok,
     %VelocityLimit{
       period: m[:period] || m["period"],
       direction: m[:direction] || m["direction"],
       cap: m[:cap] || m["cap"],
       rule: m[:rule] || m["rule"]
     }}
  end

  def cast(_), do: :error

  @doc false
  @spec load(term()) :: {:ok, VelocityLimit.t() | nil} | :error
  def load(nil), do: {:ok, nil}

  def load({period, direction, cap, rule}) do
    {:ok, %VelocityLimit{period: period, direction: direction, cap: cap, rule: rule}}
  end

  def load(_), do: :error

  @doc false
  @spec dump(term()) :: {:ok, tuple() | nil} | :error
  def dump(nil), do: {:ok, nil}
  def dump(%VelocityLimit{} = v), do: {:ok, {v.period, v.direction, v.cap, v.rule}}
  def dump(_), do: :error
end

defmodule AtomicFi.Extensions.Ecto.ControlLimitType do
  @moduledoc """
  Ecto type for the PostgreSQL `control_limit` composite type
  `(period varchar, direction varchar, cap bigint, rule varchar)`.

  Maps between `%AtomicFi.LedgerAccountContext.ControlLimit{}` (app) and the
  4-tuple Postgrex returns/expects for a composite type (db). Modeled on
  `Platform.Extensions.Ecto.TokenizedDataType`.

      field :limits_at_entry, AtomicFi.Extensions.Ecto.ControlLimitArrayType
  """

  use Ecto.Type

  alias AtomicFi.LedgerAccountContext.ControlLimit

  @doc false
  @spec type() :: atom()
  def type, do: :control_limit

  @doc false
  @spec cast(term()) :: {:ok, ControlLimit.t() | nil} | :error
  def cast(nil), do: {:ok, nil}
  def cast(%ControlLimit{} = v), do: {:ok, v}

  def cast(%{} = m) do
    {:ok,
     %ControlLimit{
       period: m[:period] || m["period"],
       direction: m[:direction] || m["direction"],
       cap: m[:cap] || m["cap"],
       rule: m[:rule] || m["rule"]
     }}
  end

  def cast(_), do: :error

  @doc false
  @spec load(term()) :: {:ok, ControlLimit.t() | nil} | :error
  def load(nil), do: {:ok, nil}

  def load({period, direction, cap, rule}) do
    {:ok, %ControlLimit{period: period, direction: direction, cap: cap, rule: rule}}
  end

  def load(_), do: :error

  @doc false
  @spec dump(term()) :: {:ok, tuple() | nil} | :error
  def dump(nil), do: {:ok, nil}
  def dump(%ControlLimit{} = v), do: {:ok, {v.period, v.direction, v.cap, v.rule}}
  def dump(_), do: :error
end

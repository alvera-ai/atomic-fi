defmodule AtomicFi.Extensions.Ecto.VelocityLimitArrayType do
  @moduledoc """
  Ecto type for a PostgreSQL `velocity_limit[]` array. Maps between a list of
  `%AtomicFi.LedgerAccountContext.VelocityLimit{}` (app) and a list of 4-tuples
  (db). Delegates each element to `AtomicFi.Extensions.Ecto.VelocityLimitType`.
  Modeled on `Platform.Extensions.Ecto.TokenizedDataArrayType`.

      field :limits_at_entry, AtomicFi.Extensions.Ecto.VelocityLimitArrayType
  """

  use Ecto.Type

  alias AtomicFi.Extensions.Ecto.VelocityLimitType
  alias AtomicFi.LedgerAccountContext.VelocityLimit

  @type t :: [VelocityLimit.t()]

  @doc false
  @spec type() :: term()
  def type, do: {:array, :velocity_limit}

  @doc false
  @spec cast(term()) :: {:ok, t()} | :error
  def cast(nil), do: {:ok, []}
  def cast(list) when is_list(list), do: map_elements(list, &VelocityLimitType.cast/1)
  def cast(_), do: :error

  @doc false
  @spec load(term()) :: {:ok, t()} | :error
  def load(nil), do: {:ok, []}
  def load(list) when is_list(list), do: map_elements(list, &VelocityLimitType.load/1)
  def load(_), do: :error

  @doc false
  @spec dump(term()) :: {:ok, [tuple()]} | :error
  def dump(nil), do: {:ok, []}
  def dump(list) when is_list(list), do: map_elements(list, &VelocityLimitType.dump/1)
  def dump(_), do: :error

  defp map_elements(list, fun) do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, mapped} -> {:cont, {:ok, acc ++ [mapped]}}
        :error -> {:halt, :error}
      end
    end)
  end
end

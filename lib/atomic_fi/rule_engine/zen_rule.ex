defmodule AtomicFi.RuleEngine.ZenRule do
  @moduledoc """
  `AtomicFi.RuleEngine.Behaviour` implementation backed by the GoRules Agent
  (ZenRule) over HTTP.

  Mirrors `AtomicFi.DecisionContext.ScreeningEngine` — a domain-layer module
  that owns its own config slice and delegates wire I/O to a pure transport
  client (`AtomicFi.ZenRule.Client`, the parallel of `AtomicFi.Watchman.Client`).

  Config (Swoosh-style per-module slice):

      config :atomic_fi, AtomicFi.RuleEngine.ZenRule, base_url: "http://localhost:8090"

  When ZenRule moves to an in-process NIF, this module's `get_limits/1` swaps
  its body to call the NIF; the `AtomicFi.RuleEngine.Behaviour` contract and
  every caller stay unchanged.
  """

  @behaviour AtomicFi.RuleEngine.Behaviour

  alias AtomicFi.LedgerAccountContext.VelocityLimit
  alias AtomicFi.RuleEngine.Payload
  alias AtomicFi.ZenRule.Client
  alias Ecto.Changeset

  @decision "de_minimis.json"

  @impl AtomicFi.RuleEngine.Behaviour
  def get_limits(entity) when is_struct(entity) do
    context = Payload.from_entity(entity)

    with {:ok, result} <- Client.evaluate(base_url(), @decision, context) do
      decode_limits(result)
    end
  end

  defp base_url do
    :atomic_fi
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:base_url)
  end

  defp decode_limits(%{"ledger_accounts" => by_id}) when is_map(by_id) do
    Enum.reduce_while(by_id, {:ok, %{}}, fn {la_id, lines}, {:ok, acc} ->
      case decode_lines(lines) do
        {:ok, decoded} -> {:cont, {:ok, Map.put(acc, la_id, decoded)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp decode_limits(_other), do: {:ok, %{}}

  defp decode_lines(lines) when is_list(lines) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, acc} ->
      case decode_line(line) do
        {:ok, vl} -> {:cont, {:ok, [vl | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end

  defp decode_lines(_), do: {:error, :invalid_lines}

  defp decode_line(%{} = attrs) do
    attrs
    |> VelocityLimit.changeset()
    |> Changeset.apply_action(:cast)
  end
end

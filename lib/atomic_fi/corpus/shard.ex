defmodule AtomicFi.Corpus.Shard do
  @moduledoc """
  Shared shard emitter for `mix corpus.generate.<src>` tasks.

  ## Pipeline

  ```
   Makefile  ──► <CORPUS_OUT>/<src>/<src>.ndjson      (subsetted sample;
                                                       pure-Python upstream
                                                       parsing — Elixir
                                                       never reads CSV
                                                       or parquet)
                                  │
                                  ▼
   mix corpus.generate.<src>      (reads the ndjson sample;
     --in <ndjson>                 calls AtomicFi.Corpus.Shard.emit/2
     --out <sharded_dir>           with a per-source mapper that turns
     --shards K                    sample rows into atomic-fi schema)
                                  │
                                  ▼
   <sharded_dir>/shard-00/{account_holders, counterparties, payment_accounts, transactions}.ndjson
   <sharded_dir>/shard-01/...
   …
   <sharded_dir>/shard-(K-1)/...
                                  │
                                  ▼
   mix corpus.validate            ("poor-man k6" — fans the shard
     <sharded_dir>                 folders across N OS schedulers in
     --concurrency K               parallel, each shard runs as its
                                   own VU with its own id space)
  ```

  ## Why mappers, not a fixed schema mapping

  Each upstream's column shape is different:

    * StableAML — wallet_address blocklist (3-column CSV → small)
    * SAML-D    — sender/receiver accounts + Is_laundering label (CSV → 12 MB)
    * AMLGentex — synthetic transaction-network parquet (sim output)

  Forcing a one-shape-fits-all mapper would erase information the bench
  wants to preserve. Each mix task supplies its own mapper that knows
  the upstream's columns. The shared emitter handles:

    * shard replication (K copies of the same logical corpus, each with
      its own external_id prefix — the "poor-man k6" workload model:
      `corpus.validate <sharded_dir> --concurrency K` then writes through
      K parallel pool checkouts, saturating the engine while each shard
      stays in its own id space).
    * ndjson writes per shard folder

  Splitting rows across shards (each shard gets a different slice) is
  *not* the model — that would just split a single workload. Replication
  produces K-way parallel pressure on the same scenario, which is what
  the upstream-driven bench is for.

  ## Mapper contract

  ```
   mapper.(shard_rows :: [map()], prefix :: String.t())
     :: %{
          account_holders:   [String.t()],
          counterparties:    [String.t()],
          payment_accounts:  [String.t()],
          transactions:      [String.t()]
        }
  ```

  Each list value is already a list of ndjson lines (one JSON object per
  line, no trailing newline). The mapper owns dedup of AH/CP/PA by
  external_id within its shard; the emitter writes the lines as-is.
  `prefix` is the shard-scoped string (e.g. `"s03-"`) the mapper MUST
  prepend to every external_id it emits.
  """

  @entity_files [
    {:account_holders, "account_holders.ndjson"},
    {:counterparties, "counterparties.ndjson"},
    {:payment_accounts, "payment_accounts.ndjson"},
    {:transactions, "transactions.ndjson"}
  ]

  @doc """
  Replicate `rows` into `shards` shard folders under `out`, calling
  `mapper` once per shard with the same `rows` and a shard-unique
  prefix. Returns `:ok`. Logs one line per shard via `Mix.shell/0`.

  Options:

    * `:out`     — sharded output directory (created if missing).
    * `:shards`  — number of shard folders.
    * `:mapper`  — `(rows, prefix) -> %{account_holders:, counterparties:,
                   payment_accounts:, transactions:}` (see moduledoc).
  """
  @spec emit([map()], keyword()) :: :ok
  def emit(rows, opts) when is_list(rows) do
    out = Keyword.fetch!(opts, :out)
    shards = Keyword.fetch!(opts, :shards)
    mapper = Keyword.fetch!(opts, :mapper)

    File.mkdir_p!(out)

    Enum.each(0..(shards - 1), fn shard_idx ->
      shard_dir = Path.join(out, shard_name(shard_idx, shards))
      File.mkdir_p!(shard_dir)
      prefix = shard_prefix(shard_idx, shards)

      lines = mapper.(rows, prefix)

      Enum.each(@entity_files, fn {key, filename} ->
        entity_lines = Map.get(lines, key, [])
        write_lines(Path.join(shard_dir, filename), entity_lines)
      end)

      Mix.shell().info(
        "  shard #{shard_idx}: " <>
          Enum.map_join(@entity_files, ", ", fn {key, _} ->
            "#{key}=#{length(Map.get(lines, key, []))}"
          end) <>
          "  → #{shard_dir}"
      )
    end)

    Mix.shell().info("✓ wrote #{shards} replicated shard(s) to #{out}")
    :ok
  end

  @doc """
  Reads an NDJSON file into a list of decoded maps. Each non-empty line
  is `Jason.decode!/1`'d. Used by every `corpus.generate.<src>` task.
  """
  @spec read_ndjson!(Path.t()) :: [map()]
  def read_ndjson!(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&Jason.decode!/1)
    |> Enum.to_list()
  end

  defp write_lines(_path, []), do: :ok

  defp write_lines(path, lines) do
    File.write!(path, Enum.join(lines, "\n") <> "\n")
  end

  defp shard_name(idx, total) do
    "shard-" <> pad(idx, total)
  end

  defp shard_prefix(idx, total) do
    "s" <> pad(idx, total) <> "-"
  end

  defp pad(idx, total) do
    width = total |> Integer.to_string() |> String.length() |> max(2)
    idx |> Integer.to_string() |> String.pad_leading(width, "0")
  end
end

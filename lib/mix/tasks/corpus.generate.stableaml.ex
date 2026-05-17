defmodule Mix.Tasks.Corpus.Generate.Stableaml do
  @shortdoc "Sample StableAML sanctioned-wallets CSV → deterministic NDJSON"

  @moduledoc """
  Reads the FINOS Labs StableAML Category-1 (sanctioned wallets) CSV and
  emits a seeded random sample as NDJSON. Same `(seed, wallets, in)` →
  byte-identical output.

  Source layout (populated by `make reseed-stableaml`):

      $CORPUS_ROOT/stableaml/address_sanctioned.csv
        — three columns, no header: blockchain, wallet_address, flag
        — Category 1: OFAC-listed, SEC-flagged, Tether/Circle-frozen wallets
        — 807 rows, ~52 kB

  Output layout (deterministic per `(seed, --wallets)` slice):

      tmp/corpus/<seed>/stableaml/wallet_addresses.ndjson
        — one row per sampled wallet:
          {"blockchain": "...", "wallet_address": "0x...", "flag": "...",
           "_label": {"source": "stableaml", "category": "sanctioned"}}

  ## Usage

      $ mix corpus.generate.stableaml                          # 100 wallets, seed=0
      $ mix corpus.generate.stableaml --wallets 500 --seed 42
      $ mix corpus.generate.stableaml --in /custom/sanc.csv --out tmp/foo
      $ mix corpus.generate.stableaml --wallets all            # emit every row

  ## Options

    * `--seed <int>`     — RNG seed (default 0). Same seed + same input
                           file = byte-identical output.
    * `--wallets <N|all>` — number of rows to sample (default 100). The
                            literal `all` emits every row in source order.
    * `--in <path>`      — path to address_sanctioned.csv (default
                           `$CORPUS_ROOT/stableaml/address_sanctioned.csv`,
                           where CORPUS_ROOT is `$ATOMIC_FI_CORPUS_ROOT`
                           or `~/.local/share/atomic-fi/corpus`).
    * `--out <path>`     — output directory (default
                           `tmp/corpus/<seed>/stableaml/`).

  No external service contact, no docker — pure file I/O. Run
  `make reseed-stableaml` first to populate the source CSV.
  """

  use Mix.Task

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [seed: :integer, wallets: :string, in: :string, out: :string]
      )

    seed = Keyword.get(opts, :seed, 0)
    wallets = parse_wallets(Keyword.get(opts, :wallets, "100"))
    in_path = Keyword.get(opts, :in, default_in_path())
    out_dir = Keyword.get(opts, :out, default_out_dir(seed))

    rows = read_csv!(in_path)
    sampled = sample(rows, wallets, seed)

    File.mkdir_p!(out_dir)
    out_path = Path.join(out_dir, "wallet_addresses.ndjson")
    write_ndjson!(out_path, sampled)

    Mix.shell().info(
      "→ wrote #{length(sampled)} / #{length(rows)} rows to #{out_path} (seed=#{seed})"
    )
  end

  defp default_in_path do
    root =
      System.get_env("ATOMIC_FI_CORPUS_ROOT") ||
        Path.join(System.user_home!(), ".local/share/atomic-fi/corpus")

    Path.join([root, "stableaml", "address_sanctioned.csv"])
  end

  defp default_out_dir(seed),
    do: Path.join(["tmp", "corpus", Integer.to_string(seed), "stableaml"])

  defp parse_wallets("all"), do: :all
  defp parse_wallets(str), do: String.to_integer(str)

  defp read_csv!(path) do
    unless File.exists?(path) do
      Mix.raise(
        "StableAML CSV not found at #{path}\n" <>
          "Run `make reseed-stableaml` to fetch it, or pass --in <path>."
      )
    end

    path
    |> File.stream!()
    |> Stream.map(&String.trim_trailing(&1, "\n"))
    |> Stream.reject(&(&1 == ""))
    |> Enum.map(&parse_row!/1)
  end

  defp parse_row!(line) do
    case String.split(line, ",", parts: 3) do
      [blockchain, wallet_address, flag] ->
        %{"blockchain" => blockchain, "wallet_address" => wallet_address, "flag" => flag}

      _ ->
        Mix.raise("malformed CSV row (expected 3 comma-separated fields): #{inspect(line)}")
    end
  end

  defp sample(rows, :all, _seed), do: rows

  defp sample(rows, n, _seed) when is_integer(n) and n >= length(rows), do: rows

  defp sample(rows, n, seed) when is_integer(n) and n > 0 do
    # Seeded shuffle: same (seed, rows) → same ordering.
    _ = :rand.seed(:exsss, {seed, seed, seed})

    rows
    |> Enum.map(&{:rand.uniform(), &1})
    |> Enum.sort()
    |> Enum.take(n)
    |> Enum.map(fn {_, row} -> row end)
  end

  defp write_ndjson!(path, rows) do
    body =
      rows
      |> Enum.map(&Jason.encode!(label_row(&1)))
      |> Enum.intersperse("\n")

    File.write!(path, [body, "\n"])
  end

  defp label_row(row) do
    Map.put(row, "_label", %{
      "source" => "stableaml",
      "category" => "sanctioned",
      "regime" => "ofac",
      "cite" => "31 CFR §501.404"
    })
  end
end

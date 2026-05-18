defmodule AtomicFi.Corpus.SyntheticSeed do
  @moduledoc """
  Deterministic synthetic NDJSON generators for the hermetic
  `mix corpus.bench` flow.

  Real-world reseeds (`make reseed-saml-d` / `make reseed-amlgentex`)
  require external tooling (Kaggle CLI, Python + uv, the AMLGentex
  simulator). For CI / quick-bench / FAA-style reproducibility we want
  a zero-dependency path: the synthetic seed is hardcoded in this
  module, expanded from a fixed RNG seed at runtime, and consumed by
  the same `mix corpus.generate.<src>` pipelines the real-data path
  uses. The Elixir source IS the seed; nothing is committed under
  `corpus/` except the resulting `proof.md`.

  Schemas mirror the real upstreams' column shapes so the downstream
  mix tasks (`corpus.generate.saml_d`, `corpus.generate.amlgentex`)
  read either source identically.
  """

  @doc """
  Synthetic SAML-D-shape rows. Matches the column shape documented in
  `corpus/upstream/saml-d/manifest.json`:

      Time, Date, Sender_account, Receiver_account, Amount,
      Payment_currency, Received_currency, Sender_bank_location,
      Receiver_bank_location, Payment_type, Is_laundering, Laundering_type

  Determinism: `(rows, seed) -> identical NDJSON list every run`.
  """
  @spec saml_d(non_neg_integer(), non_neg_integer()) :: [map()]
  def saml_d(rows, seed) do
    :rand.seed(:exsss, {seed, seed * 7919, seed * 6151})

    Enum.map(1..rows, fn idx ->
      sender_idx = rem(idx * 31, max(div(rows, 4), 1))
      receiver_idx = rem(idx * 17, max(div(rows, 3), 1))
      laundering_pick = :rand.uniform(100)

      {is_laundering, laundering_type} =
        cond do
          laundering_pick <= 2 -> {1, "Smurfing"}
          laundering_pick <= 4 -> {1, "Structuring"}
          laundering_pick <= 5 -> {1, "Layering"}
          true -> {0, "Normal"}
        end

      payment_type =
        Enum.random([
          "Cash Deposit",
          "ACH",
          "Wire Transfer",
          "Credit Card",
          "Cheque"
        ])

      amount = saml_d_amount(laundering_type)

      %{
        "Time" => "12:#{:io_lib.format("~2..0B", [rem(idx, 60)]) |> IO.iodata_to_binary()}:00",
        "Date" =>
          "2026-04-#{:io_lib.format("~2..0B", [rem(idx, 28) + 1]) |> IO.iodata_to_binary()}",
        "Sender_account" => "SND-#{pad(sender_idx, 6)}",
        "Receiver_account" => "RCV-#{pad(receiver_idx, 6)}",
        "Amount" => amount,
        "Payment_currency" => "USD",
        "Received_currency" => "USD",
        "Sender_bank_location" => "US",
        "Receiver_bank_location" => "US",
        "Payment_type" => payment_type,
        "Is_laundering" => is_laundering,
        "Laundering_type" => laundering_type
      }
    end)
  end

  @doc """
  Synthetic AMLGentex-shape rows. Field names match the simulator's
  common output (Sender / Receiver / Amount / Currency / Timestamp /
  Is_SAR) so `mix corpus.generate.amlgentex`'s forgiving extractor
  reads them identically to real sim output.
  """
  @spec amlgentex(non_neg_integer(), non_neg_integer()) :: [map()]
  def amlgentex(rows, seed) do
    :rand.seed(:exsss, {seed * 11, seed * 13, seed * 17})

    Enum.map(1..rows, fn idx ->
      sender_idx = rem(idx * 23, max(div(rows, 4), 1))
      receiver_idx = rem(idx * 19, max(div(rows, 5), 1))
      sar_pick = :rand.uniform(100)

      is_sar =
        cond do
          sar_pick <= 5 -> 1
          true -> 0
        end

      amount = amlgentex_amount(is_sar)

      %{
        "Sender" => "AG-S-#{pad(sender_idx, 6)}",
        "Receiver" => "AG-R-#{pad(receiver_idx, 6)}",
        "Amount" => amount,
        "Currency" => "USD",
        "Timestamp" =>
          "2026-04-#{:io_lib.format("~2..0B", [rem(idx, 28) + 1]) |> IO.iodata_to_binary()}T12:00:00Z",
        "Is_SAR" => is_sar,
        "pattern_type" => if(is_sar == 1, do: "fan_out", else: "normal")
      }
    end)
  end

  # Amount distributions:
  #
  #   Smurfing    — many small payments (USD 500-3000), the same band
  #                 the smurfing_pattern_sar_eligible rule (#20) trips on.
  #   Structuring — sub-CTR splits (USD 5000-9999) per the ctr_structuring
  #                 rule (#19).
  #   Layering    — round-trip mid-band (USD 1000-50000).
  #   Normal      — wide band (USD 10-25000).
  defp saml_d_amount("Smurfing"), do: 500 + :rand.uniform(2500)
  defp saml_d_amount("Structuring"), do: 5000 + :rand.uniform(4999)
  defp saml_d_amount("Layering"), do: 1000 + :rand.uniform(49_000)
  defp saml_d_amount(_normal), do: 10 + :rand.uniform(25_000)

  defp amlgentex_amount(1), do: 100 + :rand.uniform(5000)
  defp amlgentex_amount(_normal), do: 50 + :rand.uniform(20_000)

  defp pad(n, width),
    do: n |> Integer.to_string() |> String.pad_leading(width, "0")
end

# scripts/ast_rewrite_scripts/drop_legal_entity_id_from_request_structs_and_inserts.exs
#
# Issue #31 sweep 2: the AH/CP/BO ↔ LegalEntity FK direction was flipped.
# AccountHolder / Counterparty / BeneficialOwner no longer have a
# `legal_entity_id` column — LE carries the FK back via `account_holder_id`
# / `counterparty_id` / `beneficial_owner_id` (discriminated by `subject_type`).
#
# This script drops every stale `legal_entity_id:` usage that no longer
# compiles or makes sense after the flip:
#
#   1. Struct literals — drop the key from any
#        %AccountHolderRequest{…, legal_entity_id: …, …}
#        %CounterpartyRequest{…, legal_entity_id: …, …}
#        %BeneficialOwnerRequest{…, legal_entity_id: …, …}
#
#   2. ExMachina insert calls — drop `legal_entity_id: …` from kwlist args to
#        insert(:account_holder, …)
#        insert(:counterparty, …)
#        insert(:beneficial_owner, …)
#      Including module-qualified forms (e.g. `Factory.insert(:account_holder, …)`).
#
# **Out of scope** — other tables still carry a valid `legal_entity_id` FK to
# LegalEntity itself: KycRequirement / Document / LegalEntityChangeEvent /
# LegalEntity{Address,PhoneNumber,Identification}. Their factory atoms
# (`:kyc_requirement`, `:document`, `:legal_entity_change_event`, …) are NOT
# in the @factories list below, so the script ignores them.
#
# Uses Sourceror for parse/emit — preserves heredocs, comments, and most
# original formatting (Macro.to_string would have flattened heredocs into
# single-line strings).
#
# Run (dry):  mix run --no-start scripts/ast_rewrite_scripts/drop_legal_entity_id_from_request_structs_and_inserts.exs --dry-run
# Apply:      mix run --no-start scripts/ast_rewrite_scripts/drop_legal_entity_id_from_request_structs_and_inserts.exs
# Verify:     mix format && mix compile --warnings-as-errors

{:ok, _} = Application.ensure_all_started(:sourceror)

defmodule DropLegalEntityIdFromRequestStructsAndInserts do
  @moduledoc false

  @request_struct_shortnames ~w(AccountHolderRequest CounterpartyRequest BeneficialOwnerRequest)

  @factories ~w(account_holder counterparty beneficial_owner)a

  def rewrite(source) do
    source
    |> Sourceror.parse_string!()
    |> Macro.prewalk(&transform/1)
    |> Sourceror.to_string()
    |> ensure_trailing_newline()
  end

  # ── struct literals: %ModName{...} ───────────────────────────────────────
  #
  # Sourceror's preserving parser wraps literals (atoms, strings, etc.) in
  # `{:__block__, meta, [value]}` to track formatting. The patterns below
  # match those wrapped forms. Use `unwrap_atom/1` to compare against bare
  # atom names.
  defp transform({:%, m, [{:__aliases__, _, alias_parts} = aliased, {:%{}, mm, kv}]} = node)
       when is_list(kv) do
    short = alias_parts |> List.last() |> to_string()

    if short in @request_struct_shortnames do
      case drop_legal_entity_id_kv(kv) do
        ^kv -> node
        stripped -> {:%, m, [aliased, {:%{}, mm, stripped}]}
      end
    else
      node
    end
  end

  # ── insert(:atom, [kw...]) — local call ───────────────────────────────────
  defp transform({:insert, m, [factory_node, kw]} = node) when is_list(kw) do
    if unwrap_atom(factory_node) in @factories do
      case drop_legal_entity_id_kv(kw) do
        ^kw -> node
        stripped -> {:insert, m, [factory_node, stripped]}
      end
    else
      node
    end
  end

  # ── Module.insert(:atom, [kw...]) ─────────────────────────────────────────
  defp transform({{:., dm, [module, :insert]}, m, [factory_node, kw]} = node)
       when is_list(kw) do
    if unwrap_atom(factory_node) in @factories do
      case drop_legal_entity_id_kv(kw) do
        ^kw -> node
        stripped -> {{:., dm, [module, :insert]}, m, [factory_node, stripped]}
      end
    else
      node
    end
  end

  defp transform(other), do: other

  defp drop_legal_entity_id_kv(kw) do
    Enum.reject(kw, fn
      {key, _value} -> unwrap_atom(key) == :legal_entity_id
      _ -> false
    end)
  end

  defp unwrap_atom({:__block__, _, [atom]}) when is_atom(atom), do: atom
  defp unwrap_atom(atom) when is_atom(atom), do: atom
  defp unwrap_atom(_), do: nil

  defp ensure_trailing_newline(src) do
    if String.ends_with?(src, "\n"), do: src, else: src <> "\n"
  end
end

# ── driver ────────────────────────────────────────────────────────────────

dry_run? = "--dry-run" in System.argv()

candidates =
  ["lib/**/*.{ex,exs}", "test/**/*.{ex,exs}"]
  |> Enum.flat_map(&Path.wildcard/1)
  |> Enum.filter(fn path ->
    src = File.read!(path)
    String.contains?(src, "legal_entity_id")
  end)

IO.puts("scanning #{length(candidates)} candidate files…")

{stats, _} =
  Enum.map_reduce(candidates, nil, fn path, _acc ->
    orig = File.read!(path)
    rewritten = DropLegalEntityIdFromRequestStructsAndInserts.rewrite(orig)

    cond do
      rewritten == orig ->
        {{path, :unchanged}, nil}

      dry_run? ->
        IO.puts("[dry-run] would rewrite #{path}")
        {{path, :would_change}, nil}

      true ->
        File.write!(path, rewritten)
        IO.puts("✔ rewrote #{path}")
        {{path, :changed}, nil}
    end
  end)

changed = Enum.count(stats, fn {_p, s} -> s in [:changed, :would_change] end)
unchanged = length(stats) - changed
IO.puts("changed: #{changed}  unchanged: #{unchanged}")

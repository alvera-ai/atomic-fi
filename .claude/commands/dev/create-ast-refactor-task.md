---
name: create-ast-refactor-task
description: Create a one-shot AST refactoring script using Rewrite + stdlib (Code + Macro)
when_to_use:
  - Mechanical multi-file Elixir code transformations
  - Renaming functions, variables, or module references across files
  - Injecting or removing code patterns across many files
  - Any refactor touching 3+ files that should be automated
related_guides:
  - guides/cheatsheet/developer_guide.cheatmd
  - guides/cheatsheet/quality_gates.cheatmd
related_commands:
  - /qa:quality-checks (run after applying the task)
---
# Recipe: Create One-Shot AST Refactoring Script

Create a disposable script under `scripts/ast_rewrite_scripts/` that uses
**`Rewrite`** (for file enumeration + transactional writes) + **stdlib**
(`Code.string_to_quoted!/2` for parsing, `Macro.prewalk/2` for traversal,
`Macro.to_string/1` for rendering) to perform mechanical Elixir code
transformations.

**No Sourceror.** Sourceror was tried earlier; we now parse/render via stdlib
and re-normalize via `mix format` as the final step. Sourceror is not a direct
dep — it only ships transitively through Rewrite for Rewrite's internal use.
Do not call `Sourceror.*` in new scripts.

## Rules

1. **Use `Rewrite` for file I/O and source management.** Never read/write
   Elixir source files via `File.read!`/`File.write!` directly. Rewrite tracks
   original vs. modified content and handles batch writes via
   `Rewrite.write_all/1`. Each source's `:content` holds the string; you parse
   it with `Code.string_to_quoted!/2`, transform, and `Rewrite.Source.update/3`
   the `:content` back.
2. **Use stdlib `Macro.prewalk/2` for AST traversal** with pattern-matched
   function heads. Return the transformed node to replace, or the original node
   to leave unchanged. No zipper library.
3. **NEVER use sed, regex, or hand-rolled string replacement** for Elixir code
   with semantic meaning. Pure string transforms are acceptable only when the
   change is a trivial token swap AND AST roundtripping would destroy
   formatting the authors care about (e.g. `@moduledoc` heredocs). See the
   `migrate_controllers_to_flop_search_param.exs` header for the bar.
4. **Support `--dry-run`** — print `would_change`/`changed`/`unchanged` for
   every file before applying.
5. **One-shot scripts are disposable** — add a header comment stating it has
   been applied; delete or move to `scripts/ast_rewrite_scripts/archive/`
   after the merge commit lands.
6. **Place in `scripts/ast_rewrite_scripts/`** — not `lib/mix/tasks/` (these
   are ad-hoc scripts, not durable Mix tasks).
7. **Always `mix format` after** — `Macro.to_string` output differs from the
   project formatter and must be re-normalized.
8. **Pre-filter files** — only roundtrip files that actually contain the
   target pattern (text-level `String.contains?` check before parsing). Avoids
   reformat churn in unrelated files.

## Reference Implementations

Three scripts are kept in-tree as exemplars. Read them before writing a new
one:

| Script | Pattern | Use as reference for |
|---|---|---|
| `scripts/ast_rewrite_scripts/convert_interop_contracts_to_rls_macro.exs` | **PRIMARY.** Rewrite + stdlib, two-pass, converts plain `def` to macro wrappers with session-first arg, rewrites all caller sites, multi-clause dispatch via private `do_FN_NAME`. | Flagship — large semantic refactor, function-signature change, macro wrapping, cross-file caller updates |
| `scripts/ast_rewrite_scripts/replace_nil_session_in_interop_tests.exs` | Rewrite + stdlib, two-pass: rewrite call sites + inject `session` into test heads based on body-reference detection. Dry-run + apply modes. | Two-pass pattern where pass 2 depends on pass 1 analysis |
| `scripts/ast_rewrite_scripts/migrate_controllers_to_flop_search_param.exs` | **Pure string transform exception.** Documents why AST was rejected (formatting preservation of large `@moduledoc` blocks). | The bar for *not* using AST. Read the header first; threshold is high. |

## Template (Rewrite + stdlib)

```elixir
# scripts/ast_rewrite_scripts/your_refactor.exs — delete after successful merge
#
# One-line description of what this does.
#
# Run (dry):  mix run --no-start scripts/ast_rewrite_scripts/your_refactor.exs --dry-run
# Apply:      mix run --no-start scripts/ast_rewrite_scripts/your_refactor.exs
# Verify:     mix format && mix compile --warnings-as-errors && mix test

{:ok, _} = Application.ensure_all_started(:rewrite)

target_files = [
  # list paths, or compute via Path.wildcard/1
]

defmodule YourRewriter do
  @moduledoc false

  def rewrite(source) do
    ast = Code.string_to_quoted!(source, columns: true)

    ast
    |> Macro.prewalk(&transform/1)
    |> Macro.to_string()
  end

  defp transform({:foo, meta, [arg]}), do: {:bar, meta, [arg]}
  defp transform(other), do: other
end

dry_run? = "--dry-run" in System.argv()

# Pre-filter: skip files that don't contain the target token — avoids
# Macro.to_string reformat churn in unrelated files.
candidates =
  target_files
  |> Enum.filter(&File.exists?/1)
  |> Enum.filter(fn path -> String.contains?(File.read!(path), "foo") end)

project = Rewrite.new!(candidates)

{project, stats} =
  Enum.reduce(candidates, {project, []}, fn path, {proj, acc} ->
    src = Rewrite.source!(proj, path)
    orig = Rewrite.Source.get(src, :content)
    rewritten = YourRewriter.rewrite(orig)

    cond do
      rewritten == orig ->
        {proj, [{path, :unchanged} | acc]}

      dry_run? ->
        IO.puts("[dry-run] would rewrite #{path}")
        {proj, [{path, :would_change} | acc]}

      true ->
        updated = Rewrite.Source.update(src, :content, rewritten)
        {Rewrite.update!(proj, updated), [{path, :changed} | acc]}
    end
  end)

unless dry_run? do
  case Rewrite.write_all(project) do
    {:ok, _} ->
      IO.puts("✔ wrote changes")

    {:error, reason} ->
      IO.puts("✗ write failed")
      Enum.each(List.wrap(reason), &IO.puts("  #{inspect(&1)}"))
      System.halt(1)
  end
end

IO.inspect(Enum.reverse(stats), label: :summary)
```

**Why Rewrite over raw `File.read!` + `File.write!`?**

- **Atomicity.** `Rewrite.write_all/1` writes all modified sources at once —
  no orphaned half-written states if the script crashes mid-file.
- **Change tracking.** `Rewrite.Source` keeps both the original and the
  modified content, enabling `content == orig` idempotency checks without a
  second file read.
- **Uniform reducer shape.** The pattern cleanly handles per-file skip /
  would_change / changed summaries in one pass.

## Workflow

1. **Identify the pattern.** Find 2-3 concrete examples manually by grepping.
2. **Write the script** in `scripts/ast_rewrite_scripts/` following the
   template above.
3. **Dry-run** — `mix run --no-start scripts/ast_rewrite_scripts/your.exs --dry-run`.
   Verify the `would_change` count matches your grep count.
4. **Apply** — drop `--dry-run`.
5. **Verify** —
   `mix format && mix compile --warnings-as-errors && mix test path/to/affected_test.exs`.
6. **Commit** both the transformed files AND the script file (with a header
   stating it's been applied).
7. **Post-merge** — delete the script or move it to
   `scripts/ast_rewrite_scripts/archive/`.

## Elixir AST Quick Reference

```elixir
# Function call: Module.func(a, b)
{{:., meta, [{:__aliases__, meta, [:Module]}, :func]}, meta, [a, b]}

# Variable reference: my_var
{:my_var, meta, nil}

# Keyword pair in a list: foo: :bar
{:foo, :bar}

# Block: multiple statements
{:__block__, meta, [stmt1, stmt2, stmt3]}

# Map literal: %{foo: :bar}
{:%{}, meta, [{:foo, :bar}]}
```

## Common Mistakes

- **Using `File.read!` + `File.write!` directly.** You lose batch atomicity
  and the clean skip/change summary. Always wrap in `Rewrite.new!` +
  `Rewrite.Source`.
- **Calling `Sourceror.*`.** Off-design. Use `Code.string_to_quoted!/2` +
  `Macro.to_string/1` instead.
- **Skipping the pre-filter.** `Macro.to_string` reformats every file it
  touches, even ones with no matches. Always text-prefilter before parsing.
- **Forgetting the fallback clause.** `Macro.prewalk` visits every node —
  your transform function needs a catch-all `defp transform(other), do: other`
  or the traversal crashes.
- **Forgetting `columns: true`.** Without it, parse errors lack column info
  and debugging becomes guesswork.
- **Forgetting `mix format` after applying.** `Macro.to_string` output differs
  from project style; always normalize.
- **Forgetting `Application.ensure_all_started(:rewrite)`** at the top.
  Without it, `Rewrite.new!` fails cryptically.

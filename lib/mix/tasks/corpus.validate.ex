defmodule Mix.Tasks.Corpus.Validate do
  @shortdoc "Replays a corpus folder against the live atomic-fi write path and prints a markdown drift report"

  @moduledoc """
  Walks a corpus folder of NDJSON files, inserts the entity graph through the
  production contexts, then creates each transaction and diffs the resulting
  `%Transaction{}` state against the row's inline `_expected` block.

  Corpus folder layout:

      corpus/<group>/<corpus_slug>/
        account_holders.ndjson    one AccountHolderRequest-shaped row per line
                                  (external_id is the stable handle)
        counterparties.ndjson     CounterpartyRequest rows; reference parent AH
                                  via `account_holder_external_id`
        payment_accounts.ndjson   PaymentAccountRequest rows; reference parent
                                  via `account_holder_external_id` or
                                  `counterparty_external_id`
        transactions.ndjson       TransactionRequest rows. Reference parents
                                  via `*_external_id` keys. Each row carries
                                  inline `_label` (regime/cite/scenario) and
                                  `_expected` (the Transaction fields to
                                  assert: status, rejected_rule, …).

  Usage:

      $ mix corpus.validate corpus/zen_rules/de_minimis_stablecoin
      $ mix corpus.validate corpus/zen_rules/de_minimis_stablecoin --out tmp/report.md
      $ mix corpus.validate corpus/zen_rules/de_minimis_stablecoin --reset

  Always runs inside a dedicated Postgres schema (see `@schema`) — the
  platform's main schema is never touched. The schema is created and
  migrated on first run. `--reset` drops and re-migrates the schema before
  validating, giving a clean slate.

  The default prints the markdown report to stdout — useful for piping or
  for monitoring progress (per-row progress info is emitted on stderr as
  inserts happen, the report block follows at the end on stdout).

  Requires the backing services up (`make run-backing-services`) — ZenRule,
  Postgres, Watchman. The task inserts via `AccountHolderContext.create_account_holder/2`
  etc. so the full onboarding + rule-engine path runs.

  Rows persist across runs (no `Repo.transaction` wrap). The insert phase
  is idempotent on `external_id`: existing rows are updated. Use `--reset`
  to start from a clean slate.
  """

  use Mix.Task

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.Config
  alias AtomicFi.CounterpartyContext
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  alias AtomicFi.OpenApiSchema.CounterpartyRequest
  alias AtomicFi.OpenApiSchema.PaymentAccountRequest
  alias AtomicFi.OpenApiSchema.TransactionRequest
  alias AtomicFi.PaymentAccountContext
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.Repo
  alias AtomicFi.RoleContext.RoleConstants
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.TenantContext.Tenant
  alias AtomicFi.TransactionContext

  # Dedicated Postgres schema for corpus runs. Never touches `public` or
  # the platform's main schema. Owned end-to-end by this task: created,
  # migrated, dropped here. Search_path falls back to `public` so the
  # pgcrypto extension (gen_random_uuid) is reachable.
  @schema "atomic_fi_corpus"
  @search_path "#{@schema}, public"

  @impl true
  def run(args) do
    {opts, positional, _} =
      OptionParser.parse(args, strict: [out: :string, reset: :boolean])

    corpus_path =
      List.first(positional) ||
        Mix.raise("usage: mix corpus.validate <corpus_path> [--out <file>] [--reset]")

    unless File.dir?(corpus_path),
      do: Mix.raise("corpus folder not found: #{corpus_path}")

    inject_search_path_after_connect!()

    Mix.Task.run("app.start")

    ensure_schema!(opts[:reset])

    session = build_system_session()
    AtomicFi.BlocklistContext.BlocklistCache.refresh_tenant_cache(session.tenant_id)

    Mix.shell().info("→ inserting account_holders.ndjson")
    insert_account_holders(session, corpus_path)

    Mix.shell().info("→ inserting counterparties.ndjson")
    insert_counterparties(session, corpus_path)

    Mix.shell().info("→ inserting payment_accounts.ndjson")
    insert_payment_accounts(session, corpus_path)

    Mix.shell().info("→ bootstrap: unblock LedgerAccounts (no onboarding rule corpus)")
    bootstrap_unblock_ledger_accounts()

    Mix.shell().info("→ creating transactions.ndjson")
    rows = process_transactions(session, corpus_path)

    report = render_markdown(corpus_path, rows)

    case opts[:out] do
      nil ->
        IO.write(report)

      path ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, report)
        Mix.shell().info("✓ Wrote validation report to #{path}")
    end

    if Enum.any?(rows, &(&1.status in [:mismatch, :engine_error, :setup_error])) do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  # ───────────────────────────── schema isolation ─────────────────────

  # Inject an `after_connect` callback into the Repo config BEFORE the
  # app starts. Every pool checkout will SET search_path so all Repo
  # queries land in the corpus schema. Idempotent — re-setting the same
  # key is harmless.
  defp inject_search_path_after_connect! do
    repo_cfg = Application.get_env(:atomic_fi, Repo, [])

    Application.put_env(
      :atomic_fi,
      Repo,
      Keyword.put(
        repo_cfg,
        :after_connect,
        {Postgrex, :query!, ["SET search_path TO #{@search_path}", []]}
      )
    )
  end

  # Ensure the corpus schema exists and is fully migrated. On `--reset`
  # (or when the schema is missing), drop and recreate, then run the
  # configured migration paths (base migrations + seed_migrations).
  # Migrations create their objects unqualified, so they land in the
  # corpus schema (first on the connection's search_path).
  defp ensure_schema!(reset?) do
    cond do
      reset? ->
        Mix.shell().info("→ --reset: dropping #{@schema} and remigrating")
        drop_schema!()
        create_schema!()
        migrate!()

      schema_exists?() ->
        :ok

      true ->
        Mix.shell().info("→ first run: creating #{@schema} and migrating")
        create_schema!()
        migrate!()
    end
  end

  defp schema_exists? do
    %{rows: [[exists?]]} =
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = $1)",
        [@schema]
      )

    exists?
  end

  defp drop_schema! do
    Ecto.Adapters.SQL.query!(Repo, "DROP SCHEMA IF EXISTS #{@schema} CASCADE", [])
  end

  defp create_schema! do
    Ecto.Adapters.SQL.query!(Repo, "CREATE SCHEMA #{@schema}", [])
  end

  defp migrate! do
    paths =
      :atomic_fi
      |> Application.fetch_env!(:migration_paths)
      |> Map.fetch!(Repo)

    for path <- paths do
      Mix.shell().info("   migrate: #{path}")
      Ecto.Migrator.run(Repo, path, :up, all: true)
    end
  end

  # ───────────────────────────── inserts ──────────────────────────────

  defp insert_account_holders(session, corpus_path) do
    corpus_path
    |> read_ndjson("account_holders.ndjson")
    |> Enum.each(fn row ->
      ext_id = row["external_id"]

      request =
        row
        |> Map.put("chain_screening", false)
        |> stamp_tenant(session.tenant_id)
        |> to_request(AccountHolderRequest)

      case AccountHolderContext.get_account_holder_by_external_id(session, ext_id) do
        nil ->
          Mix.shell().info("   AH #{ext_id} [create]")

          case AccountHolderContext.create_account_holder(session, request) do
            {:ok, _ah} -> :ok
            {:error, reason} -> Mix.raise("AH create failed for #{ext_id}: #{inspect(reason)}")
          end

        existing ->
          Mix.shell().info("   AH #{ext_id} [update]")

          case AccountHolderContext.update_account_holder(session, existing, request) do
            {:ok, _ah} -> :ok
            {:error, reason} -> Mix.raise("AH update failed for #{ext_id}: #{inspect(reason)}")
          end
      end
    end)
  end

  defp insert_counterparties(session, corpus_path) do
    corpus_path
    |> read_ndjson("counterparties.ndjson")
    |> Enum.each(fn row ->
      number = row["external_id"]
      ah_ext = Map.fetch!(row, "account_holder_external_id")
      ah = fetch_by_external_id!(session, AccountHolder, ah_ext)

      request =
        row
        |> Map.drop(["account_holder_external_id"])
        |> Map.put("account_holder_id", ah.id)
        |> stamp_tenant(session.tenant_id)
        |> to_request(CounterpartyRequest)

      case CounterpartyContext.get_counterparty_by_external_id(session, number) do
        nil ->
          Mix.shell().info("   CP #{number} [create]")

          case CounterpartyContext.create_counterparty(session, request) do
            {:ok, _cp} -> :ok
            {:error, reason} -> Mix.raise("CP create failed for #{number}: #{inspect(reason)}")
          end

        existing ->
          Mix.shell().info("   CP #{number} [update]")

          case CounterpartyContext.update_counterparty(session, existing, request) do
            {:ok, _cp} -> :ok
            {:error, reason} -> Mix.raise("CP update failed for #{number}: #{inspect(reason)}")
          end
      end
    end)
  end

  defp insert_payment_accounts(session, corpus_path) do
    corpus_path
    |> read_ndjson("payment_accounts.ndjson")
    |> Enum.each(fn row ->
      ext_id = row["external_id"]
      {parent_field, parent_struct} = resolve_pa_parent(session, row)

      request =
        row
        |> Map.drop(["account_holder_external_id", "counterparty_external_id"])
        |> Map.put(parent_field, parent_struct.id)
        |> stamp_tenant(session.tenant_id)
        |> to_request(PaymentAccountRequest)

      case PaymentAccountContext.get_payment_account_by_external_id(session, ext_id) do
        nil ->
          Mix.shell().info("   PA #{ext_id} [create]")

          case PaymentAccountContext.create_payment_account(session, request) do
            {:ok, _pa} -> :ok
            {:error, reason} -> Mix.raise("PA create failed for #{ext_id}: #{inspect(reason)}")
          end

        existing ->
          Mix.shell().info("   PA #{ext_id} [update]")

          case PaymentAccountContext.update_payment_account(session, existing, request) do
            {:ok, _pa} -> :ok
            {:error, reason} -> Mix.raise("PA update failed for #{ext_id}: #{inspect(reason)}")
          end
      end
    end)
  end

  defp resolve_pa_parent(session, %{"account_holder_external_id" => ah_ext})
       when is_binary(ah_ext) do
    {"account_holder_id", fetch_by_external_id!(session, AccountHolder, ah_ext)}
  end

  defp resolve_pa_parent(session, %{"counterparty_external_id" => cp_ext})
       when is_binary(cp_ext) do
    {"counterparty_id", fetch_by!(session, Counterparty, external_id: cp_ext)}
  end

  # ───────────────────────────── bootstrap ────────────────────────────

  # Clears the block-by-default state every newly-materialised LedgerAccount
  # starts with (`is_blocked: true, block_reason: "pending onboarding screening"`).
  # The corpus exercises *transaction* screening only — there is no onboarding
  # rule corpus to unblock LAs through the regular `apply_controls` flow, so
  # without this bootstrap every transaction would be rejected on the
  # LA-painted `is_blocked` flag before the rule engine has a chance to run.
  defp bootstrap_unblock_ledger_accounts do
    Ecto.Adapters.SQL.query!(
      Repo,
      "UPDATE ledger_accounts SET is_blocked = false, block_reason = NULL",
      []
    )
  end

  # ───────────────────────────── transactions ─────────────────────────

  defp process_transactions(session, corpus_path) do
    corpus_path
    |> read_ndjson("transactions.ndjson")
    |> Enum.map(fn row ->
      validate_transaction(session, row)
    end)
  end

  defp validate_transaction(session, row) do
    {label, row} = Map.pop(row, "_label", %{})
    {expected, row} = Map.pop(row, "_expected")
    ext_id = row["external_id"]

    result =
      case TransactionContext.get_transaction_by_external_id(session, ext_id) do
        nil ->
          Mix.shell().info("   txn #{ext_id} [create]")

          with {:ok, request} <- build_transaction_request(session, row) do
            TransactionContext.create_transaction(session, request)
          end

        existing ->
          Mix.shell().info("   txn #{ext_id} [reuse]")
          {:ok, existing}
      end

    with {:ok, txn} <- result do
      actual = transaction_summary(txn)

      status =
        cond do
          is_nil(expected) -> :new
          matches?(expected, actual) -> :match
          true -> :mismatch
        end

      %{
        external_id: ext_id,
        label: label,
        expected: expected,
        actual: actual,
        status: status
      }
    else
      {:error, %Ecto.Changeset{} = cs} ->
        %{
          external_id: row["external_id"],
          label: label,
          expected: expected,
          actual: nil,
          status: :setup_error,
          error: changeset_errors(cs)
        }

      {:error, reason} ->
        %{
          external_id: row["external_id"],
          label: label,
          expected: expected,
          actual: nil,
          status: :engine_error,
          error: reason
        }
    end
  end

  defp build_transaction_request(session, row) do
    {scrubbed, resolved} =
      Enum.reduce(transaction_external_id_map(), {row, %{}}, fn {ext_key,
                                                                 {id_key, schema, lookup}},
                                                                {acc_row, acc_ids} ->
        case Map.pop(acc_row, ext_key) do
          {nil, acc_row} ->
            {acc_row, acc_ids}

          {ext_value, acc_row} ->
            parent = lookup.(session, schema, ext_value)
            {acc_row, Map.put(acc_ids, id_key, parent.id)}
        end
      end)

    request =
      scrubbed
      |> Map.merge(resolved)
      |> stamp_tenant(session.tenant_id)
      |> to_request(TransactionRequest)

    {:ok, request}
  end

  # external_id-keyed transaction fields → (target FK column, schema, lookup fn)
  defp transaction_external_id_map do
    by_external = &fetch_by_external_id!/3

    %{
      "account_holder_external_id" => {"account_holder_id", AccountHolder, by_external},
      "debtor_payment_account_external_id" =>
        {"debtor_payment_account_id", PaymentAccount, by_external},
      "creditor_payment_account_external_id" =>
        {"creditor_payment_account_id", PaymentAccount, by_external},
      "debtor_counterparty_external_id" => {"debtor_counterparty_id", Counterparty, by_external},
      "creditor_counterparty_external_id" =>
        {"creditor_counterparty_id", Counterparty, by_external}
    }
  end

  # The subset of %Transaction{} fields we surface in the actual/expected diff.
  defp transaction_summary(txn) do
    %{
      "status" => to_string(txn.status),
      "rejected_rule" => txn.rejected_rule,
      "rejected_code" => txn.rejected_code,
      "rejected_direction" => txn.rejected_direction && to_string(txn.rejected_direction),
      "rejected_period" => txn.rejected_period && to_string(txn.rejected_period)
    }
  end

  # Partial match: every key/value in `expected` must match `actual`.
  defp matches?(expected, actual) when is_map(expected) and is_map(actual) do
    Enum.all?(expected, fn {k, v} -> Map.get(actual, k) == v end)
  end

  # ───────────────────────────── helpers ──────────────────────────────

  defp read_ndjson(corpus_path, filename) do
    path = Path.join(corpus_path, filename)

    if File.exists?(path) do
      path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.map(&Jason.decode!/1)
      |> Enum.to_list()
    else
      []
    end
  end

  defp fetch_by_external_id!(session, schema, external_id) do
    fetch_by!(session, schema, external_id: external_id)
  end

  defp fetch_by!(session, schema, clauses) do
    case Repo.get_by(schema, clauses, session: session) do
      nil ->
        Mix.raise(
          "lookup failed: #{inspect(schema)} where #{inspect(clauses)} not found in tenant " <>
            session.tenant.slug
        )

      struct ->
        struct
    end
  end

  defp to_request(map, mod) do
    # String.to_atom (not to_existing_atom) — request struct fields are sometimes
    # generated lazily; ndjson keys are author-controlled so atom-table bloat is
    # not a concern for this dev-only task.
    atoms = for {k, v} <- map, into: %{}, do: {String.to_atom(k), v}
    struct(mod, atoms)
  end

  # Stamp tenant_id at the top level and on any nested map under known
  # parent-record keys (legal_entity is the only one today).
  defp stamp_tenant(row, tenant_id) do
    row
    |> Map.put("tenant_id", tenant_id)
    |> Map.update("legal_entity", nil, &maybe_stamp(&1, tenant_id))
  end

  defp maybe_stamp(nil, _tenant_id), do: nil
  defp maybe_stamp(map, tenant_id) when is_map(map), do: Map.put(map, "tenant_id", tenant_id)

  defp build_system_session do
    name = Config.fetch!(:system_tenant) |> Keyword.fetch!(:name)
    tenant = Repo.get_by!(Tenant, [name: name], skip_multi_tenancy_check: true)

    %Session{
      tenant_id: tenant.id,
      tenant: tenant,
      role: %{name: RoleConstants.root_role()}
    }
  end

  defp changeset_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", inspect(v))
      end)
    end)
  end

  # ───────────────────────────── rendering ────────────────────────────

  defp render_markdown(corpus_path, rows) do
    header = """
    # corpus.validate report

    - corpus: `#{corpus_path}`
    - transactions: #{length(rows)}

    """

    details =
      if rows == [] do
        "_No transactions in this corpus._\n\n"
      else
        Enum.map_join(rows, "\n", &render_row/1)
      end

    summary = render_summary(rows)

    header <> details <> "\n" <> summary
  end

  defp render_row(%{status: status, external_id: ext_id, label: label} = row) do
    """
    ## #{ext_id}

    - status:   **#{status_label(status)}**
    - regime:   #{Map.get(label, "regime", "—")}
    - cite:     #{Map.get(label, "cite", "—")}
    - scenario: #{Map.get(label, "scenario", "—")}

    #{render_body(row)}
    """
  end

  defp render_body(%{status: :setup_error, error: errors}) do
    "```text\nsetup_error (changeset): #{inspect(errors)}\n```\n"
  end

  defp render_body(%{status: :engine_error, error: reason}) do
    "```text\nengine_error: #{inspect(reason)}\n```\n"
  end

  defp render_body(%{status: :new, actual: actual}) do
    """
    <details open><summary>actual (no _expected on row)</summary>

    ```json
    #{Jason.encode!(actual, pretty: true)}
    ```
    </details>
    """
  end

  defp render_body(%{status: :match, actual: actual}) do
    """
    <details><summary>response (matches expected)</summary>

    ```json
    #{Jason.encode!(actual, pretty: true)}
    ```
    </details>
    """
  end

  defp render_body(%{status: :mismatch, actual: actual, expected: expected}) do
    """
    <details open><summary>diff</summary>

    ```diff
    - expected: #{Jason.encode!(expected)}
    + actual:   #{Jason.encode!(actual)}
    ```
    </details>
    """
  end

  defp render_summary(rows) do
    counts = Enum.frequencies_by(rows, & &1.status)

    """
    ## Summary

    | status | count |
    |---|---|
    | match | #{Map.get(counts, :match, 0)} |
    | new (no _expected) | #{Map.get(counts, :new, 0)} |
    | mismatch | #{Map.get(counts, :mismatch, 0)} |
    | setup_error | #{Map.get(counts, :setup_error, 0)} |
    | engine_error | #{Map.get(counts, :engine_error, 0)} |
    | **total** | **#{length(rows)}** |
    """
  end

  defp status_label(:match), do: "✓ match"
  defp status_label(:new), do: "🆕 new"
  defp status_label(:mismatch), do: "✗ mismatch"
  defp status_label(:setup_error), do: "⚠ setup_error"
  defp status_label(:engine_error), do: "⚠ engine_error"
end

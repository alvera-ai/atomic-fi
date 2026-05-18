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
  alias AtomicFi.BeneficialOwnerContext
  alias AtomicFi.BlocklistContext
  alias AtomicFi.Config
  alias Ecto.Adapters.SQL
  alias AtomicFi.CounterpartyContext
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  alias AtomicFi.OpenApiSchema.BeneficialOwnerRequest
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
      OptionParser.parse(args,
        strict: [out: :string, reset: :boolean, concurrency: :integer]
      )

    corpus_path =
      List.first(positional) ||
        Mix.raise("usage: mix corpus.validate <corpus_path> [--out <file>] [--reset]")

    unless File.dir?(corpus_path),
      do: Mix.raise("corpus folder not found: #{corpus_path}")

    inject_search_path_after_connect!()

    Mix.Task.run("app.start")

    ensure_schema!(opts[:reset])

    session = build_system_session()

    # Seed any internal-blocklist entries BEFORE the cache refresh: the
    # cache reads from the DB into ETS, so entries inserted later won't
    # be visible to the screening pipeline (which queries the cache by
    # tenant_id). Idempotency is unnecessary — the schema was reset
    # above (--reset) or carried over from a prior identical reseed.
    # Looking under the parent corpus_path is fine for both
    # single-folder corpora (file lives next to ah/cp/pa/txn) and
    # sharded corpora (each shard MAY carry its own blocklist; reseed
    # honours the union across shards by reading from each shard
    # below, but the single-folder path reads only here).
    blocklist_seed = read_ndjson(corpus_path, "blocklist_entries.ndjson")
    insert_blocklist_entries(session, blocklist_seed)

    AtomicFi.BlocklistContext.BlocklistCache.refresh_tenant_cache(session.tenant_id)

    shard_dirs = discover_shards(corpus_path)

    {seed_dir_for_report, vu_outputs, all_timings, rows} =
      if shard_dirs == [] do
        # Classic single-folder corpus (hand-authored scenario fixture
        # under corpus/zen_rules/<slug>/). VU fan-out via id prefix.
        ah_seed = read_ndjson(corpus_path, "account_holders.ndjson")
        cp_seed = read_ndjson(corpus_path, "counterparties.ndjson")
        bo_seed = read_ndjson(corpus_path, "beneficial_owners.ndjson")
        pa_seed = read_ndjson(corpus_path, "payment_accounts.ndjson")
        tx_seed = read_ndjson(corpus_path, "transactions.ndjson")

        concurrency = Keyword.get(opts, :concurrency, 1)

        Mix.shell().info(
          "→ fanning out across #{concurrency} VU(s) (k6 model — each VU runs the seed scenario with its own id prefix)"
        )

        vu_outputs = run_vus(session, concurrency, ah_seed, cp_seed, bo_seed, pa_seed, tx_seed)
        timings = Enum.flat_map(vu_outputs, & &1)
        rows = reduce_vu_outputs(vu_outputs)
        {corpus_path, vu_outputs, timings, rows}
      else
        # Sharded corpus — each shard-* subdir is a complete corpus
        # with its own external_id namespace; run them in parallel as K
        # independent VUs (the per-shard prefixing already disambiguates
        # ids across shards).
        Mix.shell().info(
          "→ found #{length(shard_dirs)} shard folder(s); running them in parallel as K VUs"
        )

        outputs = run_shards(session, shard_dirs)
        timings = Enum.flat_map(outputs, & &1)
        rows = reduce_vu_outputs(outputs)
        {corpus_path, outputs, timings, rows}
      end

    _ = vu_outputs

    report = render_markdown(seed_dir_for_report, rows)

    case opts[:out] do
      nil ->
        IO.write(report)

      path ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, report)
        Mix.shell().info("✓ Wrote validation report to #{path}")
    end

    print_timing(all_timings)

    if Enum.any?(rows, &(&1.status in [:mismatch, :engine_error, :setup_error])) do
      System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    end
  end

  # Discover `shard-*` subdirectories under a parent corpus path. Returns
  # `[]` when none are present (signals classic single-folder mode).
  defp discover_shards(corpus_path) do
    corpus_path
    |> File.ls!()
    |> Enum.filter(&String.starts_with?(&1, "shard-"))
    |> Enum.map(&Path.join(corpus_path, &1))
    |> Enum.filter(&File.dir?/1)
    |> Enum.sort()
  end

  # Run each shard folder as its own VU. Each shard is already prefixed
  # for id-uniqueness across shards (mix corpus.generate.<src> takes care
  # of this), so no in-memory prefixing happens here.
  defp run_shards(session, shard_dirs) do
    shard_dirs
    |> Task.async_stream(
      fn shard_dir ->
        ah = read_ndjson(shard_dir, "account_holders.ndjson")
        cp = read_ndjson(shard_dir, "counterparties.ndjson")
        bo = read_ndjson(shard_dir, "beneficial_owners.ndjson")
        pa = read_ndjson(shard_dir, "payment_accounts.ndjson")
        tx = read_ndjson(shard_dir, "transactions.ndjson")

        insert_account_holders(session, ah)
        insert_counterparties(session, cp)
        insert_beneficial_owners(session, bo)
        insert_payment_accounts(session, pa)

        Enum.map(tx, fn row -> validate_transaction(session, row) end)
      end,
      max_concurrency: max(length(shard_dirs), 1),
      ordered: true,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, rows} -> rows end)
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
      SQL.query!(
        Repo,
        "SELECT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = $1)",
        [@schema]
      )

    exists?
  end

  defp drop_schema! do
    SQL.query!(Repo, "DROP SCHEMA IF EXISTS #{@schema} CASCADE", [])
  end

  defp create_schema! do
    SQL.query!(Repo, "CREATE SCHEMA #{@schema}", [])
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

  defp insert_account_holders(session, rows) do
    Enum.each(rows, fn row ->
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

  defp insert_counterparties(session, rows) do
    Enum.each(rows, fn row ->
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

  # Internal-blocklist entries (scope=last_name|first_name|company_name,
  # entry_type=exact|regex, term, reason, active). Inserted before the
  # BlocklistCache refresh in `run/1` so the ETS cache picks them up.
  # Loader is line-by-line (no upsert) — schema reset above guarantees
  # uniqueness; on a non-reset reseed the partial unique index on
  # (tenant_id, scope, entry_type, term) catches duplicates.
  defp insert_blocklist_entries(_session, []), do: :ok

  defp insert_blocklist_entries(session, rows) do
    Enum.each(rows, fn row ->
      attrs = stamp_tenant(row, session.tenant_id)
      attrs = Map.put_new(attrs, "active", true)

      case BlocklistContext.create_blocklist_entry(session, attrs) do
        {:ok, _entry} ->
          Mix.shell().info(
            "   BL #{Map.get(row, "scope")}/#{Map.get(row, "entry_type")}: #{inspect(Map.get(row, "term"))} [create]"
          )

        {:error, %Ecto.Changeset{errors: [{key, {"has already been taken", _}} | _]}}
        when key in [:term, :tenant_id] ->
          Mix.shell().info(
            "   BL #{Map.get(row, "scope")}/#{Map.get(row, "entry_type")}: #{inspect(Map.get(row, "term"))} [exists]"
          )

        {:error, reason} ->
          Mix.raise("blocklist entry create failed for #{inspect(row)}: #{inspect(reason)}")
      end
    end)
  end

  defp insert_beneficial_owners(session, rows) do
    Enum.each(rows, fn row ->
      ext_id = row["external_id"]
      ah_ext = Map.fetch!(row, "account_holder_external_id")
      ah = fetch_by_external_id!(session, AccountHolder, ah_ext)

      request =
        row
        |> Map.drop(["account_holder_external_id"])
        |> Map.put("account_holder_id", ah.id)
        |> Map.put("chain_screening", false)
        |> stamp_tenant(session.tenant_id)
        |> to_request(BeneficialOwnerRequest)

      case BeneficialOwnerContext.get_beneficial_owner_by_external_id(session, ext_id) do
        nil ->
          Mix.shell().info("   BO #{ext_id} [create]")

          case BeneficialOwnerContext.create_beneficial_owner(session, request) do
            {:ok, _bo} -> :ok
            {:error, reason} -> Mix.raise("BO create failed for #{ext_id}: #{inspect(reason)}")
          end

        existing ->
          Mix.shell().info("   BO #{ext_id} [update]")

          case BeneficialOwnerContext.update_beneficial_owner(session, existing, request) do
            {:ok, _bo} -> :ok
            {:error, reason} -> Mix.raise("BO update failed for #{ext_id}: #{inspect(reason)}")
          end
      end
    end)
  end

  defp insert_payment_accounts(session, rows) do
    Enum.each(rows, fn row ->
      ext_id = row["external_id"]
      fk_overrides = resolve_pa_fks(session, row)

      request =
        row
        |> Map.drop(["account_holder_external_id", "counterparty_external_id"])
        |> Map.merge(fk_overrides)
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

  # Resolve any combination of `account_holder_external_id` and
  # `counterparty_external_id` into the corresponding ids. Either or both
  # may be present:
  #   - AH-owned PA       → only account_holder_external_id
  #   - CP-owned PA       → both (the host AH for partition + the CP for ownership)
  defp resolve_pa_fks(session, row) do
    %{}
    |> maybe_resolve_fk(
      session,
      row,
      "account_holder_external_id",
      "account_holder_id",
      AccountHolder
    )
    |> maybe_resolve_fk(
      session,
      row,
      "counterparty_external_id",
      "counterparty_id",
      Counterparty
    )
  end

  defp maybe_resolve_fk(acc, session, row, src_key, dest_key, schema) do
    case Map.get(row, src_key) do
      ext when is_binary(ext) ->
        Map.put(acc, dest_key, fetch_by_external_id!(session, schema, ext).id)

      _ ->
        acc
    end
  end

  # ───────────────────────────── VU fan-out (k6 model) ────────────────
  #
  # `--concurrency K` spawns K virtual users via `Task.async_stream`. Each
  # VU clones the seed corpus in-memory with its own id prefix
  # (`vu0000-`, `vu0001-`, …) and runs the full pipeline against it:
  # insert AHs → insert CPs → insert PAs → for each txn (SEQUENTIAL within
  # the VU) call validate_transaction.
  #
  # Sequential-within-VU is non-negotiable: velocity rules (BSA §5324
  # anti-structuring, etc.) window over the AH's prior debits and need
  # arrival-order semantics. Parallelism happens BETWEEN VUs, which is
  # safe because each VU has its own AH/CP/PA set — no cross-VU sharing.
  #
  # The reduce step strips the prefix and asserts every VU produced an
  # identical actual for the same logical txn; divergence between VUs
  # surfaces as a mismatch (catches non-determinism).
  defp run_vus(session, concurrency, ah_seed, cp_seed, bo_seed, pa_seed, tx_seed) do
    0..(concurrency - 1)
    |> Task.async_stream(
      fn vu ->
        prefix = vu_prefix(vu)
        ah = Enum.map(ah_seed, &prefix_external_ids(&1, prefix))
        cp = Enum.map(cp_seed, &prefix_external_ids(&1, prefix))
        bo = Enum.map(bo_seed, &prefix_external_ids(&1, prefix))
        pa = Enum.map(pa_seed, &prefix_external_ids(&1, prefix))
        tx = Enum.map(tx_seed, &prefix_external_ids(&1, prefix))

        insert_account_holders(session, ah)
        insert_counterparties(session, cp)
        insert_beneficial_owners(session, bo)
        insert_payment_accounts(session, pa)

        Enum.map(tx, fn row ->
          result = validate_transaction(session, row)
          %{result | external_id: strip_prefix(result.external_id, prefix)}
        end)
      end,
      max_concurrency: max(concurrency, 1),
      ordered: true,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, rows} -> rows end)
  end

  defp vu_prefix(vu), do: "vu#{:io_lib.format("~4..0B", [vu]) |> IO.iodata_to_binary()}-"

  # Rewrite every value whose key is `*external_id` with the VU prefix.
  # Wallet addresses, names, amounts untouched.
  defp prefix_external_ids(row, prefix) when is_map(row) do
    Map.new(row, fn
      {k, v} when is_binary(k) and is_binary(v) ->
        if String.ends_with?(k, "external_id"), do: {k, prefix <> v}, else: {k, v}

      kv ->
        kv
    end)
  end

  defp strip_prefix(nil, _prefix), do: nil

  defp strip_prefix(ext_id, prefix) when is_binary(ext_id) do
    case ext_id do
      <<^prefix::binary-size(byte_size(prefix)), rest::binary>> -> rest
      _ -> ext_id
    end
  end

  # Reduce K VUs into a single canonical row list. VU 0 is the canonical
  # ordering. For each logical txn, assert all VUs produced the same
  # `actual`; if any diverge, surface as mismatch.
  defp reduce_vu_outputs([vu0 | rest_vus]) do
    Enum.with_index(vu0)
    |> Enum.map(fn {row, idx} ->
      others = Enum.map(rest_vus, &Enum.at(&1, idx))
      reduce_row(row, others)
    end)
  end

  defp reduce_row(canonical, []), do: canonical

  defp reduce_row(canonical, others) do
    if Enum.all?(others, &(&1.actual == canonical.actual and &1.status == canonical.status)) do
      canonical
    else
      diverging = Enum.find(others, &(&1.actual != canonical.actual))

      %{
        canonical
        | status: :mismatch,
          expected: canonical.actual,
          actual: diverging && diverging.actual
      }
    end
  end

  defp validate_transaction(session, row) do
    {label, row} = Map.pop(row, "_label", %{})
    {expected, row} = Map.pop(row, "_expected")
    ext_id = row["external_id"]

    {result, elapsed_ms} = time_ms(fn -> create_or_reuse(session, ext_id, row) end)

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
        status: status,
        elapsed_ms: elapsed_ms
      }
    else
      {:error, %Ecto.Changeset{} = cs} ->
        %{
          external_id: row["external_id"],
          label: label,
          expected: expected,
          actual: nil,
          status: :setup_error,
          error: changeset_errors(cs),
          elapsed_ms: elapsed_ms
        }

      {:error, reason} ->
        %{
          external_id: row["external_id"],
          label: label,
          expected: expected,
          actual: nil,
          status: :engine_error,
          error: reason,
          elapsed_ms: elapsed_ms
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

  # Poor-man's-k6 footer. Times the `TransactionContext.create_transaction/2`
  # call per row (the slow path — RuleEngine HTTP, Postgres triggers, RLS).
  # NDJSON parsing and entity inserts are excluded; this is the screening
  # hot path only. Printed to stderr so it never lands in the deterministic
  # proof.md artifact.
  defp print_timing(rows) do
    samples = rows |> Enum.map(& &1.elapsed_ms) |> Enum.reject(&is_nil/1) |> Enum.sort()

    case samples do
      [] ->
        Mix.shell().error("Timing: (no rows timed)")

      _ ->
        total = Enum.sum(samples)
        n = length(samples)
        avg = total / n
        rate = if total > 0, do: n * 1_000 / total, else: 0.0

        Mix.shell().error("""

        Timing (poor man's k6 — per-row TransactionContext.create_transaction)
          n         #{n}
          ms_total  #{total}
          ms_avg    #{format_ms_float(avg)}
          txns/sec  #{format_rate(rate)}
          p50       #{percentile(samples, 0.50)} ms
          p95       #{percentile(samples, 0.95)} ms
          p99       #{percentile(samples, 0.99)} ms
          ms_max    #{List.last(samples)}
        """)
    end
  end

  defp percentile(sorted, p) when is_list(sorted) and is_float(p) do
    # Linear nearest-rank percentile (Excel's PERCENTILE.INC, ish).
    len = length(sorted)
    idx = max(0, min(len - 1, round(p * (len - 1))))
    Enum.at(sorted, idx)
  end

  defp format_ms_float(ms), do: :erlang.float_to_binary(ms / 1, decimals: 1)
  defp format_rate(rate), do: :erlang.float_to_binary(rate / 1, decimals: 1)

  defp time_ms(fun) do
    t0 = System.monotonic_time(:millisecond)
    result = fun.()
    {result, System.monotonic_time(:millisecond) - t0}
  end

  defp create_or_reuse(session, ext_id, row) do
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
  end

  defp status_label(:match), do: "✓ match"
  defp status_label(:new), do: "🆕 new"
  defp status_label(:mismatch), do: "✗ mismatch"
  defp status_label(:setup_error), do: "⚠ setup_error"
  defp status_label(:engine_error), do: "⚠ engine_error"
end

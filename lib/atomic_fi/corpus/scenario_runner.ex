defmodule AtomicFi.Corpus.ScenarioRunner do
  @moduledoc """
  In-process scenario runner shared by `mix corpus.validate` and
  `mix corpus.bench`. Loads a corpus folder's NDJSON files into memory,
  prefixes external_ids per VU, inserts the entity graph through the
  production contexts, and creates each transaction — returning a list
  of per-row result maps the caller can fold into a report.

  Extraction notes:

   - Schema isolation (`atomic_fi_corpus` Postgres schema, search_path
     injection, --reset) lives here so both callers share the same
     contract.
   - System session construction lives here for the same reason.
   - Per-VU id-prefixing is the only way two concurrent VUs against the
     same scenario stay disjoint at the DB layer — bench drives this via
     a UUID prefix per Task.
   - Logging is suppressed when `verbose: false` (bench default — 10k
     VUs each printing 4 inserts would drown the console).
  """

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

  @schema "atomic_fi_corpus"
  @search_path "#{@schema}, public"

  # ── schema lifecycle ─────────────────────────────────────────────

  @doc """
  Inject `after_connect` so every pool checkout runs
  `SET search_path TO atomic_fi_corpus, public`. Must be called BEFORE
  `Mix.Task.run("app.start")`.
  """
  def inject_search_path_after_connect! do
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

  @doc """
  Ensure the corpus schema exists and is fully migrated. `reset? == true`
  drops + recreates the schema before remigrating.
  """
  def ensure_schema!(reset?) do
    cond do
      reset? ->
        info("→ --reset: dropping #{@schema} and remigrating")
        drop_schema!()
        create_schema!()
        migrate!()

      schema_exists?() ->
        :ok

      true ->
        info("→ first run: creating #{@schema} and migrating")
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

  defp drop_schema!, do: SQL.query!(Repo, "DROP SCHEMA IF EXISTS #{@schema} CASCADE", [])
  defp create_schema!, do: SQL.query!(Repo, "CREATE SCHEMA #{@schema}", [])

  defp migrate! do
    paths =
      :atomic_fi
      |> Application.fetch_env!(:migration_paths)
      |> Map.fetch!(Repo)

    for path <- paths do
      info("   migrate: #{path}")
      Ecto.Migrator.run(Repo, path, :up, all: true)
    end
  end

  # ── session ──────────────────────────────────────────────────────

  @doc "Build a root system session for the configured system tenant."
  def build_system_session do
    name = Config.fetch!(:system_tenant) |> Keyword.fetch!(:name)
    tenant = Repo.get_by!(Tenant, [name: name], skip_multi_tenancy_check: true)

    %Session{
      tenant_id: tenant.id,
      tenant: tenant,
      role: %{name: RoleConstants.root_role()}
    }
  end

  # ── scenario loading ─────────────────────────────────────────────

  @doc """
  Read all NDJSON files under a scenario folder into memory. Returns a
  map with `:path`, `:ah`, `:cp`, `:bo`, `:pa`, `:tx`, `:blocklist`.
  """
  def load_scenario(path) do
    unless File.dir?(path), do: raise("corpus folder not found: #{path}")

    %{
      path: path,
      ah: read_ndjson(path, "account_holders.ndjson"),
      cp: read_ndjson(path, "counterparties.ndjson"),
      bo: read_ndjson(path, "beneficial_owners.ndjson"),
      pa: read_ndjson(path, "payment_accounts.ndjson"),
      tx: read_ndjson(path, "transactions.ndjson"),
      blocklist: read_ndjson(path, "blocklist_entries.ndjson")
    }
  end

  @doc """
  Seed blocklist entries from one or more scenarios and refresh the
  per-tenant cache once. Idempotent on the unique index — repeated calls
  across scenarios with overlapping terms log `[exists]` and continue.
  """
  def seed_blocklists!(session, scenarios, opts \\ []) do
    scenarios
    |> Enum.flat_map(& &1.blocklist)
    |> insert_blocklist_entries(session, opts)

    BlocklistContext.BlocklistCache.refresh_tenant_cache(session.tenant_id)
  end

  # ── VU execution ─────────────────────────────────────────────────

  @doc """
  Run one VU pass over a loaded scenario:

   1. Apply id-prefix to every `*external_id` field.
   2. Insert AHs → CPs → BOs → PAs.
   3. For each transaction, create-or-reuse and diff against `_expected`.

  Returns `{result_rows, prefix}` where each row is a map with
  `:external_id`, `:label`, `:expected`, `:actual`, `:status`,
  `:elapsed_ms`, and optional `:error`. Sequential within a VU
  (velocity rules depend on arrival order).

  Options:
   - `:prefix` — string to prepend to every external_id (default `""`)
   - `:verbose` — emit per-row Mix.shell info (default `true`)
  """
  def run_vu(session, scenario, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "")
    verbose = Keyword.get(opts, :verbose, true)

    ah = Enum.map(scenario.ah, &prefix_external_ids(&1, prefix))
    cp = Enum.map(scenario.cp, &prefix_external_ids(&1, prefix))
    bo = Enum.map(scenario.bo, &prefix_external_ids(&1, prefix))
    pa = Enum.map(scenario.pa, &prefix_external_ids(&1, prefix))
    tx = Enum.map(scenario.tx, &prefix_external_ids(&1, prefix))

    insert_account_holders(session, ah, verbose)
    insert_counterparties(session, cp, verbose)
    insert_beneficial_owners(session, bo, verbose)
    insert_payment_accounts(session, pa, verbose)

    rows =
      Enum.map(tx, fn row ->
        result = validate_transaction(session, row, verbose)
        %{result | external_id: strip_prefix(result.external_id, prefix)}
      end)

    {rows, prefix}
  end

  # ── inserts ──────────────────────────────────────────────────────

  # Shared upsert-by-external-id loop. Lookups, creates, and updates are
  # called through `funs` so the four entity inserts collapse to one body;
  # this keeps Credo's "nested too deep" off our backs and the diff
  # against the original four-function form trivial to follow.
  defp upsert_each(rows, session, kind, verbose, funs) do
    %{lookup: lookup, build: build, create: create, update: update} = funs

    Enum.each(rows, fn row ->
      ext_id = row["external_id"]
      request = build.(row)

      case lookup.(session, ext_id) do
        nil ->
          maybe_info(verbose, "   #{kind} #{ext_id} [create]")
          ok_or_raise(create.(session, request), "#{kind} create", ext_id)

        existing ->
          maybe_info(verbose, "   #{kind} #{ext_id} [update]")
          ok_or_raise(update.(session, existing, request), "#{kind} update", ext_id)
      end
    end)
  end

  defp ok_or_raise({:ok, _}, _label, _ext_id), do: :ok

  defp ok_or_raise({:error, reason}, label, ext_id),
    do: raise("#{label} failed for #{ext_id}: #{inspect(reason)}")

  defp insert_account_holders(session, rows, verbose) do
    upsert_each(rows, session, "AH", verbose, %{
      lookup: &AccountHolderContext.get_account_holder_by_external_id/2,
      build: fn row ->
        row
        |> Map.put("chain_screening", false)
        |> stamp_tenant(session.tenant_id)
        |> to_request(AccountHolderRequest)
      end,
      create: &AccountHolderContext.create_account_holder/2,
      update: &AccountHolderContext.update_account_holder/3
    })
  end

  defp insert_counterparties(session, rows, verbose) do
    upsert_each(rows, session, "CP", verbose, %{
      lookup: &CounterpartyContext.get_counterparty_by_external_id/2,
      build: fn row ->
        ah_ext = Map.fetch!(row, "account_holder_external_id")
        ah = fetch_by_external_id!(session, AccountHolder, ah_ext)

        row
        |> Map.drop(["account_holder_external_id"])
        |> Map.put("account_holder_id", ah.id)
        |> stamp_tenant(session.tenant_id)
        |> to_request(CounterpartyRequest)
      end,
      create: &CounterpartyContext.create_counterparty/2,
      update: &CounterpartyContext.update_counterparty/3
    })
  end

  defp insert_beneficial_owners(session, rows, verbose) do
    upsert_each(rows, session, "BO", verbose, %{
      lookup: &BeneficialOwnerContext.get_beneficial_owner_by_external_id/2,
      build: fn row ->
        ah_ext = Map.fetch!(row, "account_holder_external_id")
        ah = fetch_by_external_id!(session, AccountHolder, ah_ext)

        row
        |> Map.drop(["account_holder_external_id"])
        |> Map.put("account_holder_id", ah.id)
        |> Map.put("chain_screening", false)
        |> stamp_tenant(session.tenant_id)
        |> to_request(BeneficialOwnerRequest)
      end,
      create: &BeneficialOwnerContext.create_beneficial_owner/2,
      update: &BeneficialOwnerContext.update_beneficial_owner/3
    })
  end

  defp insert_payment_accounts(session, rows, verbose) do
    upsert_each(rows, session, "PA", verbose, %{
      lookup: &PaymentAccountContext.get_payment_account_by_external_id/2,
      build: fn row ->
        fk_overrides = resolve_pa_fks(session, row)

        row
        |> Map.drop(["account_holder_external_id", "counterparty_external_id"])
        |> Map.merge(fk_overrides)
        |> stamp_tenant(session.tenant_id)
        |> to_request(PaymentAccountRequest)
      end,
      create: &PaymentAccountContext.create_payment_account/2,
      update: &PaymentAccountContext.update_payment_account/3
    })
  end

  defp insert_blocklist_entries([], _session, _opts), do: :ok

  defp insert_blocklist_entries(rows, session, opts) do
    verbose = Keyword.get(opts, :verbose, true)

    Enum.each(rows, fn row ->
      attrs = stamp_tenant(row, session.tenant_id)
      attrs = Map.put_new(attrs, "active", true)

      case BlocklistContext.create_blocklist_entry(session, attrs) do
        {:ok, _entry} ->
          maybe_info(
            verbose,
            "   BL #{Map.get(row, "scope")}/#{Map.get(row, "entry_type")}: " <>
              "#{inspect(Map.get(row, "term"))} [create]"
          )

        {:error, %Ecto.Changeset{errors: [{key, {"has already been taken", _}} | _]}}
        when key in [:term, :tenant_id] ->
          maybe_info(
            verbose,
            "   BL #{Map.get(row, "scope")}/#{Map.get(row, "entry_type")}: " <>
              "#{inspect(Map.get(row, "term"))} [exists]"
          )

        {:error, reason} ->
          raise "blocklist entry create failed for #{inspect(row)}: #{inspect(reason)}"
      end
    end)
  end

  defp resolve_pa_fks(session, row) do
    %{}
    |> maybe_resolve_fk(
      session,
      row,
      "account_holder_external_id",
      "account_holder_id",
      AccountHolder
    )
    |> maybe_resolve_fk(session, row, "counterparty_external_id", "counterparty_id", Counterparty)
  end

  defp maybe_resolve_fk(acc, session, row, src_key, dest_key, schema) do
    case Map.get(row, src_key) do
      ext when is_binary(ext) ->
        Map.put(acc, dest_key, fetch_by_external_id!(session, schema, ext).id)

      _ ->
        acc
    end
  end

  # ── per-txn validation ───────────────────────────────────────────

  defp validate_transaction(session, row, verbose) do
    {label, row} = Map.pop(row, "_label", %{})
    {expected, row} = Map.pop(row, "_expected")
    ext_id = row["external_id"]

    {result, elapsed_ms} = time_ms(fn -> create_or_reuse(session, ext_id, row, verbose) end)

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

  defp create_or_reuse(session, ext_id, row, verbose) do
    case TransactionContext.get_transaction_by_external_id(session, ext_id) do
      nil ->
        maybe_info(verbose, "   txn #{ext_id} [create]")

        with {:ok, request} <- build_transaction_request(session, row) do
          TransactionContext.create_transaction(session, request)
        end

      existing ->
        maybe_info(verbose, "   txn #{ext_id} [reuse]")
        {:ok, existing}
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

  defp transaction_summary(txn) do
    %{
      "status" => to_string(txn.status),
      "rejected_rule" => txn.rejected_rule,
      "rejected_code" => txn.rejected_code,
      "rejected_direction" => txn.rejected_direction && to_string(txn.rejected_direction),
      "rejected_period" => txn.rejected_period && to_string(txn.rejected_period)
    }
  end

  defp matches?(expected, actual) when is_map(expected) and is_map(actual) do
    Enum.all?(expected, fn {k, v} -> Map.get(actual, k) == v end)
  end

  # ── helpers ──────────────────────────────────────────────────────

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

  defp prefix_external_ids(row, "") when is_map(row), do: row

  defp prefix_external_ids(row, prefix) when is_map(row) do
    Map.new(row, fn
      {k, v} when is_binary(k) and is_binary(v) ->
        if String.ends_with?(k, "external_id"), do: {k, prefix <> v}, else: {k, v}

      kv ->
        kv
    end)
  end

  defp strip_prefix(nil, _prefix), do: nil
  defp strip_prefix(ext_id, ""), do: ext_id

  defp strip_prefix(ext_id, prefix) when is_binary(ext_id) do
    case ext_id do
      <<^prefix::binary-size(byte_size(prefix)), rest::binary>> -> rest
      _ -> ext_id
    end
  end

  defp fetch_by_external_id!(session, schema, external_id) do
    fetch_by!(session, schema, external_id: external_id)
  end

  defp fetch_by!(session, schema, clauses) do
    case Repo.get_by(schema, clauses, session: session) do
      nil ->
        raise "lookup failed: #{inspect(schema)} where #{inspect(clauses)} not found in tenant " <>
                session.tenant.slug

      struct ->
        struct
    end
  end

  defp to_request(map, mod) do
    atoms = for {k, v} <- map, into: %{}, do: {String.to_atom(k), v}
    struct(mod, atoms)
  end

  defp stamp_tenant(row, tenant_id) do
    row
    |> Map.put("tenant_id", tenant_id)
    |> Map.update("legal_entity", nil, &maybe_stamp(&1, tenant_id))
  end

  defp maybe_stamp(nil, _tenant_id), do: nil
  defp maybe_stamp(map, tenant_id) when is_map(map), do: Map.put(map, "tenant_id", tenant_id)

  defp changeset_errors(cs) do
    Ecto.Changeset.traverse_errors(cs, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc ->
        String.replace(acc, "%{#{k}}", inspect(v))
      end)
    end)
  end

  defp time_ms(fun) do
    t0 = System.monotonic_time(:millisecond)
    result = fun.()
    {result, System.monotonic_time(:millisecond) - t0}
  end

  defp info(msg), do: Mix.shell().info(msg)
  defp maybe_info(true, msg), do: Mix.shell().info(msg)
  defp maybe_info(false, _msg), do: :ok
end

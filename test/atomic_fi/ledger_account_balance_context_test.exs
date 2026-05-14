defmodule AtomicFi.LedgerAccountBalanceContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.LedgerAccountBalanceContext
  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.LedgerAccountContext.{LedgerAccountBalance, ControlLimit}
  alias AtomicFi.LedgerEntryContext
  alias AtomicFi.OpenApiSchema.LedgerEntryRequest
  import AtomicFi.Factory

  # ── Helpers ──────────────────────────────────────────────────────────────────

  # Map the eight legacy keyword-arg shorthands to %ControlLimit{}s for the
  # composite-type array. The trigger fans these into last_*_limit columns on
  # ledger_account_balances and CHECK constraints fire on breach.
  @limit_keys [
    {:daily_debit_limit, "daily", "debit"},
    {:daily_credit_limit, "daily", "credit"},
    {:weekly_debit_limit, "weekly", "debit"},
    {:weekly_credit_limit, "weekly", "credit"},
    {:monthly_debit_limit, "monthly", "debit"},
    {:monthly_credit_limit, "monthly", "credit"},
    {:yearly_debit_limit, "yearly", "debit"},
    {:yearly_credit_limit, "yearly", "credit"}
  ]

  defp build_limits(opts) do
    Enum.flat_map(@limit_keys, fn {key, period, direction} ->
      case opts[key] do
        nil -> []
        cap -> [%ControlLimit{period: period, direction: direction, cap: cap, rule: "test"}]
      end
    end)
  end

  # Returns a fully-wired leaf LA (`:account_holder_payment_account_regime_root`).
  # Factory smart-dispatch auto-creates the PA + ancestor `*_root` row.
  defp leaf_account(session) do
    insert(:ledger_account, tenant_id: session.tenant_id)
  end

  # Builds a deeper 3-ancestor leaf (`:counter_party_payment_account_regime_root`)
  # so the propagation tests have a non-trivial chain to assert against.
  defp deep_leaf(session) do
    insert(:ledger_account,
      tenant_id: session.tenant_id,
      la_type: :counter_party_payment_account_regime_root,
      regime: "ach"
    )
  end

  defp credit(session, account, amount, opts \\ []) do
    entry_request(session, account, amount, :credit, opts)
  end

  defp debit(session, account, amount, opts \\ []) do
    entry_request(session, account, amount, :debit, opts)
  end

  defp entry_request(session, account, amount, entry_type, opts) do
    request = %LedgerEntryRequest{
      account_holder_id: account.account_holder_id,
      ledger_account_id: account.id,
      currency: "USD",
      amount: amount,
      entry_type: entry_type,
      status: :pending,
      limits_at_entry: build_limits(opts),
      tenant_id: session.tenant_id
    }

    with {:ok, entry} <- LedgerEntryContext.create_ledger_entry(session, request) do
      {:ok, LedgerEntryContext.get_ledger_entry!(session, entry.id)}
    end
  end

  # Flop filter on the read-only context — single source of truth for tenant
  # scoping, no Repo reach-arounds.
  defp balance_rows_for(session, account) do
    {:ok, {rows, _meta}} =
      LedgerAccountBalanceContext.list_ledger_account_balances(session, %{
        filters: [%{field: :ledger_account_id, op: :==, value: account.id}],
        order_by: [:balance_date],
        order_directions: [:asc],
        page_size: 100
      })

    rows
  end

  defp void_entry(session, entry) do
    void_request = %LedgerEntryRequest{
      account_holder_id: entry.account_holder_id,
      ledger_account_id: entry.ledger_account_id,
      currency: entry.currency,
      amount: entry.amount,
      entry_type: entry.entry_type,
      status: :voided,
      tenant_id: session.tenant_id
    }

    LedgerEntryContext.update_ledger_entry(session, entry, void_request)
  end

  # ── Read-only API ─────────────────────────────────────────────────────────────

  describe "ledger_account_balances read-only API" do
    test "list_ledger_account_balances/1 returns balance rows for tenant", %{session: session} do
      account = leaf_account(session)
      assert {:ok, _} = credit(session, account, 5_000)

      {:ok, {rows, _meta}} = LedgerAccountBalanceContext.list_ledger_account_balances(session)
      assert rows != []
      assert Enum.all?(rows, &(&1.tenant_id == session.tenant_id))
    end

    test "get_ledger_account_balance!/2 returns the row by id", %{session: session} do
      account = leaf_account(session)
      assert {:ok, _} = credit(session, account, 5_000)

      [row] = balance_rows_for(session, account)

      assert %LedgerAccountBalance{id: id} =
               LedgerAccountBalanceContext.get_ledger_account_balance!(session, row.id)

      assert id == row.id
    end
  end

  # ── Trigger creates balance rows ─────────────────────────────────────────────

  describe "trigger creates ledger_account_balances rows on entry insert" do
    test "credit entry creates a balance row for today", %{session: session} do
      account = leaf_account(session)
      assert balance_rows_for(session, account) == []

      assert {:ok, _} = credit(session, account, 10_000)

      rows = balance_rows_for(session, account)
      assert length(rows) == 1

      [row] = rows
      assert row.ledger_account_id == account.id
      assert row.balance_date == Date.utc_today()
      assert row.daily_credit == 10_000
      assert row.daily_debit == 0
    end

    test "debit entry creates a balance row with debit total", %{session: session} do
      account = leaf_account(session)

      assert {:ok, _} = credit(session, account, 20_000)
      assert {:ok, _} = debit(session, account, 8_000)

      [row] = balance_rows_for(session, account)
      assert row.daily_credit == 20_000
      assert row.daily_debit == 8_000
    end

    test "multiple entries on the same day upsert the single daily row", %{session: session} do
      account = leaf_account(session)

      assert {:ok, _} = credit(session, account, 1_000)
      assert {:ok, _} = credit(session, account, 2_000)
      assert {:ok, _} = credit(session, account, 3_000)

      [row] = balance_rows_for(session, account)
      assert row.daily_credit == 6_000
    end

    test "balance row carries correct period fields", %{session: session} do
      account = leaf_account(session)
      assert {:ok, _} = credit(session, account, 5_000)

      [row] = balance_rows_for(session, account)
      today = Date.utc_today()
      assert row.balance_date == today
      assert row.month == today.month
      assert row.year == today.year
      assert row.iso_week >= 1 and row.iso_week <= 53
    end

    test "weekly cumulative totals are computed correctly on same day", %{session: session} do
      account = leaf_account(session)

      assert {:ok, _} = credit(session, account, 1_000)
      assert {:ok, _} = credit(session, account, 4_000)

      [row] = balance_rows_for(session, account)
      assert row.weekly_credit == 5_000
      assert row.monthly_credit == 5_000
      assert row.yearly_credit == 5_000
    end
  end

  # ── Trigger propagates to ancestors ──────────────────────────────────────────

  describe "trigger creates balance rows for ancestor accounts" do
    test "credit on leaf creates balance rows on every ancestor", %{session: session} do
      leaf = deep_leaf(session)
      assert length(leaf.ancestor_ids) == 3

      assert {:ok, _} = credit(session, leaf, 5_000)

      for id <- [leaf.id | leaf.ancestor_ids] do
        anc = LedgerAccountContext.get_ledger_account!(session, id)
        [row] = balance_rows_for(session, anc)
        assert row.daily_credit == 5_000, "expected 5000 on #{anc.la_type}"
      end
    end

    test "voiding reverses balance on direct account row AND every ancestor row",
         %{session: session} do
      leaf = deep_leaf(session)
      assert {:ok, entry} = credit(session, leaf, 7_000)

      [leaf_before] = balance_rows_for(session, leaf)
      assert leaf_before.daily_credit == 7_000

      assert {:ok, _} = void_entry(session, entry)

      for id <- [leaf.id | leaf.ancestor_ids] do
        anc = LedgerAccountContext.get_ledger_account!(session, id)
        [row] = balance_rows_for(session, anc)
        assert row.daily_credit == 0, "expected 0 on #{anc.la_type} after void"
      end
    end
  end

  # ── last_*_limit propagation ──────────────────────────────────────────────────

  describe "trigger copies *_limit_at_entry to balance row last_*_limit columns" do
    test "daily credit limit is propagated to balance row", %{session: session} do
      account = leaf_account(session)

      assert {:ok, _} = credit(session, account, 1_000, daily_credit_limit: 50_000)

      [row] = balance_rows_for(session, account)
      assert row.last_daily_credit_limit == 50_000
    end

    test "all 8 limit columns are propagated correctly", %{session: session} do
      account = leaf_account(session)

      assert {:ok, _} =
               credit(session, account, 1_000,
                 daily_debit_limit: 10_000,
                 daily_credit_limit: 20_000,
                 weekly_debit_limit: 50_000,
                 weekly_credit_limit: 100_000,
                 monthly_debit_limit: 200_000,
                 monthly_credit_limit: 400_000,
                 yearly_debit_limit: 1_000_000,
                 yearly_credit_limit: 2_000_000
               )

      [row] = balance_rows_for(session, account)
      assert row.last_daily_debit_limit == 10_000
      assert row.last_daily_credit_limit == 20_000
      assert row.last_weekly_debit_limit == 50_000
      assert row.last_weekly_credit_limit == 100_000
      assert row.last_monthly_debit_limit == 200_000
      assert row.last_monthly_credit_limit == 400_000
      assert row.last_yearly_debit_limit == 1_000_000
      assert row.last_yearly_credit_limit == 2_000_000
    end

    test "NULL limits (unconstrained) are propagated as nil on balance row", %{session: session} do
      account = leaf_account(session)
      assert {:ok, _} = credit(session, account, 1_000)

      [row] = balance_rows_for(session, account)
      assert is_nil(row.last_daily_debit_limit)
      assert is_nil(row.last_daily_credit_limit)
      assert is_nil(row.last_weekly_debit_limit)
      assert is_nil(row.last_weekly_credit_limit)
      assert is_nil(row.last_monthly_debit_limit)
      assert is_nil(row.last_monthly_credit_limit)
      assert is_nil(row.last_yearly_debit_limit)
      assert is_nil(row.last_yearly_credit_limit)
    end

    test "second entry with different limits updates last_*_limit to most recent decision",
         %{session: session} do
      account = leaf_account(session)

      assert {:ok, _} = credit(session, account, 1_000, daily_credit_limit: 50_000)
      [row_first] = balance_rows_for(session, account)
      assert row_first.last_daily_credit_limit == 50_000

      assert {:ok, _} = credit(session, account, 2_000, daily_credit_limit: 30_000)
      [row_second] = balance_rows_for(session, account)
      assert row_second.last_daily_credit_limit == 30_000
    end
  end

  # ── Control limit CHECK constraint enforcement ──────────────────────────────

  describe "control limit CHECK constraint enforcement (DB-level)" do
    test "credit within daily_credit_limit succeeds", %{session: session} do
      account = leaf_account(session)
      assert {:ok, _} = credit(session, account, 1_000, daily_credit_limit: 50_000)
    end

    test "credit at the boundary succeeds", %{session: session} do
      account = leaf_account(session)
      assert {:ok, _} = credit(session, account, 50_000, daily_credit_limit: 50_000)
    end

    test "credit exceeding daily_credit_limit is voided with full rejected_* contract",
         %{session: session} do
      account = leaf_account(session)

      assert {:ok, _} = credit(session, account, 3_000, daily_credit_limit: 5_000)

      assert {:ok, voided} = credit(session, account, 5_000, daily_credit_limit: 5_000)
      assert voided.status == :voided
      assert voided.rejected_ledger_account_id == account.id
      assert voided.rejected_period == "daily"
      assert voided.rejected_direction == "credit"
      assert voided.rejected_rule == "test"
      assert voided.rejected_code == "LIMIT_EXCEEDED"
    end

    test "debit exceeding daily_debit_limit is voided with full rejected_* contract",
         %{session: session} do
      account = leaf_account(session)

      assert {:ok, _} = credit(session, account, 30_000)
      assert {:ok, _} = debit(session, account, 8_000, daily_debit_limit: 10_000)

      assert {:ok, voided} = debit(session, account, 3_000, daily_debit_limit: 10_000)
      assert voided.status == :voided
      assert voided.rejected_period == "daily"
      assert voided.rejected_direction == "debit"
    end

    test "weekly_credit_limit voids with full rejected_* contract", %{session: session} do
      account = leaf_account(session)

      assert {:ok, _} = credit(session, account, 80_000, weekly_credit_limit: 100_000)
      assert {:ok, voided} = credit(session, account, 30_000, weekly_credit_limit: 100_000)
      assert voided.status == :voided
      assert voided.rejected_period == "weekly"
      assert voided.rejected_direction == "credit"
    end

    test "monthly_debit_limit voids", %{session: session} do
      account = leaf_account(session)

      assert {:ok, _} = credit(session, account, 100_000)
      assert {:ok, _} = debit(session, account, 40_000, monthly_debit_limit: 50_000)
      assert {:ok, voided} = debit(session, account, 15_000, monthly_debit_limit: 50_000)
      assert voided.status == :voided
      assert voided.rejected_period == "monthly"
      assert voided.rejected_direction == "debit"
    end

    test "yearly_credit_limit voids", %{session: session} do
      account = leaf_account(session)

      assert {:ok, _} = credit(session, account, 900_000, yearly_credit_limit: 1_000_000)
      assert {:ok, voided} = credit(session, account, 200_000, yearly_credit_limit: 1_000_000)
      assert voided.status == :voided
      assert voided.rejected_period == "yearly"
      assert voided.rejected_direction == "credit"
    end

    test "NULL limit (unconstrained) — any amount passes CHECK constraint", %{session: session} do
      account = leaf_account(session)
      assert {:ok, _} = credit(session, account, 999_999_999)
      assert {:ok, _} = credit(session, account, 999_999_999)
    end

    test "voiding a constrained entry reverses running total, allowing further entries",
         %{session: session} do
      account = leaf_account(session)

      assert {:ok, entry} = credit(session, account, 4_000, daily_credit_limit: 5_000)
      assert {:ok, _} = void_entry(session, entry)
      assert {:ok, _} = credit(session, account, 5_000, daily_credit_limit: 5_000)
    end
  end
end

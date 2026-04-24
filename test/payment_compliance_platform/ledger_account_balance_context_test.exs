defmodule PaymentCompliancePlatform.LedgerAccountBalanceContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.LedgerAccountBalanceContext
  alias PaymentCompliancePlatform.LedgerAccountContext
  alias PaymentCompliancePlatform.LedgerAccountContext.LedgerAccountBalance
  alias PaymentCompliancePlatform.LedgerEntryContext
  alias PaymentCompliancePlatform.OpenApiSchema.{LedgerAccountRequest, LedgerEntryRequest}
  alias PaymentCompliancePlatform.Repo
  import PaymentCompliancePlatform.Factory

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp make_account(session, ledger, opts \\ []) do
    request = %LedgerAccountRequest{
      account_holder_id: ledger.account_holder_id,
      ledger_id: ledger.id,
      currency: "USD",
      account_type: Keyword.get(opts, :account_type, :asset),
      status: :active,
      parent_ledger_account_id: Keyword.get(opts, :parent_ledger_account_id, nil),
      tenant_id: session.tenant_id
    }

    {:ok, account} = LedgerAccountContext.create_ledger_account(session, request)
    account
  end

  defp credit(session, account, amount, opts \\ []) do
    request = %LedgerEntryRequest{
      account_holder_id: account.account_holder_id,
      ledger_account_id: account.id,
      currency: "USD",
      amount: amount,
      entry_type: :credit,
      status: :pending,
      daily_debit_limit_at_entry: opts[:daily_debit_limit],
      daily_credit_limit_at_entry: opts[:daily_credit_limit],
      weekly_debit_limit_at_entry: opts[:weekly_debit_limit],
      weekly_credit_limit_at_entry: opts[:weekly_credit_limit],
      monthly_debit_limit_at_entry: opts[:monthly_debit_limit],
      monthly_credit_limit_at_entry: opts[:monthly_credit_limit],
      yearly_debit_limit_at_entry: opts[:yearly_debit_limit],
      yearly_credit_limit_at_entry: opts[:yearly_credit_limit],
      tenant_id: session.tenant_id
    }

    LedgerEntryContext.create_ledger_entry(session, request)
  end

  defp debit(session, account, amount, opts \\ []) do
    request = %LedgerEntryRequest{
      account_holder_id: account.account_holder_id,
      ledger_account_id: account.id,
      currency: "USD",
      amount: amount,
      entry_type: :debit,
      status: :pending,
      daily_debit_limit_at_entry: opts[:daily_debit_limit],
      daily_credit_limit_at_entry: opts[:daily_credit_limit],
      weekly_debit_limit_at_entry: opts[:weekly_debit_limit],
      weekly_credit_limit_at_entry: opts[:weekly_credit_limit],
      monthly_debit_limit_at_entry: opts[:monthly_debit_limit],
      monthly_credit_limit_at_entry: opts[:monthly_credit_limit],
      yearly_debit_limit_at_entry: opts[:yearly_debit_limit],
      yearly_credit_limit_at_entry: opts[:yearly_credit_limit],
      tenant_id: session.tenant_id
    }

    LedgerEntryContext.create_ledger_entry(session, request)
  end

  defp balance_rows_for(session, account) do
    import Ecto.Query

    Repo.all(
      from(b in LedgerAccountBalance,
        where: b.ledger_account_id == ^account.id,
        order_by: [asc: b.balance_date]
      ),
      session: session
    )
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
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)
      assert {:ok, _} = credit(session, account, 5_000)

      {:ok, {rows, _meta}} = LedgerAccountBalanceContext.list_ledger_account_balances(session)
      assert rows != []
      assert Enum.all?(rows, &(&1.tenant_id == session.tenant_id))
    end

    test "get_ledger_account_balance!/2 returns the row by id", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)
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
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

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
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      # credit first to allow debit
      assert {:ok, _} = credit(session, account, 20_000)
      assert {:ok, _} = debit(session, account, 8_000)

      [row] = balance_rows_for(session, account)
      assert row.daily_credit == 20_000
      assert row.daily_debit == 8_000
    end

    test "multiple entries on the same day upsert the single daily row", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      assert {:ok, _} = credit(session, account, 1_000)
      assert {:ok, _} = credit(session, account, 2_000)
      assert {:ok, _} = credit(session, account, 3_000)

      rows = balance_rows_for(session, account)
      assert length(rows) == 1

      [row] = rows
      assert row.daily_credit == 6_000
    end

    test "balance row carries correct period fields (iso_week, month, year)", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)
      assert {:ok, _} = credit(session, account, 5_000)

      [row] = balance_rows_for(session, account)
      today = Date.utc_today()
      assert row.balance_date == today
      assert row.month == today.month
      assert row.year == today.year
      assert row.iso_week >= 1 and row.iso_week <= 53
    end

    test "weekly cumulative totals are computed correctly on same day", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      assert {:ok, _} = credit(session, account, 1_000)
      assert {:ok, _} = credit(session, account, 4_000)

      [row] = balance_rows_for(session, account)
      # WTD = sum of daily totals for the same iso_week (only today's row exists)
      assert row.weekly_credit == 5_000
      assert row.monthly_credit == 5_000
      assert row.yearly_credit == 5_000
    end
  end

  # ── Trigger propagates to ancestors ──────────────────────────────────────────

  describe "trigger creates balance rows for ancestor accounts" do
    test "credit on child creates balance rows for child AND root", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      root = make_account(session, ledger)

      child =
        make_account(session, ledger, parent_ledger_account_id: root.id, account_type: :liability)

      assert {:ok, _} = credit(session, child, 5_000)

      assert length(balance_rows_for(session, child)) == 1
      assert length(balance_rows_for(session, root)) == 1

      [child_row] = balance_rows_for(session, child)
      [root_row] = balance_rows_for(session, root)

      assert child_row.daily_credit == 5_000
      assert root_row.daily_credit == 5_000
    end

    test "credit on grandchild creates balance rows for all three levels", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      root = make_account(session, ledger)

      child =
        make_account(session, ledger, parent_ledger_account_id: root.id, account_type: :liability)

      grandchild =
        make_account(session, ledger,
          parent_ledger_account_id: child.id,
          account_type: :equity
        )

      assert {:ok, _} = credit(session, grandchild, 3_000)

      [gc_row] = balance_rows_for(session, grandchild)
      [c_row] = balance_rows_for(session, child)
      [r_row] = balance_rows_for(session, root)

      assert gc_row.daily_credit == 3_000
      assert c_row.daily_credit == 3_000
      assert r_row.daily_credit == 3_000
    end

    test "voiding reverses balance on direct account balance row AND ancestor rows", %{
      session: session
    } do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      root = make_account(session, ledger)

      child =
        make_account(session, ledger, parent_ledger_account_id: root.id, account_type: :liability)

      assert {:ok, entry} = credit(session, child, 7_000)

      [child_row_before] = balance_rows_for(session, child)
      assert child_row_before.daily_credit == 7_000

      assert {:ok, _} = void_entry(session, entry)

      [child_row_after] = balance_rows_for(session, child)
      [root_row_after] = balance_rows_for(session, root)

      assert child_row_after.daily_credit == 0
      assert root_row_after.daily_credit == 0
    end
  end

  # ── last_*_limit propagation ──────────────────────────────────────────────────

  describe "trigger copies *_limit_at_entry to balance row last_*_limit columns" do
    test "daily credit limit is propagated to balance row", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      assert {:ok, _} =
               credit(session, account, 1_000, daily_credit_limit: 50_000)

      [row] = balance_rows_for(session, account)
      assert row.last_daily_credit_limit == 50_000
    end

    test "all 8 limit columns are propagated correctly", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

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
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

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

    test "second entry with different limits updates last_*_limit to most recent decision", %{
      session: session
    } do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      # First entry: limit = 50_000
      assert {:ok, _} = credit(session, account, 1_000, daily_credit_limit: 50_000)

      [row_after_first] = balance_rows_for(session, account)
      assert row_after_first.last_daily_credit_limit == 50_000

      # Second entry: risk engine updated limit to 30_000
      assert {:ok, _} = credit(session, account, 2_000, daily_credit_limit: 30_000)

      [row_after_second] = balance_rows_for(session, account)
      assert row_after_second.last_daily_credit_limit == 30_000
    end
  end

  # ── Velocity limit CHECK constraint enforcement ──────────────────────────────

  describe "velocity limit CHECK constraint enforcement (DB-level)" do
    test "credit within daily_credit_limit succeeds", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      assert {:ok, _} = credit(session, account, 1_000, daily_credit_limit: 50_000)
    end

    test "credit that does NOT exceed daily_credit_limit succeeds (boundary)", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      # Exactly at the limit
      assert {:ok, _} = credit(session, account, 50_000, daily_credit_limit: 50_000)
    end

    test "credit exceeding daily_credit_limit is rejected by DB CHECK constraint", %{
      session: session
    } do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      # First entry sets daily_credit_limit = 5_000 and credits 3_000
      assert {:ok, _} = credit(session, account, 3_000, daily_credit_limit: 5_000)

      # Second entry would push daily_credit to 8_000 which exceeds limit 5_000
      assert_raise Ecto.ConstraintError, ~r/lab_daily_credit_limit/, fn ->
        credit(session, account, 5_000, daily_credit_limit: 5_000)
      end
    end

    test "debit exceeding daily_debit_limit is rejected by DB CHECK constraint", %{
      session: session
    } do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      # Give the account some balance first (no debit limit on credit)
      assert {:ok, _} = credit(session, account, 30_000)

      # First debit sets daily_debit_limit = 10_000 and debits 8_000
      assert {:ok, _} = debit(session, account, 8_000, daily_debit_limit: 10_000)

      # Second debit would push daily_debit to 11_000 > limit 10_000
      assert_raise Ecto.ConstraintError, ~r/lab_daily_debit_limit/, fn ->
        debit(session, account, 3_000, daily_debit_limit: 10_000)
      end
    end

    test "weekly_credit_limit is enforced", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      # Credit 80_000 with weekly limit 100_000 → WTD = 80_000 (ok)
      assert {:ok, _} = credit(session, account, 80_000, weekly_credit_limit: 100_000)

      # Another credit of 30_000 would push WTD to 110_000 > 100_000
      assert_raise Ecto.ConstraintError, ~r/lab_weekly_credit_limit/, fn ->
        credit(session, account, 30_000, weekly_credit_limit: 100_000)
      end
    end

    test "monthly_debit_limit is enforced", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      # Give balance first
      assert {:ok, _} = credit(session, account, 100_000)

      # Debit 40_000 with monthly limit 50_000 → MTD = 40_000 (ok)
      assert {:ok, _} = debit(session, account, 40_000, monthly_debit_limit: 50_000)

      # Another debit of 15_000 would push MTD to 55_000 > 50_000
      assert_raise Ecto.ConstraintError, ~r/lab_monthly_debit_limit/, fn ->
        debit(session, account, 15_000, monthly_debit_limit: 50_000)
      end
    end

    test "yearly_credit_limit is enforced", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      # Credit 900_000 with yearly limit 1_000_000 → YTD = 900_000 (ok)
      assert {:ok, _} = credit(session, account, 900_000, yearly_credit_limit: 1_000_000)

      # Another credit of 200_000 would push YTD to 1_100_000 > 1_000_000
      assert_raise Ecto.ConstraintError, ~r/lab_yearly_credit_limit/, fn ->
        credit(session, account, 200_000, yearly_credit_limit: 1_000_000)
      end
    end

    test "NULL limit (unconstrained) — any amount passes CHECK constraint", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      # No limits set → unconstrained
      assert {:ok, _} = credit(session, account, 999_999_999)
      assert {:ok, _} = credit(session, account, 999_999_999)
    end

    test "voiding a constrained entry reverses the running total, allowing further entries", %{
      session: session
    } do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      # Credit 4_000 with daily limit 5_000 → daily_credit = 4_000
      assert {:ok, entry} = credit(session, account, 4_000, daily_credit_limit: 5_000)

      # Void it → daily_credit returns to 0
      assert {:ok, _} = void_entry(session, entry)

      # Now we can credit 5_000 again within the limit
      assert {:ok, _} = credit(session, account, 5_000, daily_credit_limit: 5_000)
    end
  end
end

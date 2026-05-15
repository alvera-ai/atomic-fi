defmodule AtomicFi.Repo.Migrations.CreateLedgerAccountBalances do
  use Ecto.Migration

  def change do
    create table(:ledger_account_balances, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # FK to ledger_accounts — the account this balance row belongs to
      add :ledger_account_id,
          references(:ledger_accounts, type: :binary_id, on_delete: :delete_all),
          null: false

      # RLS scope
      add :tenant_id,
          references(:tenants, type: :binary_id, on_delete: :restrict),
          null: false

      # ── Period key ──────────────────────────────────────────────────────────
      # One row per (ledger_account_id, balance_date). Each row represents a
      # calendar day and carries cumulative week-to-date, month-to-date, and
      # year-to-date totals. Past rows become immutable historical audit data.
      add :balance_date, :date, null: false
      add :iso_week, :integer, null: false
      add :month, :integer, null: false
      add :year, :integer, null: false

      # ── Cumulative running balances (in minor currency units) ───────────────
      # Incremented by the trigger on ledger_entry INSERT.
      # Decremented by the trigger when ledger_entry.status transitions to :voided.
      # daily_debit/credit = amount credited/debited on this calendar day
      # weekly_debit/credit = week-to-date cumulative (sum of daily rows for this iso_week+year)
      # monthly/yearly — same pattern
      add :daily_debit, :integer, null: false, default: 0
      add :daily_credit, :integer, null: false, default: 0
      add :weekly_debit, :integer, null: false, default: 0
      add :weekly_credit, :integer, null: false, default: 0
      add :monthly_debit, :integer, null: false, default: 0
      add :monthly_credit, :integer, null: false, default: 0
      add :yearly_debit, :integer, null: false, default: 0
      add :yearly_credit, :integer, null: false, default: 0

      # ── Last known limits (trigger-maintained from ledger_entry.*_limit_at_entry) ──
      # The risk engine sets limits at entry creation time (written to ledger_entries).
      # The trigger copies them here so CHECK constraints can reference them.
      # NULL = unconstrained for that period/direction.
      add :last_daily_debit_limit, :integer
      add :last_daily_credit_limit, :integer
      add :last_weekly_debit_limit, :integer
      add :last_weekly_credit_limit, :integer
      add :last_monthly_debit_limit, :integer
      add :last_monthly_credit_limit, :integer
      add :last_yearly_debit_limit, :integer
      add :last_yearly_credit_limit, :integer

      timestamps(type: :utc_datetime_usec)
    end

    # One balance row per account per day
    create unique_index(:ledger_account_balances, [:ledger_account_id, :balance_date],
             name: :ledger_account_balances_account_date_unique
           )

    create index(:ledger_account_balances, [:tenant_id])
    create index(:ledger_account_balances, [:ledger_account_id, :iso_week, :year])
    create index(:ledger_account_balances, [:ledger_account_id, :month, :year])
    create index(:ledger_account_balances, [:ledger_account_id, :year])

    # ── 8 control limit CHECK constraints ─────────────────────────────────
    # Each constraint compares the cumulative running total against the last
    # limit propagated from the risk engine via the triggering ledger_entry.
    execute(
      "ALTER TABLE ledger_account_balances ADD CONSTRAINT lab_daily_debit_limit
        CHECK (last_daily_debit_limit IS NULL OR daily_debit <= last_daily_debit_limit)",
      "ALTER TABLE ledger_account_balances DROP CONSTRAINT lab_daily_debit_limit"
    )

    execute(
      "ALTER TABLE ledger_account_balances ADD CONSTRAINT lab_daily_credit_limit
        CHECK (last_daily_credit_limit IS NULL OR daily_credit <= last_daily_credit_limit)",
      "ALTER TABLE ledger_account_balances DROP CONSTRAINT lab_daily_credit_limit"
    )

    execute(
      "ALTER TABLE ledger_account_balances ADD CONSTRAINT lab_weekly_debit_limit
        CHECK (last_weekly_debit_limit IS NULL OR weekly_debit <= last_weekly_debit_limit)",
      "ALTER TABLE ledger_account_balances DROP CONSTRAINT lab_weekly_debit_limit"
    )

    execute(
      "ALTER TABLE ledger_account_balances ADD CONSTRAINT lab_weekly_credit_limit
        CHECK (last_weekly_credit_limit IS NULL OR weekly_credit <= last_weekly_credit_limit)",
      "ALTER TABLE ledger_account_balances DROP CONSTRAINT lab_weekly_credit_limit"
    )

    execute(
      "ALTER TABLE ledger_account_balances ADD CONSTRAINT lab_monthly_debit_limit
        CHECK (last_monthly_debit_limit IS NULL OR monthly_debit <= last_monthly_debit_limit)",
      "ALTER TABLE ledger_account_balances DROP CONSTRAINT lab_monthly_debit_limit"
    )

    execute(
      "ALTER TABLE ledger_account_balances ADD CONSTRAINT lab_monthly_credit_limit
        CHECK (last_monthly_credit_limit IS NULL OR monthly_credit <= last_monthly_credit_limit)",
      "ALTER TABLE ledger_account_balances DROP CONSTRAINT lab_monthly_credit_limit"
    )

    execute(
      "ALTER TABLE ledger_account_balances ADD CONSTRAINT lab_yearly_debit_limit
        CHECK (last_yearly_debit_limit IS NULL OR yearly_debit <= last_yearly_debit_limit)",
      "ALTER TABLE ledger_account_balances DROP CONSTRAINT lab_yearly_debit_limit"
    )

    execute(
      "ALTER TABLE ledger_account_balances ADD CONSTRAINT lab_yearly_credit_limit
        CHECK (last_yearly_credit_limit IS NULL OR yearly_credit <= last_yearly_credit_limit)",
      "ALTER TABLE ledger_account_balances DROP CONSTRAINT lab_yearly_credit_limit"
    )

    # ── PostgreSQL trigger function ─────────────────────────────────────────
    # Fires AFTER INSERT or AFTER UPDATE OF status on ledger_entries.
    #
    # On INSERT:
    #   - Increments ledger_accounts.balance (signed delta)
    #   - Upserts ledger_account_balances row for (account, today) — computing
    #     cumulative week/month/year totals from prior rows for the same period
    #   - Propagates to all ancestor accounts via ancestor_ids array
    #   - Copies *_limit_at_entry from the entry to last_*_limit on balance row
    #
    # On UPDATE (status → voided):
    #   - Reverses all the above (negative delta)
    #
    # Running balance accumulation and CHECK enforcement are independent:
    # the trigger always updates running totals; CHECK constraints fire
    # automatically after the UPDATE if limits are set.
    execute(
      """
      CREATE OR REPLACE FUNCTION propagate_ledger_entry_to_balances()
      RETURNS TRIGGER AS $$
      DECLARE
        v_debit_delta   INTEGER := 0;
        v_credit_delta  INTEGER := 0;
        v_ancestor_ids  UUID[];
        v_account_ids   UUID[];
        v_account_id    UUID;
        v_today         DATE    := CURRENT_DATE;
        v_iso_week      INTEGER := EXTRACT(ISODOW FROM CURRENT_DATE)::INTEGER;
        v_month         INTEGER := EXTRACT(MONTH FROM CURRENT_DATE)::INTEGER;
        v_year          INTEGER := EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER;
        v_prior_weekly_debit   INTEGER;
        v_prior_weekly_credit  INTEGER;
        v_prior_monthly_debit  INTEGER;
        v_prior_monthly_credit INTEGER;
        v_prior_yearly_debit   INTEGER;
        v_prior_yearly_credit  INTEGER;
      BEGIN
        -- Determine direction and magnitude
        IF TG_OP = 'INSERT' THEN
          IF NEW.entry_type = 'debit'  THEN v_debit_delta  := NEW.amount; END IF;
          IF NEW.entry_type = 'credit' THEN v_credit_delta := NEW.amount; END IF;
        ELSIF TG_OP = 'UPDATE' AND NEW.status = 'voided' AND OLD.status != 'voided' THEN
          -- Reverse the original entry effect
          IF OLD.entry_type = 'debit'  THEN v_debit_delta  := -OLD.amount; END IF;
          IF OLD.entry_type = 'credit' THEN v_credit_delta := -OLD.amount; END IF;
        ELSE
          RETURN NEW; -- No-op for other transitions
        END IF;

        -- Update running balance on ledger_accounts (credit = +, debit = -)
        UPDATE ledger_accounts
        SET balance = balance + v_credit_delta - v_debit_delta
        WHERE id = NEW.ledger_account_id;

        -- Collect direct account + all ancestor account IDs
        SELECT ancestor_ids INTO v_ancestor_ids
        FROM ledger_accounts WHERE id = NEW.ledger_account_id;

        v_account_ids := ARRAY[NEW.ledger_account_id] || COALESCE(v_ancestor_ids, ARRAY[]::UUID[]);

        -- Upsert balance row for each affected account
        FOREACH v_account_id IN ARRAY v_account_ids LOOP
          -- Compute cumulative WTD/MTD/YTD from existing rows for the same period
          -- (excluding today's row to avoid double-counting on existing row update)
          SELECT
            COALESCE(SUM(daily_debit),  0),
            COALESCE(SUM(daily_credit), 0)
          INTO v_prior_weekly_debit, v_prior_weekly_credit
          FROM ledger_account_balances
          WHERE ledger_account_id = v_account_id
            AND iso_week = v_iso_week AND year = v_year
            AND balance_date != v_today;

          SELECT
            COALESCE(SUM(daily_debit),  0),
            COALESCE(SUM(daily_credit), 0)
          INTO v_prior_monthly_debit, v_prior_monthly_credit
          FROM ledger_account_balances
          WHERE ledger_account_id = v_account_id
            AND month = v_month AND year = v_year
            AND balance_date != v_today;

          SELECT
            COALESCE(SUM(daily_debit),  0),
            COALESCE(SUM(daily_credit), 0)
          INTO v_prior_yearly_debit, v_prior_yearly_credit
          FROM ledger_account_balances
          WHERE ledger_account_id = v_account_id
            AND year = v_year
            AND balance_date != v_today;

          INSERT INTO ledger_account_balances (
            id, ledger_account_id, tenant_id,
            balance_date, iso_week, month, year,
            daily_debit,  daily_credit,
            weekly_debit, weekly_credit,
            monthly_debit, monthly_credit,
            yearly_debit,  yearly_credit,
            last_daily_debit_limit,    last_daily_credit_limit,
            last_weekly_debit_limit,   last_weekly_credit_limit,
            last_monthly_debit_limit,  last_monthly_credit_limit,
            last_yearly_debit_limit,   last_yearly_credit_limit,
            inserted_at, updated_at
          ) SELECT
            gen_random_uuid(), v_account_id, la.tenant_id,
            v_today, v_iso_week, v_month, v_year,
            v_debit_delta,  v_credit_delta,
            v_prior_weekly_debit  + v_debit_delta,
            v_prior_weekly_credit + v_credit_delta,
            v_prior_monthly_debit  + v_debit_delta,
            v_prior_monthly_credit + v_credit_delta,
            v_prior_yearly_debit  + v_debit_delta,
            v_prior_yearly_credit + v_credit_delta,
            -- Limits from the entry's risk-engine snapshot (NULL = unconstrained)
            NEW.daily_debit_limit_at_entry,   NEW.daily_credit_limit_at_entry,
            NEW.weekly_debit_limit_at_entry,  NEW.weekly_credit_limit_at_entry,
            NEW.monthly_debit_limit_at_entry, NEW.monthly_credit_limit_at_entry,
            NEW.yearly_debit_limit_at_entry,  NEW.yearly_credit_limit_at_entry,
            NOW(), NOW()
          FROM ledger_accounts la WHERE la.id = v_account_id
          ON CONFLICT (ledger_account_id, balance_date)
          DO UPDATE SET
            daily_debit    = ledger_account_balances.daily_debit   + EXCLUDED.daily_debit,
            daily_credit   = ledger_account_balances.daily_credit  + EXCLUDED.daily_credit,
            weekly_debit   = v_prior_weekly_debit  + ledger_account_balances.daily_debit  + EXCLUDED.daily_debit,
            weekly_credit  = v_prior_weekly_credit + ledger_account_balances.daily_credit + EXCLUDED.daily_credit,
            monthly_debit  = v_prior_monthly_debit  + ledger_account_balances.daily_debit  + EXCLUDED.daily_debit,
            monthly_credit = v_prior_monthly_credit + ledger_account_balances.daily_credit + EXCLUDED.daily_credit,
            yearly_debit   = v_prior_yearly_debit  + ledger_account_balances.daily_debit  + EXCLUDED.daily_debit,
            yearly_credit  = v_prior_yearly_credit + ledger_account_balances.daily_credit + EXCLUDED.daily_credit,
            -- Update limits to reflect the most recent risk engine decision
            last_daily_debit_limit    = EXCLUDED.last_daily_debit_limit,
            last_daily_credit_limit   = EXCLUDED.last_daily_credit_limit,
            last_weekly_debit_limit   = EXCLUDED.last_weekly_debit_limit,
            last_weekly_credit_limit  = EXCLUDED.last_weekly_credit_limit,
            last_monthly_debit_limit  = EXCLUDED.last_monthly_debit_limit,
            last_monthly_credit_limit = EXCLUDED.last_monthly_credit_limit,
            last_yearly_debit_limit   = EXCLUDED.last_yearly_debit_limit,
            last_yearly_credit_limit  = EXCLUDED.last_yearly_credit_limit,
            updated_at = NOW();
        END LOOP;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION IF EXISTS propagate_ledger_entry_to_balances CASCADE"
    )

    execute(
      """
      CREATE TRIGGER ledger_entry_propagate_to_balances
        AFTER INSERT OR UPDATE OF status ON ledger_entries
        FOR EACH ROW EXECUTE FUNCTION propagate_ledger_entry_to_balances()
      """,
      "DROP TRIGGER IF EXISTS ledger_entry_propagate_to_balances ON ledger_entries"
    )
  end
end

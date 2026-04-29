defmodule AtomicFi.Repo.Migrations.FixTriggerIsodowAndUtcDate do
  use Ecto.Migration

  def change do
    # Fix two bugs in the trigger:
    # 1. ISODOW (day-of-week 1-7) → WEEK (ISO week number 1-53)
    # 2. CURRENT_DATE (local timezone) → (NOW() AT TIME ZONE 'UTC')::DATE (always UTC)
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
        v_today         DATE    := (NOW() AT TIME ZONE 'UTC')::DATE;
        v_iso_week      INTEGER := EXTRACT(WEEK FROM (NOW() AT TIME ZONE 'UTC'))::INTEGER;
        v_month         INTEGER := EXTRACT(MONTH FROM (NOW() AT TIME ZONE 'UTC'))::INTEGER;
        v_year          INTEGER := EXTRACT(YEAR  FROM (NOW() AT TIME ZONE 'UTC'))::INTEGER;
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

        -- Collect ancestor IDs for the directly-targeted account
        SELECT ancestor_ids INTO v_ancestor_ids
        FROM ledger_accounts WHERE id = NEW.ledger_account_id;

        v_account_ids := ARRAY[NEW.ledger_account_id] || COALESCE(v_ancestor_ids, ARRAY[]::UUID[]);

        -- Update running balance on ALL affected accounts (direct + ancestors)
        UPDATE ledger_accounts
        SET balance = balance + v_credit_delta - v_debit_delta
        WHERE id = ANY(v_account_ids);

        -- Upsert ledger_account_balances row for each affected account
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
  end
end

defmodule AtomicFi.Repo.Migrations.ReshapeLedgerForVelocityLimits do
  use Ecto.Migration

  # Reshape the ledger machinery for rule-engine (ZenRule) velocity limits.
  #
  #   * NEW composite type  velocity_limit (period varchar, direction varchar, cap bigint, rule varchar)
  #   * ledger_accounts  : drop GAAP account_type (+ its unique); add side (credit|debit), regime
  #                        (generic; mandatory — Ecto sets it incl. a sentinel for the master roots),
  #                        payment_account_id / counterparty_id FKs (NULL on master roots);
  #                        3 partial unique indexes on [:ledger_id, :side, …].
  #   * ledger_entries   : drop the 8 *_limit_at_entry int cols → limits_at_entry velocity_limit[]
  #                        (the rule engine's output for this entry's leaf account: a list of
  #                        {period, direction, cap, rule}).
  #   * ledger_account_balances : UNCHANGED — keeps the 8 flat cumulative cols, the 8 flat
  #                        last_*_limit cols, and the 8 CHECK constraints. (A CHECK can't iterate an
  #                        array, so the limits the CHECKs reference must stay flat columns.)
  #   * trigger propagate_ledger_entry_to_balances : becomes BEFORE INSERT OR UPDATE OF status.
  #                        It walks ancestor_ids || self, bumps cumulative balances and fans the
  #                        entry's limits_at_entry[] out into the flat last_*_limit columns on each
  #                        ancestor balance row. The 8 CHECK constraints fire on a breach; the
  #                        trigger's EXCEPTION handler then marks the entry :voided and records
  #                        which account / period / direction / rule (rejected_* flat fields).
  #
  # Not reversible (the array reshape is one-way).

  def up do
    execute("""
    DO $$ BEGIN
      CREATE TYPE velocity_limit AS (period varchar, direction varchar, cap bigint, rule varchar);
    EXCEPTION WHEN duplicate_object THEN null;
    END $$;
    """)

    # ── ledger_accounts ────────────────────────────────────────────────────────
    drop_if_exists index(:ledger_accounts, [:ledger_id, :account_type],
                     name: :ledger_accounts_ledger_id_account_type_index
                   )

    alter table(:ledger_accounts) do
      remove :account_type
      add :side, :string, null: false, default: "credit"
      add :regime, :string, null: false, default: "_master"

      add :payment_account_id,
          references(:payment_accounts, type: :binary_id, on_delete: :restrict)

      add :counterparty_id,
          references(:counterparties, type: :binary_id, on_delete: :restrict)
    end

    # Defaults exist only to backfill any pre-existing rows; new rows set side/regime explicitly.
    execute("ALTER TABLE ledger_accounts ALTER COLUMN side DROP DEFAULT")
    execute("ALTER TABLE ledger_accounts ALTER COLUMN regime DROP DEFAULT")

    create index(:ledger_accounts, [:payment_account_id])
    create index(:ledger_accounts, [:counterparty_id])

    create unique_index(:ledger_accounts, [:ledger_id, :side, :regime],
             name: :ledger_accounts_ledger_side_regime_master_unique,
             where: "payment_account_id IS NULL AND counterparty_id IS NULL"
           )

    create unique_index(:ledger_accounts, [:ledger_id, :side, :payment_account_id, :regime],
             name: :ledger_accounts_ledger_side_pa_regime_unique,
             where: "payment_account_id IS NOT NULL"
           )

    create unique_index(:ledger_accounts, [:ledger_id, :side, :counterparty_id, :regime],
             name: :ledger_accounts_ledger_side_cp_regime_unique,
             where: "counterparty_id IS NOT NULL"
           )

    # ── ledger_entries ─────────────────────────────────────────────────────────
    alter table(:ledger_entries) do
      add :limits_at_entry, {:array, :velocity_limit}
      remove :daily_debit_limit_at_entry
      remove :weekly_debit_limit_at_entry
      remove :monthly_debit_limit_at_entry
      remove :yearly_debit_limit_at_entry
      remove :daily_credit_limit_at_entry
      remove :weekly_credit_limit_at_entry
      remove :monthly_credit_limit_at_entry
      remove :yearly_credit_limit_at_entry
    end

    # ── trigger ────────────────────────────────────────────────────────────────
    execute("DROP TRIGGER IF EXISTS ledger_entry_propagate_to_balances ON ledger_entries")
    execute(new_trigger_fn())

    execute("""
    CREATE TRIGGER ledger_entry_propagate_to_balances
      BEFORE INSERT OR UPDATE OF status ON ledger_entries
      FOR EACH ROW EXECUTE FUNCTION propagate_ledger_entry_to_balances()
    """)
  end

  def down do
    raise Ecto.MigrationError,
      message:
        "ReshapeLedgerForVelocityLimits is not reversible — restore from a backup if needed."
  end

  defp new_trigger_fn do
    """
    CREATE OR REPLACE FUNCTION propagate_ledger_entry_to_balances()
    RETURNS TRIGGER AS $$
    DECLARE
      v_debit_delta   INTEGER := 0;
      v_credit_delta  INTEGER := 0;
      v_limits        velocity_limit[];
      v_ancestor_ids  UUID[];
      v_account_ids   UUID[];
      v_account_id    UUID;
      v_breach_node   UUID;
      v_constraint    TEXT;
      v_period        TEXT;
      v_direction     TEXT;
      v_today         DATE    := (NOW() AT TIME ZONE 'UTC')::DATE;
      v_iso_week      INTEGER := EXTRACT(WEEK  FROM (NOW() AT TIME ZONE 'UTC'))::INTEGER;
      v_month         INTEGER := EXTRACT(MONTH FROM (NOW() AT TIME ZONE 'UTC'))::INTEGER;
      v_year          INTEGER := EXTRACT(YEAR  FROM (NOW() AT TIME ZONE 'UTC'))::INTEGER;
      v_pw_d INTEGER; v_pw_c INTEGER;
      v_pm_d INTEGER; v_pm_c INTEGER;
      v_py_d INTEGER; v_py_c INTEGER;
      v_ld_d BIGINT; v_ld_c BIGINT;
      v_lw_d BIGINT; v_lw_c BIGINT;
      v_lm_d BIGINT; v_lm_c BIGINT;
      v_ly_d BIGINT; v_ly_c BIGINT;
    BEGIN
      IF TG_OP = 'INSERT' THEN
        -- A rejected entry (inserted already :voided) moves nothing.
        IF NEW.status = 'voided' THEN
          RETURN NEW;
        END IF;
        IF NEW.entry_type = 'debit'  THEN v_debit_delta  := NEW.amount; END IF;
        IF NEW.entry_type = 'credit' THEN v_credit_delta := NEW.amount; END IF;
        v_limits := NEW.limits_at_entry;
      ELSIF TG_OP = 'UPDATE' AND NEW.status = 'voided' AND OLD.status != 'voided' THEN
        IF OLD.entry_type = 'debit'  THEN v_debit_delta  := -OLD.amount; END IF;
        IF OLD.entry_type = 'credit' THEN v_credit_delta := -OLD.amount; END IF;
        v_limits := OLD.limits_at_entry;
      ELSE
        RETURN NEW;
      END IF;

      -- Fan the entry's velocity_limit[] out into the 8 flat per-period/direction caps.
      v_ld_d := (SELECT l.cap FROM unnest(v_limits) AS l WHERE l.period = 'daily'   AND l.direction = 'debit'  LIMIT 1);
      v_ld_c := (SELECT l.cap FROM unnest(v_limits) AS l WHERE l.period = 'daily'   AND l.direction = 'credit' LIMIT 1);
      v_lw_d := (SELECT l.cap FROM unnest(v_limits) AS l WHERE l.period = 'weekly'  AND l.direction = 'debit'  LIMIT 1);
      v_lw_c := (SELECT l.cap FROM unnest(v_limits) AS l WHERE l.period = 'weekly'  AND l.direction = 'credit' LIMIT 1);
      v_lm_d := (SELECT l.cap FROM unnest(v_limits) AS l WHERE l.period = 'monthly' AND l.direction = 'debit'  LIMIT 1);
      v_lm_c := (SELECT l.cap FROM unnest(v_limits) AS l WHERE l.period = 'monthly' AND l.direction = 'credit' LIMIT 1);
      v_ly_d := (SELECT l.cap FROM unnest(v_limits) AS l WHERE l.period = 'yearly'  AND l.direction = 'debit'  LIMIT 1);
      v_ly_c := (SELECT l.cap FROM unnest(v_limits) AS l WHERE l.period = 'yearly'  AND l.direction = 'credit' LIMIT 1);

      SELECT ancestor_ids INTO v_ancestor_ids FROM ledger_accounts WHERE id = NEW.ledger_account_id;
      v_account_ids := ARRAY[NEW.ledger_account_id] || COALESCE(v_ancestor_ids, ARRAY[]::UUID[]);

      BEGIN
        -- Running net balance on the leaf + all ancestors (credit = +, debit = -).
        UPDATE ledger_accounts
        SET balance = balance + v_credit_delta - v_debit_delta
        WHERE id = ANY(v_account_ids);

        FOREACH v_account_id IN ARRAY v_account_ids LOOP
          v_breach_node := v_account_id;  -- in case the next UPSERT trips a CHECK on this node

          SELECT COALESCE(SUM(daily_debit), 0), COALESCE(SUM(daily_credit), 0)
          INTO v_pw_d, v_pw_c
          FROM ledger_account_balances
          WHERE ledger_account_id = v_account_id AND iso_week = v_iso_week AND year = v_year AND balance_date != v_today;

          SELECT COALESCE(SUM(daily_debit), 0), COALESCE(SUM(daily_credit), 0)
          INTO v_pm_d, v_pm_c
          FROM ledger_account_balances
          WHERE ledger_account_id = v_account_id AND month = v_month AND year = v_year AND balance_date != v_today;

          SELECT COALESCE(SUM(daily_debit), 0), COALESCE(SUM(daily_credit), 0)
          INTO v_py_d, v_py_c
          FROM ledger_account_balances
          WHERE ledger_account_id = v_account_id AND year = v_year AND balance_date != v_today;

          INSERT INTO ledger_account_balances
            (id, ledger_account_id, tenant_id, balance_date, iso_week, month, year,
             daily_debit, daily_credit, weekly_debit, weekly_credit, monthly_debit, monthly_credit,
             yearly_debit, yearly_credit,
             last_daily_debit_limit,    last_daily_credit_limit,
             last_weekly_debit_limit,   last_weekly_credit_limit,
             last_monthly_debit_limit,  last_monthly_credit_limit,
             last_yearly_debit_limit,   last_yearly_credit_limit,
             inserted_at, updated_at)
          SELECT gen_random_uuid(), v_account_id, la.tenant_id, v_today, v_iso_week, v_month, v_year,
            v_debit_delta, v_credit_delta,
            v_pw_d + v_debit_delta, v_pw_c + v_credit_delta,
            v_pm_d + v_debit_delta, v_pm_c + v_credit_delta,
            v_py_d + v_debit_delta, v_py_c + v_credit_delta,
            v_ld_d, v_ld_c, v_lw_d, v_lw_c, v_lm_d, v_lm_c, v_ly_d, v_ly_c,
            NOW(), NOW()
          FROM ledger_accounts la WHERE la.id = v_account_id
          ON CONFLICT (ledger_account_id, balance_date) DO UPDATE SET
            daily_debit    = ledger_account_balances.daily_debit   + EXCLUDED.daily_debit,
            daily_credit   = ledger_account_balances.daily_credit  + EXCLUDED.daily_credit,
            weekly_debit   = v_pw_d + ledger_account_balances.daily_debit  + EXCLUDED.daily_debit,
            weekly_credit  = v_pw_c + ledger_account_balances.daily_credit + EXCLUDED.daily_credit,
            monthly_debit  = v_pm_d + ledger_account_balances.daily_debit  + EXCLUDED.daily_debit,
            monthly_credit = v_pm_c + ledger_account_balances.daily_credit + EXCLUDED.daily_credit,
            yearly_debit   = v_py_d + ledger_account_balances.daily_debit  + EXCLUDED.daily_debit,
            yearly_credit  = v_py_c + ledger_account_balances.daily_credit + EXCLUDED.daily_credit,
            last_daily_debit_limit    = COALESCE(EXCLUDED.last_daily_debit_limit,    ledger_account_balances.last_daily_debit_limit),
            last_daily_credit_limit   = COALESCE(EXCLUDED.last_daily_credit_limit,   ledger_account_balances.last_daily_credit_limit),
            last_weekly_debit_limit   = COALESCE(EXCLUDED.last_weekly_debit_limit,   ledger_account_balances.last_weekly_debit_limit),
            last_weekly_credit_limit  = COALESCE(EXCLUDED.last_weekly_credit_limit,  ledger_account_balances.last_weekly_credit_limit),
            last_monthly_debit_limit  = COALESCE(EXCLUDED.last_monthly_debit_limit,  ledger_account_balances.last_monthly_debit_limit),
            last_monthly_credit_limit = COALESCE(EXCLUDED.last_monthly_credit_limit, ledger_account_balances.last_monthly_credit_limit),
            last_yearly_debit_limit   = COALESCE(EXCLUDED.last_yearly_debit_limit,   ledger_account_balances.last_yearly_debit_limit),
            last_yearly_credit_limit  = COALESCE(EXCLUDED.last_yearly_credit_limit,  ledger_account_balances.last_yearly_credit_limit),
            updated_at = NOW();
        END LOOP;
      EXCEPTION WHEN check_violation THEN
        -- A ledger_account_balances CHECK (lab_<period>_<direction>_limit) fired on v_breach_node;
        -- all balance changes above are rolled back. Persist the entry :voided with the details.
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        v_period    := split_part(v_constraint, '_', 2);   -- 'lab_weekly_debit_limit' → 'weekly'
        v_direction := split_part(v_constraint, '_', 3);   --                          → 'debit'
        NEW.status := 'voided';
        NEW.rejected_ledger_account_id := v_breach_node;
        NEW.rejected_period    := v_period;
        NEW.rejected_direction := v_direction;
        NEW.rejected_rule      := (SELECT l.rule FROM unnest(v_limits) AS l
                                   WHERE l.period = v_period AND l.direction = v_direction LIMIT 1);
        NEW.rejected_code      := 'LIMIT_EXCEEDED';
      END;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """
  end
end

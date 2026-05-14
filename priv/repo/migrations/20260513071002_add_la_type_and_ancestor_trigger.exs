defmodule AtomicFi.Repo.Migrations.AddLaTypeAndAncestorTrigger do
  @moduledoc """
  Locks down the LedgerAccount tree shape end-to-end. Five coupled pieces,
  all in one migration:

    1. `ledger_accounts.la_type` — string-backed enum naming the six valid
       row shapes (pa, cp, regime cross). CHECK constraint enforces
       consistency between `la_type` and (pa_id, cp_id, regime).

    2. `ledger_accounts.descendant_ids` — flat list of every LA descended
       from this row. Maintained by an AFTER INSERT trigger; together with
       `ancestor_ids` it lets the txn flow gather the full subtree per
       side in one read.

    3. No-cycle CHECK constraint — row's own id ∉ ancestor_ids,
       row's own id ∉ descendant_ids, ancestor_ids ∩ descendant_ids = ∅.

    4. BEFORE INSERT OR UPDATE OF (la_type, pa, cp, regime, ledger_id)
       trigger that caches `ancestor_ids` by looking up the required
       ancestor rows for the inserted/updated shape. **Fails fast** if
       any required ancestor is missing — a `*_regime_root` cannot be
       created before its `*_root` sibling. SQLSTATE 23514 with CONSTRAINT
       name `ledger_accounts_ancestor_resolution` → Elixir surfaces it as
       a `%Changeset{}` via `check_constraint/3`.

    5. AFTER INSERT trigger that appends NEW.id to every ancestor row's
       `descendant_ids`. The UPDATE only touches `descendant_ids`, which
       is **not** in the BEFORE trigger's `OF (...)` list → no re-entry,
       no infinite loop.

  Shapes (regime sentinel for the catch-all is "root"):

      la_type                                          pa    cp    regime
      ───────────────────────────────────────────────  ────  ────  ──────
      account_holder_root                              NULL  NULL  root
      account_holder_regime_root                       NULL  NULL  <r>
      counter_party_root                               NULL  set   root
      counter_party_regime_root                        NULL  set   <r>
      account_holder_payment_account_root              set   NULL  root
      account_holder_payment_account_regime_root       set   NULL  <r>
      counter_party_payment_account_root               set   set   root
      counter_party_payment_account_regime_root        set   set   <r>

  The AH side mirrors the CP side — `account_holder_root` is the top of
  the AH subtree, scoped by `ledger_id` (which already encodes
  `(account_holder_id, currency)`). AH-PA-* rows roll their ancestor
  chains up through the AH root + regime root (just like CP-PA-*).

  Two extra columns enable onboarding-side BLOCK enforcement:

      is_blocked     boolean default false NOT NULL
      block_reason   text     null

  The entry-propagation trigger (in the control-limits migration)
  walks `ancestor_ids ++ [self]` on every entry insert; if any LA in
  that chain has `is_blocked = true` the entry is voided with
  `rejected_code = 'BLOCKED'` before any balance work runs. The rule
  engine writes these columns at onboarding (AH/CP/PA create / update).
  """

  use Ecto.Migration

  def change do
    # ── la_type column ─────────────────────────────────────────────────────
    alter table(:ledger_accounts) do
      add :la_type, :string
    end

    # Backfill from existing (pa, cp, regime) shape; drop the legacy
    # placeholder rows (pa=NULL/cp=NULL "_root"/"all") that don't fit the
    # new model. Forward-only.
    execute(
      """
      UPDATE ledger_accounts SET la_type =
        CASE
          WHEN payment_account_id IS NULL AND counterparty_id IS NOT NULL AND regime = 'root'
            THEN 'counter_party_root'
          WHEN payment_account_id IS NULL AND counterparty_id IS NOT NULL
            THEN 'counter_party_regime_root'
          WHEN payment_account_id IS NOT NULL AND counterparty_id IS NULL AND regime = 'root'
            THEN 'account_holder_payment_account_root'
          WHEN payment_account_id IS NOT NULL AND counterparty_id IS NULL
            THEN 'account_holder_payment_account_regime_root'
          WHEN payment_account_id IS NOT NULL AND counterparty_id IS NOT NULL AND regime = 'root'
            THEN 'counter_party_payment_account_root'
          WHEN payment_account_id IS NOT NULL AND counterparty_id IS NOT NULL
            THEN 'counter_party_payment_account_regime_root'
          ELSE NULL
        END
      """,
      ""
    )

    execute("DELETE FROM ledger_accounts WHERE la_type IS NULL", "")

    alter table(:ledger_accounts) do
      modify :la_type, :string, null: false, from: {:string, null: true}
    end

    # ── la_type ↔ (pa, cp, regime) consistency ────────────────────────────
    create constraint(:ledger_accounts, :la_type_shape_check,
             check: """
             (la_type = 'account_holder_root'
                AND payment_account_id IS NULL AND counterparty_id IS NULL
                AND regime = 'root')
             OR
             (la_type = 'account_holder_regime_root'
                AND payment_account_id IS NULL AND counterparty_id IS NULL
                AND regime <> 'root')
             OR
             (la_type = 'counter_party_root'
                AND payment_account_id IS NULL AND counterparty_id IS NOT NULL
                AND regime = 'root')
             OR
             (la_type = 'counter_party_regime_root'
                AND payment_account_id IS NULL AND counterparty_id IS NOT NULL
                AND regime <> 'root')
             OR
             (la_type = 'account_holder_payment_account_root'
                AND payment_account_id IS NOT NULL AND counterparty_id IS NULL
                AND regime = 'root')
             OR
             (la_type = 'account_holder_payment_account_regime_root'
                AND payment_account_id IS NOT NULL AND counterparty_id IS NULL
                AND regime <> 'root')
             OR
             (la_type = 'counter_party_payment_account_root'
                AND payment_account_id IS NOT NULL AND counterparty_id IS NOT NULL
                AND regime = 'root')
             OR
             (la_type = 'counter_party_payment_account_regime_root'
                AND payment_account_id IS NOT NULL AND counterparty_id IS NOT NULL
                AND regime <> 'root')
             """
           )

    # ── descendant_ids column ─────────────────────────────────────────────
    alter table(:ledger_accounts) do
      add :descendant_ids, {:array, :binary_id}, null: false, default: []
    end

    # ── onboarding-set hard caps + block state ────────────────────────────
    # The rule engine at onboarding (AH/CP/PA create / update) writes these
    # columns on every materialised LA. They are the GLOBAL HARD CEILINGS
    # for that LA — NULL means infinite (no cap).
    #
    # At txn time the entry-propagation trigger tightens
    # `ledger_account_balances.last_*_limit` to LEAST(LA.max_*, entry cap)
    # before the per-period CHECK constraints fire. Entries can only ever
    # tighten, never relax.
    #
    # is_blocked + block_reason are the belt; the LA.max_* + balance CHECK
    # constraints are the suspenders. Both are checked on every entry.
    # is_blocked has no default — every LA insert must decide explicitly.
    alter table(:ledger_accounts) do
      add :max_daily_debit, :bigint
      add :max_daily_credit, :bigint
      add :max_weekly_debit, :bigint
      add :max_weekly_credit, :bigint
      add :max_monthly_debit, :bigint
      add :max_monthly_credit, :bigint
      add :max_yearly_debit, :bigint
      add :max_yearly_credit, :bigint

      add :is_blocked, :boolean, null: false
      add :block_reason, :text
    end

    create constraint(:ledger_accounts, :block_reason_required_when_blocked,
             check: "NOT is_blocked OR block_reason IS NOT NULL"
           )

    # ── no-cycle invariant ────────────────────────────────────────────────
    # Belt-and-suspenders: triggers maintain ancestors/descendants from
    # opposite directions, but manual SQL can't violate this.
    create constraint(:ledger_accounts, :no_ancestor_descendant_overlap,
             check: """
             NOT (ancestor_ids && descendant_ids)
             AND NOT (id = ANY(ancestor_ids))
             AND NOT (id = ANY(descendant_ids))
             """
           )

    # ── BEFORE INSERT/UPDATE trigger: resolve ancestor_ids ────────────────
    execute(
      """
      CREATE OR REPLACE FUNCTION ledger_accounts_resolve_ancestor_ids() RETURNS TRIGGER AS $fn$
      DECLARE
        ah_root_id        uuid;
        ah_regime_root_id uuid;
        ah_pa_root_id     uuid;
        cp_root_id        uuid;
        cp_regime_root_id uuid;
        cp_pa_root_id     uuid;
      BEGIN
        CASE NEW.la_type
          WHEN 'account_holder_root',
               'counter_party_root' THEN
            NEW.ancestor_ids := ARRAY[]::uuid[];

          WHEN 'account_holder_regime_root' THEN
            SELECT id INTO ah_root_id
              FROM ledger_accounts
             WHERE ledger_id = NEW.ledger_id
               AND payment_account_id IS NULL
               AND counterparty_id IS NULL
               AND la_type = 'account_holder_root';

            IF ah_root_id IS NULL THEN
              RAISE EXCEPTION
                'ancestor missing: account_holder_root for (ledger=%)',
                NEW.ledger_id
                USING ERRCODE = '23514',
                      CONSTRAINT = 'ledger_accounts_ancestor_resolution';
            END IF;

            NEW.ancestor_ids := ARRAY[ah_root_id]::uuid[];

          WHEN 'counter_party_regime_root' THEN
            SELECT id INTO cp_root_id
              FROM ledger_accounts
             WHERE ledger_id = NEW.ledger_id
               AND counterparty_id = NEW.counterparty_id
               AND payment_account_id IS NULL
               AND la_type = 'counter_party_root';

            IF cp_root_id IS NULL THEN
              RAISE EXCEPTION
                'ancestor missing: counter_party_root for (ledger=%, cp=%)',
                NEW.ledger_id, NEW.counterparty_id
                USING ERRCODE = '23514',
                      CONSTRAINT = 'ledger_accounts_ancestor_resolution';
            END IF;

            NEW.ancestor_ids := ARRAY[cp_root_id]::uuid[];

          WHEN 'account_holder_payment_account_root' THEN
            SELECT id INTO ah_root_id
              FROM ledger_accounts
             WHERE ledger_id = NEW.ledger_id
               AND payment_account_id IS NULL
               AND counterparty_id IS NULL
               AND la_type = 'account_holder_root';

            IF ah_root_id IS NULL THEN
              RAISE EXCEPTION
                'ancestor missing: account_holder_root for (ledger=%)',
                NEW.ledger_id
                USING ERRCODE = '23514',
                      CONSTRAINT = 'ledger_accounts_ancestor_resolution';
            END IF;

            NEW.ancestor_ids := ARRAY[ah_root_id]::uuid[];

          WHEN 'account_holder_payment_account_regime_root' THEN
            SELECT id INTO ah_root_id
              FROM ledger_accounts
             WHERE ledger_id = NEW.ledger_id
               AND payment_account_id IS NULL
               AND counterparty_id IS NULL
               AND la_type = 'account_holder_root';

            IF ah_root_id IS NULL THEN
              RAISE EXCEPTION
                'ancestor missing: account_holder_root for (ledger=%)',
                NEW.ledger_id
                USING ERRCODE = '23514',
                      CONSTRAINT = 'ledger_accounts_ancestor_resolution';
            END IF;

            SELECT id INTO ah_regime_root_id
              FROM ledger_accounts
             WHERE ledger_id = NEW.ledger_id
               AND payment_account_id IS NULL
               AND counterparty_id IS NULL
               AND regime = NEW.regime
               AND la_type = 'account_holder_regime_root';

            IF ah_regime_root_id IS NULL THEN
              RAISE EXCEPTION
                'ancestor missing: account_holder_regime_root for (ledger=%, regime=%)',
                NEW.ledger_id, NEW.regime
                USING ERRCODE = '23514',
                      CONSTRAINT = 'ledger_accounts_ancestor_resolution';
            END IF;

            SELECT id INTO ah_pa_root_id
              FROM ledger_accounts
             WHERE ledger_id = NEW.ledger_id
               AND payment_account_id = NEW.payment_account_id
               AND counterparty_id IS NULL
               AND la_type = 'account_holder_payment_account_root';

            IF ah_pa_root_id IS NULL THEN
              RAISE EXCEPTION
                'ancestor missing: account_holder_payment_account_root for (ledger=%, pa=%)',
                NEW.ledger_id, NEW.payment_account_id
                USING ERRCODE = '23514',
                      CONSTRAINT = 'ledger_accounts_ancestor_resolution';
            END IF;

            NEW.ancestor_ids :=
              ARRAY[ah_root_id, ah_regime_root_id, ah_pa_root_id]::uuid[];

          WHEN 'counter_party_payment_account_root' THEN
            SELECT id INTO cp_root_id
              FROM ledger_accounts
             WHERE ledger_id = NEW.ledger_id
               AND counterparty_id = NEW.counterparty_id
               AND payment_account_id IS NULL
               AND la_type = 'counter_party_root';

            IF cp_root_id IS NULL THEN
              RAISE EXCEPTION
                'ancestor missing: counter_party_root for (ledger=%, cp=%)',
                NEW.ledger_id, NEW.counterparty_id
                USING ERRCODE = '23514',
                      CONSTRAINT = 'ledger_accounts_ancestor_resolution';
            END IF;

            NEW.ancestor_ids := ARRAY[cp_root_id]::uuid[];

          WHEN 'counter_party_payment_account_regime_root' THEN
            SELECT id INTO cp_root_id
              FROM ledger_accounts
             WHERE ledger_id = NEW.ledger_id
               AND counterparty_id = NEW.counterparty_id
               AND payment_account_id IS NULL
               AND la_type = 'counter_party_root';

            IF cp_root_id IS NULL THEN
              RAISE EXCEPTION
                'ancestor missing: counter_party_root for (ledger=%, cp=%)',
                NEW.ledger_id, NEW.counterparty_id
                USING ERRCODE = '23514',
                      CONSTRAINT = 'ledger_accounts_ancestor_resolution';
            END IF;

            SELECT id INTO cp_regime_root_id
              FROM ledger_accounts
             WHERE ledger_id = NEW.ledger_id
               AND counterparty_id = NEW.counterparty_id
               AND payment_account_id IS NULL
               AND regime = NEW.regime
               AND la_type = 'counter_party_regime_root';

            IF cp_regime_root_id IS NULL THEN
              RAISE EXCEPTION
                'ancestor missing: counter_party_regime_root for (ledger=%, cp=%, regime=%)',
                NEW.ledger_id, NEW.counterparty_id, NEW.regime
                USING ERRCODE = '23514',
                      CONSTRAINT = 'ledger_accounts_ancestor_resolution';
            END IF;

            SELECT id INTO cp_pa_root_id
              FROM ledger_accounts
             WHERE ledger_id = NEW.ledger_id
               AND counterparty_id = NEW.counterparty_id
               AND payment_account_id = NEW.payment_account_id
               AND la_type = 'counter_party_payment_account_root';

            IF cp_pa_root_id IS NULL THEN
              RAISE EXCEPTION
                'ancestor missing: counter_party_payment_account_root for (ledger=%, cp=%, pa=%)',
                NEW.ledger_id, NEW.counterparty_id, NEW.payment_account_id
                USING ERRCODE = '23514',
                      CONSTRAINT = 'ledger_accounts_ancestor_resolution';
            END IF;

            NEW.ancestor_ids :=
              ARRAY[cp_root_id, cp_regime_root_id, cp_pa_root_id]::uuid[];
        END CASE;

        RETURN NEW;
      END;
      $fn$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION IF EXISTS ledger_accounts_resolve_ancestor_ids()"
    )

    execute(
      """
      CREATE TRIGGER ledger_accounts_resolve_ancestor_ids_trg
        BEFORE INSERT OR UPDATE OF la_type, payment_account_id, counterparty_id,
                                   regime, ledger_id
        ON ledger_accounts
        FOR EACH ROW
        EXECUTE FUNCTION ledger_accounts_resolve_ancestor_ids();
      """,
      "DROP TRIGGER IF EXISTS ledger_accounts_resolve_ancestor_ids_trg ON ledger_accounts"
    )

    # ── join table: linked_ledger_accounts ───────────────────────────────
    # Edge-list representation of the ancestor/descendant relations between
    # LedgerAccounts in the same tree. Maintained by the AFTER INSERT trigger
    # alongside the denormalised `ancestor_ids` / `descendant_ids` array
    # columns (used by the hot-path balance-propagation trigger). Purpose
    # here is Ecto-side `has_many :through` preloads.
    create table(:linked_ledger_accounts, primary_key: false) do
      add :from_ledger_account_id,
          references(:ledger_accounts, type: :binary_id, on_delete: :delete_all),
          primary_key: true,
          null: false

      add :to_ledger_account_id,
          references(:ledger_accounts, type: :binary_id, on_delete: :delete_all),
          primary_key: true,
          null: false

      add :type, :string, null: false
    end

    create index(:linked_ledger_accounts, [:to_ledger_account_id])

    create constraint(:linked_ledger_accounts, :linked_ledger_accounts_type_check,
             check: "type IN ('ancestor', 'descendant')"
           )

    # ── AFTER INSERT trigger: propagate id to ancestors' descendant_ids ───
    # AND insert mapping rows in both directions. Bounded — only fires on
    # INSERT (never on the UPDATE OF descendant_ids it issues).
    execute(
      """
      CREATE OR REPLACE FUNCTION ledger_accounts_propagate_descendant_id() RETURNS TRIGGER AS $fn$
      BEGIN
        IF array_length(NEW.ancestor_ids, 1) IS NOT NULL THEN
          -- Denormalised cache for the balance-propagation trigger (fast walk).
          UPDATE ledger_accounts
             SET descendant_ids = array_append(descendant_ids, NEW.id)
           WHERE id = ANY(NEW.ancestor_ids);

          -- Edge-list for Ecto preloads. Refresh-style: purge any prior
          -- rows touching this LA (defensive — no-op on fresh INSERT, but
          -- ensures idempotency on re-INSERT), then write the full set.
          -- Two rows per (ancestor, descendant) pair so simple
          -- `from = X, type = ?` queries work in either direction without
          -- case logic.
          DELETE FROM linked_ledger_accounts
                WHERE from_ledger_account_id = NEW.id
                   OR to_ledger_account_id   = NEW.id;

          INSERT INTO linked_ledger_accounts
            (from_ledger_account_id, to_ledger_account_id, type)
          SELECT NEW.id, ancestor_id, 'ancestor'
            FROM unnest(NEW.ancestor_ids) AS ancestor_id;

          INSERT INTO linked_ledger_accounts
            (from_ledger_account_id, to_ledger_account_id, type)
          SELECT ancestor_id, NEW.id, 'descendant'
            FROM unnest(NEW.ancestor_ids) AS ancestor_id;
        END IF;
        RETURN NULL;
      END;
      $fn$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION IF EXISTS ledger_accounts_propagate_descendant_id()"
    )

    execute(
      """
      CREATE TRIGGER ledger_accounts_propagate_descendant_id_trg
        AFTER INSERT ON ledger_accounts
        FOR EACH ROW
        EXECUTE FUNCTION ledger_accounts_propagate_descendant_id();
      """,
      "DROP TRIGGER IF EXISTS ledger_accounts_propagate_descendant_id_trg ON ledger_accounts"
    )
  end
end

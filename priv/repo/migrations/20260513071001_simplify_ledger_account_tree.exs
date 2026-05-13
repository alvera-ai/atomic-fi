defmodule AtomicFi.Repo.Migrations.SimplifyLedgerAccountTree do
  @moduledoc """
  Two changes that go together to make the LedgerAccount tree work for the
  CP / PA hierarchy:

    1. Drop `ledger_accounts.parent_ledger_account_id`. The flat
       `ancestor_ids` array is the single source of truth for traversal —
       parent_id was a redundant denormalization that complicated the model.

    2. Narrow the CP unique index to `(ledger, cp, regime) WHERE
       counterparty_id IS NOT NULL AND payment_account_id IS NULL`. Without
       this, a CP-level LA (pa=NULL, cp=Y) and a PA-belongs-to-CP LA
       (pa=X, cp=Y) would collide on the CP index.
  """

  use Ecto.Migration

  def change do
    drop index(:ledger_accounts, [:parent_ledger_account_id])

    alter table(:ledger_accounts) do
      remove :parent_ledger_account_id, references(:ledger_accounts, type: :binary_id), null: true
    end

    drop unique_index(:ledger_accounts, [:ledger_id, :counterparty_id, :regime],
           name: :ledger_accounts_ledger_cp_regime_unique
         )

    create unique_index(:ledger_accounts, [:ledger_id, :counterparty_id, :regime],
             name: :ledger_accounts_ledger_cp_regime_unique,
             where: "counterparty_id IS NOT NULL AND payment_account_id IS NULL"
           )
  end
end

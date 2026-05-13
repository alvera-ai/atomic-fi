defmodule AtomicFi.LedgerEntryContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.LedgerAccountContext.VelocityLimit
  alias AtomicFi.LedgerEntryContext
  alias AtomicFi.LedgerEntryContext.LedgerEntry
  alias AtomicFi.OpenApiSchema.LedgerEntryRequest
  import AtomicFi.Factory

  # ── Helpers ──────────────────────────────────────────────────────────────────

  # Map legacy keyword shorthands to %VelocityLimit{}s for the composite-type array.
  @limit_keys [
    {:daily_debit_limit_at_entry, "daily", "debit"},
    {:daily_credit_limit_at_entry, "daily", "credit"},
    {:weekly_debit_limit_at_entry, "weekly", "debit"},
    {:weekly_credit_limit_at_entry, "weekly", "credit"},
    {:monthly_debit_limit_at_entry, "monthly", "debit"},
    {:monthly_credit_limit_at_entry, "monthly", "credit"},
    {:yearly_debit_limit_at_entry, "yearly", "debit"},
    {:yearly_credit_limit_at_entry, "yearly", "credit"}
  ]

  defp build_limits(opts) do
    Enum.flat_map(@limit_keys, fn {key, period, direction} ->
      case opts[key] do
        nil -> []
        cap -> [%VelocityLimit{period: period, direction: direction, cap: cap, rule: "test"}]
      end
    end)
  end

  defp find_limit(limits, period, direction) do
    Enum.find(limits, &(&1.period == period and &1.direction == direction))
  end

  # Default leaf — `:account_holder_payment_account_regime_root` with 1 ancestor.
  defp make_account(session, _ledger \\ nil, _opts \\ []) do
    insert(:ledger_account, tenant_id: session.tenant_id)
  end

  defp entry_request(session, account, opts \\ []) do
    %LedgerEntryRequest{
      account_holder_id: account.account_holder_id,
      ledger_account_id: account.id,
      currency: "USD",
      amount: Keyword.get(opts, :amount, 10_000),
      entry_type: Keyword.get(opts, :entry_type, :credit),
      status: Keyword.get(opts, :status, :pending),
      limits_at_entry: build_limits(opts),
      tenant_id: session.tenant_id
    }
  end

  defp reload_account(session, account_or_id) do
    id = if is_binary(account_or_id), do: account_or_id, else: account_or_id.id
    LedgerAccountContext.get_ledger_account!(session, id)
  end

  # ── CRUD ─────────────────────────────────────────────────────────────────────

  describe "ledger_entries CRUD" do
    test "list_ledger_entries/1 returns all entries for tenant", %{session: session} do
      insert(:ledger_entry, tenant_id: session.tenant_id)
      {:ok, {entries, _meta}} = LedgerEntryContext.list_ledger_entries(session)
      assert entries != []
    end

    test "get_ledger_entry!/2 returns the entry with given id", %{session: session} do
      entry = insert(:ledger_entry, tenant_id: session.tenant_id)
      assert %LedgerEntry{id: id} = LedgerEntryContext.get_ledger_entry!(session, entry.id)
      assert id == entry.id
    end

    test "create_ledger_entry/2 with valid data creates an entry", %{session: session} do
      account = insert(:ledger_account, tenant_id: session.tenant_id)
      req = entry_request(session, account, amount: 5_000, entry_type: :credit)

      assert {:ok, %LedgerEntry{} = entry} = LedgerEntryContext.create_ledger_entry(session, req)
      assert entry.ledger_account_id == account.id
      assert entry.amount == 5_000
      assert entry.entry_type == :credit
      assert entry.status == :pending
      assert entry.tenant_id == session.tenant_id
    end

    test "create_ledger_entry/2 with missing required fields returns error", %{session: session} do
      request = %LedgerEntryRequest{
        account_holder_id: nil,
        ledger_account_id: nil,
        currency: nil,
        amount: nil,
        entry_type: nil,
        tenant_id: session.tenant_id
      }

      assert {:error, changeset} = LedgerEntryContext.create_ledger_entry(session, request)
      assert errors_on(changeset).account_holder_id != []
      assert errors_on(changeset).currency != []
      assert errors_on(changeset).amount != []
    end

    test "create_ledger_entry/2 rejects negative amount", %{session: session} do
      account = insert(:ledger_account, tenant_id: session.tenant_id)
      req = entry_request(session, account, amount: -1)

      assert {:error, changeset} = LedgerEntryContext.create_ledger_entry(session, req)
      assert errors_on(changeset).amount != []
    end

    test "delete_ledger_entry/2 deletes the entry", %{session: session} do
      entry = insert(:ledger_entry, tenant_id: session.tenant_id)
      assert {:ok, %LedgerEntry{}} = LedgerEntryContext.delete_ledger_entry(session, entry)

      assert_raise Ecto.NoResultsError, fn ->
        LedgerEntryContext.get_ledger_entry!(session, entry.id)
      end
    end

    test "change_ledger_entry/1 returns a changeset", %{session: session} do
      entry = insert(:ledger_entry, tenant_id: session.tenant_id)
      assert %Ecto.Changeset{} = LedgerEntryContext.change_ledger_entry(entry)
    end
  end

  # ── Balance propagation via DB trigger ──────────────────────────────────────

  describe "ledger_entries balance propagation (trigger)" do
    test "credit entry increments ledger_account.balance", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)
      assert reload_account(session, account).balance == 0

      req = entry_request(session, account, amount: 10_000, entry_type: :credit)
      assert {:ok, _} = LedgerEntryContext.create_ledger_entry(session, req)

      assert reload_account(session, account).balance == 10_000
    end

    test "debit entry decrements ledger_account.balance", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      # credit first to have a positive balance
      credit_req = entry_request(session, account, amount: 20_000, entry_type: :credit)
      assert {:ok, _} = LedgerEntryContext.create_ledger_entry(session, credit_req)

      debit_req = entry_request(session, account, amount: 7_500, entry_type: :debit)
      assert {:ok, _} = LedgerEntryContext.create_ledger_entry(session, debit_req)

      assert reload_account(session, account).balance == 12_500
    end

    test "multiple entries accumulate balance correctly", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      for amount <- [1_000, 2_000, 3_000] do
        req = entry_request(session, account, amount: amount, entry_type: :credit)
        assert {:ok, _} = LedgerEntryContext.create_ledger_entry(session, req)
      end

      assert reload_account(session, account).balance == 6_000
    end

    test "voiding an entry reverses the balance delta", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      credit_req = entry_request(session, account, amount: 10_000, entry_type: :credit)
      assert {:ok, entry} = LedgerEntryContext.create_ledger_entry(session, credit_req)
      assert reload_account(session, account).balance == 10_000

      void_request = %LedgerEntryRequest{
        account_holder_id: entry.account_holder_id,
        ledger_account_id: entry.ledger_account_id,
        currency: entry.currency,
        amount: entry.amount,
        entry_type: entry.entry_type,
        status: :voided,
        tenant_id: session.tenant_id
      }

      assert {:ok, voided} = LedgerEntryContext.update_ledger_entry(session, entry, void_request)
      assert voided.status == :voided
      assert reload_account(session, account).balance == 0
    end

    test "voiding a debit entry restores the balance", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      # Setup: credit 15000
      credit_req = entry_request(session, account, amount: 15_000, entry_type: :credit)
      assert {:ok, _} = LedgerEntryContext.create_ledger_entry(session, credit_req)

      # Debit 5000
      debit_req = entry_request(session, account, amount: 5_000, entry_type: :debit)
      assert {:ok, debit_entry} = LedgerEntryContext.create_ledger_entry(session, debit_req)
      assert reload_account(session, account).balance == 10_000

      # Void the debit — balance should go back to 15000
      void_request = %LedgerEntryRequest{
        account_holder_id: debit_entry.account_holder_id,
        ledger_account_id: debit_entry.ledger_account_id,
        currency: debit_entry.currency,
        amount: debit_entry.amount,
        entry_type: debit_entry.entry_type,
        status: :voided,
        tenant_id: session.tenant_id
      }

      assert {:ok, _} =
               LedgerEntryContext.update_ledger_entry(session, debit_entry, void_request)

      assert reload_account(session, account).balance == 15_000
    end

    test "non-voiding status update does not affect balance", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      credit_req = entry_request(session, account, amount: 10_000, entry_type: :credit)
      assert {:ok, entry} = LedgerEntryContext.create_ledger_entry(session, credit_req)
      assert reload_account(session, account).balance == 10_000

      post_request = %LedgerEntryRequest{
        account_holder_id: entry.account_holder_id,
        ledger_account_id: entry.ledger_account_id,
        currency: entry.currency,
        amount: entry.amount,
        entry_type: entry.entry_type,
        status: :posted,
        tenant_id: session.tenant_id
      }

      assert {:ok, updated} = LedgerEntryContext.update_ledger_entry(session, entry, post_request)
      assert updated.status == :posted
      # Balance should remain unchanged
      assert reload_account(session, account).balance == 10_000
    end
  end

  # ── Ancestor rollup via trigger ──────────────────────────────────────────────

  describe "ledger_entries ancestor balance rollup (trigger)" do
    test "credit on leaf rolls up balance to the leaf's PA root ancestor", %{session: session} do
      # Default factory leaf = :account_holder_payment_account_regime_root,
      # which carries the AH-PA root in ancestor_ids.
      leaf = insert(:ledger_account, tenant_id: session.tenant_id)
      [pa_root_id] = leaf.ancestor_ids

      assert reload_account(session, leaf).balance == 0
      assert reload_account(session, pa_root_id).balance == 0

      req = entry_request(session, leaf, amount: 5_000, entry_type: :credit)
      assert {:ok, _} = LedgerEntryContext.create_ledger_entry(session, req)

      assert reload_account(session, leaf).balance == 5_000
      assert reload_account(session, pa_root_id).balance == 5_000
    end

    test "credit rolls up through the full 3-ancestor chain", %{session: session} do
      # CP-PA-regime-root has 3 root-first ancestors: cp_root → cp_regime → cp_pa_root.
      leaf =
        insert(:ledger_account,
          tenant_id: session.tenant_id,
          la_type: :counter_party_payment_account_regime_root,
          regime: "ach"
        )

      assert length(leaf.ancestor_ids) == 3

      req = entry_request(session, leaf, amount: 3_000, entry_type: :credit)
      assert {:ok, _} = LedgerEntryContext.create_ledger_entry(session, req)

      assert reload_account(session, leaf).balance == 3_000

      for anc_id <- leaf.ancestor_ids do
        assert reload_account(session, anc_id).balance == 3_000
      end
    end

    test "voiding reverses balance on leaf AND every ancestor", %{session: session} do
      leaf = insert(:ledger_account, tenant_id: session.tenant_id)
      [pa_root_id] = leaf.ancestor_ids

      req = entry_request(session, leaf, amount: 8_000, entry_type: :credit)
      assert {:ok, entry} = LedgerEntryContext.create_ledger_entry(session, req)

      assert reload_account(session, leaf).balance == 8_000
      assert reload_account(session, pa_root_id).balance == 8_000

      void_request = %LedgerEntryRequest{
        account_holder_id: entry.account_holder_id,
        ledger_account_id: entry.ledger_account_id,
        currency: entry.currency,
        amount: entry.amount,
        entry_type: entry.entry_type,
        status: :voided,
        tenant_id: session.tenant_id
      }

      assert {:ok, _} = LedgerEntryContext.update_ledger_entry(session, entry, void_request)

      assert reload_account(session, leaf).balance == 0
      assert reload_account(session, pa_root_id).balance == 0
    end

    test "two independent leaves under the same AH — entry on one does not affect the other",
         %{session: session} do
      ah = insert(:account_holder, tenant_id: session.tenant_id)
      ledger = insert(:ledger, tenant_id: session.tenant_id, account_holder_id: ah.id)

      # Two distinct PAs ⇒ two distinct AH-PA trees.
      leaf_a =
        insert(:ledger_account,
          tenant_id: session.tenant_id,
          account_holder_id: ah.id,
          ledger_id: ledger.id
        )

      leaf_b =
        insert(:ledger_account,
          tenant_id: session.tenant_id,
          account_holder_id: ah.id,
          ledger_id: ledger.id
        )

      req = entry_request(session, leaf_a, amount: 4_000, entry_type: :credit)
      assert {:ok, _} = LedgerEntryContext.create_ledger_entry(session, req)

      assert reload_account(session, leaf_a).balance == 4_000
      assert reload_account(session, leaf_b).balance == 0
    end
  end

  # ── Velocity limit snapshots ─────────────────────────────────────────────────

  describe "ledger_entries limits_at_entry composite-type array" do
    test "stores velocity limit snapshots as a velocity_limit[] on the entry row", %{
      session: session
    } do
      account = insert(:ledger_account, tenant_id: session.tenant_id)

      req =
        entry_request(session, account,
          entry_type: :credit,
          amount: 1_000,
          daily_credit_limit_at_entry: 50_000,
          weekly_credit_limit_at_entry: 200_000,
          monthly_credit_limit_at_entry: 500_000,
          yearly_credit_limit_at_entry: 1_000_000
        )

      assert {:ok, entry} = LedgerEntryContext.create_ledger_entry(session, req)
      assert length(entry.limits_at_entry) == 4

      assert %VelocityLimit{cap: 50_000, rule: "test"} =
               find_limit(entry.limits_at_entry, "daily", "credit")

      assert %VelocityLimit{cap: 200_000} =
               find_limit(entry.limits_at_entry, "weekly", "credit")

      assert %VelocityLimit{cap: 500_000} =
               find_limit(entry.limits_at_entry, "monthly", "credit")

      assert %VelocityLimit{cap: 1_000_000} =
               find_limit(entry.limits_at_entry, "yearly", "credit")
    end

    test "no limits passed produces an empty limits_at_entry array", %{session: session} do
      account = insert(:ledger_account, tenant_id: session.tenant_id)
      req = entry_request(session, account, entry_type: :credit, amount: 1_000)

      assert {:ok, entry} = LedgerEntryContext.create_ledger_entry(session, req)
      assert entry.limits_at_entry == []
    end
  end

  # ── Status transitions ───────────────────────────────────────────────────────

  describe "ledger_entry status lifecycle" do
    test "entry can transition pending → posted", %{session: session} do
      account = insert(:ledger_account, tenant_id: session.tenant_id)
      req = entry_request(session, account, status: :pending)
      assert {:ok, entry} = LedgerEntryContext.create_ledger_entry(session, req)
      assert entry.status == :pending

      post_req = %LedgerEntryRequest{
        account_holder_id: entry.account_holder_id,
        ledger_account_id: entry.ledger_account_id,
        currency: entry.currency,
        amount: entry.amount,
        entry_type: entry.entry_type,
        status: :posted,
        tenant_id: session.tenant_id
      }

      assert {:ok, posted} = LedgerEntryContext.update_ledger_entry(session, entry, post_req)
      assert posted.status == :posted
    end

    test "entry can be voided from any status", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)
      account = make_account(session, ledger)

      # post it first
      req = entry_request(session, account, amount: 5_000, entry_type: :credit)
      assert {:ok, entry} = LedgerEntryContext.create_ledger_entry(session, req)

      post_req = %LedgerEntryRequest{
        account_holder_id: entry.account_holder_id,
        ledger_account_id: entry.ledger_account_id,
        currency: entry.currency,
        amount: entry.amount,
        entry_type: entry.entry_type,
        status: :posted,
        tenant_id: session.tenant_id
      }

      assert {:ok, posted} = LedgerEntryContext.update_ledger_entry(session, entry, post_req)

      void_req = %LedgerEntryRequest{
        account_holder_id: posted.account_holder_id,
        ledger_account_id: posted.ledger_account_id,
        currency: posted.currency,
        amount: posted.amount,
        entry_type: posted.entry_type,
        status: :voided,
        tenant_id: session.tenant_id
      }

      assert {:ok, voided} = LedgerEntryContext.update_ledger_entry(session, posted, void_req)
      assert voided.status == :voided
      assert reload_account(session, account).balance == 0
    end
  end
end

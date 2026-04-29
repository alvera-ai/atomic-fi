defmodule AtomicFi.LedgerEntryContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.LedgerEntryContext
  alias AtomicFi.LedgerEntryContext.LedgerEntry
  alias AtomicFi.OpenApiSchema.{LedgerAccountRequest, LedgerEntryRequest}
  alias AtomicFi.Repo
  import AtomicFi.Factory

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

  defp entry_request(session, account, opts \\ []) do
    %LedgerEntryRequest{
      account_holder_id: account.account_holder_id,
      ledger_account_id: account.id,
      currency: "USD",
      amount: Keyword.get(opts, :amount, 10_000),
      entry_type: Keyword.get(opts, :entry_type, :credit),
      status: Keyword.get(opts, :status, :pending),
      daily_debit_limit_at_entry: Keyword.get(opts, :daily_debit_limit_at_entry, nil),
      daily_credit_limit_at_entry: Keyword.get(opts, :daily_credit_limit_at_entry, nil),
      weekly_debit_limit_at_entry: Keyword.get(opts, :weekly_debit_limit_at_entry, nil),
      weekly_credit_limit_at_entry: Keyword.get(opts, :weekly_credit_limit_at_entry, nil),
      monthly_debit_limit_at_entry: Keyword.get(opts, :monthly_debit_limit_at_entry, nil),
      monthly_credit_limit_at_entry: Keyword.get(opts, :monthly_credit_limit_at_entry, nil),
      yearly_debit_limit_at_entry: Keyword.get(opts, :yearly_debit_limit_at_entry, nil),
      yearly_credit_limit_at_entry: Keyword.get(opts, :yearly_credit_limit_at_entry, nil),
      tenant_id: session.tenant_id
    }
  end

  defp reload_account(session, account) do
    alias AtomicFi.LedgerAccountContext.LedgerAccount

    Repo.get!(LedgerAccount, account.id, session: session)
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
    test "credit entry increments balance on direct account AND all ancestor accounts", %{
      session: session
    } do
      ledger = insert(:ledger, tenant_id: session.tenant_id)

      root = make_account(session, ledger)

      child =
        make_account(session, ledger, parent_ledger_account_id: root.id, account_type: :liability)

      assert reload_account(session, root).balance == 0
      assert reload_account(session, child).balance == 0

      req = entry_request(session, child, amount: 5_000, entry_type: :credit)
      assert {:ok, _} = LedgerEntryContext.create_ledger_entry(session, req)

      assert reload_account(session, child).balance == 5_000
      assert reload_account(session, root).balance == 5_000
    end

    test "credit rolls up through three-level hierarchy (root → child → grandchild)", %{
      session: session
    } do
      ledger = insert(:ledger, tenant_id: session.tenant_id)

      root = make_account(session, ledger)

      child =
        make_account(session, ledger, parent_ledger_account_id: root.id, account_type: :liability)

      grandchild =
        make_account(session, ledger,
          parent_ledger_account_id: child.id,
          account_type: :equity
        )

      req = entry_request(session, grandchild, amount: 3_000, entry_type: :credit)
      assert {:ok, _} = LedgerEntryContext.create_ledger_entry(session, req)

      assert reload_account(session, grandchild).balance == 3_000
      assert reload_account(session, child).balance == 3_000
      assert reload_account(session, root).balance == 3_000
    end

    test "voiding reverses balance on direct account AND all ancestors", %{session: session} do
      ledger = insert(:ledger, tenant_id: session.tenant_id)

      root = make_account(session, ledger)

      child =
        make_account(session, ledger, parent_ledger_account_id: root.id, account_type: :liability)

      req = entry_request(session, child, amount: 8_000, entry_type: :credit)
      assert {:ok, entry} = LedgerEntryContext.create_ledger_entry(session, req)

      assert reload_account(session, child).balance == 8_000
      assert reload_account(session, root).balance == 8_000

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

      assert reload_account(session, child).balance == 0
      assert reload_account(session, root).balance == 0
    end

    test "two independent children — entry on one child does not affect the other", %{
      session: session
    } do
      ledger = insert(:ledger, tenant_id: session.tenant_id)

      root = make_account(session, ledger)

      child_a =
        make_account(session, ledger, parent_ledger_account_id: root.id, account_type: :liability)

      child_b =
        make_account(session, ledger,
          parent_ledger_account_id: root.id,
          account_type: :equity
        )

      req = entry_request(session, child_a, amount: 4_000, entry_type: :credit)
      assert {:ok, _} = LedgerEntryContext.create_ledger_entry(session, req)

      assert reload_account(session, child_a).balance == 4_000
      assert reload_account(session, child_b).balance == 0
      assert reload_account(session, root).balance == 4_000
    end
  end

  # ── Velocity limit snapshots ─────────────────────────────────────────────────

  describe "ledger_entries *_limit_at_entry snapshot fields" do
    test "stores velocity limit snapshots from risk engine on the entry row", %{session: session} do
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
      assert entry.daily_credit_limit_at_entry == 50_000
      assert entry.weekly_credit_limit_at_entry == 200_000
      assert entry.monthly_credit_limit_at_entry == 500_000
      assert entry.yearly_credit_limit_at_entry == 1_000_000
    end

    test "nil limits (unconstrained) are stored as nil on the entry row", %{session: session} do
      account = insert(:ledger_account, tenant_id: session.tenant_id)
      req = entry_request(session, account, entry_type: :credit, amount: 1_000)

      assert {:ok, entry} = LedgerEntryContext.create_ledger_entry(session, req)
      assert is_nil(entry.daily_credit_limit_at_entry)
      assert is_nil(entry.daily_debit_limit_at_entry)
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

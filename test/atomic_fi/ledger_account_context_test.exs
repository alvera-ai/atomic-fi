defmodule AtomicFi.LedgerAccountContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.LedgerAccountContext.LedgerAccount
  alias AtomicFi.OpenApiSchema.LedgerAccountRequest
  import AtomicFi.Factory

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp ledger_for(session) do
    insert(:ledger, tenant_id: session.tenant_id)
  end

  defp request_for(session, ledger, overrides \\ %{}) do
    base = %{
      account_holder_id: ledger.account_holder_id,
      ledger_id: ledger.id,
      currency: "USD",
      regime: "ach",
      la_type: :account_holder_payment_account_regime_root,
      status: :active,
      payment_account_id: nil,
      counterparty_id: nil,
      tenant_id: session.tenant_id
    }

    struct(LedgerAccountRequest, Map.merge(base, overrides))
  end

  defp pa_for(session, ledger) do
    insert(:payment_account,
      tenant_id: session.tenant_id,
      account_holder_id: ledger.account_holder_id,
      currency: ledger.currency
    )
  end

  defp cp_for(session, ledger) do
    insert(:counterparty,
      tenant_id: session.tenant_id,
      account_holder_id: ledger.account_holder_id
    )
  end

  # ── CRUD ─────────────────────────────────────────────────────────────────

  describe "CRUD" do
    test "list_ledger_accounts/1 returns accounts for tenant", %{session: session} do
      insert(:ledger_account, tenant_id: session.tenant_id)
      assert {:ok, {accounts, _}} = LedgerAccountContext.list_ledger_accounts(session)
      assert accounts != []
    end

    test "get_ledger_account!/2 returns the row", %{session: session} do
      account = insert(:ledger_account, tenant_id: session.tenant_id)

      assert %LedgerAccount{id: id} =
               LedgerAccountContext.get_ledger_account!(session, account.id)

      assert id == account.id
    end

    test "create_ledger_account/2 validates required fields", %{session: session} do
      request = %LedgerAccountRequest{tenant_id: session.tenant_id}
      assert {:error, changeset} = LedgerAccountContext.create_ledger_account(session, request)
      assert errors_on(changeset).account_holder_id != []
      assert errors_on(changeset).ledger_id != []
      assert errors_on(changeset).currency != []
      assert errors_on(changeset).regime != []
      assert errors_on(changeset).la_type != []
    end

    test "update_ledger_account/3 mutates status", %{session: session} do
      account = insert(:ledger_account, tenant_id: session.tenant_id, status: :active)

      request = %LedgerAccountRequest{
        account_holder_id: account.account_holder_id,
        ledger_id: account.ledger_id,
        currency: account.currency,
        regime: account.regime,
        la_type: account.la_type,
        payment_account_id: account.payment_account_id,
        counterparty_id: account.counterparty_id,
        status: :closed,
        tenant_id: session.tenant_id
      }

      assert {:ok, updated} =
               LedgerAccountContext.update_ledger_account(session, account, request)

      assert updated.status == :closed
    end

    test "delete_ledger_account/2 removes the row", %{session: session} do
      account = insert(:ledger_account, tenant_id: session.tenant_id)

      assert {:ok, %LedgerAccount{}} =
               LedgerAccountContext.delete_ledger_account(session, account)

      assert_raise Ecto.NoResultsError, fn ->
        LedgerAccountContext.get_ledger_account!(session, account.id)
      end
    end

    test "change_ledger_account/1 returns a changeset", %{session: session} do
      account = insert(:ledger_account, tenant_id: session.tenant_id)
      assert %Ecto.Changeset{} = LedgerAccountContext.change_ledger_account(account)
    end
  end

  # ── Trigger: ancestor_ids materialisation per la_type ────────────────────

  describe "trigger ledger_accounts_resolve_ancestor_ids — happy paths" do
    test ":counter_party_root has empty ancestor_ids", %{session: session} do
      ledger = ledger_for(session)
      cp = cp_for(session, ledger)

      assert {:ok, root} =
               LedgerAccountContext.create_ledger_account(
                 session,
                 request_for(session, ledger, %{
                   la_type: :counter_party_root,
                   regime: "root",
                   counterparty_id: cp.id
                 })
               )

      assert root.ancestor_ids == []
    end

    test ":counter_party_regime_root resolves the cp_root as its ancestor", %{session: session} do
      ledger = ledger_for(session)
      cp = cp_for(session, ledger)

      assert {:ok, cp_root} =
               LedgerAccountContext.create_ledger_account(
                 session,
                 request_for(session, ledger, %{
                   la_type: :counter_party_root,
                   regime: "root",
                   counterparty_id: cp.id
                 })
               )

      assert {:ok, cp_regime} =
               LedgerAccountContext.create_ledger_account(
                 session,
                 request_for(session, ledger, %{
                   la_type: :counter_party_regime_root,
                   regime: "ach",
                   counterparty_id: cp.id
                 })
               )

      assert cp_regime.ancestor_ids == [cp_root.id]
    end

    test ":account_holder_payment_account_regime_root resolves the full AH chain root-first",
         %{session: session} do
      ledger = ledger_for(session)
      pa = pa_for(session, ledger)

      {:ok, ah_root} =
        LedgerAccountContext.create_ledger_account(
          session,
          request_for(session, ledger, %{la_type: :account_holder_root, regime: "root"})
        )

      {:ok, ah_regime} =
        LedgerAccountContext.create_ledger_account(
          session,
          request_for(session, ledger, %{la_type: :account_holder_regime_root, regime: "ach"})
        )

      {:ok, pa_root} =
        LedgerAccountContext.create_ledger_account(
          session,
          request_for(session, ledger, %{
            la_type: :account_holder_payment_account_root,
            regime: "root",
            payment_account_id: pa.id
          })
        )

      assert {:ok, pa_regime} =
               LedgerAccountContext.create_ledger_account(
                 session,
                 request_for(session, ledger, %{
                   la_type: :account_holder_payment_account_regime_root,
                   regime: "ach",
                   payment_account_id: pa.id
                 })
               )

      assert pa_regime.ancestor_ids == [ah_root.id, ah_regime.id, pa_root.id]
    end

    test ":counter_party_payment_account_regime_root resolves the full 3-deep chain root-first",
         %{session: session} do
      ledger = ledger_for(session)
      cp = cp_for(session, ledger)
      pa = pa_for(session, ledger)

      {:ok, cp_root} =
        LedgerAccountContext.create_ledger_account(
          session,
          request_for(session, ledger, %{
            la_type: :counter_party_root,
            regime: "root",
            counterparty_id: cp.id
          })
        )

      {:ok, cp_regime} =
        LedgerAccountContext.create_ledger_account(
          session,
          request_for(session, ledger, %{
            la_type: :counter_party_regime_root,
            regime: "ach",
            counterparty_id: cp.id
          })
        )

      {:ok, cp_pa_root} =
        LedgerAccountContext.create_ledger_account(
          session,
          request_for(session, ledger, %{
            la_type: :counter_party_payment_account_root,
            regime: "root",
            counterparty_id: cp.id,
            payment_account_id: pa.id
          })
        )

      assert {:ok, cp_pa_regime} =
               LedgerAccountContext.create_ledger_account(
                 session,
                 request_for(session, ledger, %{
                   la_type: :counter_party_payment_account_regime_root,
                   regime: "ach",
                   counterparty_id: cp.id,
                   payment_account_id: pa.id
                 })
               )

      # Root-first: cp_root, then cp_regime, then cp_pa_root.
      assert cp_pa_regime.ancestor_ids == [cp_root.id, cp_regime.id, cp_pa_root.id]
    end
  end

  describe "trigger ledger_accounts_resolve_ancestor_ids — missing ancestor → changeset error" do
    test ":counter_party_regime_root without the cp_root surfaces as %Changeset{}", %{
      session: session
    } do
      ledger = ledger_for(session)
      cp = cp_for(session, ledger)

      assert {:error, changeset} =
               LedgerAccountContext.create_ledger_account(
                 session,
                 request_for(session, ledger, %{
                   la_type: :counter_party_regime_root,
                   regime: "ach",
                   counterparty_id: cp.id
                 })
               )

      assert errors_on(changeset).ancestor_ids != []
    end

    test ":account_holder_payment_account_regime_root without the pa_root surfaces as %Changeset{}",
         %{session: session} do
      ledger = ledger_for(session)
      pa = pa_for(session, ledger)

      assert {:error, changeset} =
               LedgerAccountContext.create_ledger_account(
                 session,
                 request_for(session, ledger, %{
                   la_type: :account_holder_payment_account_regime_root,
                   regime: "ach",
                   payment_account_id: pa.id
                 })
               )

      assert errors_on(changeset).ancestor_ids != []
    end
  end

  describe "trigger AFTER INSERT — descendant_ids + linked_ledger_accounts" do
    test "inserting a leaf back-fills descendant_ids on every ancestor and writes edge rows",
         %{session: session} do
      ledger = ledger_for(session)
      pa = pa_for(session, ledger)

      {:ok, _ah_root} =
        LedgerAccountContext.create_ledger_account(
          session,
          request_for(session, ledger, %{la_type: :account_holder_root, regime: "root"})
        )

      {:ok, pa_root} =
        LedgerAccountContext.create_ledger_account(
          session,
          request_for(session, ledger, %{
            la_type: :account_holder_payment_account_root,
            regime: "root",
            payment_account_id: pa.id
          })
        )

      {:ok, _ah_regime} =
        LedgerAccountContext.create_ledger_account(
          session,
          request_for(session, ledger, %{la_type: :account_holder_regime_root, regime: "ach"})
        )

      {:ok, pa_regime} =
        LedgerAccountContext.create_ledger_account(
          session,
          request_for(session, ledger, %{
            la_type: :account_holder_payment_account_regime_root,
            regime: "ach",
            payment_account_id: pa.id
          })
        )

      # descendant_ids on pa_root is back-filled by the AFTER INSERT trigger;
      # re-fetch via the context so we get the current row.
      pa_root = LedgerAccountContext.get_ledger_account!(session, pa_root.id)
      assert pa_regime.id in pa_root.descendant_ids

      # The context preloads `linked_ledger_accounts: :to` — assert both
      # directions of the edge from each endpoint's perspective.
      leaf = LedgerAccountContext.get_ledger_account!(session, pa_regime.id)

      assert Enum.any?(leaf.linked_ledger_accounts, fn e ->
               e.to_ledger_account_id == pa_root.id and e.type == :ancestor
             end)

      assert Enum.any?(pa_root.linked_ledger_accounts, fn e ->
               e.to_ledger_account_id == pa_regime.id and e.type == :descendant
             end)
    end
  end
end

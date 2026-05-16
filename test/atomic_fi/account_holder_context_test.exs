defmodule AtomicFi.AccountHolderContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.LedgerContext
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  import AtomicFi.Factory

  describe "account_holders" do
    test "list_account_holders/1 returns all account_holders for tenant", %{session: session} do
      insert(:account_holder, tenant_id: session.tenant_id)
      {:ok, {account_holders, _meta}} = AccountHolderContext.list_account_holders(session)
      assert account_holders != []
    end

    test "get_account_holder!/2 returns the account_holder with given id", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      assert %AccountHolder{id: id} =
               AccountHolderContext.get_account_holder!(session, account_holder.id)

      assert id == account_holder.id
    end

    test "get_account_holder_by_external_id/2 matches get_account_holder!/2 preloads", %{
      session: session
    } do
      account_holder =
        insert(:account_holder, external_id: "ah-by-ext", tenant_id: session.tenant_id)

      by_id = AccountHolderContext.get_account_holder!(session, account_holder.id)
      by_ext = AccountHolderContext.get_account_holder_by_external_id(session, "ah-by-ext")

      assert by_ext.id == by_id.id
      assert by_ext.legal_entity.id == by_id.legal_entity.id
      assert is_list(by_ext.legal_entity.addresses)
      assert is_list(by_ext.legal_entity.phone_numbers)
      assert is_list(by_ext.legal_entity.identifications)
    end

    test "get_account_holder_by_external_id/2 returns nil when handle is unknown", %{
      session: session
    } do
      assert AccountHolderContext.get_account_holder_by_external_id(session, "missing") == nil
    end

    test "create_account_holder/2 with valid data creates an account_holder", %{
      session: session
    } do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      request = %AccountHolderRequest{
        account_holder_type: :individual,
        status: :pending,
        kyc_status: :not_started,
        risk_level: :low,
        enabled_currencies: ["USD"],
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:ok, %AccountHolder{} = account_holder} =
               AccountHolderContext.create_account_holder(session, request)

      assert account_holder.legal_entity_id == legal_entity.id
      assert account_holder.account_holder_type == :individual
      assert account_holder.status == :pending
      assert account_holder.kyc_status == :not_started
      assert account_holder.risk_level == :low
      assert account_holder.tenant_id == session.tenant_id
    end

    test "create_account_holder/2 with invalid data returns error changeset", %{session: session} do
      request = %AccountHolderRequest{
        account_holder_type: nil,
        status: :pending,
        kyc_status: :not_started,
        risk_level: :low,
        enabled_currencies: [],
        chain_screening: false
      }

      assert {:error, %Ecto.Changeset{}} =
               AccountHolderContext.create_account_holder(session, request)
    end

    test "update_account_holder/3 with valid data updates the account_holder", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %AccountHolderRequest{
        account_holder_type: account_holder.account_holder_type,
        status: :active,
        kyc_status: :approved,
        risk_level: :medium,
        enabled_currencies: ["USD"],
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:ok, %AccountHolder{} = updated} =
               AccountHolderContext.update_account_holder(session, account_holder, request)

      assert updated.status == :active
      assert updated.kyc_status == :approved
      assert updated.risk_level == :medium
    end

    test "update_account_holder/3 with invalid data returns error changeset", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %AccountHolderRequest{
        account_holder_type: nil,
        status: :pending,
        kyc_status: :not_started,
        risk_level: :low,
        enabled_currencies: [],
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:error, %Ecto.Changeset{}} =
               AccountHolderContext.update_account_holder(session, account_holder, request)
    end

    test "delete_account_holder/2 deletes the account_holder", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      assert {:ok, %AccountHolder{}} =
               AccountHolderContext.delete_account_holder(session, account_holder)

      assert_raise Ecto.NoResultsError, fn ->
        AccountHolderContext.get_account_holder!(session, account_holder.id)
      end
    end

    test "change_account_holder/1 returns an account_holder changeset", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      assert %Ecto.Changeset{} = AccountHolderContext.change_account_holder(account_holder)
    end
  end

  describe "ledger account tree audit (issue #31 phase 1)" do
    setup %{session: session, tenant: tenant} do
      {:ok, _} =
        AtomicFi.TenantContext.update_tenant(session, tenant, %{
          enabled_regimes: ["ach", "wire"]
        })

      :ok
    end

    defp ah_request(session, legal_entity_id, currencies, regimes) do
      %AccountHolderRequest{
        account_holder_type: :individual,
        status: :pending,
        kyc_status: :not_started,
        risk_level: :low,
        enabled_currencies: currencies,
        enabled_regimes: regimes,
        tenant_id: session.tenant_id,
        chain_screening: false
      }
    end

    test "create_account_holder/2 materialises one Ledger + AH-tree per enabled currency",
         %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)
      request = ah_request(session, legal_entity.id, ["USD", "EUR"], ["ach", "wire"])

      assert {:ok, ah} = AccountHolderContext.create_account_holder(session, request)

      {:ok, {ledgers, _}} =
        LedgerContext.list_ledgers(session, %{
          filters: [%{field: :account_holder_id, op: :==, value: ah.id}]
        })

      assert Enum.map(ledgers, & &1.currency) |> Enum.sort() == ["EUR", "USD"]

      las = LedgerAccountContext.list_for_entity(session, ah)

      # Per ledger: 1 ah_root + 2 ah_regime_root → 3 × 2 ledgers = 6 LAs.
      assert length(las) == 6
      assert Enum.count(las, &(&1.la_type == :account_holder_root)) == 2
      assert Enum.count(las, &(&1.la_type == :account_holder_regime_root)) == 4

      regimes_per_ledger =
        las
        |> Enum.filter(&(&1.la_type == :account_holder_regime_root))
        |> Enum.group_by(& &1.ledger_id, & &1.regime)

      assert Enum.all?(regimes_per_ledger, fn {_lid, rs} -> Enum.sort(rs) == ["ach", "wire"] end)
    end

    test "create_account_holder/2 with empty enabled_currencies materialises no Ledgers / LAs",
         %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)
      request = ah_request(session, legal_entity.id, [], ["ach"])

      assert {:ok, ah} = AccountHolderContext.create_account_holder(session, request)

      {:ok, {ledgers, _}} =
        LedgerContext.list_ledgers(session, %{
          filters: [%{field: :account_holder_id, op: :==, value: ah.id}]
        })

      assert ledgers == []
      assert LedgerAccountContext.list_for_entity(session, ah) == []
    end

    test "create_account_holder/2 leaves AH LAs block-by-default until onboarding applies controls",
         %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)
      request = ah_request(session, legal_entity.id, ["USD"], ["ach"])

      assert {:ok, ah} = AccountHolderContext.create_account_holder(session, request)

      las = LedgerAccountContext.list_for_entity(session, ah)
      assert Enum.all?(las, & &1.is_blocked)
      assert Enum.all?(las, &(is_binary(&1.block_reason) and &1.block_reason != ""))
    end

    test "update_account_holder/3 appends missing AH regime-root LAs when enabled_regimes grows",
         %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      {:ok, ah} =
        AccountHolderContext.create_account_holder(
          session,
          ah_request(session, legal_entity.id, ["USD"], ["ach"])
        )

      assert length(LedgerAccountContext.list_for_entity(session, ah)) == 2

      {:ok, updated} =
        AccountHolderContext.update_account_holder(
          session,
          ah,
          ah_request(session, ah.legal_entity_id, ["USD"], ["ach", "wire"])
        )

      las = LedgerAccountContext.list_for_entity(session, updated)
      assert length(las) == 3
      regimes = las |> Enum.map(& &1.regime) |> Enum.sort()
      assert regimes == ["ach", "root", "wire"]
    end

    test "update_account_holder/3 appends a new Ledger + AH-tree when enabled_currencies grows",
         %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      {:ok, ah} =
        AccountHolderContext.create_account_holder(
          session,
          ah_request(session, legal_entity.id, ["USD"], ["ach"])
        )

      {:ok, updated} =
        AccountHolderContext.update_account_holder(
          session,
          ah,
          ah_request(session, ah.legal_entity_id, ["USD", "EUR"], ["ach"])
        )

      {:ok, {ledgers, _}} =
        LedgerContext.list_ledgers(session, %{
          filters: [%{field: :account_holder_id, op: :==, value: updated.id}]
        })

      assert Enum.map(ledgers, & &1.currency) |> Enum.sort() == ["EUR", "USD"]

      las = LedgerAccountContext.list_for_entity(session, updated)
      # 2 ledgers × (1 root + 1 regime_root) = 4
      assert length(las) == 4
    end

    test "update_account_holder/3 is idempotent — no duplicate LAs when regimes unchanged",
         %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      {:ok, ah} =
        AccountHolderContext.create_account_holder(
          session,
          ah_request(session, legal_entity.id, ["USD"], ["ach", "wire"])
        )

      before_count = length(LedgerAccountContext.list_for_entity(session, ah))

      {:ok, updated} =
        AccountHolderContext.update_account_holder(
          session,
          ah,
          ah_request(session, ah.legal_entity_id, ["USD"], ["ach", "wire"])
        )

      assert length(LedgerAccountContext.list_for_entity(session, updated)) == before_count
    end

    test "delete_account_holder/2 is restricted by FK when LA tree exists",
         %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      {:ok, ah} =
        AccountHolderContext.create_account_holder(
          session,
          ah_request(session, legal_entity.id, ["USD"], ["ach"])
        )

      # AH has a materialised LA tree — Repo.delete should hit
      # `ledger_accounts.account_holder_id` ON DELETE RESTRICT.
      assert_raise Ecto.ConstraintError, fn ->
        AccountHolderContext.delete_account_holder(session, ah)
      end
    end
  end
end

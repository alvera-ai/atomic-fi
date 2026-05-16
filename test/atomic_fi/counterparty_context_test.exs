defmodule AtomicFi.CounterpartyContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.CounterpartyContext
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  alias AtomicFi.OpenApiSchema.CounterpartyRequest
  import AtomicFi.Factory

  describe "counterparties" do
    test "list_counterparties/1 returns all counterparties for tenant", %{session: session} do
      insert(:counterparty, tenant_id: session.tenant_id)
      {:ok, {counterparties, _meta}} = CounterpartyContext.list_counterparties(session)
      assert counterparties != []
    end

    test "get_counterparty!/2 returns the counterparty with given id", %{session: session} do
      counterparty = insert(:counterparty, tenant_id: session.tenant_id)

      assert %Counterparty{id: id} =
               CounterpartyContext.get_counterparty!(session, counterparty.id)

      assert id == counterparty.id
    end

    test "create_counterparty/2 with valid data creates a counterparty", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      request = %CounterpartyRequest{
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id,
        status: :active,
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:ok, %Counterparty{} = counterparty} =
               CounterpartyContext.create_counterparty(session, request)

      assert counterparty.account_holder_id == account_holder.id
      assert counterparty.legal_entity_id == legal_entity.id
      assert counterparty.status == :active
      assert counterparty.tenant_id == session.tenant_id
    end

    test "create_counterparty/2 with optional external_id", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      request = %CounterpartyRequest{
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id,
        status: :active,
        external_id: "CP-001",
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:ok, %Counterparty{} = counterparty} =
               CounterpartyContext.create_counterparty(session, request)

      assert counterparty.external_id == "CP-001"
    end

    test "create_counterparty/2 with invalid data returns error changeset", %{session: session} do
      request = %CounterpartyRequest{
        status: nil,
        chain_screening: false
      }

      assert {:error, %Ecto.Changeset{}} =
               CounterpartyContext.create_counterparty(session, request)
    end

    test "create_counterparty/2 enforces unique (account_holder_id, legal_entity_id) when no external_id is supplied",
         %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      request = %CounterpartyRequest{
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id,
        status: :active,
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:ok, _} = CounterpartyContext.create_counterparty(session, request)

      assert {:error, %Ecto.Changeset{}} =
               CounterpartyContext.create_counterparty(session, request)
    end

    test "create_counterparty/2 is get-or-create on external_id (external SoE id)",
         %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      request = %CounterpartyRequest{
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id,
        external_id: "EXT-CP-42",
        status: :active,
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:ok, %Counterparty{id: id1, external_id: "EXT-CP-42"}} =
               CounterpartyContext.create_counterparty(session, request)

      # Re-POST with same external_id — returns existing record (idempotent),
      # even if other fields (status, FKs) would differ. External-system idempotency
      # key wins; updates go through PUT.
      other_le = insert(:legal_entity, tenant_id: session.tenant_id)

      request2 = %CounterpartyRequest{
        account_holder_id: account_holder.id,
        legal_entity_id: other_le.id,
        external_id: "EXT-CP-42",
        status: :suspended,
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:ok, %Counterparty{id: id2, legal_entity_id: le_id2, status: status2}} =
               CounterpartyContext.create_counterparty(session, request2)

      assert id1 == id2
      assert le_id2 == legal_entity.id
      assert status2 == :active
    end

    test "create_counterparty/2 with nested legal_entity creates both atomically",
         %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %CounterpartyRequest{
        account_holder_id: account_holder.id,
        legal_entity: %{
          legal_entity_type: :individual,
          first_name: "Jane",
          last_name: "External",
          date_of_birth: ~D[1985-03-15],
          citizenship_country: "US",
          politically_exposed_person: false,
          tenant_id: session.tenant_id
        },
        status: :active,
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:ok, %Counterparty{legal_entity_id: le_id} = counterparty} =
               CounterpartyContext.create_counterparty(session, request)

      assert is_binary(le_id)
      assert counterparty.account_holder_id == account_holder.id
      assert counterparty.status == :active

      le =
        AtomicFi.LegalEntityContext.get_legal_entity!(session, le_id)

      assert le.first_name == "Jane"
      assert le.last_name == "External"
      assert le.tenant_id == session.tenant_id
    end

    test "create_counterparty/2 requires either legal_entity_id or nested legal_entity",
         %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %CounterpartyRequest{
        account_holder_id: account_holder.id,
        status: :active,
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:error, %Ecto.Changeset{}} =
               CounterpartyContext.create_counterparty(session, request)
    end

    test "update_counterparty/3 with valid data updates the counterparty", %{session: session} do
      counterparty = insert(:counterparty, tenant_id: session.tenant_id)

      request = %CounterpartyRequest{
        account_holder_id: counterparty.account_holder_id,
        legal_entity_id: counterparty.legal_entity_id,
        status: :suspended,
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:ok, %Counterparty{} = updated} =
               CounterpartyContext.update_counterparty(session, counterparty, request)

      assert updated.status == :suspended
    end

    test "update_counterparty/3 with invalid data returns error changeset", %{session: session} do
      counterparty = insert(:counterparty, tenant_id: session.tenant_id)

      # Non-existent legal_entity_id trips foreign_key_constraint — nil values are
      # stripped by ExOpenApiUtils.Mapper and don't propagate, so use a live bad value.
      request = %CounterpartyRequest{
        legal_entity_id: Ecto.UUID.generate(),
        status: :suspended,
        chain_screening: false
      }

      assert {:error, %Ecto.Changeset{}} =
               CounterpartyContext.update_counterparty(session, counterparty, request)
    end

    test "delete_counterparty/2 deletes the counterparty", %{session: session} do
      counterparty = insert(:counterparty, tenant_id: session.tenant_id)

      assert {:ok, %Counterparty{}} =
               CounterpartyContext.delete_counterparty(session, counterparty)

      assert_raise Ecto.NoResultsError, fn ->
        CounterpartyContext.get_counterparty!(session, counterparty.id)
      end
    end

    test "change_counterparty/1 returns a counterparty changeset", %{session: session} do
      counterparty = insert(:counterparty, tenant_id: session.tenant_id)
      assert %Ecto.Changeset{} = CounterpartyContext.change_counterparty(counterparty)
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

    # Builds an AH via the context so its Ledger + AH-tree exist before any CP write.
    defp create_ah(session, currencies, regimes) do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      {:ok, ah} =
        AccountHolderContext.create_account_holder(session, %AccountHolderRequest{
          legal_entity_id: legal_entity.id,
          holder_type: :individual,
          status: :pending,
          kyc_status: :not_started,
          risk_level: :low,
          enabled_currencies: currencies,
          enabled_regimes: regimes,
          tenant_id: session.tenant_id,
          chain_screening: false
        })

      ah
    end

    test "create_counterparty/2 materialises CP-root + CP-regime-root LAs per AH ledger",
         %{session: session} do
      ah = create_ah(session, ["USD", "EUR"], ["ach", "wire"])
      cp_le = insert(:legal_entity, tenant_id: session.tenant_id)

      {:ok, cp} =
        CounterpartyContext.create_counterparty(session, %CounterpartyRequest{
          account_holder_id: ah.id,
          legal_entity_id: cp_le.id,
          status: :active,
          enabled_regimes: ["ach", "wire"],
          tenant_id: session.tenant_id,
          chain_screening: false
        })

      las = LedgerAccountContext.list_for_entity(session, cp)

      # 2 ledgers × (1 cp_root + 2 cp_regime_root) = 6
      assert length(las) == 6
      assert Enum.count(las, &(&1.la_type == :counter_party_root)) == 2
      assert Enum.count(las, &(&1.la_type == :counter_party_regime_root)) == 4
      assert Enum.all?(las, & &1.is_blocked)
    end

    test "create_counterparty/2 leaves the AH's own LAs untouched",
         %{session: session} do
      ah = create_ah(session, ["USD"], ["ach"])
      before_ah_count = length(LedgerAccountContext.list_for_entity(session, ah))

      cp_le = insert(:legal_entity, tenant_id: session.tenant_id)

      {:ok, _cp} =
        CounterpartyContext.create_counterparty(session, %CounterpartyRequest{
          account_holder_id: ah.id,
          legal_entity_id: cp_le.id,
          status: :active,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id,
          chain_screening: false
        })

      assert length(LedgerAccountContext.list_for_entity(session, ah)) == before_ah_count
    end

    test "update_counterparty/3 appends missing CP regime-root LAs when enabled_regimes grows",
         %{session: session} do
      ah = create_ah(session, ["USD"], ["ach", "wire"])
      cp_le = insert(:legal_entity, tenant_id: session.tenant_id)

      {:ok, cp} =
        CounterpartyContext.create_counterparty(session, %CounterpartyRequest{
          account_holder_id: ah.id,
          legal_entity_id: cp_le.id,
          status: :active,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id,
          chain_screening: false
        })

      assert length(LedgerAccountContext.list_for_entity(session, cp)) == 2

      {:ok, updated} =
        CounterpartyContext.update_counterparty(session, cp, %CounterpartyRequest{
          account_holder_id: cp.account_holder_id,
          legal_entity_id: cp.legal_entity_id,
          status: cp.status,
          enabled_regimes: ["ach", "wire"],
          tenant_id: session.tenant_id,
          chain_screening: false
        })

      las = LedgerAccountContext.list_for_entity(session, updated)
      assert length(las) == 3
      regimes = las |> Enum.map(& &1.regime) |> Enum.sort()
      assert regimes == ["ach", "root", "wire"]
    end

    test "update_counterparty/3 is idempotent — no duplicate LAs when regimes unchanged",
         %{session: session} do
      ah = create_ah(session, ["USD"], ["ach"])
      cp_le = insert(:legal_entity, tenant_id: session.tenant_id)

      {:ok, cp} =
        CounterpartyContext.create_counterparty(session, %CounterpartyRequest{
          account_holder_id: ah.id,
          legal_entity_id: cp_le.id,
          status: :active,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id,
          chain_screening: false
        })

      before_count = length(LedgerAccountContext.list_for_entity(session, cp))

      {:ok, updated} =
        CounterpartyContext.update_counterparty(session, cp, %CounterpartyRequest{
          account_holder_id: cp.account_holder_id,
          legal_entity_id: cp.legal_entity_id,
          status: :suspended,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id,
          chain_screening: false
        })

      assert length(LedgerAccountContext.list_for_entity(session, updated)) == before_count
    end

    test "delete_counterparty/2 is restricted by FK when LA tree exists",
         %{session: session} do
      ah = create_ah(session, ["USD"], ["ach"])
      cp_le = insert(:legal_entity, tenant_id: session.tenant_id)

      {:ok, cp} =
        CounterpartyContext.create_counterparty(session, %CounterpartyRequest{
          account_holder_id: ah.id,
          legal_entity_id: cp_le.id,
          status: :active,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id,
          chain_screening: false
        })

      assert_raise Ecto.ConstraintError, fn ->
        CounterpartyContext.delete_counterparty(session, cp)
      end
    end
  end
end

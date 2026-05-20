defmodule AtomicFi.CounterpartyContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.CounterpartyContext
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  alias AtomicFi.OpenApiSchema.CounterpartyRequest
  alias AtomicFi.OpenApiSchema.LegalEntityRequest
  import AtomicFi.Factory

  defp le_request(session, overrides \\ %{}) do
    base = %LegalEntityRequest{
      legal_entity_type: :individual,
      tenant_id: session.tenant_id,
      first_name: "CP",
      last_name: "Holder",
      citizenship_country: "US"
    }

    struct(base, overrides)
  end

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

    test "get_counterparty_by_external_id/2 matches get_counterparty!/2 preloads", %{
      session: session
    } do
      counterparty =
        insert(:counterparty, external_id: "cp-by-ext", tenant_id: session.tenant_id)

      insert(:legal_entity,
        counterparty_id: counterparty.id,
        subject_type: :counterparty,
        account_holder_id: counterparty.account_holder_id,
        tenant_id: session.tenant_id
      )

      by_id = CounterpartyContext.get_counterparty!(session, counterparty.id)
      by_ext = CounterpartyContext.get_counterparty_by_external_id(session, "cp-by-ext")

      assert by_ext.id == by_id.id
      assert by_ext.legal_entity.id == by_id.legal_entity.id
      assert is_list(by_ext.legal_entity.addresses)
      assert is_list(by_ext.legal_entity.phone_numbers)
      assert is_list(by_ext.legal_entity.identifications)
    end

    test "get_counterparty_by_external_id/2 returns nil when handle is unknown", %{
      session: session
    } do
      assert CounterpartyContext.get_counterparty_by_external_id(session, "missing") == nil
    end

    test "create_counterparty/2 with valid data creates a counterparty", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %CounterpartyRequest{
        account_holder_id: account_holder.id,
        status: :active,
        tenant_id: session.tenant_id,
        chain_screening: false,
        legal_entity: le_request(session)
      }

      assert {:ok, %Counterparty{} = counterparty} =
               CounterpartyContext.create_counterparty(session, request)

      assert counterparty.account_holder_id == account_holder.id
      assert counterparty.legal_entity.account_holder_id == account_holder.id
      assert counterparty.legal_entity.subject_type == :counterparty
      assert counterparty.status == :active
      assert counterparty.tenant_id == session.tenant_id
    end

    test "create_counterparty/2 with optional external_id", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %CounterpartyRequest{
        account_holder_id: account_holder.id,
        status: :active,
        external_id: "CP-001",
        tenant_id: session.tenant_id,
        chain_screening: false,
        legal_entity: le_request(session)
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

    test "create_counterparty/2 is get-or-create on external_id (external SoE id)",
         %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %CounterpartyRequest{
        account_holder_id: account_holder.id,
        external_id: "EXT-CP-42",
        status: :active,
        tenant_id: session.tenant_id,
        chain_screening: false,
        legal_entity: le_request(session)
      }

      assert {:ok, %Counterparty{id: id1, external_id: "EXT-CP-42"}} =
               CounterpartyContext.create_counterparty(session, request)

      # Re-POST with same external_id — returns existing record (idempotent),
      # even if other fields (status, FKs) would differ.
      request2 = %CounterpartyRequest{
        account_holder_id: account_holder.id,
        external_id: "EXT-CP-42",
        status: :suspended,
        tenant_id: session.tenant_id,
        chain_screening: false,
        legal_entity: le_request(session)
      }

      assert {:ok, %Counterparty{id: id2, status: status2}} =
               CounterpartyContext.create_counterparty(session, request2)

      assert id1 == id2
      assert status2 == :active
    end

    test "create_counterparty/2 requires nested legal_entity",
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

      insert(:legal_entity,
        counterparty_id: counterparty.id,
        subject_type: :counterparty,
        account_holder_id: counterparty.account_holder_id,
        tenant_id: session.tenant_id
      )

      counterparty = CounterpartyContext.get_counterparty!(session, counterparty.id)

      request = %CounterpartyRequest{
        account_holder_id: counterparty.account_holder_id,
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

      request = %CounterpartyRequest{
        status: :not_a_valid_status,
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

    defp create_ah(session, currencies, regimes) do
      {:ok, ah} =
        AccountHolderContext.create_account_holder(session, %AccountHolderRequest{
          account_holder_type: :individual,
          status: :pending,
          kyc_status: :not_started,
          risk_level: :low,
          enabled_currencies: currencies,
          enabled_regimes: regimes,
          tenant_id: session.tenant_id,
          chain_screening: false,
          legal_entity: %LegalEntityRequest{
            legal_entity_type: :individual,
            tenant_id: session.tenant_id,
            first_name: "AH",
            last_name: "Owner",
            citizenship_country: "US"
          }
        })

      ah
    end

    defp cp_le_request(session) do
      %LegalEntityRequest{
        legal_entity_type: :individual,
        tenant_id: session.tenant_id,
        first_name: "CP",
        last_name: "Holder",
        citizenship_country: "US"
      }
    end

    test "create_counterparty/2 materialises CP-root + CP-regime-root LAs per AH ledger",
         %{session: session} do
      ah = create_ah(session, ["USD", "EUR"], ["ach", "wire"])

      {:ok, cp} =
        CounterpartyContext.create_counterparty(session, %CounterpartyRequest{
          account_holder_id: ah.id,
          status: :active,
          enabled_regimes: ["ach", "wire"],
          tenant_id: session.tenant_id,
          chain_screening: false,
          legal_entity: cp_le_request(session)
        })

      las = LedgerAccountContext.list_for_entity(session, cp)

      # 2 ledgers × (1 cp_root + 2 cp_regime_root) = 6
      assert length(las) == 6
      assert Enum.count(las, &(&1.la_type == :counter_party_root)) == 2
      assert Enum.count(las, &(&1.la_type == :counter_party_regime_root)) == 4
      assert Enum.all?(las, &(&1.is_blocked == false))
    end

    test "create_counterparty/2 leaves the AH's own LAs untouched",
         %{session: session} do
      ah = create_ah(session, ["USD"], ["ach"])
      before_ah_count = length(LedgerAccountContext.list_for_entity(session, ah))

      {:ok, _cp} =
        CounterpartyContext.create_counterparty(session, %CounterpartyRequest{
          account_holder_id: ah.id,
          status: :active,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id,
          chain_screening: false,
          legal_entity: cp_le_request(session)
        })

      assert length(LedgerAccountContext.list_for_entity(session, ah)) == before_ah_count
    end

    test "update_counterparty/3 appends missing CP regime-root LAs when enabled_regimes grows",
         %{session: session} do
      ah = create_ah(session, ["USD"], ["ach", "wire"])

      {:ok, cp} =
        CounterpartyContext.create_counterparty(session, %CounterpartyRequest{
          account_holder_id: ah.id,
          status: :active,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id,
          chain_screening: false,
          legal_entity: cp_le_request(session)
        })

      assert length(LedgerAccountContext.list_for_entity(session, cp)) == 2

      {:ok, updated} =
        CounterpartyContext.update_counterparty(session, cp, %CounterpartyRequest{
          account_holder_id: cp.account_holder_id,
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

      {:ok, cp} =
        CounterpartyContext.create_counterparty(session, %CounterpartyRequest{
          account_holder_id: ah.id,
          status: :active,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id,
          chain_screening: false,
          legal_entity: cp_le_request(session)
        })

      before_count = length(LedgerAccountContext.list_for_entity(session, cp))

      {:ok, updated} =
        CounterpartyContext.update_counterparty(session, cp, %CounterpartyRequest{
          account_holder_id: cp.account_holder_id,
          status: :suspended,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id,
          chain_screening: false
        })

      assert length(LedgerAccountContext.list_for_entity(session, updated)) == before_count
    end

    test "delete_counterparty/2 returns {:error, changeset} when LA tree exists",
         %{session: session} do
      ah = create_ah(session, ["USD"], ["ach"])

      {:ok, cp} =
        CounterpartyContext.create_counterparty(session, %CounterpartyRequest{
          account_holder_id: ah.id,
          status: :active,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id,
          chain_screening: false,
          legal_entity: cp_le_request(session)
        })

      # CP write lifecycle materialises ledger_accounts — ON DELETE RESTRICT
      # is converted to a changeset error in the context so the controller
      # renders 422 instead of crashing.
      assert {:error, %Ecto.Changeset{errors: errors, valid?: false}} =
               CounterpartyContext.delete_counterparty(session, cp)

      assert {:id, {message, [constraint: :foreign, constraint_name: _]}} =
               List.keyfind(errors, :id, 0)

      assert message =~ "exist for this counterparty"
    end
  end
end

defmodule AtomicFi.PaymentAccountContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.CounterpartyContext
  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  alias AtomicFi.OpenApiSchema.CounterpartyRequest
  alias AtomicFi.OpenApiSchema.PaymentAccountRequest
  alias AtomicFi.PaymentAccountContext
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  import AtomicFi.Factory

  describe "payment_accounts" do
    test "list_payment_accounts/1 returns all payment accounts for tenant", %{session: session} do
      insert(:payment_account, tenant_id: session.tenant_id)
      {:ok, {payment_accounts, _meta}} = PaymentAccountContext.list_payment_accounts(session)
      assert payment_accounts != []
    end

    test "list_payment_accounts/1 returns own tenant records", %{session: session} do
      own = insert(:payment_account, tenant_id: session.tenant_id)

      {:ok, {payment_accounts, _meta}} = PaymentAccountContext.list_payment_accounts(session)
      ids = Enum.map(payment_accounts, & &1.id)
      assert own.id in ids
    end

    test "get_payment_account!/2 returns the payment account with given id", %{session: session} do
      payment_account = insert(:payment_account, tenant_id: session.tenant_id)

      assert %PaymentAccount{id: id} =
               PaymentAccountContext.get_payment_account!(session, payment_account.id)

      assert id == payment_account.id
    end

    test "create_payment_account/2 with valid data creates a payment account", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      insert(:ledger,
        tenant_id: session.tenant_id,
        account_holder_id: account_holder.id,
        currency: "USD"
      )

      request = %PaymentAccountRequest{
        account_type: :bank_account,
        currency: "USD",
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %PaymentAccount{} = payment_account} =
               PaymentAccountContext.create_payment_account(session, request)

      assert payment_account.account_type == :bank_account
      assert payment_account.status == :active
      assert payment_account.account_holder_id == account_holder.id
      assert payment_account.tenant_id == session.tenant_id
    end

    test "create_payment_account/2 with optional fields", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      insert(:ledger,
        tenant_id: session.tenant_id,
        account_holder_id: account_holder.id,
        currency: "EUR"
      )

      request = %PaymentAccountRequest{
        account_type: :bank_account,
        status: :suspended,
        currency: "EUR",
        account_number: "12345678",
        routing_number: "021000021",
        iban: "DE89370400440532013000",
        swift_bic: "DEUTDEDB",
        bank_name: "Deutsche Bank",
        payment_account_number: "ACC-2026-001",
        payment_account_external_id: "ext-acc-001",
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %PaymentAccount{} = payment_account} =
               PaymentAccountContext.create_payment_account(session, request)

      assert payment_account.status == :suspended
      assert payment_account.currency == "EUR"
      assert payment_account.account_number == "12345678"
      assert payment_account.routing_number == "021000021"
      assert payment_account.iban == "DE89370400440532013000"
      assert payment_account.swift_bic == "DEUTDEDB"
      assert payment_account.bank_name == "Deutsche Bank"
      assert payment_account.payment_account_number == "ACC-2026-001"
      assert payment_account.payment_account_external_id == "ext-acc-001"
    end

    test "create_payment_account/2 with card type and card_pan", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      insert(:ledger,
        tenant_id: session.tenant_id,
        account_holder_id: account_holder.id,
        currency: "USD"
      )

      request = %PaymentAccountRequest{
        account_type: :card,
        card_pan: "4111",
        currency: "USD",
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %PaymentAccount{} = payment_account} =
               PaymentAccountContext.create_payment_account(session, request)

      assert payment_account.account_type == :card
      assert payment_account.card_pan == "4111"
    end

    test "create_payment_account/2 defaults status to :active when not provided", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      insert(:ledger,
        tenant_id: session.tenant_id,
        account_holder_id: account_holder.id,
        currency: "USD"
      )

      request = %PaymentAccountRequest{
        account_type: :wallet,
        currency: "USD",
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %PaymentAccount{} = payment_account} =
               PaymentAccountContext.create_payment_account(session, request)

      assert payment_account.status == :active
    end

    test "create_payment_account/2 with invalid data returns error changeset", %{
      session: session
    } do
      request = %PaymentAccountRequest{
        account_type: nil,
        account_holder_id: nil,
        tenant_id: session.tenant_id
      }

      assert {:error, %Ecto.Changeset{}} =
               PaymentAccountContext.create_payment_account(session, request)
    end

    test "create_payment_account/2 enforces unique payment_account_external_id per tenant", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      insert(:ledger,
        tenant_id: session.tenant_id,
        account_holder_id: account_holder.id,
        currency: "USD"
      )

      request = %PaymentAccountRequest{
        account_type: :bank_account,
        currency: "USD",
        payment_account_external_id: "ext-unique-001",
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, _} = PaymentAccountContext.create_payment_account(session, request)
      assert {:error, changeset} = PaymentAccountContext.create_payment_account(session, request)

      errors = errors_on(changeset)

      assert Map.get(errors, :payment_account_external_id) == ["has already been taken"] or
               Map.get(errors, :tenant_id) == ["has already been taken"]
    end

    test "create_payment_account/2 allows nil external_id for multiple accounts", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      insert(:ledger,
        tenant_id: session.tenant_id,
        account_holder_id: account_holder.id,
        currency: "USD"
      )

      make_request = fn ->
        %PaymentAccountRequest{
          account_type: :bank_account,
          currency: "USD",
          account_holder_id: account_holder.id,
          tenant_id: session.tenant_id
        }
      end

      assert {:ok, _} = PaymentAccountContext.create_payment_account(session, make_request.())
      assert {:ok, _} = PaymentAccountContext.create_payment_account(session, make_request.())
    end

    test "update_payment_account/3 with valid data updates the payment account", %{
      session: session
    } do
      payment_account = insert(:payment_account, tenant_id: session.tenant_id)

      request = %PaymentAccountRequest{
        account_type: payment_account.account_type,
        currency: payment_account.currency,
        status: :suspended,
        account_holder_id: payment_account.account_holder_id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %PaymentAccount{} = updated} =
               PaymentAccountContext.update_payment_account(session, payment_account, request)

      assert updated.status == :suspended
    end

    test "update_payment_account/3 with invalid data returns error changeset", %{
      session: session
    } do
      payment_account = insert(:payment_account, tenant_id: session.tenant_id)

      # Non-existent account_holder_id trips foreign_key_constraint; nil values are
      # stripped by ExOpenApiUtils.Mapper, so use a live bad value.
      request = %PaymentAccountRequest{
        account_type: payment_account.account_type,
        account_holder_id: Ecto.UUID.generate(),
        tenant_id: session.tenant_id
      }

      assert {:error, %Ecto.Changeset{}} =
               PaymentAccountContext.update_payment_account(session, payment_account, request)
    end

    test "delete_payment_account/2 deletes the payment account", %{session: session} do
      payment_account = insert(:payment_account, tenant_id: session.tenant_id)

      assert {:ok, %PaymentAccount{}} =
               PaymentAccountContext.delete_payment_account(session, payment_account)

      assert_raise Ecto.NoResultsError, fn ->
        PaymentAccountContext.get_payment_account!(session, payment_account.id)
      end
    end

    test "change_payment_account/1 returns a payment account changeset", %{session: session} do
      payment_account = insert(:payment_account, tenant_id: session.tenant_id)

      assert %Ecto.Changeset{} = PaymentAccountContext.change_payment_account(payment_account)
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

    defp create_cp(session, ah, regimes) do
      cp_le = insert(:legal_entity, tenant_id: session.tenant_id)

      {:ok, cp} =
        CounterpartyContext.create_counterparty(session, %CounterpartyRequest{
          account_holder_id: ah.id,
          legal_entity_id: cp_le.id,
          status: :active,
          enabled_regimes: regimes,
          tenant_id: session.tenant_id,
          chain_screening: false
        })

      cp
    end

    test "create_payment_account/2 (AH-owned) materialises AH-PA root + regime-root LAs",
         %{session: session} do
      ah = create_ah(session, ["USD"], ["ach", "wire"])

      {:ok, pa} =
        PaymentAccountContext.create_payment_account(session, %PaymentAccountRequest{
          account_type: :bank_account,
          currency: "USD",
          account_holder_id: ah.id,
          enabled_regimes: ["ach", "wire"],
          tenant_id: session.tenant_id
        })

      las = LedgerAccountContext.list_for_entity(session, pa)

      assert length(las) == 3
      assert Enum.count(las, &(&1.la_type == :account_holder_payment_account_root)) == 1
      assert Enum.count(las, &(&1.la_type == :account_holder_payment_account_regime_root)) == 2
      assert Enum.all?(las, &(&1.counterparty_id == nil))
      assert Enum.all?(las, & &1.is_blocked)
    end

    test "create_payment_account/2 (CP-owned) materialises CP-PA root + regime-root LAs",
         %{session: session} do
      ah = create_ah(session, ["USD"], ["ach"])
      cp = create_cp(session, ah, ["ach"])

      {:ok, pa} =
        PaymentAccountContext.create_payment_account(session, %PaymentAccountRequest{
          account_type: :bank_account,
          currency: "USD",
          account_holder_id: ah.id,
          counterparty_id: cp.id,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id
        })

      las = LedgerAccountContext.list_for_entity(session, pa)

      assert length(las) == 2
      assert Enum.count(las, &(&1.la_type == :counter_party_payment_account_root)) == 1
      assert Enum.count(las, &(&1.la_type == :counter_party_payment_account_regime_root)) == 1
      assert Enum.all?(las, &(&1.counterparty_id == cp.id))
      assert Enum.all?(las, & &1.is_blocked)
    end

    test "create_payment_account/2 leaves the parent AH and CP own-LAs untouched",
         %{session: session} do
      ah = create_ah(session, ["USD"], ["ach"])
      cp = create_cp(session, ah, ["ach"])

      before_ah = length(LedgerAccountContext.list_for_entity(session, ah))
      before_cp = length(LedgerAccountContext.list_for_entity(session, cp))

      {:ok, _pa} =
        PaymentAccountContext.create_payment_account(session, %PaymentAccountRequest{
          account_type: :bank_account,
          currency: "USD",
          account_holder_id: ah.id,
          counterparty_id: cp.id,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id
        })

      assert length(LedgerAccountContext.list_for_entity(session, ah)) == before_ah
      assert length(LedgerAccountContext.list_for_entity(session, cp)) == before_cp
    end

    test "update_payment_account/3 appends missing PA regime-root LAs when enabled_regimes grows",
         %{session: session} do
      ah = create_ah(session, ["USD"], ["ach", "wire"])

      {:ok, pa} =
        PaymentAccountContext.create_payment_account(session, %PaymentAccountRequest{
          account_type: :bank_account,
          currency: "USD",
          account_holder_id: ah.id,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id
        })

      assert length(LedgerAccountContext.list_for_entity(session, pa)) == 2

      {:ok, updated} =
        PaymentAccountContext.update_payment_account(session, pa, %PaymentAccountRequest{
          account_type: pa.account_type,
          currency: pa.currency,
          account_holder_id: pa.account_holder_id,
          enabled_regimes: ["ach", "wire"],
          tenant_id: session.tenant_id
        })

      las = LedgerAccountContext.list_for_entity(session, updated)
      assert length(las) == 3
      regimes = las |> Enum.map(& &1.regime) |> Enum.sort()
      assert regimes == ["ach", "root", "wire"]
    end

    test "update_payment_account/3 is idempotent — no duplicate LAs when regimes unchanged",
         %{session: session} do
      ah = create_ah(session, ["USD"], ["ach"])

      {:ok, pa} =
        PaymentAccountContext.create_payment_account(session, %PaymentAccountRequest{
          account_type: :bank_account,
          currency: "USD",
          account_holder_id: ah.id,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id
        })

      before_count = length(LedgerAccountContext.list_for_entity(session, pa))

      {:ok, updated} =
        PaymentAccountContext.update_payment_account(session, pa, %PaymentAccountRequest{
          account_type: pa.account_type,
          currency: pa.currency,
          status: :suspended,
          account_holder_id: pa.account_holder_id,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id
        })

      assert length(LedgerAccountContext.list_for_entity(session, updated)) == before_count
    end

    test "delete_payment_account/2 is restricted by FK when LA tree exists",
         %{session: session} do
      ah = create_ah(session, ["USD"], ["ach"])

      {:ok, pa} =
        PaymentAccountContext.create_payment_account(session, %PaymentAccountRequest{
          account_type: :bank_account,
          currency: "USD",
          account_holder_id: ah.id,
          enabled_regimes: ["ach"],
          tenant_id: session.tenant_id
        })

      assert_raise Ecto.ConstraintError, fn ->
        PaymentAccountContext.delete_payment_account(session, pa)
      end
    end
  end
end

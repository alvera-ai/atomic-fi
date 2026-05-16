defmodule AtomicFi.OnboardingContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.OnboardingContext
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  alias AtomicFi.RuleEngineMock
  alias AtomicFi.SessionContext.Session

  import AtomicFi.Factory
  import Mox

  setup :verify_on_exit!

  setup %{session: session, tenant: tenant} do
    {:ok, _} =
      AtomicFi.TenantContext.update_tenant(session, tenant, %{enabled_regimes: ["ach", "wire"]})

    :ok
  end

  describe "enqueue_next/2" do
    test "returns {:ok, nil} when scheduled_at is nil", %{session: session} do
      ah = build_ah(session)
      assert {:ok, nil} = OnboardingContext.enqueue_next(ah, nil)
    end

    test "returns {:ok, job_id} when scheduled_at is set", %{session: session} do
      ah = build_ah(session)
      scheduled_at = DateTime.add(DateTime.utc_now(), 60, :second)

      assert {:ok, job_id} = OnboardingContext.enqueue_next(ah, scheduled_at)
      assert is_integer(job_id)
    end
  end

  describe "refresh/2" do
    test "clears rescreen_job_id and re-runs onboarding", %{session: session} do
      ah = build_ah(session)
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      stub(RuleEngineMock, :get_controls, fn _session, :onboarding, _entity ->
        {:ok, %{controls: %{}, next_screening_at: future}}
      end)

      # Seed an initial rescreen_job_id via a first onboard.
      {:ok, ah_with_job} = OnboardingContext.onboard(session, ah)
      initial_job_id = ah_with_job.rescreen_job_id
      assert is_integer(initial_job_id)

      {:ok, refreshed} = OnboardingContext.refresh(session, ah_with_job)

      assert is_integer(refreshed.rescreen_job_id)
      # New job linked — different id from the prior one.
      assert refreshed.rescreen_job_id != initial_job_id
    end
  end

  describe "load_for_rescreen/1" do
    test "resolves session + AH entity from Oban args", %{session: session} do
      ah = build_ah(session)

      args = %{
        "entity_module" => "Elixir.AtomicFi.AccountHolderContext.AccountHolder",
        "entity_id" => ah.id,
        "tenant_id" => ah.tenant_id
      }

      assert {:ok, loaded_session, loaded_entity} = OnboardingContext.load_for_rescreen(args)
      assert loaded_session.tenant_id == ah.tenant_id
      assert loaded_entity.id == ah.id
    end

    test "resolves session + CP entity from Oban args", %{session: session} do
      ah = build_ah(session)
      cp = insert(:counterparty, account_holder_id: ah.id, tenant_id: session.tenant_id)
      insert(:legal_entity,
        counterparty_id: cp.id,
        subject_type: :counterparty,
        account_holder_id: ah.id,
        tenant_id: session.tenant_id
      )

      args = %{
        "entity_module" => "Elixir.AtomicFi.CounterpartyContext.Counterparty",
        "entity_id" => cp.id,
        "tenant_id" => cp.tenant_id
      }

      assert {:ok, _session, loaded_entity} = OnboardingContext.load_for_rescreen(args)
      assert loaded_entity.id == cp.id
    end

    test "resolves session + PA entity from Oban args", %{session: session} do
      ah = build_ah(session)

      {:ok, pa} =
        AtomicFi.PaymentAccountContext.create_payment_account(
          session,
          %AtomicFi.OpenApiSchema.PaymentAccountRequest{
            account_type: :bank_account,
            currency: "USD",
            account_holder_id: ah.id,
            enabled_regimes: ["ach"],
            tenant_id: session.tenant_id
          }
        )

      args = %{
        "entity_module" => "Elixir.AtomicFi.PaymentAccountContext.PaymentAccount",
        "entity_id" => pa.id,
        "tenant_id" => pa.tenant_id
      }

      assert {:ok, _session, loaded_entity} = OnboardingContext.load_for_rescreen(args)
      assert loaded_entity.id == pa.id
    end

    test "raises when the entity does not exist for this tenant", %{tenant: tenant} do
      args = %{
        "entity_module" => "Elixir.AtomicFi.AccountHolderContext.AccountHolder",
        "entity_id" => Ecto.UUID.generate(),
        "tenant_id" => tenant.id
      }

      assert_raise Ecto.NoResultsError, fn ->
        OnboardingContext.load_for_rescreen(args)
      end
    end
  end

  describe "onboard/2 engine_result branches" do
    test "happy path — engine returns a {controls, next_screening_at} envelope",
         %{session: session} do
      ah = build_ah(session)
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      stub(RuleEngineMock, :get_controls, fn _session, :onboarding, _entity ->
        {:ok, %{controls: %{}, next_screening_at: future}}
      end)

      assert {:ok, updated} = OnboardingContext.onboard(session, ah)
      assert updated.id == ah.id
      assert is_integer(updated.rescreen_job_id)
    end

    test "engine error path propagates", %{session: session} do
      ah = build_ah(session)

      stub(RuleEngineMock, :get_controls, fn _session, :onboarding, _entity ->
        {:error, :engine_unreachable}
      end)

      assert {:error, :engine_unreachable} = OnboardingContext.onboard(session, ah)
    end
  end

  defp build_ah(%Session{} = session) do
    {:ok, ah} =
      AccountHolderContext.create_account_holder(session, %AccountHolderRequest{
        account_holder_type: :individual,
        status: :pending,
        kyc_status: :not_started,
        risk_level: :low,
        enabled_currencies: ["USD"],
        enabled_regimes: ["ach"],
        tenant_id: session.tenant_id,
        chain_screening: false,
        legal_entity: %AtomicFi.OpenApiSchema.LegalEntityRequest{
          legal_entity_type: :individual,
          tenant_id: session.tenant_id,
          first_name: "Test",
          last_name: "Holder",
          citizenship_country: "US"
        }
      })

    ah
  end
end

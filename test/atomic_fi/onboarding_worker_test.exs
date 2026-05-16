defmodule AtomicFi.OnboardingWorkerTest do
  use AtomicFi.DataCase
  use Oban.Testing, repo: AtomicFi.Repo

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.OnboardingWorker
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  alias AtomicFi.RuleEngineMock
  alias AtomicFi.SessionContext.Session

  import AtomicFi.Factory
  import Mox

  setup :verify_on_exit!

  setup %{session: session, tenant: tenant} do
    {:ok, _} =
      AtomicFi.TenantContext.update_tenant(session, tenant, %{enabled_regimes: ["ach"]})

    :ok
  end

  describe "perform/1" do
    test "re-runs onboarding for the entity referenced by job args",
         %{session: session, tenant: tenant} do
      ah = build_ah(session)

      stub(RuleEngineMock, :get_controls, fn _session, :onboarding, _entity ->
        {:ok, %{controls: %{}, next_screening_at: nil}}
      end)

      job_args = %{
        "entity_module" => "Elixir.AtomicFi.AccountHolderContext.AccountHolder",
        "entity_id" => ah.id,
        "tenant_id" => tenant.id
      }

      assert :ok = perform_job(OnboardingWorker, job_args)

      refreshed = AccountHolderContext.get_account_holder!(session, ah.id)
      # next_screening_at: nil → enqueue_next returns {:ok, nil} → rescreen_job_id cleared
      assert refreshed.rescreen_job_id == nil
    end
  end

  defp build_ah(%Session{} = session) do
    legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

    {:ok, ah} =
      AccountHolderContext.create_account_holder(session, %AccountHolderRequest{
        legal_entity_id: legal_entity.id,
        account_holder_type: :individual,
        status: :pending,
        kyc_status: :not_started,
        risk_level: :low,
        enabled_currencies: ["USD"],
        enabled_regimes: ["ach"],
        tenant_id: session.tenant_id,
        chain_screening: false
      })

    ah
  end
end

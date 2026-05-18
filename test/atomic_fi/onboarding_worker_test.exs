defmodule AtomicFi.OnboardingWorkerTest do
  use AtomicFi.DataCase
  use Oban.Testing, repo: AtomicFi.Repo

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.OnboardingWorker
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

      stub(RuleEngineMock, :evaluate, fn _session, _project, _decision, _payload ->
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
    ah = insert(:account_holder, tenant_id: session.tenant_id, enabled_regimes: ["ach"])
    insert(:legal_entity, account_holder_id: ah.id, tenant_id: session.tenant_id)
    AccountHolderContext.get_account_holder!(session, ah.id)
  end
end

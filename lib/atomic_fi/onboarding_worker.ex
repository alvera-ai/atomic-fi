defmodule AtomicFi.OnboardingWorker do
  @moduledoc """
  Periodic re-onboarding for an AH / CP / PA / BO.

  Triggered indirectly: `OnboardingContext.onboard/2` enqueues this
  worker `scheduled_at: next_screening_at` (the timestamp the
  RuleEngine returned alongside its Controls) and writes the resulting
  job id onto the entity's `rescreen_job_id` column.

  `perform/1`:

    1. Loads the entity by its struct-module name + id.
    2. Nulls its `rescreen_job_id` — the running job *is* the
       currently-referenced row; the pointer is dropped before any
       work redoes itself so the FK target lifecycle stays clean.
    3. Delegates to `OnboardingContext.onboard/2`, which re-screens,
       re-evaluates the RuleEngine, re-applies the per-LA controls,
       enqueues the next iteration of this worker, and writes the new
       `rescreen_job_id` back onto the entity.

  Args:

      %{
        "entity_module" => "Elixir.AtomicFi.AccountHolderContext.AccountHolder" | …,
        "entity_id"     => uuid,
        "tenant_id"     => uuid
      }
  """

  use Oban.Worker, queue: :onboarding, max_attempts: 3

  alias AtomicFi.OnboardingContext
  alias AtomicFi.Repo
  alias AtomicFi.TenantContext.Tenant

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "entity_module" => entity_module,
          "entity_id" => entity_id,
          "tenant_id" => tenant_id
        }
      }) do
    session = build_session(tenant_id)
    module = String.to_existing_atom(entity_module)
    entity = Repo.get!(module, entity_id, session: session)

    {:ok, entity} =
      entity
      |> Ecto.Changeset.change(%{rescreen_job_id: nil})
      |> Repo.update(session: session)

    case OnboardingContext.onboard(session, entity) do
      {:ok, _entity} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_session(tenant_id) do
    tenant = Repo.get!(Tenant, tenant_id, skip_multi_tenancy_check: true)
    %{tenant_id: tenant_id, tenant: tenant}
  end
end

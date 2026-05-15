defmodule AtomicFi.Repo.Migrations.AddRescreenJobIdToOnboardableEntities do
  use Ecto.Migration

  # OnboardingWorker re-runs the onboarding flow on a schedule. The four
  # onboardable entities (account_holders, counterparties, payment_accounts,
  # beneficial_owners) each carry a pointer to the currently-scheduled job.
  # The worker manages the lifecycle: nulls this column when it starts and
  # re-sets it after enqueueing the next iteration, so the referenced row
  # is never pruned while still referenced.
  #
  # BOs are screen-only — the RuleEngine still runs (against the BO's
  # parent AH or CP), but apply_controls targets the PARENT's LAs. The
  # BO's own `rescreen_job_id` holds the BO's next-screen schedule.
  #
  # The column is bigint (not our UUID convention) because that is Oban's
  # `oban_jobs.id` type, and the table lives in the `oban` schema. Has to
  # run AFTER the Oban migration (`20260224221532_create_oban_jobs.exs`)
  # because the FK target must exist first.

  def change do
    alter table(:account_holders) do
      add :rescreen_job_id,
          references(:oban_jobs, prefix: "oban", type: :bigint),
          comment: "FK to oban.oban_jobs row scheduled to re-screen this AH"
    end

    alter table(:counterparties) do
      add :rescreen_job_id,
          references(:oban_jobs, prefix: "oban", type: :bigint),
          comment: "FK to oban.oban_jobs row scheduled to re-screen this CP"
    end

    alter table(:payment_accounts) do
      add :rescreen_job_id,
          references(:oban_jobs, prefix: "oban", type: :bigint),
          comment: "FK to oban.oban_jobs row scheduled to re-screen this PA"
    end

    alter table(:beneficial_owners) do
      add :rescreen_job_id,
          references(:oban_jobs, prefix: "oban", type: :bigint),
          comment: "FK to oban.oban_jobs row scheduled to re-screen this BO"
    end
  end
end

defprotocol AtomicFi.ControlProtocol do
  @moduledoc """
  Per-entity callback for the onboarding flow.

  `OnboardingContext.onboard/2` produces a `result` envelope from the
  `RuleEngine` (per-LA controls + a `next_screening_at` timestamp) and
  hands it to this protocol so the appropriate entity context can decide
  what to do with it.

  Implementations typically:

    1. Apply the per-LA controls (AH / CP / PA — via
       `LedgerAccountContext.apply_controls/2`). BO has no LedgerAccounts
       and the rule is expected to emit empty controls for a BO; if it
       wants caps to propagate it should target the BO's parent AH/CP
       LAs directly.
    2. Enqueue the next `OnboardingWorker` scheduled at
       `result.next_screening_at` (skipped when `nil`).
    3. Link the freshly-enqueued job id onto the entity's
       `rescreen_job_id` column — narrow update that MUST NOT loop back
       through the entity's public `update_*` path (that path triggers
       this onboarding flow).

  Returns the entity with `rescreen_job_id` reflecting the new job, or
  unchanged when no job was enqueued.
  """

  alias AtomicFi.SessionContext.Session

  @type result :: %{
          controls: %{optional(Ecto.UUID.t()) => AtomicFi.RuleEngine.Control.t()},
          next_screening_at: DateTime.t() | nil
        }

  @spec process_controls(t(), Session.t(), result()) :: {:ok, t()} | {:error, term()}
  def process_controls(entity, session, result)
end

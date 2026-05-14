defmodule AtomicFi.OnboardingContext do
  @moduledoc """
  Onboarding orchestration for AH / CP / PA / BO write paths.

  ## Flow

  Given a freshly-written entity (insert or update), in order:

    1. `ComplianceScreeningContext.screen_<type>` — sync sanctions / PEP
       screening. Records a `%ComplianceScreening{}` audit row. PA is a
       no-op screening-wise — payment accounts carry no PII of their own
       (the parent AccountHolder does).
    2. `AtomicFi.RuleEngine.get_controls(:onboarding, entity)` — sync HTTP
       call to ZenRule for per-LA controls + a `next_screening_at` hint.
    3. `LedgerAccountContext.apply_controls/2` — flushes the engine's
       Controls onto LedgerAccount rows (is_blocked, block_reason,
       max_*). For a BO this is a no-op when the rule emits no
       LA-keyed entries; if a rule author wants caps to propagate, the
       rule should target the BO's AH / CP LAs explicitly.

  Steps 4–5 (Oban enqueue + `rescreen_job_id` link) are wired in stage 2.

  ## Loop safety

  The flow updates LedgerAccount rows (and, in stage 2, the entity's
  `rescreen_job_id` column). Those writes MUST NOT loop back through
  the public `update_*` paths that trigger this onboarding flow —
  callers go directly via the schema changeset and `Repo.update/2`.

  ## Where it is called from

  Synchronously from each entity's write boundary:

    * `AccountHolderContext.create/update`
    * `CounterpartyContext` `after_cp_changed`
    * `PaymentAccountContext` `after_pa_changed`
    * `BeneficialOwnerContext.create/update`

  And from `AtomicFi.OnboardingRescreenWorker` (stage 2) on the
  scheduled re-screen.
  """

  use AtomicFi.LoggerMacro

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.BeneficialOwnerContext.BeneficialOwner
  alias AtomicFi.ComplianceScreeningContext
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.RuleEngine
  alias AtomicFi.SessionContext.Session

  @type entity ::
          AccountHolder.t() | Counterparty.t() | PaymentAccount.t() | BeneficialOwner.t()

  @doc """
  Runs the full onboarding flow for `entity`. Returns the entity on
  success so callers can chain it through their own `{:ok, entity}`
  pipelines.

  On any engine / screening failure, the entity itself is left as-is
  (already written by the caller) and its LedgerAccount rows stay in
  the block-by-default state set during creation — fail-closed.
  """
  @spec onboard(Session.t(), entity()) :: {:ok, entity()} | {:error, term()}
  def_with_rls_and_logging onboard(session, entity), log_fields: [] do
    with {:ok, _screenings} <- screen(session, entity),
         {:ok, _next_screening_at} <- engine_and_apply(session, entity) do
      {:ok, entity}
    end
  end

  defp screen(session, %AccountHolder{} = account_holder) do
    ComplianceScreeningContext.screen_account_holder(session, %{
      account_holder_id: account_holder.id
    })
  end

  defp screen(session, %Counterparty{} = counterparty) do
    ComplianceScreeningContext.screen_counterparty(session, %{
      account_holder_id: counterparty.account_holder_id,
      counterparty_id: counterparty.id
    })
  end

  defp screen(session, %BeneficialOwner{} = beneficial_owner) do
    ComplianceScreeningContext.screen_beneficial_owner(session, %{
      account_holder_id: beneficial_owner.account_holder_id,
      beneficial_owner_id: beneficial_owner.id
    })
  end

  defp screen(_session, %PaymentAccount{}), do: {:ok, []}

  defp engine_and_apply(session, entity) do
    case RuleEngine.get_controls(session, :onboarding, entity) do
      {:ok, :no_limits} ->
        {:ok, nil}

      {:ok, %{controls: controls, next_screening_at: next_screening_at}} ->
        with :ok <- LedgerAccountContext.apply_controls(session, controls) do
          {:ok, next_screening_at}
        end

      {:error, _} = err ->
        err
    end
  end
end

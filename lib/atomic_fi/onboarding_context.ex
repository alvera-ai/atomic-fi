defmodule AtomicFi.OnboardingContext do
  @moduledoc """
  Onboarding orchestration for AH / CP / PA / BO write paths.

  ## Flow

  Given a freshly-written entity (insert or update), in order:

    1. `ComplianceScreeningContext.screen_<type>` — sync sanctions / PEP
       screening. Records a `%ComplianceScreening{}` audit row. PA is a
       no-op screening-wise (payment accounts carry no PII; the parent
       AccountHolder does).
    2. `AtomicFi.RuleEngine.get_controls(:onboarding, entity)` — sync HTTP
       call to ZenRule for a `result` envelope: per-LA controls +
       `next_screening_at`.
    3. `AtomicFi.ControlProtocol.process_controls(entity, session, result)`
       — entity-specific dispatch. Each impl applies controls to its LAs
       (no-op for BO), enqueues the next `OnboardingWorker` scheduled at
       `next_screening_at`, and links the new job id onto the entity's
       `rescreen_job_id` column.

  ## Loop safety

  The flow updates LedgerAccount rows and the entity's `rescreen_job_id`
  column. Those writes MUST NOT loop back through the public `update_*`
  paths (which would re-trigger this flow) — defimpls go via narrow
  Repo.update changesets.

  Called synchronously from each entity's write boundary:

    * `AccountHolderContext.create_account_holder/2`
    * `CounterpartyContext` `after_cp_changed/2`
    * `PaymentAccountContext` `after_pa_changed/2`
    * `BeneficialOwnerContext.create_beneficial_owner/2`

  And from `AtomicFi.OnboardingWorker.perform/1` on the scheduled re-screen.
  """

  use AtomicFi.LoggerMacro

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.BeneficialOwnerContext.BeneficialOwner
  alias AtomicFi.ComplianceScreeningContext
  alias AtomicFi.ControlProtocol
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.OnboardingWorker
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.RuleEngine
  alias AtomicFi.ScreeningEngine
  alias AtomicFi.SessionContext.Session

  @type entity ::
          AccountHolder.t() | Counterparty.t() | PaymentAccount.t() | BeneficialOwner.t()

  @typedoc """
  Engine result envelope passed to `AtomicFi.ControlProtocol.process_controls/3`.

    * `:engine_entity` — the entity the rule engine was called against. For
      AH/CP/PA this is the entity itself; for BO this is the parent AH (or
      CP, once the legal_entity-based dispatch lands). Defimpls apply
      `result.controls` to *engine_entity*'s LedgerAccounts so a BO's
      onboarding caps land on its parent.
  """
  @type result :: %{
          controls: %{optional(Ecto.UUID.t()) => AtomicFi.RuleEngine.Control.t()},
          next_screening_at: DateTime.t() | nil,
          engine_entity: AccountHolder.t() | Counterparty.t() | PaymentAccount.t()
        }

  @doc """
  Runs the full onboarding flow for `entity`. Returns the entity (with
  any `rescreen_job_id` updates applied by the protocol dispatch) on
  success.
  """
  @spec onboard(Session.t(), entity()) :: {:ok, entity()} | {:error, term()}
  def_with_rls_and_logging onboard(session, entity), log_fields: [] do
    engine_entity = resolve_engine_entity(session, entity)

    with {:ok, _screenings} <- screen(session, entity),
         {:ok, result} <- engine_result(session, engine_entity),
         {:ok, entity} <-
           ControlProtocol.process_controls(
             entity,
             session,
             Map.put(result, :engine_entity, engine_entity)
           ) do
      {:ok, entity}
    end
  end

  # The entity the RuleEngine actually runs against. AH/CP/PA run against
  # themselves; a BO runs against its parent AH (TODO: CP variant once
  # legal-entity-based dispatch lands). The protocol impl then applies
  # the engine's per-LA controls to `engine_entity`'s LAs.
  defp resolve_engine_entity(_session, %AccountHolder{} = entity), do: entity
  defp resolve_engine_entity(_session, %Counterparty{} = entity), do: entity
  defp resolve_engine_entity(_session, %PaymentAccount{} = entity), do: entity

  defp resolve_engine_entity(session, %BeneficialOwner{} = bo) do
    AccountHolderContext.get_account_holder!(session, bo.account_holder_id)
  end

  @doc """
  Enqueues the next `OnboardingWorker` for `entity` at `scheduled_at`,
  returning the new Oban job id. Used by `ControlProtocol` impls.

  `scheduled_at == nil` is a no-op returning `{:ok, nil}`. The Oban args
  carry the entity's full struct module name so the worker can reload
  it without a hand-maintained type-tag map.
  """
  @spec enqueue_next(entity(), DateTime.t() | nil) ::
          {:ok, pos_integer() | nil} | {:error, term()}
  def enqueue_next(_entity, nil), do: {:ok, nil}

  def enqueue_next(entity, %DateTime{} = scheduled_at) do
    %{
      "entity_module" => entity.__struct__ |> Atom.to_string(),
      "entity_id" => entity.id,
      "tenant_id" => entity.tenant_id
    }
    |> OnboardingWorker.new(scheduled_at: scheduled_at)
    |> Oban.insert()
    |> case do
      {:ok, %Oban.Job{id: job_id}} -> {:ok, job_id}
      {:error, _} = err -> err
    end
  end

  defp screen(session, %AccountHolder{} = account_holder) do
    with {:ok, screening} <- ScreeningEngine.screen_account_holder(session, account_holder),
         {:ok, persisted} <-
           ComplianceScreeningContext.record_screening(session, screening, %{
             account_holder_id: account_holder.id
           }) do
      {:ok, [persisted]}
    end
  end

  defp screen(session, %Counterparty{} = counterparty) do
    with {:ok, screening} <- ScreeningEngine.screen_counterparty(session, counterparty),
         {:ok, persisted} <-
           ComplianceScreeningContext.record_screening(session, screening, %{
             account_holder_id: counterparty.account_holder_id,
             counterparty_id: counterparty.id
           }) do
      {:ok, [persisted]}
    end
  end

  defp screen(_session, %PaymentAccount{}), do: {:ok, []}

  defp screen(session, %BeneficialOwner{} = beneficial_owner) do
    with {:ok, screening} <-
           ScreeningEngine.screen_beneficial_owner(session, beneficial_owner),
         {:ok, persisted} <-
           ComplianceScreeningContext.record_screening(session, screening, %{
             account_holder_id: beneficial_owner.account_holder_id,
             beneficial_owner_id: beneficial_owner.id
           }) do
      {:ok, [persisted]}
    end
  end

  # Returns the engine result envelope. `:no_limits` from the engine is
  # normalised to an empty envelope so the protocol dispatch still
  # links / enqueues consistently.
  defp engine_result(session, entity) do
    case RuleEngine.get_controls(session, :onboarding, entity) do
      {:ok, :no_limits} -> {:ok, %{controls: %{}, next_screening_at: nil}}
      {:ok, %{controls: _, next_screening_at: _} = result} -> {:ok, result}
      {:error, _} = err -> err
    end
  end
end

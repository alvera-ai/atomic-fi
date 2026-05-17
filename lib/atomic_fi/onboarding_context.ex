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

  require Logger

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.BeneficialOwnerContext.BeneficialOwner
  alias AtomicFi.ComplianceScreeningContext
  alias AtomicFi.ControlProtocol
  alias AtomicFi.CounterpartyContext
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.OnboardingWorker
  alias AtomicFi.PaymentAccountContext
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.Repo
  alias AtomicFi.RoleContext.RoleConstants
  alias AtomicFi.RuleEngine
  alias AtomicFi.ScreeningEngine
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.TenantContext.Tenant

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
    require Logger
    Logger.info("[onboard] entry entity=#{inspect(entity.__struct__)} id=#{entity.id}")
    engine_entity = resolve_engine_entity(session, entity)
    Logger.info("[onboard] engine_entity resolved")

    with :ok <- log_step("screen.start"),
         {:ok, _screenings} <- screen(session, entity),
         :ok <- log_step("screen.done → engine_result.start"),
         {:ok, result} <- engine_result(session, engine_entity),
         :ok <-
           log_step(
             "engine_result.done controls=#{map_size(result.controls)} → process_controls.start"
           ),
         {:ok, entity} <-
           ControlProtocol.process_controls(
             entity,
             session,
             Map.put(result, :engine_entity, engine_entity)
           ),
         :ok <- log_step("process_controls.done") do
      {:ok, entity}
    end
  end

  defp log_step(msg) do
    require Logger
    Logger.info("[onboard] #{msg}")
    :ok
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
  Re-runs the onboarding flow for an existing entity. Clears the entity's
  current `rescreen_job_id` first (the running job IS that pointer; it must
  be dropped before any work that may re-link it). Then delegates to
  `onboard/2`.

  Callable from:

    * `AtomicFi.OnboardingWorker.perform/1` — on every scheduled re-screen.
    * `AccountHolderController` / `CounterpartyController` /
      `PaymentAccountController` `:refresh` actions — manual operator-driven
      re-screen via `POST .../:id/refresh`.

  Idempotent: re-running on a freshly-refreshed entity is a no-op for the
  rescreen_job_id clear step, then runs onboarding again (which may
  enqueue a new scheduled job).
  """
  @spec refresh(Session.t(), entity()) :: {:ok, entity()} | {:error, term()}
  def refresh(session, entity) do
    with {:ok, entity} <- clear_rescreen_job_id(session, entity),
         {:ok, entity} <- onboard(session, entity) do
      {:ok, entity}
    end
  end

  @doc """
  Worker-only: given the Oban job args map, resolve a session for the
  job's tenant and load the entity by `entity_module` + `entity_id`.
  Returns `{:ok, session, entity}`. Raises if any lookup fails — the
  Oban job is a closed-system message we constructed ourselves, so a
  miss here is a real invariant violation.
  """
  @spec load_for_rescreen(map()) :: {:ok, Session.t(), entity()}
  def load_for_rescreen(%{
        "entity_module" => entity_module,
        "entity_id" => entity_id,
        "tenant_id" => tenant_id
      }) do
    session = build_system_session(tenant_id)
    module = String.to_existing_atom(entity_module)
    entity = load_entity!(session, module, entity_id)
    {:ok, session, entity}
  end

  # Narrow per-entity loader so the worker can ask the relevant context
  # for a fully preloaded struct without reaching into Repo.
  defp load_entity!(session, AccountHolder, id),
    do: AccountHolderContext.get_account_holder!(session, id)

  defp load_entity!(session, Counterparty, id),
    do: CounterpartyContext.get_counterparty!(session, id)

  defp load_entity!(session, PaymentAccount, id),
    do: PaymentAccountContext.get_payment_account!(session, id)

  # Minimal session for the worker. The worker re-runs onboarding under
  # the tenant the original write was for — there's no human user. Uses
  # the "root" reserved role so RLS is bypassed (platform-admin path in
  # `AtomicFi.Repo.platform_admin?/1`); the worker is system-internal.
  defp build_system_session(tenant_id) do
    tenant = Repo.get!(Tenant, tenant_id, skip_multi_tenancy_check: true)

    %Session{
      tenant_id: tenant_id,
      tenant: tenant,
      role: %{name: RoleConstants.root_role()}
    }
  end

  # Narrow update — bypasses the public `update_*` paths (which would re-
  # trigger the full onboarding flow). Polymorphic on entity type.
  defp clear_rescreen_job_id(session, entity) do
    entity
    |> Ecto.Changeset.change(%{rescreen_job_id: nil})
    |> Repo.update(session: session)
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
    job_changeset =
      %{
        "entity_module" => entity.__struct__ |> Atom.to_string(),
        "entity_id" => entity.id,
        "tenant_id" => entity.tenant_id
      }
      |> OnboardingWorker.new(scheduled_at: scheduled_at)

    case Oban.insert(job_changeset) do
      {:ok, %Oban.Job{id: job_id}} ->
        {:ok, job_id}

      # coveralls-ignore-start — Oban.insert error path. Args/scheduled_at are
      # fully controlled by this function; reaching this branch means Oban or
      # the DB is in a state our public-API tests can't induce.
      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        Logger.error(
          msg: "onboarding_enqueue_failed",
          entity_module: entity.__struct__,
          entity_id: entity.id,
          tenant_id: entity.tenant_id,
          errors: inspect(errors)
        )

        raise "OnboardingContext.enqueue_next: Oban.insert rejected job for " <>
                "entity_module=#{inspect(entity.__struct__)} entity_id=#{entity.id} " <>
                "errors=#{inspect(changeset.errors)}"

        # coveralls-ignore-stop
    end
  end

  defp screen(session, %AccountHolder{legal_entity: %{id: le_id}} = account_holder) do
    with {:ok, screening} <- ScreeningEngine.screen_account_holder(session, account_holder),
         {:ok, persisted} <-
           ComplianceScreeningContext.record_screening(session, screening, %{
             legal_entity_id: le_id
           }) do
      {:ok, [persisted]}
    end
  end

  defp screen(session, %Counterparty{legal_entity: %{id: le_id}} = counterparty) do
    with {:ok, screening} <- ScreeningEngine.screen_counterparty(session, counterparty),
         {:ok, persisted} <-
           ComplianceScreeningContext.record_screening(session, screening, %{
             legal_entity_id: le_id
           }) do
      {:ok, [persisted]}
    end
  end

  defp screen(_session, %PaymentAccount{}), do: {:ok, []}

  defp screen(session, %BeneficialOwner{legal_entity: %{id: le_id}} = beneficial_owner) do
    with {:ok, screening} <-
           ScreeningEngine.screen_beneficial_owner(session, beneficial_owner),
         {:ok, persisted} <-
           ComplianceScreeningContext.record_screening(session, screening, %{
             legal_entity_id: le_id
           }) do
      {:ok, [persisted]}
    end
  end

  # Returns the engine result envelope. `:no_limits` from the engine is
  # normalised to an empty envelope so the protocol dispatch still
  # links / enqueues consistently.
  defp engine_result(session, entity) do
    require Logger
    Logger.info("[engine_result] calling RuleEngine.get_controls/3")
    t0 = System.monotonic_time(:millisecond)

    case RuleEngine.get_controls(session, :onboarding, entity) do
      {:ok, :no_limits} ->
        Logger.info("[engine_result] :no_limits in #{System.monotonic_time(:millisecond) - t0}ms")
        {:ok, %{controls: %{}, next_screening_at: nil}}

      {:ok, %{controls: _, next_screening_at: _} = result} ->
        Logger.info("[engine_result] :ok in #{System.monotonic_time(:millisecond) - t0}ms")
        {:ok, result}

      {:error, _} = err ->
        Logger.error("[engine_result] error: #{inspect(err)}")
        err
    end
  end
end

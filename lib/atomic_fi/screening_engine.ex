defmodule AtomicFi.ScreeningEngine do
  @moduledoc """
  Screening engine — public face (dispatcher).

  Callers (`AtomicFi.ComplianceScreeningContext`,
  `AtomicFi.OnboardingContext`) invoke this module directly:

      ScreeningEngine.screen_account_holder(session, account_holder, [])

  Returns an unsaved `%ComplianceScreening{}` struct with nested
  `%SanctionsMatch{}` + `%BlocklistMatch{}` rows.

  **Engine reports facts; RuleEngine decides outcome.** Per-result
  `screening_status` is always `:pending` — the engine never folds match
  scores into a verdict. Downstream callers (onboarding → ZenRule)
  decide what to block.

  Persistence is the caller's job — preview controllers return the
  struct as-is, the onboarding flow sets entity FKs and inserts via
  `ComplianceScreeningContext.record_screening/3`.

  ## Mock seam

  `DataCase / ConnCase` setup hook calls
  `Mox.stub_with(ScreeningEngineMock, ScreeningEngine.Default)` so the
  mock falls through to the real impl by default; per-test
  `Mox.expect(ScreeningEngineMock, :screen_account_holder, fn _, _, _ -> … end)`
  overrides without setting up Watchman state.
  """

  @behaviour AtomicFi.ScreeningEngine.Behaviour

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.BeneficialOwnerContext.BeneficialOwner
  alias AtomicFi.ComplianceScreeningContext.ComplianceScreening
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.ScreeningEngine.Default
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.TransactionContext.Transaction

  @screening_engine Application.compile_env(:atomic_fi, :screening_engine, Default)

  @type entity_type :: :individual | :company | :crypto_address | :payment_account
  @type list_info :: %{started_at: DateTime.t(), lists: term(), version: term()}

  @impl true
  @spec get_watchman_list_info() :: {:ok, list_info()} | {:error, term()}
  def get_watchman_list_info, do: @screening_engine.get_watchman_list_info()

  @impl true
  @spec screen_account_holder(Session.t(), AccountHolder.t(), keyword()) ::
          {:ok, ComplianceScreening.t()} | {:error, term()}
  def screen_account_holder(session, %AccountHolder{} = ah, opts \\ []),
    do: @screening_engine.screen_account_holder(session, ah, opts)

  @impl true
  @spec screen_beneficial_owner(Session.t(), BeneficialOwner.t(), keyword()) ::
          {:ok, ComplianceScreening.t()} | {:error, term()}
  def screen_beneficial_owner(session, %BeneficialOwner{} = bo, opts \\ []),
    do: @screening_engine.screen_beneficial_owner(session, bo, opts)

  @impl true
  @spec screen_counterparty(Session.t(), Counterparty.t(), keyword()) ::
          {:ok, ComplianceScreening.t()} | {:error, term()}
  def screen_counterparty(session, %Counterparty{} = cp, opts \\ []),
    do: @screening_engine.screen_counterparty(session, cp, opts)

  @impl true
  @spec screen_payment_account(Session.t(), PaymentAccount.t(), keyword()) ::
          {:ok, ComplianceScreening.t()} | {:error, term()}
  def screen_payment_account(session, %PaymentAccount{} = pa, opts \\ []),
    do: @screening_engine.screen_payment_account(session, pa, opts)

  @impl true
  @spec screen_transaction(Session.t(), Transaction.t(), keyword()) ::
          {:ok, [ComplianceScreening.t()]} | {:error, term()}
  def screen_transaction(session, %Transaction{} = txn, opts \\ []),
    do: @screening_engine.screen_transaction(session, txn, opts)
end

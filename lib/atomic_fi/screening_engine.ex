defmodule AtomicFi.ScreeningEngine do
  @moduledoc """
  Screening engine — public face (dispatcher).

  Callers (`AtomicFi.ComplianceScreeningContext`) invoke this module
  directly:

      ScreeningEngine.screen_account_holder(session, account_holder, [])

  The configured impl module (defaults to
  `AtomicFi.ScreeningEngine.Default`; tests swap in
  `AtomicFi.ScreeningEngineMock`) is resolved at compile time via
  `:screening_engine` config. The swap is **invisible to callers** —
  this dispatcher delegates every Behaviour call through.

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
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.ScreeningEngine.Default
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.TransactionContext.Transaction

  @screening_engine Application.compile_env(:atomic_fi, :screening_engine, Default)

  # ── public types (re-exported from Default for Behaviour + callers) ─────

  @type sanctions_match_result :: %{
          matched_name: String.t(),
          matched_entity_type: String.t() | nil,
          match_score: float(),
          sanctions_match_type: :exact | :fuzzy | :ubo | :entity,
          source_list: String.t(),
          source_id: String.t() | nil,
          addresses: [map()],
          business_data: map() | nil,
          person_data: map() | nil,
          contact_data: map() | nil,
          source_data: map() | nil,
          suppressed: boolean()
        }

  @type blocklist_match_result :: %{
          matched_term: String.t(),
          match_type: :exact | :regex,
          scope: :first_name | :last_name | :company_name,
          reason: String.t(),
          blocklist_updated_at: DateTime.t() | nil
        }

  @type screening_result :: %{
          entity_type: :individual | :company,
          entity_name: String.t(),
          screening_status: :pass | :potential_match | :blocked,
          match_count: non_neg_integer(),
          screening_score: float() | nil,
          screened_at: DateTime.t(),
          sanctions_matches: [sanctions_match_result()],
          blocklist_matches: [blocklist_match_result()]
        }

  @type list_info :: %{started_at: DateTime.t(), lists: term(), version: term()}

  # ── behaviour delegations ───────────────────────────────────────────────

  @impl true
  @spec get_watchman_list_info() :: {:ok, list_info()} | {:error, term()}
  def get_watchman_list_info, do: @screening_engine.get_watchman_list_info()

  @impl true
  @spec screen_account_holder(Session.t(), AccountHolder.t(), keyword()) ::
          {:ok, screening_result()} | {:error, term()}
  def screen_account_holder(session, %AccountHolder{} = ah, opts \\ []),
    do: @screening_engine.screen_account_holder(session, ah, opts)

  @impl true
  @spec screen_beneficial_owner(Session.t(), BeneficialOwner.t(), keyword()) ::
          {:ok, screening_result()} | {:error, term()}
  def screen_beneficial_owner(session, %BeneficialOwner{} = bo, opts \\ []),
    do: @screening_engine.screen_beneficial_owner(session, bo, opts)

  @impl true
  @spec screen_counterparty(Session.t(), Counterparty.t(), keyword()) ::
          {:ok, screening_result()} | {:error, term()}
  def screen_counterparty(session, %Counterparty{} = cp, opts \\ []),
    do: @screening_engine.screen_counterparty(session, cp, opts)

  @impl true
  @spec screen_payment_account(Session.t(), PaymentAccount.t(), keyword()) ::
          {:ok, screening_result()} | {:error, term()}
  def screen_payment_account(session, %PaymentAccount{} = pa, opts \\ []),
    do: @screening_engine.screen_payment_account(session, pa, opts)

  @impl true
  @spec screen_transaction(Session.t(), Transaction.t(), keyword()) ::
          {:ok, [screening_result()]} | {:error, term()}
  def screen_transaction(session, %Transaction{} = txn, opts \\ []),
    do: @screening_engine.screen_transaction(session, txn, opts)

  # ── public non-behaviour helper ─────────────────────────────────────────

  @doc """
  Determine the overall screening status from a list of screening results.

  Precedence: `blocked` > `potential_match` > `pass`. Pure function —
  used by callers directly, not part of the Behaviour.
  """
  @spec determine_overall_status([screening_result()]) ::
          :pass | :potential_match | :blocked
  defdelegate determine_overall_status(results), to: Default
end

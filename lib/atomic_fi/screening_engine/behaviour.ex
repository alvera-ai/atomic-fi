defmodule AtomicFi.ScreeningEngine.Behaviour do
  @moduledoc """
  Domain-level contract for the compliance screening engine.

  Implementations orchestrate blocklist check + Watchman sanctions search and
  return an unsaved `%ComplianceScreening{}` struct carrying the result (with
  nested `%SanctionsMatch{}` + `%BlocklistMatch{}` rows). Implementations are
  pure with respect to persistence — callers (preview controllers,
  `AtomicFi.OnboardingContext`) decide whether to insert.

  ## Inputs

  All entity inputs are assumed to be **fully preloaded** — the engine does
  not re-fetch from the database. Required preloads per entity:

  | Entity              | Required preloads                                  |
  |---------------------|----------------------------------------------------|
  | `AccountHolder`     | `:legal_entity` (with `:addresses`, `:phone_numbers`, `:identifications`) |
  | `BeneficialOwner`   | `:legal_entity` (same nested as above)             |
  | `Counterparty`      | `:legal_entity` (same nested as above)             |
  | `PaymentAccount`    | `:account_holder` → `:legal_entity` (same nested)  |
  | `Transaction`       | debtor + creditor parties resolved (account_holder + legal_entity for each side) |

  ## Mock seam

  Mocked in tests via `AtomicFi.ScreeningEngineMock` (Mox). The DataCase /
  ConnCase setup hook calls `Mox.stub_with(ScreeningEngineMock, ScreeningEngine)`
  so existing tests fall through to the real engine; per-test
  `Mox.expect/3` overrides the screening result without setting up
  Watchman state.
  """

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.BeneficialOwnerContext.BeneficialOwner
  alias AtomicFi.ComplianceScreeningContext.ComplianceScreening
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.ScreeningEngine
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.TransactionContext.Transaction

  @type opts :: keyword()

  @callback screen_account_holder(Session.t(), AccountHolder.t(), opts()) ::
              {:ok, ComplianceScreening.t()} | {:error, term()}

  @callback screen_beneficial_owner(Session.t(), BeneficialOwner.t(), opts()) ::
              {:ok, ComplianceScreening.t()} | {:error, term()}

  @callback screen_counterparty(Session.t(), Counterparty.t(), opts()) ::
              {:ok, ComplianceScreening.t()} | {:error, term()}

  @callback screen_payment_account(Session.t(), PaymentAccount.t(), opts()) ::
              {:ok, ComplianceScreening.t()} | {:error, term()}

  @callback screen_transaction(Session.t(), Transaction.t(), opts()) ::
              {:ok, [ComplianceScreening.t()]} | {:error, term()}

  @callback get_watchman_list_info() ::
              {:ok, ScreeningEngine.list_info()} | {:error, term()}
end

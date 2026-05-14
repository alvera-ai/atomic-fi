# Thin protocol wrappers — each impl delegates to its owning context's
# `process_controls/3` function. The real work (apply_controls, enqueue,
# narrow update of rescreen_job_id) lives in the entity context.

defimpl AtomicFi.ControlProtocol, for: AtomicFi.AccountHolderContext.AccountHolder do
  defdelegate process_controls(entity, session, result),
    to: AtomicFi.AccountHolderContext
end

defimpl AtomicFi.ControlProtocol, for: AtomicFi.CounterpartyContext.Counterparty do
  defdelegate process_controls(entity, session, result),
    to: AtomicFi.CounterpartyContext
end

defimpl AtomicFi.ControlProtocol, for: AtomicFi.PaymentAccountContext.PaymentAccount do
  defdelegate process_controls(entity, session, result),
    to: AtomicFi.PaymentAccountContext
end

# BO is screen-only at its own level — its impl applies `result.controls`
# to the engine_entity's (parent AH/CP's) LedgerAccounts, then enqueues +
# links the BO's own re-screen `OnboardingWorker`.
defimpl AtomicFi.ControlProtocol, for: AtomicFi.BeneficialOwnerContext.BeneficialOwner do
  defdelegate process_controls(entity, session, result),
    to: AtomicFi.BeneficialOwnerContext
end

defmodule AtomicFi.Factory do
  @moduledoc """
  Main factory module that aggregates all context-specific factories.

  Each context has its own factory module in test/support/factory/
  """
  use ExMachina.Ecto, repo: AtomicFi.Repo

  use AtomicFi.Factory.TenantFactory
  use AtomicFi.Factory.UserFactory
  use AtomicFi.Factory.RoleFactory
  use AtomicFi.Factory.ApiKeyFactory
  use AtomicFi.Factory.UserRoleMappingFactory
  use AtomicFi.Factory.SessionFactory
  use AtomicFi.Factory.CustomerFactory
  use AtomicFi.Factory.AccountHolderFactory
  use AtomicFi.Factory.BlocklistEntryFactory

  @doc """
  Helper to insert a tenant and initialize its blocklist cache.

  Use this instead of `insert(:tenant)` when the test will perform screening
  operations that require an initialized cache.

  ## Examples

      tenant = insert_tenant_with_cache()
      session = %Session{tenant_id: tenant.id, ...}
      ComplianceScreeningContext.screen_account_holder(session, request)
  """
  def insert_tenant_with_cache(attrs \\ %{}) do
    tenant = insert(:tenant, attrs)
    AtomicFi.DecisionContext.BlocklistCache.refresh_tenant_cache(tenant.id)
    tenant
  end

  use AtomicFi.Factory.LegalEntityFactory
  use AtomicFi.Factory.BeneficialOwnerFactory
  use AtomicFi.Factory.CounterpartyFactory
  use AtomicFi.Factory.LedgerFactory
  use AtomicFi.Factory.LedgerAccountFactory
  use AtomicFi.Factory.LedgerEntryFactory
  use AtomicFi.Factory.KycRequirementFactory
  use AtomicFi.Factory.DocumentFactory
  use AtomicFi.Factory.PaymentAccountFactory
  use AtomicFi.Factory.TransactionFactory
  use AtomicFi.Factory.AccountActivitySnapshotFactory
  use AtomicFi.Factory.LegalEntityChangeEventFactory
  use AtomicFi.Factory.PartyActivitySnapshotFactory
  use AtomicFi.Factory.RiskClassificationFactory
end

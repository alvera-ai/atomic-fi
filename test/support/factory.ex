defmodule PaymentCompliancePlatform.Factory do
  @moduledoc """
  Main factory module that aggregates all context-specific factories.

  Each context has its own factory module in test/support/factory/
  """
  use ExMachina.Ecto, repo: PaymentCompliancePlatform.Repo

  use PaymentCompliancePlatform.Factory.TenantFactory
  use PaymentCompliancePlatform.Factory.UserFactory
  use PaymentCompliancePlatform.Factory.RoleFactory
  use PaymentCompliancePlatform.Factory.ApiKeyFactory
  use PaymentCompliancePlatform.Factory.UserRoleMappingFactory
  use PaymentCompliancePlatform.Factory.SessionFactory
  use PaymentCompliancePlatform.Factory.CustomerFactory
  use PaymentCompliancePlatform.Factory.AccountHolderFactory
  use PaymentCompliancePlatform.Factory.BlocklistEntryFactory

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
    PaymentCompliancePlatform.DecisionContext.BlocklistCache.refresh_tenant_cache(tenant.id)
    tenant
  end

  use PaymentCompliancePlatform.Factory.LegalEntityFactory
  use PaymentCompliancePlatform.Factory.BeneficialOwnerFactory
  use PaymentCompliancePlatform.Factory.CounterpartyFactory
  use PaymentCompliancePlatform.Factory.LedgerFactory
  use PaymentCompliancePlatform.Factory.LedgerAccountFactory
  use PaymentCompliancePlatform.Factory.LedgerEntryFactory
  use PaymentCompliancePlatform.Factory.KycRequirementFactory
  use PaymentCompliancePlatform.Factory.DocumentFactory
  use PaymentCompliancePlatform.Factory.PaymentAccountFactory
  use PaymentCompliancePlatform.Factory.TransactionFactory
  use PaymentCompliancePlatform.Factory.AccountActivitySnapshotFactory
  use PaymentCompliancePlatform.Factory.LegalEntityChangeEventFactory
end

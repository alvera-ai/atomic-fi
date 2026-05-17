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
  use AtomicFi.Factory.AccountHolderFactory
  use AtomicFi.Factory.BlocklistEntryFactory
  use AtomicFi.Factory.ComplianceScreeningFactory

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
    AtomicFi.BlocklistContext.BlocklistCache.refresh_tenant_cache(tenant.id)
    tenant
  end

  @doc """
  Hydrates an inserted AccountHolder with its identity LegalEntity tree
  (LE + LE's identifications, addresses, phone_numbers).

  `Repo.preload(..., force: true)` re-queries every assoc — needed when
  the test inserted an LE row AFTER the factory built the AH struct, since
  the factory pre-sets `legal_entity: nil` and stale-nil fields aren't
  re-hydrated by a default preload call.

  Pattern-matches on `%AccountHolder{}` so the wrong arg blows up loudly
  at the callsite.

  ## Examples

      ah = insert(:account_holder, tenant_id: tenant.id)
      insert(:legal_entity, account_holder_id: ah.id, tenant_id: tenant.id)
      ah = with_hydrated_account_holder(ah)
      ah.legal_entity.id  # the AH-owned identity LE
  """
  @spec with_hydrated_account_holder(AtomicFi.AccountHolderContext.AccountHolder.t()) ::
          AtomicFi.AccountHolderContext.AccountHolder.t()
  def with_hydrated_account_holder(%AtomicFi.AccountHolderContext.AccountHolder{} = ah) do
    AtomicFi.Repo.preload(
      ah,
      [legal_entity: [:addresses, :phone_numbers, :identifications]],
      force: true,
      skip_multi_tenancy_check: true
    )
  end

  @doc """
  Hydrates an inserted Counterparty with its identity LegalEntity tree.

  See `with_hydrated_account_holder/1` for the rationale around `force: true`
  and the explicit pattern match.
  """
  @spec with_hydrated_counterparty(AtomicFi.CounterpartyContext.Counterparty.t()) ::
          AtomicFi.CounterpartyContext.Counterparty.t()
  def with_hydrated_counterparty(%AtomicFi.CounterpartyContext.Counterparty{} = cp) do
    AtomicFi.Repo.preload(
      cp,
      [legal_entity: [:addresses, :phone_numbers, :identifications]],
      force: true,
      skip_multi_tenancy_check: true
    )
  end

  @doc """
  Hydrates an inserted BeneficialOwner with its identity LegalEntity tree.

  See `with_hydrated_account_holder/1` for the rationale around `force: true`
  and the explicit pattern match.
  """
  @spec with_hydrated_beneficial_owner(AtomicFi.BeneficialOwnerContext.BeneficialOwner.t()) ::
          AtomicFi.BeneficialOwnerContext.BeneficialOwner.t()
  def with_hydrated_beneficial_owner(%AtomicFi.BeneficialOwnerContext.BeneficialOwner{} = bo) do
    AtomicFi.Repo.preload(
      bo,
      [legal_entity: [:addresses, :phone_numbers, :identifications]],
      force: true,
      skip_multi_tenancy_check: true
    )
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

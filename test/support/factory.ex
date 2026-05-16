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
  Inserts an AccountHolder + its identity LegalEntity in two steps.

  Returns the AccountHolder with `legal_entity` preloaded. Use this where
  tests previously relied on `insert(:account_holder)` auto-attaching an LE
  via the (now-removed) `legal_entity_id` column on AccountHolder.

  ## Examples

      ah = insert_account_holder_with_legal_entity(tenant_id: tenant.id)
      ah.legal_entity.id  # the AH-owned identity LE
  """
  def insert_account_holder_with_legal_entity(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    tenant_id =
      Map.get_lazy(attrs, :tenant_id, fn ->
        insert(:tenant).id
      end)

    {le_attrs, ah_attrs} = Map.pop(attrs, :legal_entity, %{})

    ah_attrs = Map.put(ah_attrs, :tenant_id, tenant_id)
    ah = insert(:account_holder, ah_attrs)

    le_attrs =
      le_attrs
      |> Enum.into(%{})
      |> Map.put(:tenant_id, tenant_id)
      |> Map.put(:account_holder_id, ah.id)
      |> Map.put_new(:subject_type, :account_holder)

    le = insert(:legal_entity, le_attrs)

    %{ah | legal_entity: le}
  end

  @doc """
  Inserts a Counterparty + its identity LegalEntity (subject_type=:counterparty).

  Returns the CP with `legal_entity` preloaded. The LE's `account_holder_id`
  rolls up to the CP's parent AH for AH-uniform compliance attribution.
  """
  def insert_counterparty_with_legal_entity(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    tenant_id =
      Map.get_lazy(attrs, :tenant_id, fn ->
        insert(:tenant).id
      end)

    {le_attrs, cp_attrs} = Map.pop(attrs, :legal_entity, %{})
    cp_attrs = Map.put(cp_attrs, :tenant_id, tenant_id)
    cp = insert(:counterparty, cp_attrs)

    le_attrs =
      le_attrs
      |> Enum.into(%{})
      |> Map.put(:tenant_id, tenant_id)
      |> Map.put(:subject_type, :counterparty)
      |> Map.put(:account_holder_id, cp.account_holder_id)
      |> Map.put(:counterparty_id, cp.id)

    le = insert(:legal_entity, le_attrs)

    %{cp | legal_entity: le}
  end

  @doc """
  Inserts a BeneficialOwner + its identity LegalEntity (subject_type=:beneficial_owner).

  Returns the BO with `legal_entity` preloaded. The LE's `account_holder_id`
  rolls up to the BO's parent AH.
  """
  def insert_beneficial_owner_with_legal_entity(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})

    tenant_id =
      Map.get_lazy(attrs, :tenant_id, fn ->
        insert(:tenant).id
      end)

    {le_attrs, bo_attrs} = Map.pop(attrs, :legal_entity, %{})
    bo_attrs = Map.put(bo_attrs, :tenant_id, tenant_id)
    bo = insert(:beneficial_owner, bo_attrs)

    le_attrs =
      le_attrs
      |> Enum.into(%{})
      |> Map.put(:tenant_id, tenant_id)
      |> Map.put(:subject_type, :beneficial_owner)
      |> Map.put(:account_holder_id, bo.account_holder_id)
      |> Map.put(:beneficial_owner_id, bo.id)

    le = insert(:legal_entity, le_attrs)

    %{bo | legal_entity: le}
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

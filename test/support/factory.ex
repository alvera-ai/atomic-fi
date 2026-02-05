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
  use PaymentCompliancePlatform.Factory.DecisionFactory
  use PaymentCompliancePlatform.Factory.BlocklistEntryFactory
end

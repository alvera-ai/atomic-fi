defmodule AlveraPhoenixTemplateServer.Factory do
  @moduledoc """
  Main factory module that aggregates all context-specific factories.

  Each context has its own factory module in test/support/factory/
  """
  use ExMachina.Ecto, repo: AlveraPhoenixTemplateServer.Repo

  use AlveraPhoenixTemplateServer.Factory.TenantFactory
  use AlveraPhoenixTemplateServer.Factory.UserFactory
  use AlveraPhoenixTemplateServer.Factory.RoleFactory
  use AlveraPhoenixTemplateServer.Factory.ApiKeyFactory
  use AlveraPhoenixTemplateServer.Factory.UserRoleMappingFactory
  use AlveraPhoenixTemplateServer.Factory.SessionFactory
  use AlveraPhoenixTemplateServer.Factory.CustomerFactory
end

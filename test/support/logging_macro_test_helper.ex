defmodule PaymentCompliancePlatform.LoggingMacroTestHelper do
  @moduledoc """
  Test helper module to verify def_with_rls_and_logging macro works correctly.
  """

  require Logger
  import PaymentCompliancePlatform.LoggerMacro, only: [def_with_rls_and_logging: 3]

  alias PaymentCompliancePlatform.RoleContext.Role
  alias PaymentCompliancePlatform.SessionContext.Session

  @doc """
  Simple success case - returns {:ok, :success}
  """
  @spec test_success(Session.t()) :: {:ok, :success}
  def_with_rls_and_logging test_success(_session), log_fields: [] do
    {:ok, :success}
  end

  @doc """
  Simple failure case - returns {:error, :failure}
  """
  @spec test_failure(Session.t()) :: {:error, :failure}
  def_with_rls_and_logging test_failure(_session), log_fields: [] do
    {:error, :failure}
  end

  @doc """
  Test with logged parameters
  """
  @spec test_with_params(Session.t(), String.t(), String.t()) :: {:ok, {String.t(), String.t()}}
  def_with_rls_and_logging test_with_params(_session, param1, param2),
    log_fields: [:param1, :param2] do
    {:ok, {param1, param2}}
  end

  @doc """
  Test with default parameters
  """
  @spec test_with_defaults(Session.t(), String.t()) :: {:ok, String.t()}
  def_with_rls_and_logging test_with_defaults(_session, value \\ "default"),
    log_fields: [:value] do
    {:ok, value}
  end

  @doc """
  Test returning non-tuple (should log as :success)
  """
  @spec test_non_tuple(Session.t()) :: String.t()
  def_with_rls_and_logging test_non_tuple(_session), log_fields: [] do
    "plain value"
  end

  @doc """
  Test returning custom status tuple
  """
  @spec test_custom_status(Session.t()) :: {:pending, String.t()}
  def_with_rls_and_logging test_custom_status(_session), log_fields: [] do
    {:pending, "custom status"}
  end

  @doc """
  Test exception handling - raises ArithmeticError when divisor is 0
  """
  @spec test_exception(Session.t(), number()) :: {:ok, number()}
  def_with_rls_and_logging test_exception(_session, divisor), log_fields: [:divisor] do
    result = div(1, divisor)
    {:ok, result}
  end

  @doc """
  Test with Ecto schema parameter - verifies ID extraction in log_fields
  """
  @spec test_with_schema_param(Session.t(), Role.t()) :: {:ok, String.t()}
  def_with_rls_and_logging test_with_schema_param(_session, role), log_fields: [:role] do
    {:ok, "processed role"}
  end

  @doc """
  Test returning Ecto schema - verifies target_object_id logging
  """
  @spec test_returning_schema(Session.t(), String.t()) :: {:ok, Role.t()}
  def_with_rls_and_logging test_returning_schema(_session, role_id), log_fields: [:role_id] do
    # Create a minimal Role struct with just an ID for testing
    role = %Role{id: role_id, name: "Test Role"}
    {:ok, role}
  end

  @doc """
  Test returning Ecto schema with error tuple - verifies target_object_id not logged for errors
  """
  @spec test_returning_error_schema(Session.t()) :: {:error, Role.t()}
  def_with_rls_and_logging test_returning_error_schema(_session), log_fields: [] do
    # Create a minimal Role struct
    role = %Role{id: Ecto.UUID.generate(), name: "Error Role"}
    {:error, role}
  end

  @doc """
  Test with both schema param and schema return - verifies both ID extractions
  """
  @spec test_schema_param_and_return(Session.t(), Role.t()) :: {:ok, Role.t()}
  def_with_rls_and_logging test_schema_param_and_return(_session, input_role),
    log_fields: [:input_role] do
    # Return a different role to distinguish input vs output in logs
    output_role = %Role{id: Ecto.UUID.generate(), name: "Output Role"}
    {:ok, output_role}
  end

  @doc """
  Test with map parameter - verifies map logging (mimics list_* functions with flop_params)
  """
  @spec test_with_map_param(Session.t(), map()) :: {:ok, String.t()}
  def_with_rls_and_logging test_with_map_param(_session, params \\ %{}), log_fields: [:params] do
    # Use params to avoid unused variable warning
    _params = params
    {:ok, "processed with params"}
  end
end

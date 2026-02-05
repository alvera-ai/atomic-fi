defmodule AlveraPhoenixTemplateServer.LoggingMacroTest do
  use AlveraPhoenixTemplateServer.DataCase, async: false
  import ExUnit.CaptureLog

  alias AlveraPhoenixTemplateServer.LoggingMacroTestHelper

  describe "def_with_rls_and_logging macro - function behavior" do
    test "success branch returns correct value", %{session: session} do
      assert {:ok, :success} = LoggingMacroTestHelper.test_success(session)
    end

    test "failure branch returns correct value", %{session: session} do
      assert {:error, :failure} = LoggingMacroTestHelper.test_failure(session)
    end

    test "function with parameters works correctly", %{session: session} do
      assert {:ok, {"foo", "bar"}} =
               LoggingMacroTestHelper.test_with_params(session, "foo", "bar")
    end

    test "function with default parameters works", %{session: session} do
      assert {:ok, "default"} = LoggingMacroTestHelper.test_with_defaults(session)
      assert {:ok, "custom"} = LoggingMacroTestHelper.test_with_defaults(session, "custom")
    end

    test "non-tuple return value works", %{session: session} do
      assert "plain value" = LoggingMacroTestHelper.test_non_tuple(session)
    end

    test "custom status tuple works", %{session: session} do
      assert {:pending, "custom status"} = LoggingMacroTestHelper.test_custom_status(session)
    end

    test "exception is properly raised and logged", %{session: session} do
      log =
        capture_log(fn ->
          assert_raise ArithmeticError, fn ->
            LoggingMacroTestHelper.test_exception(session, 0)
          end
        end)

      # Only check error-level log (start log is info-level, not captured in tests)
      assert log =~ "test_exception_exception"
      assert log =~ "bad argument in arithmetic expression"
    end
  end

  describe "def_with_rls_and_logging macro - audit logging features" do
    alias AlveraPhoenixTemplateServer.RoleContext.Role

    test "extracts ID from Ecto schema parameter in log_fields", %{session: session} do
      # Temporarily set log level to :info to capture info-level logs
      original_level = Logger.level()
      Logger.configure(level: :info)

      role_id = Ecto.UUID.generate()
      role = %Role{id: role_id, name: "Test Role"}

      log =
        capture_log(fn ->
          assert {:ok, "processed role"} =
                   LoggingMacroTestHelper.test_with_schema_param(session, role)
        end)

      # Reset log level back to original
      Logger.configure(level: original_level)

      # Verify the role ID is logged, not the whole struct
      assert log =~ "test_with_schema_param_start"
      assert log =~ "role: \"#{role_id}\""
    end

    test "logs target_object_id when returning Ecto schema in {:ok, schema} tuple", %{
      session: session
    } do
      # Temporarily set log level to :info to capture info-level logs
      original_level = Logger.level()
      Logger.configure(level: :info)

      role_id = Ecto.UUID.generate()

      log =
        capture_log(fn ->
          assert {:ok, %Role{id: ^role_id}} =
                   LoggingMacroTestHelper.test_returning_schema(session, role_id)
        end)

      # Reset log level back to original
      Logger.configure(level: original_level)

      # Verify target_object_id is logged with the returned role's ID
      assert log =~ "test_returning_schema_end"
      assert log =~ "target_object_id: \"#{role_id}\""
      assert log =~ "status: :success"
    end

    test "logs target_object_id for error tuples with Ecto schemas", %{session: session} do
      # Temporarily set log level to :info to capture info-level logs
      original_level = Logger.level()
      Logger.configure(level: :info)

      log =
        capture_log(fn ->
          {:error, %Role{}} = LoggingMacroTestHelper.test_returning_error_schema(session)
        end)

      # Reset log level back to original
      Logger.configure(level: original_level)

      assert log =~ "test_returning_error_schema_end"
      assert log =~ "status: :failure"
      assert log =~ "target_object_id:"
    end

    test "extracts IDs from both input params and output schemas", %{session: session} do
      # Temporarily set log level to :info to capture info-level logs
      original_level = Logger.level()
      Logger.configure(level: :info)

      input_role_id = Ecto.UUID.generate()
      input_role = %Role{id: input_role_id, name: "Input Role"}

      log =
        capture_log(fn ->
          {:ok, %Role{}} =
            LoggingMacroTestHelper.test_schema_param_and_return(session, input_role)
        end)

      # Reset log level back to original
      Logger.configure(level: original_level)

      # Verify both start and end logs are present
      assert log =~ "test_schema_param_and_return_start"
      assert log =~ "test_schema_param_and_return_end"
      # Verify both IDs are logged
      assert log =~ "input_role: \"#{input_role_id}\""
      assert log =~ "target_object_id:"
    end

    test "logs map parameters correctly (mimics list_* functions)", %{session: session} do
      # Temporarily set log level to :info to capture info-level logs
      original_level = Logger.level()
      Logger.configure(level: :info)

      params = %{page: 1, page_size: 20, filters: [%{field: :name, op: :ilike, value: "test"}]}

      log =
        capture_log(fn ->
          assert {:ok, "processed with params"} =
                   LoggingMacroTestHelper.test_with_map_param(session, params)
        end)

      # Reset log level back to original
      Logger.configure(level: original_level)

      # Verify the map is logged in the start log
      assert log =~ "test_with_map_param_start"
      assert log =~ "params:"
      # Verify the map content is logged (checking for some key fields)
      assert log =~ "page: 1"
      assert log =~ "page_size: 20"
    end
  end
end

defmodule AtomicFi.RulesContextTest do
  # async: false — tests share the on-disk priv/zenrule directory, so they
  # must run serially even with unique filenames (avoids any race on
  # File.ls during list_rules tests).
  use AtomicFi.DataCase, async: false

  alias AtomicFi.RulesContext
  alias AtomicFi.RulesTestHelper

  describe "project_name/1" do
    test "maps :onboarding to kebab folder slug" do
      assert RulesContext.project_name(:onboarding) == "onboarding"
    end

    test "maps :transaction_screening to kebab folder slug" do
      assert RulesContext.project_name(:transaction_screening) == "transaction-screening"
    end
  end

  describe "list_rules/2" do
    test "includes test-written rules", %{session: session} do
      a = RulesTestHelper.unique_rule_name()
      b = RulesTestHelper.unique_rule_name()

      RulesTestHelper.register_for_cleanup(:transaction_screening, a)
      RulesTestHelper.register_for_cleanup(:transaction_screening, b)

      :ok = RulesContext.write_rule(session, :transaction_screening, a, Base.encode64("{}"))
      :ok = RulesContext.write_rule(session, :transaction_screening, b, Base.encode64("{}"))

      assert {:ok, names} = RulesContext.list_rules(session, :transaction_screening)
      assert a in names
      assert b in names
    end

    test "result is sorted", %{session: session} do
      assert {:ok, names} = RulesContext.list_rules(session, :transaction_screening)
      assert names == Enum.sort(names)
    end

    test "skips dotfiles", %{session: session} do
      # .gitkeep lives in priv/zenrule/onboarding to keep the folder tracked;
      # list_rules must not return it.
      assert {:ok, names} = RulesContext.list_rules(session, :onboarding)
      refute Enum.any?(names, &String.starts_with?(&1, "."))
    end

    test "rejects invalid rule_type", %{session: session} do
      assert_raise ArgumentError, fn ->
        RulesContext.list_rules(session, :bogus)
      end
    end
  end

  describe "get_rule/3" do
    test "reads bytes of a written rule", %{session: session} do
      name = RulesTestHelper.unique_rule_name()
      RulesTestHelper.register_for_cleanup(:transaction_screening, name)
      body = ~s({"x":1})

      :ok = RulesContext.write_rule(session, :transaction_screening, name, Base.encode64(body))

      assert {:ok, ^body} = RulesContext.get_rule(session, :transaction_screening, name)
    end

    test "returns :enoent for missing rule", %{session: session} do
      missing = RulesTestHelper.unique_rule_name()
      assert {:error, :enoent} = RulesContext.get_rule(session, :transaction_screening, missing)
    end

    test "rejects path-traversal names", %{session: session} do
      assert {:error, :invalid_name} =
               RulesContext.get_rule(session, :transaction_screening, "../etc/passwd")

      assert {:error, :invalid_name} =
               RulesContext.get_rule(session, :transaction_screening, "sub/dir/rule.json")
    end
  end

  describe "write_rule/4" do
    test "decodes base64 and writes JDM file", %{session: session} do
      name = RulesTestHelper.unique_rule_name()
      RulesTestHelper.register_for_cleanup(:transaction_screening, name)
      body = ~s({"hello":"world"})

      assert :ok =
               RulesContext.write_rule(
                 session,
                 :transaction_screening,
                 name,
                 Base.encode64(body)
               )

      assert {:ok, ^body} = RulesContext.get_rule(session, :transaction_screening, name)
    end

    test "refuses to overwrite an existing rule", %{session: session} do
      name = RulesTestHelper.unique_rule_name()
      RulesTestHelper.register_for_cleanup(:transaction_screening, name)
      :ok = RulesContext.write_rule(session, :transaction_screening, name, Base.encode64("{}"))

      assert {:error, :already_exists} =
               RulesContext.write_rule(
                 session,
                 :transaction_screening,
                 name,
                 Base.encode64("{}")
               )
    end

    test "rejects malformed base64", %{session: session} do
      name = RulesTestHelper.unique_rule_name()

      assert {:error, :invalid_base64} =
               RulesContext.write_rule(session, :transaction_screening, name, "!!!not_b64!!!")
    end

    test "rejects path-traversal names", %{session: session} do
      assert {:error, :invalid_name} =
               RulesContext.write_rule(
                 session,
                 :transaction_screening,
                 "../escape.json",
                 Base.encode64("{}")
               )
    end
  end

  describe "update_rule/4" do
    test "overwrites an existing rule", %{session: session} do
      name = RulesTestHelper.unique_rule_name()
      RulesTestHelper.register_for_cleanup(:transaction_screening, name)
      :ok = RulesContext.write_rule(session, :transaction_screening, name, Base.encode64("{}"))
      updated = ~s({"updated":true})

      assert :ok =
               RulesContext.update_rule(
                 session,
                 :transaction_screening,
                 name,
                 Base.encode64(updated)
               )

      assert {:ok, ^updated} = RulesContext.get_rule(session, :transaction_screening, name)
    end

    test "fails when rule does not exist", %{session: session} do
      missing = RulesTestHelper.unique_rule_name()

      assert {:error, :enoent} =
               RulesContext.update_rule(
                 session,
                 :transaction_screening,
                 missing,
                 Base.encode64("{}")
               )
    end
  end

  describe "delete_rule/3" do
    test "removes the rule", %{session: session} do
      name = RulesTestHelper.unique_rule_name()
      RulesTestHelper.register_for_cleanup(:transaction_screening, name)
      :ok = RulesContext.write_rule(session, :transaction_screening, name, Base.encode64("{}"))

      assert :ok = RulesContext.delete_rule(session, :transaction_screening, name)
      assert {:error, :enoent} = RulesContext.get_rule(session, :transaction_screening, name)
    end

    test "is idempotent when file is already absent", %{session: session} do
      ghost = RulesTestHelper.unique_rule_name()
      assert :ok = RulesContext.delete_rule(session, :transaction_screening, ghost)
    end
  end
end

defmodule AtomicFi.ConfigTest do
  use ExUnit.Case, async: false

  alias AtomicFi.Config

  @test_key :__config_test_key__
  @nested_key :__config_test_nested__

  setup do
    on_exit(fn ->
      Application.delete_env(:atomic_fi, @test_key)
      Application.delete_env(:atomic_fi, @nested_key)
    end)

    :ok
  end

  describe "get/1 and get/2" do
    test "returns value for atom key" do
      Application.put_env(:atomic_fi, @test_key, "value")
      assert Config.get(@test_key) == "value"
    end

    test "returns nil when key is missing and no default given" do
      assert Config.get(@test_key) == nil
    end

    test "returns default when key is missing" do
      assert Config.get(@test_key, "default") == "default"
    end

    test "returns value for single-element path list" do
      Application.put_env(:atomic_fi, @test_key, "value")
      assert Config.get([@test_key], "default") == "value"
    end

    test "returns value for nested keyword path" do
      Application.put_env(:atomic_fi, @nested_key, child: "nested_value")
      assert Config.get([@nested_key, :child], "default") == "nested_value"
    end

    test "returns value for nested map path" do
      Application.put_env(:atomic_fi, @nested_key, %{child: "map_value"})
      assert Config.get([@nested_key, :child], "default") == "map_value"
    end

    test "returns default when nested key is missing" do
      Application.put_env(:atomic_fi, @nested_key, child: "v")
      assert Config.get([@nested_key, :missing], "default") == "default"
    end

    test "returns default when path traverses a non-map/list" do
      Application.put_env(:atomic_fi, @nested_key, "leaf")
      assert Config.get([@nested_key, :child], "default") == "default"
    end
  end

  describe "fetch/1" do
    test "returns {:ok, value} for atom key" do
      Application.put_env(:atomic_fi, @test_key, "value")
      assert Config.fetch(@test_key) == {:ok, "value"}
    end

    test "returns :error when atom key missing" do
      assert Config.fetch(@test_key) == :error
    end

    test "returns {:ok, value} for nested path" do
      Application.put_env(:atomic_fi, @nested_key, child: "nv")
      assert Config.fetch([@nested_key, :child]) == {:ok, "nv"}
    end

    test "returns :error when nested key missing" do
      Application.put_env(:atomic_fi, @nested_key, child: "nv")
      assert Config.fetch([@nested_key, :missing]) == :error
    end
  end

  describe "fetch!/1" do
    test "returns value when key exists" do
      Application.put_env(:atomic_fi, @test_key, "value")
      assert Config.fetch!(@test_key) == "value"
    end

    test "raises Config.Error when key missing" do
      assert_raise Config.Error, ~r/Missing configuration value/, fn ->
        Config.fetch!(@test_key)
      end
    end
  end

  describe "put/2" do
    test "sets a top-level atom key" do
      Config.put(@test_key, "v")
      assert Application.get_env(:atomic_fi, @test_key) == "v"
    end

    test "sets a single-element path" do
      Config.put([@test_key], "v")
      assert Application.get_env(:atomic_fi, @test_key) == "v"
    end

    test "sets a nested path on an existing keyword list" do
      Application.put_env(:atomic_fi, @nested_key, child: "old")
      Config.put([@nested_key, :child], "new")
      assert Application.get_env(:atomic_fi, @nested_key)[:child] == "new"
    end

    test "sets a nested path when parent is missing (starts empty)" do
      Config.put([@nested_key, :child], "new")
      assert Application.get_env(:atomic_fi, @nested_key)[:child] == "new"
    end
  end

  describe "delete/1" do
    test "deletes a top-level atom key" do
      Application.put_env(:atomic_fi, @test_key, "v")
      Config.delete(@test_key)
      assert Application.get_env(:atomic_fi, @test_key) == nil
    end

    test "deletes a single-element path" do
      Application.put_env(:atomic_fi, @test_key, "v")
      Config.delete([@test_key])
      assert Application.get_env(:atomic_fi, @test_key) == nil
    end

    test "deletes a nested key" do
      Application.put_env(:atomic_fi, @nested_key, child: "v", other: "keep")
      Config.delete([@nested_key, :child])
      env = Application.get_env(:atomic_fi, @nested_key)
      refute Keyword.has_key?(env, :child)
      assert env[:other] == "keep"
    end

    test "is a no-op when nested path is missing" do
      Application.put_env(:atomic_fi, @nested_key, other: "keep")
      assert Config.delete([@nested_key, :missing]) == :error
      assert Application.get_env(:atomic_fi, @nested_key)[:other] == "keep"
    end
  end
end

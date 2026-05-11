defmodule AtomicFiApi.Helpers.ApiHelpersTest do
  use ExUnit.Case, async: true

  alias AtomicFiApi.Helpers.ApiHelpers

  describe "parse_flop_params/1" do
    test "parses string-keyed page + page_size as integers" do
      result = ApiHelpers.parse_flop_params(%{"page" => "3", "page_size" => "25"})
      assert result == %{page: 3, page_size: 25}
    end

    test "parses atom-keyed page + page_size" do
      result = ApiHelpers.parse_flop_params(%{page: 1, page_size: 50})
      assert result == %{page: 1, page_size: 50}
    end

    test "converts a single order_by string into a list of atoms" do
      result = ApiHelpers.parse_flop_params(%{"order_by" => "name"})
      assert result[:order_by] == [:name]
    end

    test "converts an order_by list of strings into atoms" do
      result = ApiHelpers.parse_flop_params(%{"order_by" => ["name", "inserted_at"]})
      assert result[:order_by] == [:name, :inserted_at]
    end

    test "leaves atoms in an order_by list untouched" do
      result = ApiHelpers.parse_flop_params(%{"order_by" => [:name, "inserted_at"]})
      assert result[:order_by] == [:name, :inserted_at]
    end

    test "parses a single order_directions string into a list" do
      result = ApiHelpers.parse_flop_params(%{"order_by" => "name", "order_directions" => "desc"})
      assert result[:order_directions] == [:desc]
    end

    test "parses an order_directions list of strings" do
      result =
        ApiHelpers.parse_flop_params(%{
          "order_by" => ["a", "b"],
          "order_directions" => ["asc", "desc"]
        })

      assert result[:order_directions] == [:asc, :desc]
    end

    test "defaults order_directions to :asc when only order_by is provided" do
      result = ApiHelpers.parse_flop_params(%{"order_by" => ["a", "b"]})
      assert result[:order_directions] == [:asc, :asc]
    end

    test "passes filters straight through" do
      filters = [%{field: :status, op: :==, value: "active"}]
      result = ApiHelpers.parse_flop_params(%{"filters" => filters})
      assert result[:filters] == filters
    end

    test "ignores unknown keys" do
      result = ApiHelpers.parse_flop_params(%{"random_key" => "x", "page" => "1"})
      assert result == %{page: 1}
    end

    test "returns nil for non-binary, non-integer page" do
      result = ApiHelpers.parse_flop_params(%{"page" => :not_an_integer})
      assert result == %{page: nil}
    end

    test "returns nil for unparsable page string" do
      result = ApiHelpers.parse_flop_params(%{"page" => "not-a-number"})
      assert result == %{page: nil}
    end

    test "leaves atoms in an order_directions list untouched" do
      result =
        ApiHelpers.parse_flop_params(%{"order_by" => "a", "order_directions" => [:asc]})

      assert result[:order_directions] == [:asc]
    end

    test "non-binary, non-list order_by returns nil" do
      result = ApiHelpers.parse_flop_params(%{"order_by" => 42})
      assert result[:order_by] == nil
    end
  end
end

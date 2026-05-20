defmodule AtomicFi.LedgerAccountContext.ControlLimitTest do
  use ExUnit.Case, async: true

  alias AtomicFi.LedgerAccountContext.ControlLimit
  alias AtomicFi.LedgerAccountContext.LedgerAccount

  describe "ControlLimit.changeset/2" do
    test "accepts valid attrs" do
      cs =
        ControlLimit.changeset(%ControlLimit{}, %{
          period: "daily",
          direction: "debit",
          cap: 1_000,
          rule: "test"
        })

      assert cs.valid?
    end

    test "requires period and direction" do
      cs = ControlLimit.changeset(%ControlLimit{}, %{cap: 1_000})
      refute cs.valid?
      assert cs.errors[:period]
      assert cs.errors[:direction]
    end

    test "rejects invalid period and direction enums" do
      cs =
        ControlLimit.changeset(%ControlLimit{}, %{
          period: "hourly",
          direction: "sideways",
          cap: 100
        })

      refute cs.valid?
      assert cs.errors[:period]
      assert cs.errors[:direction]
    end

    test "rejects negative cap" do
      cs =
        ControlLimit.changeset(%ControlLimit{}, %{
          period: "daily",
          direction: "debit",
          cap: -1
        })

      refute cs.valid?
      assert cs.errors[:cap]
    end
  end

  describe "JSON rendering via ExOpenApiUtils.Mapper" do
    test "Mapper.to_map/1 returns a plain map (no Jason.Encoder dependency)" do
      limit = %ControlLimit{
        period: "daily",
        direction: "debit",
        cap: 1_000,
        rule: "test_rule"
      }

      result = ExOpenApiUtils.Mapper.to_map(limit)

      assert is_map(result)
      refute is_struct(result)

      assert result[:period] == "daily" or result["period"] == "daily"

      # And it Jason-encodes cleanly. Before ControlLimit used AtomicFi.Schema
      # this raised Protocol.UndefinedError, breaking every LedgerEntry index
      # response that carried a non-empty limits_at_entry[].
      assert {:ok, json} = Jason.encode(result)
      assert is_binary(json)
    end
  end

  describe "LedgerAccount introspection helpers" do
    test "root_regime/0 returns the sentinel regime" do
      assert is_binary(LedgerAccount.root_regime())
    end

    test "la_types/0 returns all enum values" do
      types = LedgerAccount.la_types()
      assert is_list(types)
      assert :account_holder_root in types
      assert :counter_party_payment_account_regime_root in types
    end
  end
end

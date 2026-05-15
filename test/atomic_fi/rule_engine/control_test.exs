defmodule AtomicFi.RuleEngine.ControlTest do
  use ExUnit.Case, async: true

  alias AtomicFi.RuleEngine.Control

  describe "changeset/2" do
    test "casts known fields and validates cap non-negativity" do
      attrs = %{
        "daily_debit_cap" => 1_000,
        "daily_credit_cap" => 2_000,
        "weekly_debit_cap" => 5_000,
        "monthly_debit_cap" => 20_000,
        "yearly_debit_cap" => 200_000,
        "is_blocked" => false,
        "reason" => "de_minimis"
      }

      cs = Control.changeset(%Control{}, attrs)
      assert cs.valid?
      {:ok, control} = Ecto.Changeset.apply_action(cs, :cast)
      assert control.daily_debit_cap == 1_000
      assert control.reason == "de_minimis"
      assert control.is_blocked == false
    end

    test "rejects negative caps" do
      cs = Control.changeset(%Control{}, %{"daily_debit_cap" => -1})
      refute cs.valid?
      assert {"must be greater than or equal to %{number}", _} = cs.errors[:daily_debit_cap]
    end

    test "requires block_reason when is_blocked is true" do
      cs = Control.changeset(%Control{}, %{"is_blocked" => true})
      refute cs.valid?
      assert {"is required when is_blocked is true", _} = cs.errors[:block_reason]
    end

    test "accepts is_blocked true when block_reason is provided" do
      cs =
        Control.changeset(%Control{}, %{
          "is_blocked" => true,
          "block_reason" => "OFAC_SDN match"
        })

      assert cs.valid?
    end

    test "default control (no attrs) is valid" do
      cs = Control.changeset(%{})
      assert cs.valid?
    end
  end

  describe "tighter/2" do
    test "picks the smaller cap per slot, nil meaning unconstrained" do
      a = %Control{
        daily_debit_cap: 1_000,
        daily_credit_cap: nil,
        weekly_debit_cap: 10_000,
        weekly_credit_cap: 8_000,
        monthly_debit_cap: nil,
        monthly_credit_cap: 50_000,
        yearly_debit_cap: 100_000,
        yearly_credit_cap: 150_000,
        reason: "rule_a"
      }

      b = %Control{
        daily_debit_cap: 500,
        daily_credit_cap: 2_000,
        weekly_debit_cap: 20_000,
        weekly_credit_cap: nil,
        monthly_debit_cap: 25_000,
        monthly_credit_cap: nil,
        yearly_debit_cap: nil,
        yearly_credit_cap: 100_000,
        reason: "rule_b"
      }

      merged = Control.tighter(a, b)

      assert merged.daily_debit_cap == 500
      # one side nil → other wins
      assert merged.daily_credit_cap == 2_000
      assert merged.weekly_debit_cap == 10_000
      assert merged.weekly_credit_cap == 8_000
      assert merged.monthly_debit_cap == 25_000
      assert merged.monthly_credit_cap == 50_000
      assert merged.yearly_debit_cap == 100_000
      assert merged.yearly_credit_cap == 100_000
      assert merged.reason == "rule_a; rule_b"
    end

    test "merge_reasons handles nil + duplicate reasons" do
      a = %Control{reason: "rule_x"}
      b = %Control{reason: nil}
      assert Control.tighter(a, b).reason == "rule_x"
      assert Control.tighter(b, a).reason == "rule_x"
      assert Control.tighter(a, a).reason == "rule_x"
    end
  end
end

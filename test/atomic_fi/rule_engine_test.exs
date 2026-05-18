defmodule AtomicFi.RuleEngineTest do
  use ExUnit.Case, async: true

  alias AtomicFi.RuleEngine
  alias AtomicFi.RuleEngine.Control

  describe "effective_control/2" do
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

      merged = RuleEngine.effective_control(a, b)

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

    test "reason handles nil + duplicate" do
      a = %Control{reason: "rule_x"}
      b = %Control{reason: nil}
      assert RuleEngine.effective_control(a, b).reason == "rule_x"
      assert RuleEngine.effective_control(b, a).reason == "rule_x"
      assert RuleEngine.effective_control(a, a).reason == "rule_x"
    end

    test "is_blocked is true if either side blocked (OR)" do
      blocking = %Control{is_blocked: true, block_reason: "ofac", reason: "ofac"}
      passing = %Control{is_blocked: false, reason: "tag"}

      assert RuleEngine.effective_control(blocking, passing).is_blocked == true
      assert RuleEngine.effective_control(passing, blocking).is_blocked == true
      assert RuleEngine.effective_control(passing, passing).is_blocked == false
      assert RuleEngine.effective_control(blocking, blocking).is_blocked == true
    end

    test "block_reason concatenates only blocking contributions" do
      blocking_a = %Control{is_blocked: true, block_reason: "ofac", reason: "ofac"}
      blocking_b = %Control{is_blocked: true, block_reason: "structuring", reason: "structuring"}
      passing = %Control{is_blocked: false, reason: "tag"}

      assert RuleEngine.effective_control(blocking_a, blocking_b).block_reason ==
               "ofac; structuring"

      # passing side doesn't bleed into block_reason even with a reason tag
      assert RuleEngine.effective_control(blocking_a, passing).block_reason == "ofac"
      assert RuleEngine.effective_control(passing, blocking_a).block_reason == "ofac"
      assert RuleEngine.effective_control(passing, passing).block_reason == nil
    end
  end

  describe "fold/1" do
    test "empty list → empty controls + nil next_screening_at" do
      assert RuleEngine.fold([]) == %{controls: %{}, next_screening_at: nil}
    end

    test "single rule passes through" do
      la = "la-1"
      c = %Control{daily_debit_cap: 100, reason: "r1"}
      result = %{controls: %{la => c}, next_screening_at: nil}
      folded = RuleEngine.fold([result])
      assert folded.controls[la] == c
      assert folded.next_screening_at == nil
    end

    test "two rules on same LA → effective_control applied" do
      la = "la-1"

      r1 = %{
        controls: %{la => %Control{daily_debit_cap: 1_000, reason: "r1"}},
        next_screening_at: nil
      }

      r2 = %{
        controls: %{la => %Control{daily_debit_cap: 500, reason: "r2"}},
        next_screening_at: nil
      }

      folded = RuleEngine.fold([r1, r2])
      assert folded.controls[la].daily_debit_cap == 500
      assert folded.controls[la].reason == "r1; r2"
    end

    test "two rules on different LAs → both preserved" do
      r1 = %{controls: %{"la-1" => %Control{daily_debit_cap: 100}}, next_screening_at: nil}
      r2 = %{controls: %{"la-2" => %Control{daily_debit_cap: 200}}, next_screening_at: nil}

      folded = RuleEngine.fold([r1, r2])
      assert Map.keys(folded.controls) |> Enum.sort() == ["la-1", "la-2"]
    end

    test "next_screening_at picks the earliest non-nil" do
      early = ~U[2026-06-01 00:00:00Z]
      late = ~U[2026-12-01 00:00:00Z]

      r1 = %{controls: %{}, next_screening_at: late}
      r2 = %{controls: %{}, next_screening_at: early}
      r3 = %{controls: %{}, next_screening_at: nil}

      assert RuleEngine.fold([r1, r2, r3]).next_screening_at == early
      assert RuleEngine.fold([r3, r1]).next_screening_at == late
      assert RuleEngine.fold([r3, r3]).next_screening_at == nil
    end

    test "blocking rule on one LA + non-blocking tag on another → both survive cleanly" do
      blocking = %Control{is_blocked: true, block_reason: "ofac", reason: "ofac"}
      tag = %Control{is_blocked: false, reason: "audit_tag"}

      r1 = %{controls: %{"la-1" => blocking}, next_screening_at: nil}
      r2 = %{controls: %{"la-2" => tag}, next_screening_at: nil}

      folded = RuleEngine.fold([r1, r2])
      assert folded.controls["la-1"].is_blocked == true
      assert folded.controls["la-1"].block_reason == "ofac"
      assert folded.controls["la-2"].is_blocked == false
      assert folded.controls["la-2"].block_reason == nil
    end
  end
end

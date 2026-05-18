defmodule AtomicFi.RuleEngine.DefaultTest do
  use AtomicFi.DataCase, async: true

  alias AtomicFi.RuleEngine
  alias AtomicFi.RuleEngine.Control
  alias AtomicFi.TransactionContext.Transaction

  # These tests drive the live ZenRule agent (http://localhost:8090) against
  # static JDM fixtures under priv/zenrule/test-fixtures-{good,bad}/. The
  # `:test_fixtures_good` / `:test_fixtures_bad` rule_types live only in
  # config/test.exs — prod's compiled binary never sees them.
  #
  # Combined, the two rule_types exercise the full decoder surface of
  # AtomicFi.RuleEngine.Default plus the public fold in AtomicFi.RuleEngine:
  #
  #   • Default.evaluate/4 — one HTTP call → one decoded rule_result
  #   • decode_rule_result/1 with ledger_accounts payload
  #   • decode_controls_map/1 fold + decode_control/1 cast
  #   • RuleEngine.apply_rules orchestration: rule listing + parallel
  #     fan-out + effective_control + fold across rules
  #   • decode_next_screening_at/1 for nil, valid ISO, and bad ISO
  #   • earliest/2 inside fold (one rule has a date, another nil)
  #   • {:error, _} halt path when a decoder errors

  describe "RuleEngine.apply_rules/3 — test-fixtures-good (happy path)" do
    test "merges 3 rules: tighter caps + adds slots + earliest next_screening_at",
         %{session: session} do
      transaction = %Transaction{tenant_id: session.tenant_id}

      assert {:ok, %{controls: controls, next_screening_at: nsa}} =
               RuleEngine.apply_rules(session, :test_fixtures_good, transaction)

      # la_test_001 is touched by both happy_caps and second_rule. Expect the
      # tighter daily_debit_cap (3000), plus union of other slots.
      assert %Control{} = la_001 = Map.get(controls, "la_test_001")
      assert la_001.daily_debit_cap == 3_000
      assert la_001.daily_credit_cap == 8_000
      assert la_001.monthly_credit_cap == 100_000

      # la_test_002 is touched only by with_next_screening
      assert %Control{} = la_002 = Map.get(controls, "la_test_002")
      assert la_002.yearly_debit_cap == 1_000_000

      # next_screening_at takes the EARLIEST non-nil across rules:
      # early_screening (2026-06-01) wins over with_next_screening (2026-12-31).
      assert nsa == ~U[2026-06-01 00:00:00Z]
    end
  end

  describe "RuleEngine.apply_rules/3 — test-fixtures-bad (error path)" do
    test "halts with {:error, {:invalid_next_screening_at, _}} on bad ISO",
         %{session: session} do
      transaction = %Transaction{tenant_id: session.tenant_id}

      assert {:error, {:invalid_next_screening_at, _reason}} =
               RuleEngine.apply_rules(session, :test_fixtures_bad, transaction)
    end

    test "halts with %Ecto.Changeset{} when a rule emits invalid (negative) caps",
         %{session: session} do
      transaction = %Transaction{tenant_id: session.tenant_id}

      assert {:error, %Ecto.Changeset{valid?: false}} =
               RuleEngine.apply_rules(session, :test_fixtures_bad_caps, transaction)
    end
  end

  describe "RuleEngine.apply_rules/3 — :no_limits short-circuit" do
    test "transaction-screening returns :no_limits when no rule emits caps",
         %{session: session} do
      # When no rule produces controls AND no rule supplies a next_screening_at,
      # apply_rules collapses to :no_limits.
      transaction = %Transaction{tenant_id: session.tenant_id, transaction_type: :credit_transfer}

      assert {:ok, :no_limits} =
               RuleEngine.apply_rules(session, :transaction_screening, transaction)
    end
  end
end

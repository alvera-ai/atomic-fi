defmodule AtomicFi.RuleEngine.DefaultTest do
  use AtomicFi.DataCase, async: false

  alias AtomicFi.RuleEngine.{Control, Default}
  alias AtomicFi.TransactionContext.Transaction

  # These tests drive the live ZenRule agent (http://localhost:8090) against
  # static JDM fixtures under priv/zenrule/test-fixtures-{good,bad}/. The
  # `:test_fixtures_good` / `:test_fixtures_bad` rule_types live only in
  # config/test.exs — prod's compiled binary never sees them.
  #
  # Combined, the two rule_types exercise the full decoder surface of
  # AtomicFi.RuleEngine.Default:
  #
  #   • get_controls happy path (function head + evaluate_and_merge fold)
  #   • decode_rule_result/1 with ledger_accounts payload
  #   • decode_controls_map/1 fold + decode_control/1 cast
  #   • merge_results/2 + Control.tighter/2 (two rules on same LA)
  #   • decode_next_screening_at/1 for nil, valid ISO, and bad ISO
  #   • earliest/2 (one rule has a screening date, the other nil)
  #   • {:error, _} halt path from evaluate_one when a decoder errors

  describe "get_controls/3 — test-fixtures-good (happy path)" do
    test "merges 3 rules: tighter caps + adds slots + earliest next_screening_at",
         %{session: session} do
      transaction = %Transaction{tenant_id: session.tenant_id}

      assert {:ok, %{controls: controls, next_screening_at: nsa}} =
               Default.get_controls(session, :test_fixtures_good, transaction)

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
      # The intermediate fold steps exercise earliest(a, nil) and earliest(a, b).
      assert nsa == ~U[2026-06-01 00:00:00Z]
    end
  end

  describe "get_controls/3 — test-fixtures-bad (error path)" do
    test "halts with {:error, {:invalid_next_screening_at, _}} on bad ISO",
         %{session: session} do
      transaction = %Transaction{tenant_id: session.tenant_id}

      assert {:error, {:invalid_next_screening_at, _reason}} =
               Default.get_controls(session, :test_fixtures_bad, transaction)
    end

    test "halts with %Ecto.Changeset{} when a rule emits invalid (negative) caps",
         %{session: session} do
      transaction = %Transaction{tenant_id: session.tenant_id}

      assert {:error, %Ecto.Changeset{valid?: false}} =
               Default.get_controls(session, :test_fixtures_bad_caps, transaction)
    end
  end

  describe "get_controls/3 — :no_limits short-circuit" do
    test "transaction-screening (de_minimis emits transaction.* shape) returns :no_limits",
         %{session: session} do
      # de_minimis.json writes to transaction.* fields, not ledger_accounts.*,
      # so decode_rule_result falls through to the empty-controls catch-all
      # and get_controls returns :no_limits.
      transaction = %Transaction{tenant_id: session.tenant_id, transaction_type: :credit_transfer}

      assert {:ok, :no_limits} =
               Default.get_controls(session, :transaction_screening, transaction)
    end
  end
end

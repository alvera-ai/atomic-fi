defmodule AtomicFi.RuleEngine do
  @moduledoc """
  Rule engine — payload assembly, rule fan-out, cross-rule fold.

  Callers (`AtomicFi.TransactionContext`, `OnboardingContext`, …) invoke
  `apply_rules/3` directly:

      RuleEngine.apply_rules(session, :transaction_screening, %Transaction{})
      RuleEngine.apply_rules(session, :onboarding, %AccountHolder{})

  ## Two-layer split

  ```
   callers ──► apply_rules
                ├─► build_payload              (shape the entity tree
                │                                for the rule engine —
                │                                Mapper.to_map mirror of
                │                                the public API response
                │                                plus rule-internal
                │                                projections per PA side)
                │
                ├─► Task.async_stream(names, fn name ->            ── MAP step
                │      @rule_engine.evaluate(session, project,        (N parallel
                │                              name, payload)          calls;
                │    end)                                              ordered:true
                │                                                      keeps fold
                │     └── dispatched Behaviour impl is a THIN          deterministic)
                │         per-decision transport wrapper — one
                │         (project, decision, payload) tuple in,
                │         one rule_result out (HTTP to ZenRule
                │         today; NIF tomorrow). Rule listing,
                │         payload assembly, fan-out, and fold all
                │         live in the common layer above, so a
                │         future impl substitutes only `evaluate/4`.
                │
                └─► fold(per-rule-results)                          ── REDUCE step
                                                (effective_control/2 per LA;
                                                earliest non-nil
                                                next_screening_at)

   ── result ──────────────────────────────────────────────────────────
     {:ok, %{controls: %{la_id => Control}, next_screening_at: dt}}
   | {:ok, :no_limits}
  ```

  The common layer owns *payload assembly*, *rule listing*, *parallel
  fan-out*, and *fold*. The dispatched impl is a thin per-decision
  translator. Swapping the JDM evaluator (NIF / next release) only
  requires replacing one `evaluate/4` callback; payload shape, fan-out
  ordering, and effective-control semantics stay coherent across
  regimes.

  ## Pluggable impl

  Compile-time resolved via the `:rule_engine` config slice. Default is
  `AtomicFi.RuleEngine.Default` (HTTP to the GoRules Agent). Tests swap
  in `AtomicFi.RuleEngineMock`, which `stub_with`s the Default so
  unstubbed tests fall through to the real engine.

  ## Effective control (industry term: *effective limit*)

  Per LA, across all rules that fired:

    * cap = min of all non-nil caps (strictest cap wins; nil = ∞)
    * is_blocked = OR across rules
    * block_reason = `; `-joined audit of every rule that BLOCKED
                     (a non-blocking tag never bleeds into the
                     block reason)
    * reason = `; `-joined audit of every rule that fired

  Matches how Stripe / Adyen / card-network docs describe limit
  stacking after issuer, regulatory, and velocity overlays combine.

  ## Payload shape

  `build_payload/2` mirrors the entity's public API response (via
  `ExOpenApiUtils.Mapper`), so the rule engine — whether reached over
  HTTP today or via an in-process NIF later — sees the same structure
  clients do. For a transaction the payload also carries the entity
  tree plus two **flat lists** synthesised per-PA-side at build time:

    - `<side>_payment_account.las`                  every LedgerAccount the rule
                                                    may target (regime leaves
                                                    and roots on the PA's DAG)
    - `<side>_payment_account.compliance_screenings` every screening (party LE
                                                    and instrument PA) touching
                                                    that side, regardless of
                                                    subject type

  Flat lists let the rule walk one list, filter on what it cares about
  (regime, scope, screening_type, …), without the rule layer having to
  know "leaf" vs "ancestor" or "AH vs CP vs BO".

  ## Config

      config :atomic_fi, AtomicFi.RuleEngine, base_url: "http://localhost:8090"
  """

  require Logger

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.ComplianceScreeningContext
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.LedgerAccountContext.LedgerAccount
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.RuleEngine.Control
  alias AtomicFi.RuleEngine.Default
  alias AtomicFi.RulesContext
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.TransactionContext
  alias AtomicFi.TransactionContext.Transaction

  @typedoc "Rule bucket — maps 1:1 to a ZenRule project (kebab-case folder slug)."
  @type rule_type :: :onboarding | :transaction_screening | atom()

  @typedoc "Plain, JSON-serialisable map handed to the rule engine impl."
  @type payload :: %{optional(atom() | String.t()) => term()}

  @typedoc "Controls keyed by ledger_account_id."
  @type controls :: %{optional(Ecto.UUID.t()) => Control.t()}

  @typedoc """
  Per-rule output envelope returned by `evaluate/4` impls (one element
  per rule that fires under a rule_type).

    * `:controls` — per-LA Controls this rule emitted.
    * `:next_screening_at` — re-screening hint from this rule, or `nil`.
  """
  @type rule_result :: %{
          controls: controls(),
          next_screening_at: DateTime.t() | nil
        }

  @typedoc """
  Folded result returned by `apply_rules/3`. `next_screening_at` is the
  earliest non-nil hint across all rules.
  """
  @type folded :: %{
          controls: controls(),
          next_screening_at: DateTime.t() | nil
        }

  @doc """
  Evaluate ONE decision against the prepared payload — a thin
  transport wrapper around whatever rule-engine backend is plugged in.

  `RuleEngine.apply_rules/3` is the orchestrator: it lists every
  decision under the rule_type, builds the payload, runs this callback
  N times in parallel (`Task.async_stream`), and folds the per-rule
  outputs into one effective control map. The impl never lists rules,
  never assembles payloads, never folds — it just translates one
  `(project, decision, payload)` tuple into one `rule_result`.

  GoRules' API surface (Agent, BRMS, Cloud) exposes one decision per
  HTTP call — see https://docs.gorules.io/openapi/agent.json — so the
  HTTP impl really is one call per invocation. A future in-process NIF
  impl drops in with the same contract.

  Implemented by `AtomicFi.RuleEngine.Default` (HTTP to the GoRules
  Agent). Mox seam for tests.
  """
  @callback evaluate(
              session :: Session.t(),
              project :: String.t(),
              decision :: String.t(),
              payload :: payload()
            ) :: {:ok, rule_result()} | {:error, term()}

  @rule_engine Application.compile_env(:atomic_fi, :rule_engine, Default)

  @doc """
  Public API: list every rule under `rule_type`, build the payload from
  `entity`, evaluate each rule, fold the per-rule outputs into one
  effective control map. Empty merged controls + nil hint →
  `{:ok, :no_limits}`; otherwise `{:ok, folded}`.
  """
  @spec apply_rules(Session.t(), rule_type(), struct()) ::
          {:ok, folded()} | {:ok, :no_limits} | {:error, term()}
  def apply_rules(session, rule_type, entity) do
    Logger.info(
      "[rule_engine] apply_rules rule_type=#{inspect(rule_type)} entity=#{inspect(entity.__struct__)}"
    )

    with {:ok, names} <- RulesContext.list_rules(session, rule_type),
         _ = Logger.info("[rule_engine] rules listed: #{inspect(names)}"),
         project = RulesContext.project_name(rule_type),
         payload = build_payload(session, entity),
         {:ok, results} <- evaluate_in_parallel(session, project, names, payload) do
      %{controls: controls, next_screening_at: next} = merged = fold(results)
      Logger.info("[rule_engine] fold done controls=#{map_size(controls)} next=#{inspect(next)}")

      if map_size(controls) == 0 and is_nil(next),
        do: {:ok, :no_limits},
        else: {:ok, merged}
    end
  end

  # Per-rule fan-out — N parallel `@rule_engine.evaluate/4` calls. Per-call
  # latency caps total fan-out at the slowest rule, not their sum. Short-circuits
  # on the first {:error, _} (any other rules whose Tasks haven't completed
  # yet still get GC'd by Task.async_stream once the stream is dropped).
  #
  # `ordered: true` keeps fold semantics stable across runs even when the
  # underlying HTTP call latencies fluctuate — `effective_control/2` is
  # commutative for caps but `merge_strings` joins `reason`/`block_reason` in
  # input order. Stable ordering = byte-stable `proof.md`.
  defp evaluate_in_parallel(session, project, names, payload) do
    names
    |> Task.async_stream(
      fn name -> @rule_engine.evaluate(session, project, name, payload) end,
      timeout: :infinity,
      ordered: true
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, rule_result}}, {:ok, acc} -> {:cont, {:ok, [rule_result | acc]}}
      {:ok, {:error, _} = err}, _acc -> {:halt, err}
      {:exit, reason}, _acc -> {:halt, {:error, {:rule_engine_task_exit, reason}}}
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      err -> err
    end
  end

  # ────────────────────────────  PAYLOAD  ────────────────────────────

  @doc """
  Build the rule-engine payload for any supported entity. Mirrors the
  entity's public API response (via `ExOpenApiUtils.Mapper`), plus the
  flat `las[]` / `compliance_screenings[]` rule-engine-internal
  projections per PA side.

  Public for testability (the `rule_engine_test.exs` payload describe
  block exercises this directly); production callers should go through
  `apply_rules/3`.
  """
  @spec build_payload(Session.t(), struct()) :: payload()
  def build_payload(session, %Transaction{} = transaction),
    do: build_transaction_payload(session, transaction)

  def build_payload(session, %AccountHolder{} = ah), do: build_onboarding_payload(session, ah)
  def build_payload(session, %Counterparty{} = cp), do: build_onboarding_payload(session, cp)
  def build_payload(session, %PaymentAccount{} = pa), do: build_onboarding_payload(session, pa)

  def build_payload(_session, other) when is_struct(other),
    do: ExOpenApiUtils.Mapper.to_map(other)

  # Onboarding payload — shape mirrors a Transaction payload's per-PA-side:
  # the entity itself plus a flat `las[]` of every LedgerAccount the rule may
  # target. The permissive onboarding rule walks `las[]` and emits a Control
  # per la_id, which `LedgerAccountContext.apply_controls/3` then writes back.
  defp build_onboarding_payload(session, entity) do
    las =
      session
      |> LedgerAccountContext.list_for_entity(entity)
      |> Enum.map(&la_to_map/1)

    entity
    |> ExOpenApiUtils.Mapper.to_map()
    |> Map.put("las", las)
  end

  # Transaction payload — expects debtor/creditor PAs (with nested
  # `account_holder`), debtor/creditor counterparties, and the originating
  # AH to be preloaded; unloaded or absent associations emit as `nil`.
  # `las[]` and `compliance_screenings[]` are queried fresh from each PA at
  # build time — rule-engine-internal projections, not preloaded.
  defp build_transaction_payload(session, %Transaction{} = transaction) do
    %{
      transaction: map_entity(transaction),
      account_holder: ah_payload(session, transaction.account_holder, transaction.id),
      debtor_payment_account: pa_payload(session, transaction.debtor_payment_account),
      creditor_payment_account: pa_payload(session, transaction.creditor_payment_account),
      debtor_counterparty: map_entity(transaction.debtor_counterparty),
      creditor_counterparty: map_entity(transaction.creditor_counterparty)
    }
  end

  # Injects `recent_debits_24h[]` onto the originating AccountHolder so
  # BSA §5324 (anti-structuring / velocity) rules can window over the
  # holder's recent outflows. Rejected transactions are excluded — they
  # didn't move money and so don't count toward the aggregate.
  defp ah_payload(_session, %Ecto.Association.NotLoaded{}, _exclude_id), do: nil
  defp ah_payload(_session, nil, _exclude_id), do: nil

  defp ah_payload(session, %AccountHolder{id: ah_id} = ah, exclude_id) do
    debits =
      session
      |> TransactionContext.list_recent_debits_for_account_holder(ah_id, exclude_id)
      |> Enum.map(&map_entity/1)

    ah
    |> map_entity()
    |> Map.put("recent_debits_24h", debits)
  end

  defp map_entity(%Ecto.Association.NotLoaded{}), do: nil
  defp map_entity(nil), do: nil
  defp map_entity(struct), do: ExOpenApiUtils.Mapper.to_map(struct)

  defp pa_payload(_session, %Ecto.Association.NotLoaded{}), do: nil
  defp pa_payload(_session, nil), do: nil

  defp pa_payload(session, %PaymentAccount{} = pa) do
    pa
    |> ExOpenApiUtils.Mapper.to_map()
    |> Map.put("account_holder", map_entity(pa.account_holder))
    |> Map.put("las", build_las(session, pa))
    |> Map.put("compliance_screenings", build_compliance_screenings(session, pa))
  end

  defp build_las(session, %PaymentAccount{} = pa) do
    session
    |> LedgerAccountContext.list_for_entity(pa)
    |> Enum.map(&la_to_map/1)
  end

  # Rule-internal serializer. The public LedgerAccount OpenAPI schema does not
  # expose `is_blocked`, `block_reason`, or the `max_*` caps; the rule engine
  # legitimately needs to read all of them (e.g. for re-evaluation against
  # onboarding-set caps). Hand-rolling the projection here keeps those fields
  # out of the public API surface.
  defp la_to_map(%LedgerAccount{} = la) do
    %{
      "id" => la.id,
      "la_type" => la.la_type && to_string(la.la_type),
      "regime" => la.regime,
      "currency" => la.currency,
      "max_daily_debit" => la.max_daily_debit,
      "max_daily_credit" => la.max_daily_credit,
      "max_weekly_debit" => la.max_weekly_debit,
      "max_weekly_credit" => la.max_weekly_credit,
      "max_monthly_debit" => la.max_monthly_debit,
      "max_monthly_credit" => la.max_monthly_credit,
      "max_yearly_debit" => la.max_yearly_debit,
      "max_yearly_credit" => la.max_yearly_credit,
      "is_blocked" => la.is_blocked,
      "block_reason" => la.block_reason,
      "balance" => la.balance,
      "payment_account_id" => la.payment_account_id,
      "counterparty_id" => la.counterparty_id
    }
  end

  # Flat per-PA-side compliance screenings. Aggregates without caring about
  # subject type:
  #
  #   - the PA itself (instrument screenings — wallet / IBAN)
  #   - the LE of PA's AccountHolder (party — identity PII)
  #   - the LEs of the AH's BeneficialOwners (party)
  #   - the LE of PA's Counterparty (party)
  #
  # Each row keeps `scope` as the rule's filter discriminator.
  defp build_compliance_screenings(session, %PaymentAccount{} = pa) do
    [pa | party_subjects(session, pa)]
    |> Enum.flat_map(&ComplianceScreeningContext.get_screenings_for_target(session, &1))
    |> Enum.uniq_by(& &1.id)
    |> Enum.map(&ExOpenApiUtils.Mapper.to_map/1)
  end

  # Resolve the LegalEntities behind a PaymentAccount — its AH's identity LE
  # and (if a CP-owned PA) the CP's LE. Returns a flat list of %LegalEntity{};
  # assoc lookups happen via the existing context getters so RLS is preserved.
  # BO LEs are not surfaced yet — wire them up when a rule needs them.
  defp party_subjects(session, %PaymentAccount{} = pa) do
    ah_subjects =
      case pa.account_holder_id do
        nil ->
          []

        ah_id ->
          ah = AtomicFi.AccountHolderContext.get_account_holder!(session, ah_id)
          List.wrap(present(ah.legal_entity))
      end

    cp_subjects =
      case pa.counterparty_id do
        nil ->
          []

        cp_id ->
          cp = AtomicFi.CounterpartyContext.get_counterparty!(session, cp_id)
          List.wrap(present(cp.legal_entity))
      end

    ah_subjects ++ cp_subjects
  end

  defp present(nil), do: nil
  defp present(%Ecto.Association.NotLoaded{}), do: nil
  defp present(value), do: value

  # ──────────────────────────────  FOLD  ──────────────────────────────

  @doc """
  Fold a list of per-rule outputs into one merged envelope.
  """
  @spec fold([rule_result()]) :: folded()
  def fold(results) when is_list(results) do
    Enum.reduce(results, %{controls: %{}, next_screening_at: nil}, &fold_one(&2, &1))
  end

  defp fold_one(a, b) do
    %{
      controls:
        Map.merge(a.controls, b.controls, fn _la_id, %Control{} = c1, %Control{} = c2 ->
          effective_control(c1, c2)
        end),
      next_screening_at: earliest(a.next_screening_at, b.next_screening_at)
    }
  end

  defp earliest(nil, b), do: b
  defp earliest(a, nil), do: a
  defp earliest(a, b), do: if(DateTime.compare(a, b) == :lt, do: a, else: b)

  @doc """
  Effective control on one LA when two rules both emitted — see module
  doc for semantics. Fan-in across N rules is via `fold/1`.
  """
  @spec effective_control(Control.t(), Control.t()) :: Control.t()
  def effective_control(%Control{} = a, %Control{} = b) do
    %Control{
      daily_debit_cap: min_cap(a.daily_debit_cap, b.daily_debit_cap),
      daily_credit_cap: min_cap(a.daily_credit_cap, b.daily_credit_cap),
      weekly_debit_cap: min_cap(a.weekly_debit_cap, b.weekly_debit_cap),
      weekly_credit_cap: min_cap(a.weekly_credit_cap, b.weekly_credit_cap),
      monthly_debit_cap: min_cap(a.monthly_debit_cap, b.monthly_debit_cap),
      monthly_credit_cap: min_cap(a.monthly_credit_cap, b.monthly_credit_cap),
      yearly_debit_cap: min_cap(a.yearly_debit_cap, b.yearly_debit_cap),
      yearly_credit_cap: min_cap(a.yearly_credit_cap, b.yearly_credit_cap),
      is_blocked: a.is_blocked or b.is_blocked,
      block_reason: merge_block_reasons(a, b),
      reason: merge_strings(a.reason, b.reason)
    }
  end

  defp min_cap(nil, b), do: b
  defp min_cap(a, nil), do: a
  defp min_cap(a, b), do: min(a, b)

  defp merge_strings(nil, b), do: b
  defp merge_strings(a, nil), do: a
  defp merge_strings(a, a), do: a
  defp merge_strings(a, b), do: "#{a}; #{b}"

  defp merge_block_reasons(%Control{is_blocked: false}, %Control{is_blocked: false}), do: nil

  defp merge_block_reasons(%Control{is_blocked: true} = a, %Control{is_blocked: false}),
    do: a.block_reason

  defp merge_block_reasons(%Control{is_blocked: false}, %Control{is_blocked: true} = b),
    do: b.block_reason

  defp merge_block_reasons(%Control{is_blocked: true} = a, %Control{is_blocked: true} = b),
    do: merge_strings(a.block_reason, b.block_reason)
end

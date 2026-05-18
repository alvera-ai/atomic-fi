defmodule AtomicFi.RuleEngine.Payload do
  @moduledoc """
  Builds the rule engine evaluation context from domain entities.

  Each entity is shaped like its API response (via `ExOpenApiUtils.Mapper`), so
  the rules engine — whether reached over HTTP (`AtomicFi.RuleEngine` today)
  or via an in-process NIF later — sees the same structure clients do. The
  conversion never lives in a context or in the transport.

  For a transaction the context also carries the entity tree (account holder,
  debtor/creditor payment accounts and counterparties) plus two **flat lists**
  synthesised per-PA-side at payload-build time:

    - `<side>_payment_account.las`                  every LedgerAccount the rule
                                                    may target (regime leaves
                                                    and roots on the PA's DAG)
    - `<side>_payment_account.compliance_screenings` every screening (party LE
                                                    and instrument PA) touching
                                                    that side, regardless of
                                                    subject type

  Flat lists let the rule walk a single list, filter on what it cares about
  (regime, scope, screening_type, …), without the rule layer having to know
  "leaf" vs "ancestor" or "AH vs CP vs BO".
  """

  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.ComplianceScreeningContext
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.LedgerAccountContext
  alias AtomicFi.LedgerAccountContext.LedgerAccount
  alias AtomicFi.PaymentAccountContext.PaymentAccount
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.TransactionContext
  alias AtomicFi.TransactionContext.Transaction

  @typedoc "Plain, JSON-serialisable map handed to the rule engine."
  @type t :: %{optional(atom() | String.t()) => term()}

  @doc "Build the evaluation context for any supported entity."
  @spec from_entity(Session.t(), struct()) :: t()
  def from_entity(session, %Transaction{} = transaction),
    do: from_transaction(session, transaction)

  def from_entity(session, %AccountHolder{} = ah), do: from_onboarding_entity(session, ah)
  def from_entity(session, %Counterparty{} = cp), do: from_onboarding_entity(session, cp)
  def from_entity(session, %PaymentAccount{} = pa), do: from_onboarding_entity(session, pa)

  def from_entity(_session, other) when is_struct(other),
    do: ExOpenApiUtils.Mapper.to_map(other)

  # Onboarding payload — shape mirrors a Transaction payload's per-PA-side:
  # the entity itself plus a flat `las[]` of every LedgerAccount the rule may
  # target. The permissive onboarding rule walks `las[]` and emits a Control
  # per la_id, which `LedgerAccountContext.apply_controls/3` then writes back.
  defp from_onboarding_entity(session, entity) do
    las =
      session
      |> LedgerAccountContext.list_for_entity(entity)
      |> Enum.map(&la_to_map/1)

    entity
    |> ExOpenApiUtils.Mapper.to_map()
    |> Map.put("las", las)
  end

  @doc """
  Context for a transaction evaluation.

  Expects the transaction's debtor/creditor payment accounts (with nested
  `account_holder`), debtor/creditor counterparties, and account holder to
  be preloaded; unloaded or absent associations are emitted as `nil`.

  `las[]` and `compliance_screenings[]` are queried fresh from each PA at
  build time (not preloaded) — they are rule-engine-internal projections and
  do not belong on the public PA OpenAPI surface.
  """
  @spec from_transaction(Session.t(), Transaction.t()) :: t()
  def from_transaction(session, %Transaction{} = transaction) do
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
end

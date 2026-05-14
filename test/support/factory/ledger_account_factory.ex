defmodule AtomicFi.Factory.LedgerAccountFactory do
  @moduledoc """
  Factory for LedgerAccount context schemas.

  Smart-dispatched on `la_type`. The 6 `la_type`s carve out the
  (payment_account_id, counterparty_id, regime) cross. For each, the factory
  ensures the proper CP / PA rows exist and recursively upserts any required
  ancestor LedgerAccount rows so the BEFORE-INSERT trigger
  (`ledger_accounts_resolve_ancestor_ids`) can resolve `ancestor_ids`.

  Default `la_type` is `:account_holder_payment_account_regime_root` with
  `regime: "ach"` — a fully-leaf row, so `insert(:ledger_account, ...)` calls
  with no `la_type` keep working and produce a postable leaf.

  Ancestor upserts are idempotent: each ancestor is looked up by its
  `(ledger_id, payment_account_id, counterparty_id, regime)` identity before
  insert, so re-using the same CP/PA across multiple factory calls in one
  test does not trip the partial unique indexes.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.LedgerAccountContext.LedgerAccount
      alias AtomicFi.Repo

      def ledger_account_factory(attrs \\ %{}) do
        attrs = Enum.into(attrs, %{})
        la_type = Map.get(attrs, :la_type, :account_holder_payment_account_regime_root)

        tenant_id = Map.get_lazy(attrs, :tenant_id, fn -> insert(:tenant).id end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        ledger_id =
          Map.get_lazy(attrs, :ledger_id, fn ->
            insert(:ledger, tenant_id: tenant_id, account_holder_id: account_holder_id).id
          end)

        currency = Map.get(attrs, :currency, "USD")

        base = %{
          tenant_id: tenant_id,
          account_holder_id: account_holder_id,
          ledger_id: ledger_id,
          currency: currency
        }

        build_la(la_type, attrs, base)
      end

      # ── Dispatch on la_type ────────────────────────────────────────────────

      defp build_la(:counter_party_root, attrs, base) do
        cp_id = resolve_counterparty_id(attrs, base)
        la_struct(base, :counter_party_root, "root", nil, cp_id, attrs)
      end

      defp build_la(:counter_party_regime_root, attrs, base) do
        cp_id = resolve_counterparty_id(attrs, base)
        regime = Map.get(attrs, :regime, "ach")

        ensure_ledger_account(base, :counter_party_root, "root", nil, cp_id)

        la_struct(base, :counter_party_regime_root, regime, nil, cp_id, attrs)
      end

      defp build_la(:account_holder_root, attrs, base) do
        la_struct(base, :account_holder_root, "root", nil, nil, attrs)
      end

      defp build_la(:account_holder_regime_root, attrs, base) do
        regime = Map.get(attrs, :regime, "ach")

        ensure_ledger_account(base, :account_holder_root, "root", nil, nil)

        la_struct(base, :account_holder_regime_root, regime, nil, nil, attrs)
      end

      defp build_la(:account_holder_payment_account_root, attrs, base) do
        pa_id = resolve_payment_account_id(attrs, base, nil)

        ensure_ledger_account(base, :account_holder_root, "root", nil, nil)

        la_struct(base, :account_holder_payment_account_root, "root", pa_id, nil, attrs)
      end

      defp build_la(:account_holder_payment_account_regime_root, attrs, base) do
        pa_id = resolve_payment_account_id(attrs, base, nil)
        regime = Map.get(attrs, :regime, "ach")

        ensure_ledger_account(base, :account_holder_root, "root", nil, nil)
        ensure_ledger_account(base, :account_holder_regime_root, regime, nil, nil)
        ensure_ledger_account(base, :account_holder_payment_account_root, "root", pa_id, nil)

        la_struct(base, :account_holder_payment_account_regime_root, regime, pa_id, nil, attrs)
      end

      defp build_la(:counter_party_payment_account_root, attrs, base) do
        cp_id = resolve_counterparty_id(attrs, base)
        pa_id = resolve_payment_account_id(attrs, base, cp_id)

        ensure_ledger_account(base, :counter_party_root, "root", nil, cp_id)

        la_struct(base, :counter_party_payment_account_root, "root", pa_id, cp_id, attrs)
      end

      defp build_la(:counter_party_payment_account_regime_root, attrs, base) do
        cp_id = resolve_counterparty_id(attrs, base)
        pa_id = resolve_payment_account_id(attrs, base, cp_id)
        regime = Map.get(attrs, :regime, "ach")

        ensure_ledger_account(base, :counter_party_root, "root", nil, cp_id)
        ensure_ledger_account(base, :counter_party_regime_root, regime, nil, cp_id)
        ensure_ledger_account(base, :counter_party_payment_account_root, "root", pa_id, cp_id)

        la_struct(base, :counter_party_payment_account_regime_root, regime, pa_id, cp_id, attrs)
      end

      # ── Helpers ────────────────────────────────────────────────────────────

      defp resolve_counterparty_id(attrs, base) do
        Map.get_lazy(attrs, :counterparty_id, fn ->
          insert(:counterparty,
            tenant_id: base.tenant_id,
            account_holder_id: base.account_holder_id
          ).id
        end)
      end

      defp resolve_payment_account_id(attrs, base, counterparty_id) do
        Map.get_lazy(attrs, :payment_account_id, fn ->
          pa_attrs = [
            tenant_id: base.tenant_id,
            account_holder_id: base.account_holder_id,
            currency: base.currency
          ]

          pa_attrs =
            if counterparty_id,
              do: [{:counterparty_id, counterparty_id} | pa_attrs],
              else: pa_attrs

          insert(:payment_account, pa_attrs).id
        end)
      end

      # Build the final (unpersisted) struct that ExMachina will insert.
      # `attrs` is splatted last so test overrides (status:, balance:, …) win.
      defp la_struct(base, la_type, regime, payment_account_id, counterparty_id, attrs) do
        %LedgerAccount{
          tenant_id: base.tenant_id,
          account_holder_id: base.account_holder_id,
          ledger_id: base.ledger_id,
          currency: base.currency,
          la_type: la_type,
          regime: regime,
          payment_account_id: payment_account_id,
          counterparty_id: counterparty_id,
          status: :active,
          balance: 0,
          # is_blocked is NOT NULL in the DB (no default). Factories
          # default to false; tests opt in to `is_blocked: true` per case.
          is_blocked: false
        }
        |> merge_attributes(
          Map.drop(attrs, [:la_type, :regime, :counterparty_id, :payment_account_id])
        )
      end

      # Idempotent ancestor insert. Looked up by the natural identity tuple so
      # repeat calls in a single test share the same row and don't fight the
      # partial unique indexes. Built as a manual query because `Repo.get_by`
      # forbids nil-equality comparisons on nullable columns.
      defp ensure_ledger_account(base, la_type, regime, payment_account_id, counterparty_id) do
        import Ecto.Query

        query =
          from(la in LedgerAccount,
            where:
              la.ledger_id == ^base.ledger_id and
                la.regime == ^regime and
                la.la_type == ^la_type
          )

        query =
          case payment_account_id do
            nil -> from(la in query, where: is_nil(la.payment_account_id))
            id -> from(la in query, where: la.payment_account_id == ^id)
          end

        query =
          case counterparty_id do
            nil -> from(la in query, where: is_nil(la.counterparty_id))
            id -> from(la in query, where: la.counterparty_id == ^id)
          end

        case Repo.one(query, skip_multi_tenancy_check: true) do
          %LedgerAccount{} = existing ->
            existing

          nil ->
            insert(:ledger_account,
              tenant_id: base.tenant_id,
              account_holder_id: base.account_holder_id,
              ledger_id: base.ledger_id,
              currency: base.currency,
              la_type: la_type,
              regime: regime,
              payment_account_id: payment_account_id,
              counterparty_id: counterparty_id
            )
        end
      end
    end
  end
end

defmodule AtomicFi.Factory.CounterpartyFactory do
  @moduledoc """
  Factory for Counterparty context schemas.

  Counterparty owns no FK to LegalEntity — LE carries the FK back via
  `legal_entities.counterparty_id` (subject_type = :counterparty). This
  factory only inserts the CP; tests that need the paired LE use
  `insert_counterparty_with_legal_entity/1` (in `AtomicFi.Factory`).
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.CounterpartyContext.Counterparty

      def counterparty_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        %Counterparty{
          account_holder_id: account_holder_id,
          status: :active,
          tenant_id: tenant_id
        }
        |> merge_attributes(attrs)
        |> evaluate_lazy_attributes()
      end
    end
  end
end

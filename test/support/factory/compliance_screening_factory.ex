defmodule AtomicFi.Factory.ComplianceScreeningFactory do
  @moduledoc """
  Factory for ComplianceScreening rows.

  Primary anchor is `legal_entity_id` (party screening) or `payment_account_id`
  (instrument screening) — exactly one per DB CHECK. The factory accepts
  whichever the caller provides; if neither is passed it inserts a LegalEntity
  for an AccountHolder and anchors to that.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.ComplianceScreeningContext.ComplianceScreening

      def compliance_screening_factory(attrs \\ %{}) do
        attrs = Enum.into(attrs, %{})

        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn -> insert(:tenant).id end)

        # If the caller passed an account_holder_id but no legal_entity_id,
        # resolve / insert the AH's identity LE so the screening has an anchor.
        attrs = ensure_anchor(attrs, tenant_id)

        scope = Map.get(attrs, :scope, infer_scope(attrs))

        %ComplianceScreening{
          tenant_id: tenant_id,
          scope: scope,
          screening_type: :sanctions,
          screening_status: :pass,
          screened_entity_type: :individual,
          screened_entity_name: "Test Subject",
          match_count: 0
        }
        |> merge_attributes(Map.drop(attrs, [:account_holder_id]))
        |> evaluate_lazy_attributes()
      end

      defp ensure_anchor(%{legal_entity_id: _} = attrs, _tenant_id), do: attrs
      defp ensure_anchor(%{payment_account_id: _} = attrs, _tenant_id), do: attrs

      defp ensure_anchor(%{account_holder_id: ah_id} = attrs, tenant_id)
           when not is_nil(ah_id) do
        le =
          insert(:legal_entity,
            tenant_id: tenant_id,
            account_holder_id: ah_id,
            subject_type: :account_holder
          )

        attrs
        |> Map.put(:legal_entity_id, le.id)
        |> Map.delete(:account_holder_id)
      end

      defp ensure_anchor(attrs, tenant_id) do
        ah = insert(:account_holder, tenant_id: tenant_id)

        le =
          insert(:legal_entity,
            tenant_id: tenant_id,
            account_holder_id: ah.id,
            subject_type: :account_holder
          )

        Map.put(attrs, :legal_entity_id, le.id)
      end

      defp infer_scope(%{payment_account_id: pa_id}) when not is_nil(pa_id),
        do: :payment_account

      defp infer_scope(_attrs), do: :account_holder
    end
  end
end

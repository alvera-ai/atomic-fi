defmodule AtomicFi.Factory.DocumentFactory do
  @moduledoc """
  Factory for Document context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias AtomicFi.DocumentContext.Document

      def document_factory(attrs \\ %{}) do
        tenant_id =
          Map.get_lazy(attrs, :tenant_id, fn ->
            insert(:tenant).id
          end)

        account_holder_id =
          Map.get_lazy(attrs, :account_holder_id, fn ->
            insert(:account_holder, tenant_id: tenant_id).id
          end)

        %Document{
          document_type: :identity_document,
          name: "kyc_passport",
          status: :draft,
          primary: true,
          account_holder_id: account_holder_id,
          tenant_id: tenant_id
        }
        |> merge_attributes(attrs)
        |> evaluate_lazy_attributes()
      end
    end
  end
end

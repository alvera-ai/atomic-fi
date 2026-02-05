defmodule PaymentCompliancePlatform.Factory.BlocklistEntryFactory do
  @moduledoc """
  Factory for BlocklistEntry context schemas.
  """

  defmacro __using__(_opts) do
    quote do
      alias PaymentCompliancePlatform.BlocklistContext.BlocklistEntry

      def blocklist_entry_factory do
        unique_suffix = String.slice(Ecto.UUID.generate(), 0, 8)

        %BlocklistEntry{
          scope: Enum.random([:first_name, :last_name, :company_name]),
          entry_type: Enum.random([:exact, :regex]),
          term: "blocked_term_" <> unique_suffix,
          reason: "Test blocklist entry - " <> unique_suffix,
          active: true
        }
      end
    end
  end
end

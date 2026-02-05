defmodule PaymentCompliancePlatform.DecisionContextFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `PaymentCompliancePlatform.DecisionContext` context.
  """

  @doc """
  Generate a decision.
  """
  def decision_fixture(attrs \\ %{}) do
    {:ok, decision} =
      attrs
      |> Enum.into(%{
        account_holder_name: "some account_holder_name",
        account_holder_type: "some account_holder_type",
        entities_with_matches: 42,
        list_synced_at: ~U[2026-02-04 17:51:00.000000Z],
        list_version: "some list_version",
        overall_status: "some overall_status",
        total_entities_screened: 42
      })
      |> PaymentCompliancePlatform.DecisionContext.create_decision()

    decision
  end
end

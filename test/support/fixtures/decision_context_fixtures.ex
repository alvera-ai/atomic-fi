defmodule PaymentCompliancePlatform.DecisionContextFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `PaymentCompliancePlatform.DecisionContext` context.
  """

  import PaymentCompliancePlatform.DataCase, only: [system_session: 0]
  import PaymentCompliancePlatform.AccountHolderContextFixtures

  @doc """
  Generate a decision.
  """
  def decision_fixture(attrs \\ %{}) do
    session = system_session()
    account_holder = account_holder_fixture()

    {:ok, decision} =
      attrs
      |> Enum.into(%{
        account_holder_id: account_holder.id,
        overall_status: "pass",
        total_entities_screened: 42,
        entities_with_matches: 0,
        list_synced_at: ~U[2026-02-04 17:51:00.000000Z],
        list_sources: %{lists: %{"us_ofac" => 100}, version: "1.0"},
        tenant_id: session.tenant_id
      })
      |> then(&PaymentCompliancePlatform.DecisionContext.create_decision(session, &1))

    decision
  end
end

defmodule AtomicFi.ComplianceScreeningContext.ScreeningWorkerTest do
  use AtomicFi.DataCase

  alias AtomicFi.ComplianceScreeningContext.ScreeningWorker

  setup %{session: session} do
    init_blocklist_cache(session.tenant_id)
    :ok
  end

  describe "perform/1 — account_holder" do
    test "screens an account holder via the worker", %{session: session} do
      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Alice",
          last_name: "Worker"
        )

      account_holder =
        insert(:account_holder,
          tenant_id: session.tenant_id,
          legal_entity_id: legal_entity.id
        )

      job = %Oban.Job{
        args: %{
          "subject" => "account_holder",
          "account_holder_id" => account_holder.id,
          "tenant_id" => session.tenant_id
        }
      }

      assert :ok = ScreeningWorker.perform(job)
    end
  end

  describe "perform/1 — beneficial_owner" do
    test "screens a beneficial owner via the worker", %{session: session} do
      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Bob",
          last_name: "BO"
        )

      account_holder =
        insert(:account_holder,
          tenant_id: session.tenant_id,
          legal_entity_id: legal_entity.id
        )

      bo_legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Charlie",
          last_name: "Owner"
        )

      bo =
        insert(:beneficial_owner,
          tenant_id: session.tenant_id,
          account_holder_id: account_holder.id,
          legal_entity_id: bo_legal_entity.id
        )

      job = %Oban.Job{
        args: %{
          "subject" => "beneficial_owner",
          "account_holder_id" => account_holder.id,
          "beneficial_owner_id" => bo.id,
          "tenant_id" => session.tenant_id
        }
      }

      assert :ok = ScreeningWorker.perform(job)
    end
  end

  describe "perform/1 — counterparty" do
    test "screens a counterparty via the worker", %{session: session} do
      ah_legal_entity =
        insert(:legal_entity, tenant_id: session.tenant_id, first_name: "X", last_name: "Y")

      account_holder =
        insert(:account_holder,
          tenant_id: session.tenant_id,
          legal_entity_id: ah_legal_entity.id
        )

      cp_legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Counter",
          last_name: "Party"
        )

      cp =
        insert(:counterparty,
          tenant_id: session.tenant_id,
          account_holder_id: account_holder.id,
          legal_entity_id: cp_legal_entity.id
        )

      job = %Oban.Job{
        args: %{
          "subject" => "counterparty",
          "account_holder_id" => account_holder.id,
          "counterparty_id" => cp.id,
          "tenant_id" => session.tenant_id
        }
      }

      assert :ok = ScreeningWorker.perform(job)
    end
  end
end

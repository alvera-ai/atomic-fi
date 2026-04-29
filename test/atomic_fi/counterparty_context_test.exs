defmodule AtomicFi.CounterpartyContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.CounterpartyContext
  alias AtomicFi.CounterpartyContext.Counterparty
  alias AtomicFi.OpenApiSchema.CounterpartyRequest
  import AtomicFi.Factory

  describe "counterparties" do
    test "list_counterparties/1 returns all counterparties for tenant", %{session: session} do
      insert(:counterparty, tenant_id: session.tenant_id)
      {:ok, {counterparties, _meta}} = CounterpartyContext.list_counterparties(session)
      assert counterparties != []
    end

    test "get_counterparty!/2 returns the counterparty with given id", %{session: session} do
      counterparty = insert(:counterparty, tenant_id: session.tenant_id)

      assert %Counterparty{id: id} =
               CounterpartyContext.get_counterparty!(session, counterparty.id)

      assert id == counterparty.id
    end

    test "create_counterparty/2 with valid data creates a counterparty", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      request = %CounterpartyRequest{
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id,
        status: :active,
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:ok, %Counterparty{} = counterparty} =
               CounterpartyContext.create_counterparty(session, request)

      assert counterparty.account_holder_id == account_holder.id
      assert counterparty.legal_entity_id == legal_entity.id
      assert counterparty.status == :active
      assert counterparty.tenant_id == session.tenant_id
    end

    test "create_counterparty/2 with optional counterparty_number", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      request = %CounterpartyRequest{
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id,
        status: :active,
        counterparty_number: "CP-001",
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:ok, %Counterparty{} = counterparty} =
               CounterpartyContext.create_counterparty(session, request)

      assert counterparty.counterparty_number == "CP-001"
    end

    test "create_counterparty/2 with invalid data returns error changeset", %{session: session} do
      request = %CounterpartyRequest{
        status: nil,
        chain_screening: false
      }

      assert {:error, %Ecto.Changeset{}} =
               CounterpartyContext.create_counterparty(session, request)
    end

    test "create_counterparty/2 enforces unique (account_holder_id, legal_entity_id)", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      request = %CounterpartyRequest{
        account_holder_id: account_holder.id,
        legal_entity_id: legal_entity.id,
        status: :active,
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:ok, _} = CounterpartyContext.create_counterparty(session, request)

      assert {:error, %Ecto.Changeset{}} =
               CounterpartyContext.create_counterparty(session, request)
    end

    test "update_counterparty/3 with valid data updates the counterparty", %{session: session} do
      counterparty = insert(:counterparty, tenant_id: session.tenant_id)

      request = %CounterpartyRequest{
        account_holder_id: counterparty.account_holder_id,
        legal_entity_id: counterparty.legal_entity_id,
        status: :suspended,
        tenant_id: session.tenant_id,
        chain_screening: false
      }

      assert {:ok, %Counterparty{} = updated} =
               CounterpartyContext.update_counterparty(session, counterparty, request)

      assert updated.status == :suspended
    end

    test "update_counterparty/3 with invalid data returns error changeset", %{session: session} do
      counterparty = insert(:counterparty, tenant_id: session.tenant_id)

      # Non-existent legal_entity_id trips foreign_key_constraint — nil values are
      # stripped by ExOpenApiUtils.Mapper and don't propagate, so use a live bad value.
      request = %CounterpartyRequest{
        legal_entity_id: Ecto.UUID.generate(),
        status: :suspended,
        chain_screening: false
      }

      assert {:error, %Ecto.Changeset{}} =
               CounterpartyContext.update_counterparty(session, counterparty, request)
    end

    test "delete_counterparty/2 deletes the counterparty", %{session: session} do
      counterparty = insert(:counterparty, tenant_id: session.tenant_id)

      assert {:ok, %Counterparty{}} =
               CounterpartyContext.delete_counterparty(session, counterparty)

      assert_raise Ecto.NoResultsError, fn ->
        CounterpartyContext.get_counterparty!(session, counterparty.id)
      end
    end

    test "change_counterparty/1 returns a counterparty changeset", %{session: session} do
      counterparty = insert(:counterparty, tenant_id: session.tenant_id)
      assert %Ecto.Changeset{} = CounterpartyContext.change_counterparty(counterparty)
    end
  end
end

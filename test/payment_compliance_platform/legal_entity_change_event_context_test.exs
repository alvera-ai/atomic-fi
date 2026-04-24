defmodule PaymentCompliancePlatform.LegalEntityChangeEventContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.LegalEntityChangeEventContext
  alias PaymentCompliancePlatform.LegalEntityChangeEventContext.LegalEntityChangeEvent
  alias PaymentCompliancePlatform.LegalEntityContext
  alias PaymentCompliancePlatform.OpenApiSchema.LegalEntityChangeEventRequest
  alias PaymentCompliancePlatform.OpenApiSchema.LegalEntityRequest
  import PaymentCompliancePlatform.Factory

  defp make_request(session, legal_entity_id, attrs \\ %{}) do
    base = %LegalEntityChangeEventRequest{
      event_type: :address_change,
      change_channel: :web,
      legal_entity_id: legal_entity_id,
      tenant_id: session.tenant_id
    }

    Map.merge(base, attrs)
  end

  describe "legal entity change events — CRUD" do
    test "list_legal_entity_change_events/1 returns all events for tenant", %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      insert(:legal_entity_change_event,
        tenant_id: session.tenant_id,
        legal_entity_id: legal_entity.id
      )

      {:ok, {events, _meta}} =
        LegalEntityChangeEventContext.list_legal_entity_change_events(session)

      assert events != []
    end

    test "list_legal_entity_change_events/1 returns own tenant records", %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      own =
        insert(:legal_entity_change_event,
          tenant_id: session.tenant_id,
          legal_entity_id: legal_entity.id
        )

      {:ok, {events, _meta}} =
        LegalEntityChangeEventContext.list_legal_entity_change_events(session)

      ids = Enum.map(events, & &1.id)
      assert own.id in ids
    end

    test "get_legal_entity_change_event!/2 returns the event with given id", %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      event =
        insert(:legal_entity_change_event,
          tenant_id: session.tenant_id,
          legal_entity_id: legal_entity.id
        )

      assert %LegalEntityChangeEvent{id: id} =
               LegalEntityChangeEventContext.get_legal_entity_change_event!(session, event.id)

      assert id == event.id
    end

    test "create_legal_entity_change_event/2 with minimal valid data creates an event", %{
      session: session
    } do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)
      request = make_request(session, legal_entity.id)

      assert {:ok, %LegalEntityChangeEvent{} = event} =
               LegalEntityChangeEventContext.create_legal_entity_change_event(session, request)

      assert event.event_type == :address_change
      assert event.change_channel == :web
      assert event.legal_entity_id == legal_entity.id
      assert event.tenant_id == session.tenant_id
    end

    test "create_legal_entity_change_event/2 defaults event_status to :pending", %{
      session: session
    } do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)
      request = make_request(session, legal_entity.id)

      assert {:ok, %LegalEntityChangeEvent{} = event} =
               LegalEntityChangeEventContext.create_legal_entity_change_event(session, request)

      assert event.event_status == :pending
    end

    test "create_legal_entity_change_event/2 with all event types", %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      for type <- [
            :address_change,
            :phone_change,
            :email_change,
            :beneficiary_added,
            :beneficiary_removed,
            :beneficiary_modified,
            :account_inquiry,
            :contact_info_change,
            :authorised_signer_change
          ] do
        request = make_request(session, legal_entity.id, %{event_type: type})

        assert {:ok, %LegalEntityChangeEvent{} = event} =
                 LegalEntityChangeEventContext.create_legal_entity_change_event(session, request)

        assert event.event_type == type
      end
    end

    test "create_legal_entity_change_event/2 with acmt references", %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      request = %LegalEntityChangeEventRequest{
        event_type: :phone_change,
        change_channel: :mobile,
        acmt_instruction_id: "MSG-2026-001",
        acmt_confirmation_id: "CONF-2026-001",
        legal_entity_id: legal_entity.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %LegalEntityChangeEvent{} = event} =
               LegalEntityChangeEventContext.create_legal_entity_change_event(session, request)

      assert event.acmt_instruction_id == "MSG-2026-001"
      assert event.acmt_confirmation_id == "CONF-2026-001"
    end

    test "create_legal_entity_change_event/2 with invalid data returns error changeset", %{
      session: session
    } do
      request = %LegalEntityChangeEventRequest{
        event_type: nil,
        change_channel: nil,
        legal_entity_id: nil,
        tenant_id: session.tenant_id
      }

      assert {:error, %Ecto.Changeset{}} =
               LegalEntityChangeEventContext.create_legal_entity_change_event(session, request)
    end

    test "create_legal_entity_change_event/2 enforces unique acmt_instruction_id per tenant", %{
      session: session
    } do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      make_req = fn ->
        %LegalEntityChangeEventRequest{
          event_type: :address_change,
          change_channel: :web,
          acmt_instruction_id: "DEDUP-MSG-001",
          legal_entity_id: legal_entity.id,
          tenant_id: session.tenant_id
        }
      end

      assert {:ok, _} =
               LegalEntityChangeEventContext.create_legal_entity_change_event(
                 session,
                 make_req.()
               )

      assert {:error, changeset} =
               LegalEntityChangeEventContext.create_legal_entity_change_event(
                 session,
                 make_req.()
               )

      errors = errors_on(changeset)

      assert Map.get(errors, :acmt_instruction_id) == ["has already been taken"] or
               Map.get(errors, :tenant_id) == ["has already been taken"]
    end

    test "create_legal_entity_change_event/2 allows nil acmt_instruction_id for multiple events",
         %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      make_req = fn ->
        make_request(session, legal_entity.id)
      end

      assert {:ok, _} =
               LegalEntityChangeEventContext.create_legal_entity_change_event(
                 session,
                 make_req.()
               )

      assert {:ok, _} =
               LegalEntityChangeEventContext.create_legal_entity_change_event(
                 session,
                 make_req.()
               )
    end

    test "update_legal_entity_change_event/3 updates mutable fields", %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      event =
        insert(:legal_entity_change_event,
          tenant_id: session.tenant_id,
          legal_entity_id: legal_entity.id,
          event_status: :pending
        )

      request = %LegalEntityChangeEventRequest{
        event_type: event.event_type,
        change_channel: :branch,
        event_status: :confirmed,
        acmt_confirmation_id: "CONF-2026-999",
        legal_entity_id: legal_entity.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %LegalEntityChangeEvent{} = updated} =
               LegalEntityChangeEventContext.update_legal_entity_change_event(
                 session,
                 event,
                 request
               )

      assert updated.event_status == :confirmed
      assert updated.change_channel == :branch
      assert updated.acmt_confirmation_id == "CONF-2026-999"
    end

    test "update_legal_entity_change_event/3 does not update legal_entity_id (immutable)", %{
      session: session
    } do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)
      other_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      event =
        insert(:legal_entity_change_event,
          tenant_id: session.tenant_id,
          legal_entity_id: legal_entity.id
        )

      request = %LegalEntityChangeEventRequest{
        event_type: event.event_type,
        change_channel: event.change_channel,
        event_status: :confirmed,
        # This should be ignored — legal_entity_id is immutable
        legal_entity_id: other_entity.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %LegalEntityChangeEvent{} = updated} =
               LegalEntityChangeEventContext.update_legal_entity_change_event(
                 session,
                 event,
                 request
               )

      # legal_entity_id must not have changed
      assert updated.legal_entity_id == legal_entity.id
    end

    test "delete_legal_entity_change_event/2 deletes the event", %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      event =
        insert(:legal_entity_change_event,
          tenant_id: session.tenant_id,
          legal_entity_id: legal_entity.id
        )

      assert {:ok, %LegalEntityChangeEvent{}} =
               LegalEntityChangeEventContext.delete_legal_entity_change_event(session, event)

      assert_raise Ecto.NoResultsError, fn ->
        LegalEntityChangeEventContext.get_legal_entity_change_event!(session, event.id)
      end
    end

    test "change_legal_entity_change_event/1 returns a changeset", %{session: session} do
      legal_entity = insert(:legal_entity, tenant_id: session.tenant_id)

      event =
        insert(:legal_entity_change_event,
          tenant_id: session.tenant_id,
          legal_entity_id: legal_entity.id
        )

      assert %Ecto.Changeset{} =
               LegalEntityChangeEventContext.change_legal_entity_change_event(event)
    end
  end

  describe "auto-creation via update_legal_entity" do
    test "update_legal_entity/3 creates a LegalEntityChangeEvent with JSONB diff", %{
      session: session
    } do
      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          legal_entity_type: :individual,
          first_name: "John",
          last_name: "Doe"
        )

      request = %LegalEntityRequest{
        legal_entity_type: :individual,
        first_name: "Jane",
        last_name: "Doe",
        tenant_id: session.tenant_id
      }

      assert {:ok, updated} =
               LegalEntityContext.update_legal_entity(session, legal_entity, request)

      {:ok, {events, _}} =
        LegalEntityChangeEventContext.list_legal_entity_change_events(session)

      event = Enum.find(events, &(&1.legal_entity_id == legal_entity.id))

      assert event != nil
      # Trigger should have flipped status to :recorded
      assert event.event_status == :recorded
      # JSONB diff should capture first_name change
      assert event.changes["first_name"] == ["John", "Jane"]
      # previous_state should have old first_name
      assert event.previous_state["first_name"] == "John"
      # Trigger should have updated legal_entity.latest_change_event_id
      assert updated.latest_change_event_id == event.id
    end

    test "update_legal_entity/3 does NOT create a change event when no fields change", %{
      session: session
    } do
      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          legal_entity_type: :individual,
          first_name: "John",
          last_name: "Doe",
          middle_name: nil,
          prefix: nil,
          suffix: nil,
          preferred_name: nil,
          date_of_birth: nil,
          citizenship_country: nil,
          politically_exposed_person: nil,
          business_name: nil,
          doing_business_as_names: [],
          date_formed: nil,
          website: nil,
          subject_type: nil,
          legal_structure: nil
        )

      # Exactly matching values — changeset.changes will be %{}
      request = %LegalEntityRequest{
        legal_entity_type: :individual,
        first_name: "John",
        last_name: "Doe",
        middle_name: nil,
        prefix: nil,
        suffix: nil,
        preferred_name: nil,
        date_of_birth: nil,
        citizenship_country: nil,
        politically_exposed_person: nil,
        business_name: nil,
        doing_business_as_names: [],
        date_formed: nil,
        website: nil,
        subject_type: nil,
        legal_structure: nil,
        tenant_id: session.tenant_id
      }

      {:ok, {events_before, _}} =
        LegalEntityChangeEventContext.list_legal_entity_change_events(session)

      count_before = length(events_before)

      assert {:ok, _updated} =
               LegalEntityContext.update_legal_entity(session, legal_entity, request)

      {:ok, {events_after, _}} =
        LegalEntityChangeEventContext.list_legal_entity_change_events(session)

      assert length(events_after) == count_before
    end

    test "create_legal_entity/2 does NOT create a change event (only updates do)", %{
      session: session
    } do
      {:ok, {events_before, _}} =
        LegalEntityChangeEventContext.list_legal_entity_change_events(session)

      count_before = length(events_before)

      request = %LegalEntityRequest{
        legal_entity_type: :individual,
        first_name: "Alice",
        tenant_id: session.tenant_id
      }

      assert {:ok, _} = LegalEntityContext.create_legal_entity(session, request)

      {:ok, {events_after, _}} =
        LegalEntityChangeEventContext.list_legal_entity_change_events(session)

      assert length(events_after) == count_before
    end

    test "update_legal_entity/3 infers event_type from changed fields", %{session: session} do
      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          legal_entity_type: :individual,
          first_name: "John"
        )

      request = %LegalEntityRequest{
        legal_entity_type: :individual,
        first_name: "Johnny",
        tenant_id: session.tenant_id
      }

      assert {:ok, _updated} =
               LegalEntityContext.update_legal_entity(session, legal_entity, request)

      {:ok, {events, _}} =
        LegalEntityChangeEventContext.list_legal_entity_change_events(session)

      event = Enum.find(events, &(&1.legal_entity_id == legal_entity.id))

      assert event != nil
      assert event.event_type == :contact_info_change
    end
  end
end

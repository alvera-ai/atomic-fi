defmodule AtomicFi.ComplianceScreeningContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.ComplianceScreeningContext
  alias AtomicFi.ComplianceScreeningContext.BlocklistMatch
  alias AtomicFi.ComplianceScreeningContext.ComplianceScreening
  alias AtomicFi.ComplianceScreeningContext.SanctionsMatch

  import AtomicFi.Factory

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # fetch_suppressed_source_ids/1 calls Repo.all/2 without a session — this works
  # only with the DataCase system_session (which belongs to the seeded system tenant
  # that owns the sandbox connection). For screening tests we reuse the system_session
  # from DataCase setup and simply init the blocklist cache.
  defp init_session_cache(%{session: session}) do
    init_blocklist_cache(session.tenant_id)
    session
  end

  defp compliance_screening_attrs(account_holder_id, tenant_id) do
    %{
      scope: :account_holder,
      screening_type: :sanctions,
      screening_status: :pass,
      screened_entity_type: :individual,
      screened_entity_name: "Alice Smith",
      account_holder_id: account_holder_id,
      tenant_id: tenant_id
    }
  end

  # Insert a ComplianceScreening with child SanctionsMatch rows directly
  defp insert_screening_with_sanctions(session, account_holder_id, sanctions_matches) do
    alias AtomicFi.ComplianceScreeningContext.ComplianceScreening
    alias AtomicFi.ComplianceScreeningContext.SanctionsMatch

    {:ok, cs} =
      ComplianceScreeningContext.create_compliance_screening(session, %{
        scope: :account_holder,
        screening_type: :sanctions,
        screening_status: :potential_match,
        screened_entity_type: :individual,
        screened_entity_name: "Test User",
        match_count: length(sanctions_matches),
        account_holder_id: account_holder_id,
        tenant_id: session.tenant_id
      })

    inserted_matches =
      Enum.map(sanctions_matches, fn attrs ->
        %SanctionsMatch{}
        |> SanctionsMatch.changeset(Map.merge(attrs, %{compliance_screening_id: cs.id}))
        |> Repo.insert!(session: session)
      end)

    {cs, inserted_matches}
  end

  # Insert a ComplianceScreening with child BlocklistMatch rows directly
  defp insert_screening_with_blocklist(session, account_holder_id, blocklist_matches) do
    alias AtomicFi.ComplianceScreeningContext.BlocklistMatch

    {:ok, cs} =
      ComplianceScreeningContext.create_compliance_screening(session, %{
        scope: :account_holder,
        screening_type: :sanctions,
        screening_status: :blocked,
        screened_entity_type: :individual,
        screened_entity_name: "John Doe",
        account_holder_id: account_holder_id,
        tenant_id: session.tenant_id
      })

    inserted_matches =
      Enum.map(blocklist_matches, fn attrs ->
        %BlocklistMatch{}
        |> BlocklistMatch.changeset(Map.merge(attrs, %{compliance_screening_id: cs.id}))
        |> Repo.insert!(session: session)
      end)

    {cs, inserted_matches}
  end

  # ---------------------------------------------------------------------------
  # ComplianceScreening CRUD
  # ---------------------------------------------------------------------------

  describe "list_compliance_screenings/2" do
    test "returns all compliance screenings for the tenant", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {:ok, cs} =
        ComplianceScreeningContext.create_compliance_screening(
          session,
          compliance_screening_attrs(account_holder.id, session.tenant_id)
        )

      {:ok, {screenings, _meta}} =
        ComplianceScreeningContext.list_compliance_screenings(session)

      ids = Enum.map(screenings, & &1.id)
      assert cs.id in ids
    end

    # NOTE: Cross-tenant RLS isolation cannot be tested with system_session —
    # system_session is a platform admin that bypasses RLS entirely.
    # See MEMORY.md: "RLS Isolation Tests" section.
  end

  describe "get_compliance_screening!/2" do
    test "returns the compliance screening with given id", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {:ok, cs} =
        ComplianceScreeningContext.create_compliance_screening(
          session,
          compliance_screening_attrs(account_holder.id, session.tenant_id)
        )

      result = ComplianceScreeningContext.get_compliance_screening!(session, cs.id)
      assert result.id == cs.id
    end

    test "raises Ecto.NoResultsError for unknown id", %{session: session} do
      assert_raise Ecto.NoResultsError, fn ->
        ComplianceScreeningContext.get_compliance_screening!(session, Ecto.UUID.generate())
      end
    end
  end

  describe "create_compliance_screening/2" do
    test "with valid data creates a compliance screening", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      assert {:ok, %ComplianceScreening{} = cs} =
               ComplianceScreeningContext.create_compliance_screening(
                 session,
                 compliance_screening_attrs(account_holder.id, session.tenant_id)
               )

      assert cs.scope == :account_holder
      assert cs.screening_type == :sanctions
      assert cs.screening_status == :pass
      assert cs.screened_entity_type == :individual
      assert cs.screened_entity_name == "Alice Smith"
      assert cs.account_holder_id == account_holder.id
      assert cs.tenant_id == session.tenant_id
    end

    test "with optional fields creates a compliance screening", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      attrs =
        compliance_screening_attrs(account_holder.id, session.tenant_id)
        |> Map.merge(%{
          screening_score: Decimal.new("75.5"),
          match_count: 2,
          pep_indicator: true,
          pep_list_name: "EU PEP List",
          compliance_screening_number: "CS-2024-001"
        })

      assert {:ok, %ComplianceScreening{} = cs} =
               ComplianceScreeningContext.create_compliance_screening(session, attrs)

      assert cs.pep_indicator == true
      assert cs.pep_list_name == "EU PEP List"
      assert cs.match_count == 2
      assert cs.compliance_screening_number == "CS-2024-001"
    end

    test "with counterparty scope sets counterparty_id", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)
      counterparty = insert(:counterparty, tenant_id: session.tenant_id)

      attrs =
        compliance_screening_attrs(account_holder.id, session.tenant_id)
        |> Map.merge(%{scope: :counterparty, counterparty_id: counterparty.id})

      assert {:ok, %ComplianceScreening{} = cs} =
               ComplianceScreeningContext.create_compliance_screening(session, attrs)

      assert cs.scope == :counterparty
      assert cs.counterparty_id == counterparty.id
    end

    test "with invalid data (missing required fields) returns error changeset", %{
      session: session
    } do
      assert {:error, %Ecto.Changeset{}} =
               ComplianceScreeningContext.create_compliance_screening(session, %{
                 screening_type: :sanctions
               })
    end

    test "with invalid screening_score returns error changeset", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      attrs =
        compliance_screening_attrs(account_holder.id, session.tenant_id)
        |> Map.put(:screening_score, Decimal.new("150.0"))

      assert {:error, %Ecto.Changeset{}} =
               ComplianceScreeningContext.create_compliance_screening(session, attrs)
    end

    test "with invalid escalation_level returns error changeset", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      attrs =
        compliance_screening_attrs(account_holder.id, session.tenant_id)
        |> Map.put(:escalation_level, 10)

      assert {:error, %Ecto.Changeset{}} =
               ComplianceScreeningContext.create_compliance_screening(session, attrs)
    end
  end

  describe "update_compliance_screening/3" do
    test "with valid data updates the compliance screening", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {:ok, cs} =
        ComplianceScreeningContext.create_compliance_screening(
          session,
          compliance_screening_attrs(account_holder.id, session.tenant_id)
        )

      assert {:ok, %ComplianceScreening{} = updated} =
               ComplianceScreeningContext.update_compliance_screening(session, cs, %{
                 screening_status: :potential_match,
                 manual_review_required: true,
                 review_notes: "Needs review"
               })

      assert updated.screening_status == :potential_match
      assert updated.manual_review_required == true
      assert updated.review_notes == "Needs review"
    end

    test "with invalid data returns error changeset", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {:ok, cs} =
        ComplianceScreeningContext.create_compliance_screening(
          session,
          compliance_screening_attrs(account_holder.id, session.tenant_id)
        )

      assert {:error, %Ecto.Changeset{}} =
               ComplianceScreeningContext.update_compliance_screening(session, cs, %{
                 scope: nil
               })
    end
  end

  describe "delete_compliance_screening/2" do
    test "deletes the compliance screening", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {:ok, cs} =
        ComplianceScreeningContext.create_compliance_screening(
          session,
          compliance_screening_attrs(account_holder.id, session.tenant_id)
        )

      assert {:ok, %ComplianceScreening{}} =
               ComplianceScreeningContext.delete_compliance_screening(session, cs)

      assert_raise Ecto.NoResultsError, fn ->
        ComplianceScreeningContext.get_compliance_screening!(session, cs.id)
      end
    end
  end

  describe "change_compliance_screening/2" do
    test "returns a changeset", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {:ok, cs} =
        ComplianceScreeningContext.create_compliance_screening(
          session,
          compliance_screening_attrs(account_holder.id, session.tenant_id)
        )

      assert %Ecto.Changeset{} = ComplianceScreeningContext.change_compliance_screening(cs)
    end

    test "returns a changeset with given attrs", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {:ok, cs} =
        ComplianceScreeningContext.create_compliance_screening(
          session,
          compliance_screening_attrs(account_holder.id, session.tenant_id)
        )

      changeset =
        ComplianceScreeningContext.change_compliance_screening(cs, %{
          review_notes: "Note"
        })

      assert %Ecto.Changeset{} = changeset
      assert changeset.changes[:review_notes] == "Note"
    end
  end

  # ---------------------------------------------------------------------------
  # SanctionsMatch CRUD
  # ---------------------------------------------------------------------------

  describe "list_sanctions_matches/3" do
    test "returns sanctions matches for a compliance screening", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {cs, _} =
        insert_screening_with_sanctions(session, account_holder.id, [
          %{
            matched_name: "Vladimir Vladimirovich PUTIN",
            match_score: 0.73,
            source_list: "us_ofac",
            sanctions_match_type: :fuzzy,
            false_positive_qualifier: :none,
            tenant_id: session.tenant_id
          }
        ])

      {:ok, {matches, _meta}} =
        ComplianceScreeningContext.list_sanctions_matches(session, cs.id)

      assert length(matches) == 1
      assert hd(matches).matched_name == "Vladimir Vladimirovich PUTIN"
    end

    test "returns empty list for screening with no sanctions matches", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {:ok, cs} =
        ComplianceScreeningContext.create_compliance_screening(
          session,
          compliance_screening_attrs(account_holder.id, session.tenant_id)
        )

      {:ok, {matches, _meta}} =
        ComplianceScreeningContext.list_sanctions_matches(session, cs.id)

      assert matches == []
    end
  end

  describe "update_sanctions_match/3" do
    test "updates false_positive_qualifier to manual_override", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {cs, [sm]} =
        insert_screening_with_sanctions(session, account_holder.id, [
          %{
            matched_name: "TEST ENTITY",
            match_score: 0.75,
            source_list: "us_ofac",
            sanctions_match_type: :fuzzy,
            false_positive_qualifier: :none,
            tenant_id: session.tenant_id
          }
        ])

      {:ok, {[listed_sm], _}} = ComplianceScreeningContext.list_sanctions_matches(session, cs.id)
      assert listed_sm.id == sm.id

      assert {:ok, %SanctionsMatch{} = updated} =
               ComplianceScreeningContext.update_sanctions_match(session, listed_sm, %{
                 false_positive_qualifier: :manual_override,
                 review_notes: "Known entity — confirmed not a match"
               })

      assert updated.false_positive_qualifier == :manual_override
      assert updated.review_notes == "Known entity — confirmed not a match"
    end

    test "returns error changeset for invalid update", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {cs, _} =
        insert_screening_with_sanctions(session, account_holder.id, [
          %{
            matched_name: "TEST ENTITY",
            match_score: 0.75,
            source_list: "us_ofac",
            sanctions_match_type: :fuzzy,
            false_positive_qualifier: :none,
            tenant_id: session.tenant_id
          }
        ])

      {:ok, {[sm], _}} = ComplianceScreeningContext.list_sanctions_matches(session, cs.id)

      # matched_name is required — setting to nil should fail
      assert {:error, %Ecto.Changeset{}} =
               ComplianceScreeningContext.update_sanctions_match(session, sm, %{
                 matched_name: nil
               })
    end
  end

  # ---------------------------------------------------------------------------
  # BlocklistMatch CRUD
  # ---------------------------------------------------------------------------

  describe "list_blocklist_matches/3" do
    test "returns blocklist matches for a compliance screening", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {cs, _} =
        insert_screening_with_blocklist(session, account_holder.id, [
          %{
            matched_term: "john",
            match_type: :exact,
            scope: :first_name,
            tenant_id: session.tenant_id
          }
        ])

      {:ok, {matches, _meta}} =
        ComplianceScreeningContext.list_blocklist_matches(session, cs.id)

      assert length(matches) == 1
      assert hd(matches).matched_term == "john"
    end

    test "returns empty list for screening with no blocklist matches", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {:ok, cs} =
        ComplianceScreeningContext.create_compliance_screening(
          session,
          compliance_screening_attrs(account_holder.id, session.tenant_id)
        )

      {:ok, {matches, _meta}} =
        ComplianceScreeningContext.list_blocklist_matches(session, cs.id)

      assert matches == []
    end
  end

  describe "update_blocklist_match/3" do
    test "updates false_positive_qualifier to manual_override", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {cs, [bm]} =
        insert_screening_with_blocklist(session, account_holder.id, [
          %{
            matched_term: "john",
            match_type: :exact,
            scope: :first_name,
            tenant_id: session.tenant_id
          }
        ])

      {:ok, {[listed_bm], _}} = ComplianceScreeningContext.list_blocklist_matches(session, cs.id)
      assert listed_bm.id == bm.id

      assert {:ok, %BlocklistMatch{} = updated} =
               ComplianceScreeningContext.update_blocklist_match(session, listed_bm, %{
                 false_positive_qualifier: :manual_override,
                 review_notes: "Confirmed not a match"
               })

      assert updated.false_positive_qualifier == :manual_override
      assert updated.review_notes == "Confirmed not a match"
    end

    test "returns error changeset for invalid update", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      {cs, _} =
        insert_screening_with_blocklist(session, account_holder.id, [
          %{
            matched_term: "john",
            match_type: :exact,
            scope: :first_name,
            tenant_id: session.tenant_id
          }
        ])

      {:ok, {[bm], _}} = ComplianceScreeningContext.list_blocklist_matches(session, cs.id)

      # matched_term is required — setting to nil should fail
      assert {:error, %Ecto.Changeset{}} =
               ComplianceScreeningContext.update_blocklist_match(session, bm, %{
                 matched_term: nil
               })
    end
  end

  # ---------------------------------------------------------------------------
  # Screening — ISO 20022 entry points (real Watchman at localhost:8084)
  # Run `make backing-services` to start Watchman before running these tests.
  # ---------------------------------------------------------------------------

  describe "screen_account_holder/2" do
    test "screens a clean individual and returns pass or potential_match", %{session: session} do
      session = init_session_cache(%{session: session})

      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Alice",
          last_name: "Smith"
        )

      account_holder =
        insert(:account_holder, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)

      assert {:ok, [screening]} =
               ComplianceScreeningContext.screen_account_holder(session, %{
                 account_holder_id: account_holder.id
               })

      assert %ComplianceScreening{} = screening
      assert screening.scope == :account_holder
      assert screening.screening_type == :sanctions
      assert screening.screened_entity_type == :individual
      assert screening.screened_entity_name == "Alice Smith"
      assert screening.account_holder_id == account_holder.id
      assert screening.tenant_id == session.tenant_id
      assert screening.screening_status in [:pass, :potential_match, :blocked]
    end

    test "screens a blocklisted individual and returns blocked", %{session: session} do
      session = init_session_cache(%{session: session})
      seed_blocklist_for_tenant(session.tenant_id)

      legal_entity =
        insert(:legal_entity, tenant_id: session.tenant_id, first_name: "John", last_name: "Doe")

      account_holder =
        insert(:account_holder, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)

      assert {:ok, [screening]} =
               ComplianceScreeningContext.screen_account_holder(session, %{
                 account_holder_id: account_holder.id
               })

      assert screening.screening_status == :blocked
      assert screening.screened_entity_type == :individual
      assert screening.screened_entity_name == "John Doe"
    end

    test "screens a blocklisted business and returns blocked", %{session: session} do
      session = init_session_cache(%{session: session})
      seed_blocklist_for_tenant(session.tenant_id)

      legal_entity =
        insert(:business_legal_entity, tenant_id: session.tenant_id, business_name: "Acme")

      account_holder =
        insert(:account_holder, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)

      assert {:ok, [screening]} =
               ComplianceScreeningContext.screen_account_holder(session, %{
                 account_holder_id: account_holder.id
               })

      assert screening.screening_status == :blocked
      assert screening.screened_entity_type == :company
      assert screening.screened_entity_name == "Acme"
    end

    test "screens a known sanctioned individual and returns potential_match or blocked", %{
      session: session
    } do
      session = init_session_cache(%{session: session})

      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Vladimir",
          last_name: "Putin"
        )

      account_holder =
        insert(:account_holder, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)

      assert {:ok, [screening]} =
               ComplianceScreeningContext.screen_account_holder(session, %{
                 account_holder_id: account_holder.id
               })

      assert screening.screening_status in [:potential_match, :blocked]
      assert screening.match_count > 0
      assert screening.sanctions_matches != []
    end

    test "auto-suppresses previously overridden source_ids", %{session: session} do
      session = init_session_cache(%{session: session})

      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Vladimir",
          last_name: "Putin"
        )

      account_holder =
        insert(:account_holder, tenant_id: session.tenant_id, legal_entity_id: legal_entity.id)

      request = %{account_holder_id: account_holder.id}

      {:ok, [first_screening]} =
        ComplianceScreeningContext.screen_account_holder(session, request)

      # Mark the first sanctions match as a manual_override
      {:ok, {[sm | _], _}} =
        ComplianceScreeningContext.list_sanctions_matches(session, first_screening.id)

      {:ok, _} =
        ComplianceScreeningContext.update_sanctions_match(session, sm, %{
          false_positive_qualifier: :manual_override
        })

      # Re-screen — the overridden source_id should be auto_suppressed
      {:ok, [second_screening]} =
        ComplianceScreeningContext.screen_account_holder(session, request)

      {:ok, {second_matches, _}} =
        ComplianceScreeningContext.list_sanctions_matches(session, second_screening.id)

      suppressed = Enum.find(second_matches, &(&1.source_id == sm.source_id))

      if suppressed do
        assert suppressed.false_positive_qualifier == :auto_suppressed
      end
    end
  end

  describe "screen_beneficial_owner/2" do
    test "screens a clean individual beneficial owner and returns pass or potential_match", %{
      session: session
    } do
      session = init_session_cache(%{session: session})
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Clara",
          last_name: "Bennet"
        )

      beneficial_owner =
        insert(:beneficial_owner,
          tenant_id: session.tenant_id,
          account_holder_id: account_holder.id,
          legal_entity_id: legal_entity.id
        )

      assert {:ok, [screening]} =
               ComplianceScreeningContext.screen_beneficial_owner(session, %{
                 account_holder_id: account_holder.id,
                 beneficial_owner_id: beneficial_owner.id
               })

      assert %ComplianceScreening{} = screening
      assert screening.scope == :account_holder
      assert screening.screened_entity_name == "Clara Bennet"
      assert screening.screening_status in [:pass, :potential_match, :blocked]
    end

    test "screens a blocklisted beneficial owner and returns blocked", %{session: session} do
      session = init_session_cache(%{session: session})
      seed_blocklist_for_tenant(session.tenant_id)
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      legal_entity =
        insert(:legal_entity, tenant_id: session.tenant_id, first_name: "John", last_name: "Doe")

      beneficial_owner =
        insert(:beneficial_owner,
          tenant_id: session.tenant_id,
          account_holder_id: account_holder.id,
          legal_entity_id: legal_entity.id
        )

      assert {:ok, [screening]} =
               ComplianceScreeningContext.screen_beneficial_owner(session, %{
                 account_holder_id: account_holder.id,
                 beneficial_owner_id: beneficial_owner.id
               })

      assert screening.screening_status == :blocked
    end
  end

  describe "screen_counterparty/2" do
    test "screens a clean individual counterparty and returns pass or potential_match", %{
      session: session
    } do
      session = init_session_cache(%{session: session})
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Maria",
          last_name: "Garcia"
        )

      counterparty =
        insert(:counterparty,
          tenant_id: session.tenant_id,
          account_holder_id: account_holder.id,
          legal_entity_id: legal_entity.id
        )

      assert {:ok, [screening]} =
               ComplianceScreeningContext.screen_counterparty(session, %{
                 account_holder_id: account_holder.id,
                 counterparty_id: counterparty.id
               })

      assert %ComplianceScreening{} = screening
      assert screening.scope == :counterparty
      assert screening.counterparty_id == counterparty.id
      assert screening.account_holder_id == account_holder.id
      assert screening.screened_entity_name == "Maria Garcia"
    end

    test "screens a blocklisted company counterparty and returns blocked", %{session: session} do
      session = init_session_cache(%{session: session})
      seed_blocklist_for_tenant(session.tenant_id)
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      legal_entity =
        insert(:business_legal_entity, tenant_id: session.tenant_id, business_name: "Acme")

      counterparty =
        insert(:counterparty,
          tenant_id: session.tenant_id,
          account_holder_id: account_holder.id,
          legal_entity_id: legal_entity.id
        )

      assert {:ok, [screening]} =
               ComplianceScreeningContext.screen_counterparty(session, %{
                 account_holder_id: account_holder.id,
                 counterparty_id: counterparty.id
               })

      assert screening.screening_status == :blocked
      assert screening.scope == :counterparty
    end
  end
end

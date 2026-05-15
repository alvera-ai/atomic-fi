defmodule AtomicFi.ComplianceScreeningContextTest do
  use AtomicFi.DataCase

  alias AtomicFi.ComplianceScreeningContext
  alias AtomicFi.ComplianceScreeningContext.BlocklistMatch
  alias AtomicFi.ComplianceScreeningContext.ComplianceScreening
  alias AtomicFi.ComplianceScreeningContext.SanctionsMatch
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  alias AtomicFi.OpenApiSchema.BeneficialOwnerRequest
  alias AtomicFi.OpenApiSchema.CounterpartyRequest
  alias AtomicFi.OpenApiSchema.PaymentAccountRequest

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

  # ---------------------------------------------------------------------------
  # Stateless preview screening — *Request in, unsaved %ComplianceScreening{} out
  # ---------------------------------------------------------------------------

  describe "screen_account_holder/2 (preview)" do
    test "AHRequest with inline individual LE → unsaved struct with :pending status",
         %{session: session} do
      _ = init_session_cache(%{session: session})

      request = %AccountHolderRequest{
        tenant_id: session.tenant_id,
        holder_type: :individual,
        legal_entity: %{
          first_name: "Alice",
          last_name: "Smith",
          legal_entity_type: :individual
        }
      }

      assert {:ok, %ComplianceScreening{} = screening} =
               ComplianceScreeningContext.screen_account_holder(session, request)

      assert is_nil(screening.id)
      assert is_nil(screening.tenant_id)
      assert is_nil(screening.account_holder_id)
      assert screening.scope == :account_holder
      assert screening.screening_type == :sanctions
      assert screening.screening_status == :pending
      assert screening.screened_entity_type == :individual
      assert screening.screened_entity_name == "Alice Smith"
    end

    test "blocklisted individual surfaces a blocklist_match (status stays :pending)",
         %{session: session} do
      _ = init_session_cache(%{session: session})
      seed_blocklist_for_tenant(session.tenant_id)

      request = %AccountHolderRequest{
        tenant_id: session.tenant_id,
        holder_type: :individual,
        legal_entity: %{
          first_name: "John",
          last_name: "Doe",
          legal_entity_type: :individual
        }
      }

      assert {:ok, %ComplianceScreening{} = screening} =
               ComplianceScreeningContext.screen_account_holder(session, request)

      assert screening.screening_status == :pending
      refute screening.blocklist_matches == []
      assert screening.screened_entity_type == :individual
      assert screening.screened_entity_name == "John Doe"
    end

    test "AHRequest with inline business LE → :company entity type", %{session: session} do
      _ = init_session_cache(%{session: session})
      seed_blocklist_for_tenant(session.tenant_id)

      request = %AccountHolderRequest{
        tenant_id: session.tenant_id,
        holder_type: :business,
        legal_entity: %{
          business_name: "Acme",
          legal_entity_type: :business
        }
      }

      assert {:ok, screening} =
               ComplianceScreeningContext.screen_account_holder(session, request)

      assert screening.screened_entity_type == :company
      assert screening.screened_entity_name == "Acme"
      refute screening.blocklist_matches == []
    end

    test "Vladimir Putin produces sanctions_matches", %{session: session} do
      _ = init_session_cache(%{session: session})

      request = %AccountHolderRequest{
        tenant_id: session.tenant_id,
        holder_type: :individual,
        legal_entity: %{
          first_name: "Vladimir",
          last_name: "Putin",
          legal_entity_type: :individual
        }
      }

      assert {:ok, screening} =
               ComplianceScreeningContext.screen_account_holder(session, request)

      assert screening.match_count > 0
      assert screening.sanctions_matches != []
    end
  end

  describe "screen_beneficial_owner/2 (preview)" do
    test "BORequest with inline LE → unsaved %CS{} with scope :beneficial_owner",
         %{session: session} do
      _ = init_session_cache(%{session: session})

      request = %BeneficialOwnerRequest{
        tenant_id: session.tenant_id,
        account_holder_id: Ecto.UUID.generate(),
        control_type: :shareholder,
        legal_entity: %{
          first_name: "Clara",
          last_name: "Bennet",
          legal_entity_type: :individual
        }
      }

      assert {:ok, %ComplianceScreening{} = screening} =
               ComplianceScreeningContext.screen_beneficial_owner(session, request)

      assert is_nil(screening.id)
      assert screening.scope == :beneficial_owner
      assert screening.screened_entity_name == "Clara Bennet"
      assert screening.screening_status == :pending
    end
  end

  describe "screen_counterparty/2 (preview)" do
    test "CPRequest with inline LE → unsaved %CS{} with scope :counterparty",
         %{session: session} do
      _ = init_session_cache(%{session: session})

      request = %CounterpartyRequest{
        tenant_id: session.tenant_id,
        account_holder_id: Ecto.UUID.generate(),
        legal_entity: %{
          first_name: "Maria",
          last_name: "Garcia",
          legal_entity_type: :individual
        }
      }

      assert {:ok, %ComplianceScreening{} = screening} =
               ComplianceScreeningContext.screen_counterparty(session, request)

      assert is_nil(screening.id)
      assert screening.scope == :counterparty
      assert screening.screened_entity_name == "Maria Garcia"
      assert screening.screening_status == :pending
    end

    test "blocklisted business CP surfaces a blocklist_match", %{session: session} do
      _ = init_session_cache(%{session: session})
      seed_blocklist_for_tenant(session.tenant_id)

      request = %CounterpartyRequest{
        tenant_id: session.tenant_id,
        account_holder_id: Ecto.UUID.generate(),
        legal_entity: %{
          business_name: "Acme",
          legal_entity_type: :business
        }
      }

      assert {:ok, screening} =
               ComplianceScreeningContext.screen_counterparty(session, request)

      assert screening.scope == :counterparty
      refute screening.blocklist_matches == []
    end
  end

  describe "screen_payment_account/2 (preview)" do
    test "non-crypto rail returns a no-screen :pending result", %{session: session} do
      _ = init_session_cache(%{session: session})

      request = %PaymentAccountRequest{
        tenant_id: session.tenant_id,
        account_type: :bank_account,
        currency: "USD",
        account_holder_id: Ecto.UUID.generate()
      }

      assert {:ok, %ComplianceScreening{} = screening} =
               ComplianceScreeningContext.screen_payment_account(session, request)

      assert screening.scope == :payment_account
      assert screening.screening_status == :pending
      assert screening.match_count == 0
      assert screening.sanctions_matches == []
    end

    test "crypto wallet hits Watchman", %{session: session} do
      _ = init_session_cache(%{session: session})

      request = %PaymentAccountRequest{
        tenant_id: session.tenant_id,
        account_type: :crypto_wallet,
        currency: "BTC",
        wallet_address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa",
        wallet_chain: "XBT",
        account_holder_id: Ecto.UUID.generate()
      }

      assert {:ok, %ComplianceScreening{} = screening} =
               ComplianceScreeningContext.screen_payment_account(session, request)

      assert screening.scope == :payment_account
      assert screening.screened_entity_type == :crypto_address
      assert screening.screening_status == :pending
    end
  end

  describe "record_screening/3 (onboarding persistence)" do
    test "AH scope — persists with account_holder_id FK", %{session: session} do
      _ = init_session_cache(%{session: session})

      request = %AccountHolderRequest{
        tenant_id: session.tenant_id,
        holder_type: :individual,
        legal_entity: %{
          first_name: "Alice",
          last_name: "Smith",
          legal_entity_type: :individual
        }
      }

      {:ok, unsaved} = ComplianceScreeningContext.screen_account_holder(session, request)
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      assert {:ok, %ComplianceScreening{} = persisted} =
               ComplianceScreeningContext.record_screening(session, unsaved, %{
                 account_holder_id: account_holder.id
               })

      refute is_nil(persisted.id)
      assert persisted.tenant_id == session.tenant_id
      assert persisted.account_holder_id == account_holder.id
      assert persisted.scope == :account_holder
      assert persisted.screened_entity_name == "Alice Smith"
    end

    test "CP scope — persists with counterparty_id + account_holder_id FKs",
         %{session: session} do
      _ = init_session_cache(%{session: session})
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      counterparty_le =
        insert(:business_legal_entity,
          tenant_id: session.tenant_id,
          business_name: "Acme Corp #{System.unique_integer([:positive])}"
        )

      counterparty =
        insert(:counterparty,
          tenant_id: session.tenant_id,
          account_holder_id: account_holder.id,
          legal_entity_id: counterparty_le.id
        )

      request = %CounterpartyRequest{
        tenant_id: session.tenant_id,
        account_holder_id: account_holder.id,
        legal_entity: %{
          business_name: counterparty_le.business_name,
          legal_entity_type: :business
        }
      }

      {:ok, unsaved} = ComplianceScreeningContext.screen_counterparty(session, request)

      assert {:ok, %ComplianceScreening{} = persisted} =
               ComplianceScreeningContext.record_screening(session, unsaved, %{
                 account_holder_id: account_holder.id,
                 counterparty_id: counterparty.id
               })

      refute is_nil(persisted.id)
      assert persisted.scope == :counterparty
      assert persisted.account_holder_id == account_holder.id
      assert persisted.counterparty_id == counterparty.id
    end

    test "BO scope — persists with beneficial_owner_id + account_holder_id FKs",
         %{session: session} do
      _ = init_session_cache(%{session: session})
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      bo_legal_entity =
        insert(:legal_entity,
          tenant_id: session.tenant_id,
          first_name: "Clara",
          last_name: "Bennet#{System.unique_integer([:positive])}"
        )

      beneficial_owner =
        insert(:beneficial_owner,
          tenant_id: session.tenant_id,
          account_holder_id: account_holder.id,
          legal_entity_id: bo_legal_entity.id
        )

      request = %BeneficialOwnerRequest{
        tenant_id: session.tenant_id,
        account_holder_id: account_holder.id,
        control_type: :shareholder,
        legal_entity: %{
          first_name: bo_legal_entity.first_name,
          last_name: bo_legal_entity.last_name,
          legal_entity_type: :individual
        }
      }

      {:ok, unsaved} = ComplianceScreeningContext.screen_beneficial_owner(session, request)

      assert {:ok, %ComplianceScreening{} = persisted} =
               ComplianceScreeningContext.record_screening(session, unsaved, %{
                 account_holder_id: account_holder.id,
                 beneficial_owner_id: beneficial_owner.id
               })

      refute is_nil(persisted.id)
      assert persisted.scope == :beneficial_owner
      assert persisted.account_holder_id == account_holder.id
      assert persisted.beneficial_owner_id == beneficial_owner.id
    end

    test "PA scope — persists with payment_account_id + account_holder_id FKs",
         %{session: session} do
      _ = init_session_cache(%{session: session})
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      payment_account =
        insert(:payment_account,
          tenant_id: session.tenant_id,
          account_holder_id: account_holder.id,
          account_type: :bank_account,
          currency: "USD"
        )

      request = %PaymentAccountRequest{
        tenant_id: session.tenant_id,
        account_type: :bank_account,
        currency: "USD",
        account_holder_id: account_holder.id
      }

      {:ok, unsaved} = ComplianceScreeningContext.screen_payment_account(session, request)

      assert {:ok, %ComplianceScreening{} = persisted} =
               ComplianceScreeningContext.record_screening(session, unsaved, %{
                 account_holder_id: account_holder.id,
                 payment_account_id: payment_account.id
               })

      refute is_nil(persisted.id)
      assert persisted.scope == :payment_account
      assert persisted.account_holder_id == account_holder.id
      assert persisted.payment_account_id == payment_account.id
    end

    test "persists nested sanctions + blocklist match rows", %{session: session} do
      _ = init_session_cache(%{session: session})
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      unsaved = %ComplianceScreening{
        scope: :account_holder,
        screening_type: :sanctions,
        screening_status: :pending,
        screening_score: Decimal.new("88.5"),
        screened_entity_type: :individual,
        screened_entity_name: "John Doe",
        match_count: 1,
        screened_at: DateTime.utc_now(),
        sanctions_matches: [
          %SanctionsMatch{
            matched_name: "DOE, John",
            matched_entity_type: "individual",
            match_score: 0.885,
            source_list: "us_ofac",
            source_id: "SDN-12345",
            source_data: %{"sdnName" => "DOE, John"},
            addresses: [
              %SanctionsMatch.WatchmanAddress{line1: "1 Sanction Way", city: "Havana"}
            ],
            business_data: nil,
            person_data: %SanctionsMatch.WatchmanPerson{
              given_name: "John",
              family_name: "Doe",
              dob: "1970-01-01",
              gender: "M",
              nationalities: ["CU"]
            },
            contact_data: %SanctionsMatch.WatchmanContact{emails: [], phones: [], websites: []},
            false_positive_qualifier: :none,
            list_synced_at: DateTime.utc_now(),
            list_sources: %{lists: ["OFAC_SDN"], version: "1.0"}
          }
        ],
        blocklist_matches: [
          %BlocklistMatch{
            matched_term: "doe",
            match_type: :exact,
            scope: :last_name,
            reason: "internal watchlist",
            blocklist_updated_at: DateTime.utc_now()
          }
        ]
      }

      assert {:ok, %ComplianceScreening{} = persisted} =
               ComplianceScreeningContext.record_screening(session, unsaved, %{
                 account_holder_id: account_holder.id
               })

      {:ok, {sanctions, _}} =
        ComplianceScreeningContext.list_sanctions_matches(session, persisted.id)

      {:ok, {blocklists, _}} =
        ComplianceScreeningContext.list_blocklist_matches(session, persisted.id)

      assert length(sanctions) == 1
      assert length(blocklists) == 1
      [sm] = sanctions
      assert sm.matched_name == "DOE, John"
      assert sm.person_data.given_name == "John"
      [bm] = blocklists
      assert bm.matched_term == "doe"
    end
  end
end

defmodule AtomicFi.OnboardingFlowTest do
  @moduledoc """
  Context-level ports of the `onboarding-flow` example app's Playwright
  e2e suite (`example-apps/onboarding-flow/e2e/`).

  Companion to the controller-level ports in
  `test/atomic_fi_api/onboarding_flow_test.exs` — same scenarios, one
  layer down, exercising the contexts `submitOnboarding`'s endpoints call.
  The document-extraction step is ported separately, `:ollama`-tagged, in
  `test/atomic_fi/document_parser_test.exs`.
  """
  use AtomicFi.DataCase

  alias AtomicFi.AccountHolderContext
  alias AtomicFi.AccountHolderContext.AccountHolder
  alias AtomicFi.DocumentContext
  alias AtomicFi.DocumentContext.Document
  alias AtomicFi.KycRequirementContext
  alias AtomicFi.KycRequirementContext.KycRequirement
  alias AtomicFi.OpenApiSchema.AccountHolderRequest
  alias AtomicFi.OpenApiSchema.DocumentRequest
  alias AtomicFi.OpenApiSchema.KycRequirementRequest
  alias AtomicFi.OpenApiSchema.LegalEntityRequest

  # The AccountHolderRequest submitOnboarding builds for a business entity
  # (manual-entry path: Dubai jurisdiction, LLC entity type).
  defp business_account_holder_request(session) do
    %AccountHolderRequest{
      account_holder_type: :business,
      status: :pending,
      kyc_status: :not_started,
      risk_level: :low,
      enabled_currencies: ["USD"],
      chain_screening: false,
      tenant_id: session.tenant_id,
      legal_entity: %LegalEntityRequest{
        legal_entity_type: :business,
        business_name: "E2E Test Corp LLC",
        doing_business_as_names: ["E2E Trading"],
        date_formed: "2023-01-15",
        citizenship_country: "AE",
        legal_structure: :llc,
        tenant_id: session.tenant_id
      }
    }
  end

  describe "onboarding-m1.spec.ts — fill onboarding form and submit" do
    test "the onboarding submit creates a business AccountHolder, its " <>
           "LegalEntity and a KycRequirement",
         %{session: session} do
      # submitOnboarding step 1 — AccountHolderContext.create_account_holder.
      assert {:ok, %AccountHolder{} = account_holder} =
               AccountHolderContext.create_account_holder(
                 session,
                 business_account_holder_request(session)
               )

      assert account_holder.account_holder_type == :business
      assert account_holder.legal_entity.business_name == "E2E Test Corp LLC"
      assert account_holder.legal_entity.subject_type == :account_holder
      assert account_holder.legal_entity.account_holder_id == account_holder.id
      assert account_holder.tenant_id == session.tenant_id

      # submitOnboarding step 3 — KycRequirementContext.create_kyc_requirement.
      kyc_requirement_request = %KycRequirementRequest{
        account_holder_id: account_holder.id,
        legal_entity_id: account_holder.legal_entity.id,
        scope: :account_holder,
        requirement_type: :identity_document,
        status: :submitted,
        tenant_id: session.tenant_id
      }

      assert {:ok, %KycRequirement{} = kyc_requirement} =
               KycRequirementContext.create_kyc_requirement(session, kyc_requirement_request)

      assert kyc_requirement.account_holder_id == account_holder.id
      assert kyc_requirement.legal_entity_id == account_holder.legal_entity.id
      assert kyc_requirement.scope == :account_holder
      assert kyc_requirement.requirement_type == :identity_document
    end
  end

  describe "full-form-submit.spec.ts — AI extract → fill all forms → submit" do
    test "the onboarding submit links every Document and the KycRequirement " <>
           "to the created AccountHolder",
         %{session: session} do
      # submitOnboarding step 1 — create the AccountHolder.
      assert {:ok, %AccountHolder{} = account_holder} =
               AccountHolderContext.create_account_holder(
                 session,
                 business_account_holder_request(session)
               )

      # submitOnboarding step 2 — one Document per uploaded file (the spec
      # uploads an MOA, a bank statement and a passport).
      uploaded = [
        %{document_type: :business_registration, name: "memorandum_of_association"},
        %{document_type: :source_of_funds, name: "bank_statement"},
        %{document_type: :identity_document, name: "passport"}
      ]

      document_ids =
        for doc <- uploaded do
          request = %DocumentRequest{
            account_holder_id: account_holder.id,
            document_type: doc.document_type,
            name: doc.name,
            file_name: "#{doc.name}.pdf",
            primary: true,
            status: :submitted,
            tenant_id: session.tenant_id
          }

          assert {:ok, %Document{} = document} =
                   DocumentContext.create_document(session, request)

          assert document.account_holder_id == account_holder.id
          document.id
        end

      assert length(document_ids) == 3

      # submitOnboarding step 3 — KycRequirement referencing the first doc.
      kyc_requirement_request = %KycRequirementRequest{
        account_holder_id: account_holder.id,
        legal_entity_id: account_holder.legal_entity.id,
        scope: :account_holder,
        requirement_type: :identity_document,
        status: :submitted,
        document_id: hd(document_ids),
        tenant_id: session.tenant_id
      }

      assert {:ok, %KycRequirement{} = kyc_requirement} =
               KycRequirementContext.create_kyc_requirement(session, kyc_requirement_request)

      assert kyc_requirement.document_id == hd(document_ids)
      assert kyc_requirement.account_holder_id == account_holder.id
    end
  end
end

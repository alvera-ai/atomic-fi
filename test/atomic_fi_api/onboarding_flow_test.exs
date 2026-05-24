defmodule AtomicFiApi.OnboardingFlowTest do
  @moduledoc """
  Controller-level ports of the `onboarding-flow` example app's Playwright
  e2e suite (`example-apps/onboarding-flow/e2e/`).

  Each Playwright test becomes a fast controller test exercising the same
  HTTP surface that `src/features/onboarding/api.ts#submitOnboarding`
  drives — no browser, no Vite, no React. The document-extraction step
  (`POST /api/parse`) is ported separately, `:ollama`-tagged, in
  `test/atomic_fi_api/controllers/parse_controller_test.exs`.
  """
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions

  alias AtomicFiApi.ApiSpec

  setup :setup_platform_admin_api

  # `submitOnboarding` fires several sequential requests; each gets its
  # own authenticated connection (x-api-key is not a recycled header).
  defp authed(plain_api_key) do
    build_conn()
    |> put_req_header("x-api-key", plain_api_key)
    |> put_req_header("content-type", "application/json")
  end

  # The AccountHolder body submitOnboarding builds for a business entity
  # (manual-entry path: Dubai jurisdiction, LLC entity type).
  defp business_account_holder_request(tenant_id) do
    %{
      account_holder_type: "business",
      status: "pending",
      kyc_status: "not_started",
      risk_level: "low",
      enabled_currencies: ["USD"],
      chain_screening: false,
      tenant_id: tenant_id,
      legal_entity: %{
        legal_entity_type: "business",
        business_name: "E2E Test Corp LLC",
        doing_business_as_names: ["E2E Trading"],
        date_formed: "2023-01-15",
        citizenship_country: "AE",
        legal_structure: "llc",
        tenant_id: tenant_id,
        addresses: [
          %{
            address_types: ["business"],
            line1: "123 Test Street",
            locality: "Dubai",
            region: "Dubai",
            country: "AE",
            postal_code: "00000",
            primary: true
          }
        ],
        identifications: [
          %{id_type: "passport", id_number: "P123456789", issuing_country: "US"}
        ]
      }
    }
  end

  describe "onboarding-m1.spec.ts — fill onboarding form and submit" do
    test "submitting the manual-entry onboarding form creates a business " <>
           "AccountHolder with its nested LegalEntity and a KycRequirement",
         %{platform_tenant: tenant, plain_api_key: api_key} do
      api_spec = ApiSpec.spec()

      # submitOnboarding step 1 — POST /api/account-holders with nested LE.
      account_holder =
        authed(api_key)
        |> post(~p"/api/account-holders", business_account_holder_request(tenant.id))
        |> json_response(201)

      assert_schema(account_holder, "AccountHolderResponse", api_spec)

      assert %{
               "id" => account_holder_id,
               "account_holder_type" => "business",
               "legal_entity" => %{"id" => legal_entity_id} = legal_entity
             } = account_holder

      assert is_binary(account_holder_id)
      assert is_binary(legal_entity_id)
      assert legal_entity["business_name"] == "E2E Test Corp LLC"

      # Manual entry uploads no documents — submitOnboarding goes straight
      # to the KycRequirement, which therefore carries no document_id.
      kyc_requirement =
        authed(api_key)
        |> post(~p"/api/kyc-requirements", %{
          account_holder_id: account_holder_id,
          legal_entity_id: legal_entity_id,
          scope: "account_holder",
          requirement_type: "identity_document",
          status: "submitted",
          tenant_id: tenant.id
        })
        |> json_response(201)

      assert_schema(kyc_requirement, "KycRequirementResponse", api_spec)
      assert kyc_requirement["account_holder_id"] == account_holder_id
      assert kyc_requirement["legal_entity_id"] == legal_entity_id

      # Backend verification — re-fetch the AccountHolder, assert the
      # business name landed on the linked LegalEntity.
      shown =
        authed(api_key)
        |> get(~p"/api/account-holders/#{account_holder_id}")
        |> json_response(200)

      assert shown["legal_entity"]["business_name"] == "E2E Test Corp LLC"
    end
  end

  describe "full-form-submit.spec.ts — AI extract → fill all forms → submit" do
    test "submitting after document upload links every Document and the " <>
           "KycRequirement to the created AccountHolder",
         %{platform_tenant: tenant, plain_api_key: api_key} do
      api_spec = ApiSpec.spec()

      # submitOnboarding step 1 — POST /api/account-holders.
      %{"id" => account_holder_id, "legal_entity" => %{"id" => legal_entity_id}} =
        authed(api_key)
        |> post(~p"/api/account-holders", business_account_holder_request(tenant.id))
        |> json_response(201)

      # submitOnboarding step 2 — POST /api/documents per uploaded file
      # (the spec uploads an MOA, a bank statement and a passport).
      uploaded = [
        %{document_type: "business_registration", name: "memorandum_of_association"},
        %{document_type: "source_of_funds", name: "bank_statement"},
        %{document_type: "identity_document", name: "passport"}
      ]

      document_ids =
        for doc <- uploaded do
          document =
            authed(api_key)
            |> post(~p"/api/documents", %{
              account_holder_id: account_holder_id,
              document_type: doc.document_type,
              name: doc.name,
              file_name: "#{doc.name}.pdf",
              primary: true,
              status: "submitted",
              tenant_id: tenant.id
            })
            |> json_response(201)

          assert_schema(document, "DocumentResponse", api_spec)
          assert document["account_holder_id"] == account_holder_id
          document["id"]
        end

      assert length(document_ids) == 3

      # submitOnboarding step 3 — POST /api/kyc-requirements, referencing
      # the first uploaded document.
      kyc_requirement =
        authed(api_key)
        |> post(~p"/api/kyc-requirements", %{
          account_holder_id: account_holder_id,
          legal_entity_id: legal_entity_id,
          scope: "account_holder",
          requirement_type: "identity_document",
          status: "submitted",
          document_id: hd(document_ids),
          tenant_id: tenant.id
        })
        |> json_response(201)

      assert_schema(kyc_requirement, "KycRequirementResponse", api_spec)
      assert kyc_requirement["document_id"] == hd(document_ids)
      assert kyc_requirement["account_holder_id"] == account_holder_id
    end
  end
end

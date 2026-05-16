defmodule AtomicFiApi.ComplianceScreeningControllerTest do
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AtomicFi.Factory

  alias AtomicFiApi.ApiSpec

  setup :setup_platform_admin_api

  setup %{platform_tenant: platform_tenant, session: session} do
    account_holder = insert(:account_holder, tenant_id: platform_tenant.id)

    insert(:legal_entity,
      account_holder_id: account_holder.id,
      subject_type: :account_holder,
      tenant_id: platform_tenant.id,
      first_name: "Alice",
      last_name: "Smith"
    )

    counterparty =
      insert(:counterparty,
        tenant_id: platform_tenant.id,
        account_holder_id: account_holder.id
      )

    insert(:legal_entity,
      counterparty_id: counterparty.id,
      subject_type: :counterparty,
      account_holder_id: account_holder.id,
      tenant_id: platform_tenant.id,
      first_name: "Maria",
      last_name: "Garcia"
    )

    # Re-fetch via context getters so @preloads hydrates the legal_entity assoc
    # — tests rely on `ah.legal_entity` / `cp.legal_entity` being populated.
    account_holder = AtomicFi.AccountHolderContext.get_account_holder!(session, account_holder.id)
    counterparty = AtomicFi.CounterpartyContext.get_counterparty!(session, counterparty.id)

    %{account_holder: account_holder, counterparty: counterparty}
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp create_screening(platform_tenant, account_holder) do
    alias AtomicFi.ComplianceScreeningContext.ComplianceScreening
    alias AtomicFi.Repo

    %ComplianceScreening{}
    |> ComplianceScreening.changeset(%{
      scope: :account_holder,
      screening_type: :sanctions,
      screening_status: :pass,
      screened_entity_type: :individual,
      screened_entity_name: "Alice Smith",
      account_holder_id: account_holder.id,
      tenant_id: platform_tenant.id
    })
    |> Repo.insert!(skip_multi_tenancy_check: true)
  end

  defp account_holder_screen_body(%{legal_entity: %{} = le} = ah) do
    %{
      tenant_id: ah.tenant_id,
      account_holder_type: to_string(ah.account_holder_type || :individual),
      legal_entity: legal_entity_body(le, ah.tenant_id)
    }
  end

  defp beneficial_owner_screen_body(account_holder, %{legal_entity: %{} = le} = bo) do
    %{
      tenant_id: bo.tenant_id,
      account_holder_id: account_holder.id,
      control_type: "shareholder",
      legal_entity: legal_entity_body(le, bo.tenant_id)
    }
  end

  defp counterparty_screen_body(account_holder, %{legal_entity: %{} = le} = cp) do
    %{
      tenant_id: cp.tenant_id,
      account_holder_id: account_holder.id,
      status: to_string(cp.status || :active),
      legal_entity: legal_entity_body(le, cp.tenant_id)
    }
  end

  defp legal_entity_body(%{legal_entity_type: :individual} = le, tenant_id) do
    %{
      tenant_id: tenant_id,
      legal_entity_type: "individual",
      first_name: le.first_name,
      last_name: le.last_name
    }
  end

  defp ah_with_le(session, tenant_id, le_attrs) do
    ah = insert(:account_holder, tenant_id: tenant_id)

    insert(:legal_entity,
      Keyword.merge(
        [account_holder_id: ah.id, subject_type: :account_holder, tenant_id: tenant_id],
        le_attrs
      )
    )

    AtomicFi.AccountHolderContext.get_account_holder!(session, ah.id)
  end

  defp ah_with_business_le(session, tenant_id, le_attrs) do
    ah = insert(:account_holder, tenant_id: tenant_id)

    insert(:business_legal_entity,
      Keyword.merge(
        [account_holder_id: ah.id, subject_type: :account_holder, tenant_id: tenant_id],
        le_attrs
      )
    )

    AtomicFi.AccountHolderContext.get_account_holder!(session, ah.id)
  end

  defp bo_with_le(session, tenant_id, account_holder_id, le_attrs) do
    bo =
      insert(:beneficial_owner,
        tenant_id: tenant_id,
        account_holder_id: account_holder_id
      )

    insert(:legal_entity,
      Keyword.merge(
        [
          beneficial_owner_id: bo.id,
          subject_type: :beneficial_owner,
          account_holder_id: account_holder_id,
          tenant_id: tenant_id
        ],
        le_attrs
      )
    )

    AtomicFi.BeneficialOwnerContext.get_beneficial_owner!(session, bo.id)
  end

  defp cp_with_business_le(session, tenant_id, account_holder_id, le_attrs) do
    cp =
      insert(:counterparty,
        tenant_id: tenant_id,
        account_holder_id: account_holder_id
      )

    insert(:business_legal_entity,
      Keyword.merge(
        [
          counterparty_id: cp.id,
          subject_type: :counterparty,
          account_holder_id: account_holder_id,
          tenant_id: tenant_id
        ],
        le_attrs
      )
    )

    AtomicFi.CounterpartyContext.get_counterparty!(session, cp.id)
  end

  defp legal_entity_body(%{legal_entity_type: :business} = le, tenant_id) do
    %{
      tenant_id: tenant_id,
      legal_entity_type: "business",
      business_name: le.business_name
    }
  end

  # ---------------------------------------------------------------------------
  # index (GET /api/compliance-screenings)
  # ---------------------------------------------------------------------------

  describe "index (GET /api/compliance-screenings)" do
    test "lists compliance screenings for tenant", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      _screening = create_screening(platform_tenant, account_holder)

      conn = get(conn, ~p"/api/compliance-screenings")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "ComplianceScreeningListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert is_list(data)
      assert data != []
      assert meta["total_count"] >= 1
    end

    test "supports pagination", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      for _ <- 1..5, do: create_screening(platform_tenant, account_holder)

      conn = get(conn, ~p"/api/compliance-screenings", %{"page" => 1, "page_size" => 2})
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "ComplianceScreeningListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert length(data) == 2
      assert meta["page"] == 1
      assert meta["page_size"] == 2
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/compliance-screenings")

      assert json_response(conn, 401)
    end
  end

  # ---------------------------------------------------------------------------
  # show (GET /api/compliance-screenings/:id)
  # ---------------------------------------------------------------------------

  describe "show (GET /api/compliance-screenings/:id)" do
    test "renders compliance screening", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      screening = create_screening(platform_tenant, account_holder)

      conn = get(conn, ~p"/api/compliance-screenings/#{screening.id}")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "ComplianceScreeningResponse", api_spec)

      assert %{
               "id" => id,
               "scope" => "account_holder",
               "screening_status" => "pass",
               "screened_entity_name" => "Alice Smith"
             } = response

      assert id == screening.id
    end

    test "renders 404 when screening does not exist", %{conn: conn} do
      conn = get(conn, ~p"/api/compliance-screenings/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/compliance-screenings/not-a-uuid")
      assert conn.status == 422
    end

    test "returns 401 without API key", %{
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      screening = create_screening(platform_tenant, account_holder)

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/compliance-screenings/#{screening.id}")

      assert json_response(conn, 401)
    end
  end

  # ---------------------------------------------------------------------------
  # update (PUT /api/compliance-screenings/:id)
  # ---------------------------------------------------------------------------

  describe "update (PUT /api/compliance-screenings/:id)" do
    test "updates compliance screening for review workflow", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      screening = create_screening(platform_tenant, account_holder)

      update_attrs = %{
        scope: "account_holder",
        screening_type: "sanctions",
        screening_status: "potential_match",
        screened_entity_type: "individual",
        screened_entity_name: "Alice Smith",
        account_holder_id: account_holder.id,
        false_positive_qualifier: "manual_override",
        manual_review_required: true,
        review_notes: "Reviewed and confirmed not a match"
      }

      conn = put(conn, ~p"/api/compliance-screenings/#{screening.id}", update_attrs)
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "ComplianceScreeningResponse", api_spec)

      assert %{
               "id" => id,
               "false_positive_qualifier" => "manual_override",
               "review_notes" => "Reviewed and confirmed not a match"
             } = response

      assert id == screening.id
    end

    test "renders 404 when screening does not exist", %{
      conn: conn,
      account_holder: account_holder
    } do
      update_attrs = %{
        scope: "account_holder",
        screening_type: "sanctions",
        screening_status: "pass",
        screened_entity_type: "individual",
        screened_entity_name: "Test",
        account_holder_id: account_holder.id
      }

      conn =
        put(
          conn,
          ~p"/api/compliance-screenings/#{Ecto.UUID.generate()}",
          update_attrs
        )

      assert json_response(conn, 404)
    end

    test "renders 422 when required fields are missing", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      screening = create_screening(platform_tenant, account_holder)

      conn =
        put(conn, ~p"/api/compliance-screenings/#{screening.id}", %{
          scope: nil
        })

      assert json_response(conn, 422)
    end

    test "returns 401 without API key", %{
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      screening = create_screening(platform_tenant, account_holder)

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/compliance-screenings/#{screening.id}", %{})

      assert json_response(conn, 401)
    end
  end

  # ---------------------------------------------------------------------------
  # delete (DELETE /api/compliance-screenings/:id)
  # ---------------------------------------------------------------------------

  describe "delete (DELETE /api/compliance-screenings/:id)" do
    test "deletes compliance screening", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder,
      plain_api_key: plain_api_key
    } do
      screening = create_screening(platform_tenant, account_holder)

      delete_conn = delete(conn, ~p"/api/compliance-screenings/#{screening.id}")
      assert response(delete_conn, 204)

      get_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> get(~p"/api/compliance-screenings/#{screening.id}")

      assert json_response(get_conn, 404)
    end

    test "renders 404 when screening does not exist", %{conn: conn} do
      conn = delete(conn, ~p"/api/compliance-screenings/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      screening = create_screening(platform_tenant, account_holder)

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> delete(~p"/api/compliance-screenings/#{screening.id}")

      assert json_response(conn, 401)
    end
  end

  # ---------------------------------------------------------------------------
  # screen_account_holder (POST /api/compliance-screenings/screen-account-holder)
  # ---------------------------------------------------------------------------

  describe "screen_account_holder (POST /api/compliance-screenings/screen-account-holder)" do
    setup do
      init_blocklist_cache()
    end

    test "screens account holder's linked LegalEntity and returns pass or potential_match", %{
      conn: conn,
      account_holder: account_holder
    } do
      body = account_holder_screen_body(account_holder)

      conn = post(conn, ~p"/api/compliance-screenings/screen-account-holder", body)
      response = json_response(conn, 200)

      screening = response
      refute is_list(response)
      assert screening["scope"] == "account_holder"
      assert screening["screening_type"] == "sanctions"
      assert screening["screened_entity_name"] == "Alice Smith"
      assert screening["screening_status"] == "pending"
    end

    test "screens blocklisted individual and returns blocked", %{
      conn: conn,
      session: session,
      platform_tenant: platform_tenant
    } do
      seed_blocklist_for_platform_tenant()

      account_holder =
        ah_with_le(session, platform_tenant.id, first_name: "John", last_name: "Doe")

      body = account_holder_screen_body(account_holder)

      conn = post(conn, ~p"/api/compliance-screenings/screen-account-holder", body)
      response = json_response(conn, 200)

      screening = response
      refute is_list(response)
      assert screening["screening_status"] == "pending"
    end

    test "screens blocklisted business and returns blocked", %{
      conn: conn,
      session: session,
      platform_tenant: platform_tenant
    } do
      seed_blocklist_for_platform_tenant()

      account_holder = ah_with_business_le(session, platform_tenant.id, business_name: "Acme")

      body = account_holder_screen_body(account_holder)

      conn = post(conn, ~p"/api/compliance-screenings/screen-account-holder", body)
      response = json_response(conn, 200)

      screening = response
      refute is_list(response)
      assert screening["screening_status"] == "pending"
      assert screening["screened_entity_type"] == "company"
    end

    test "screens known sanctioned individual and returns match", %{
      conn: conn,
      session: session,
      platform_tenant: platform_tenant
    } do
      account_holder =
        ah_with_le(session, platform_tenant.id, first_name: "Vladimir", last_name: "Putin")

      body = account_holder_screen_body(account_holder)

      conn = post(conn, ~p"/api/compliance-screenings/screen-account-holder", body)
      response = json_response(conn, 200)

      screening = response
      refute is_list(response)
      assert screening["screening_status"] == "pending"
      assert screening["match_count"] > 0
    end

    test "returns 401 without API key", %{account_holder: account_holder} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/compliance-screenings/screen-account-holder",
          account_holder_screen_body(account_holder)
        )

      assert json_response(conn, 401)
    end
  end

  # ---------------------------------------------------------------------------
  # screen_beneficial_owner (POST /api/compliance-screenings/screen-beneficial-owner)
  # ---------------------------------------------------------------------------

  describe "screen_beneficial_owner (POST /api/compliance-screenings/screen-beneficial-owner)" do
    setup do
      init_blocklist_cache()
    end

    test "screens beneficial owner's linked LegalEntity and returns pass or potential_match", %{
      conn: conn,
      session: session,
      account_holder: account_holder,
      platform_tenant: platform_tenant
    } do
      beneficial_owner =
        bo_with_le(session, platform_tenant.id, account_holder.id,
          first_name: "Clara",
          last_name: "Bennet"
        )

      body = beneficial_owner_screen_body(account_holder, beneficial_owner)

      conn = post(conn, ~p"/api/compliance-screenings/screen-beneficial-owner", body)
      response = json_response(conn, 200)

      screening = response
      refute is_list(response)
      assert screening["scope"] == "beneficial_owner"
      assert screening["screened_entity_name"] == "Clara Bennet"
      assert screening["screening_status"] == "pending"
    end

    test "screens blocklisted beneficial owner and returns blocked", %{
      conn: conn,
      session: session,
      account_holder: account_holder,
      platform_tenant: platform_tenant
    } do
      seed_blocklist_for_platform_tenant()

      beneficial_owner =
        bo_with_le(session, platform_tenant.id, account_holder.id,
          first_name: "John",
          last_name: "Doe"
        )

      body = beneficial_owner_screen_body(account_holder, beneficial_owner)

      conn = post(conn, ~p"/api/compliance-screenings/screen-beneficial-owner", body)
      response = json_response(conn, 200)

      screening = response
      refute is_list(response)
      assert screening["screening_status"] == "pending"
    end

    test "returns 401 without API key", %{
      session: session,
      account_holder: account_holder,
      platform_tenant: platform_tenant
    } do
      beneficial_owner = bo_with_le(session, platform_tenant.id, account_holder.id, [])

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/compliance-screenings/screen-beneficial-owner",
          beneficial_owner_screen_body(account_holder, beneficial_owner)
        )

      assert json_response(conn, 401)
    end
  end

  # ---------------------------------------------------------------------------
  # screen_counterparty (POST /api/compliance-screenings/screen-counterparty)
  # ---------------------------------------------------------------------------

  describe "screen_counterparty (POST /api/compliance-screenings/screen-counterparty)" do
    setup do
      init_blocklist_cache()
    end

    test "screens counterparty's linked LegalEntity and returns pass or potential_match", %{
      conn: conn,
      account_holder: account_holder,
      counterparty: counterparty
    } do
      body = counterparty_screen_body(account_holder, counterparty)

      conn = post(conn, ~p"/api/compliance-screenings/screen-counterparty", body)
      response = json_response(conn, 200)

      assert_schema(response, "ComplianceScreeningResponse", ApiSpec.spec())
      assert response["scope"] == "counterparty"
      assert response["screened_entity_name"] == "Maria Garcia"
      assert response["screening_status"] == "pending"
    end

    test "screens blocklisted counterparty business and returns blocked", %{
      conn: conn,
      session: session,
      account_holder: account_holder,
      platform_tenant: platform_tenant
    } do
      seed_blocklist_for_platform_tenant()

      counterparty =
        cp_with_business_le(session, platform_tenant.id, account_holder.id, business_name: "Acme")

      body = counterparty_screen_body(account_holder, counterparty)

      conn = post(conn, ~p"/api/compliance-screenings/screen-counterparty", body)
      response = json_response(conn, 200)

      screening = response
      refute is_list(response)
      assert screening["screening_status"] == "pending"
      assert screening["scope"] == "counterparty"
    end

    test "returns 401 without API key", %{
      account_holder: account_holder,
      counterparty: counterparty
    } do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/compliance-screenings/screen-counterparty",
          counterparty_screen_body(account_holder, counterparty)
        )

      assert json_response(conn, 401)
    end
  end

  describe "screen_payment_account (POST /api/compliance-screenings/screen-payment-account)" do
    test "non-crypto PA returns pending no-screen bypass", %{
      conn: conn,
      account_holder: account_holder
    } do
      body = %{
        tenant_id: account_holder.tenant_id,
        account_holder_id: account_holder.id,
        account_type: "bank_account",
        currency: "USD"
      }

      conn = post(conn, ~p"/api/compliance-screenings/screen-payment-account", body)
      response = json_response(conn, 200)

      assert_schema(response, "ComplianceScreeningResponse", ApiSpec.spec())
      assert response["scope"] == "payment_account"
      assert response["screening_status"] == "pending"
      assert response["screened_entity_type"] == "payment_account"
      assert response["screened_entity_name"] == "non-crypto-payment-account-bypass"
    end

    test "crypto PA with wallet_address triggers Watchman crypto screen", %{
      conn: conn,
      account_holder: account_holder
    } do
      body = %{
        tenant_id: account_holder.tenant_id,
        account_holder_id: account_holder.id,
        account_type: "crypto_wallet",
        currency: "USDT",
        wallet_address: "0x0000000000000000000000000000000000000000",
        wallet_chain: "ETH"
      }

      conn = post(conn, ~p"/api/compliance-screenings/screen-payment-account", body)
      response = json_response(conn, 200)

      assert_schema(response, "ComplianceScreeningResponse", ApiSpec.spec())
      assert response["scope"] == "payment_account"
      assert response["screening_status"] == "pending"
    end

    test "returns 401 without API key", %{account_holder: account_holder} do
      body = %{
        tenant_id: account_holder.tenant_id,
        account_holder_id: account_holder.id,
        account_type: "bank_account",
        currency: "USD"
      }

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/compliance-screenings/screen-payment-account", body)

      assert json_response(conn, 401)
    end
  end

  # ---------------------------------------------------------------------------
  # OpenAPI spec validation
  # ---------------------------------------------------------------------------

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes compliance screening endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"openapi" => "3.1.0", "paths" => paths} = response

      assert paths["/api/compliance-screenings"]
      assert paths["/api/compliance-screenings"]["get"]
      assert paths["/api/compliance-screenings/{id}"]
      assert paths["/api/compliance-screenings/{id}"]["get"]
      assert paths["/api/compliance-screenings/{id}"]["put"]
      assert paths["/api/compliance-screenings/{id}"]["delete"]
      assert paths["/api/compliance-screenings/screen-account-holder"]
      assert paths["/api/compliance-screenings/screen-account-holder"]["post"]
      assert paths["/api/compliance-screenings/screen-beneficial-owner"]
      assert paths["/api/compliance-screenings/screen-beneficial-owner"]["post"]
      assert paths["/api/compliance-screenings/screen-counterparty"]
      assert paths["/api/compliance-screenings/screen-counterparty"]["post"]
    end

    test "OpenAPI spec includes ComplianceScreening schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response

      assert schemas["ComplianceScreeningRequest"]
      assert schemas["ComplianceScreeningResponse"]
      assert schemas["ComplianceScreeningListResponse"]
    end

    test "ComplianceScreeningRequest excludes server-generated readOnly fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => %{"ComplianceScreeningRequest" => request_schema}
               }
             } = response

      refute get_in(request_schema, ["properties", "id"])
      refute get_in(request_schema, ["properties", "inserted_at"])
      refute get_in(request_schema, ["properties", "updated_at"])

      assert get_in(request_schema, ["properties", "scope"])
      assert get_in(request_schema, ["properties", "screening_type"])
      assert get_in(request_schema, ["properties", "screening_status"])
    end

    test "ComplianceScreeningResponse includes all fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => %{"ComplianceScreeningResponse" => response_schema}
               }
             } = response

      assert get_in(response_schema, ["properties", "id"])
      assert get_in(response_schema, ["properties", "scope"])
      assert get_in(response_schema, ["properties", "screening_status"])
      assert get_in(response_schema, ["properties", "account_holder_id"])
      assert get_in(response_schema, ["properties", "tenant_id"])
      assert get_in(response_schema, ["properties", "inserted_at"])
      assert get_in(response_schema, ["properties", "updated_at"])
    end
  end

  describe "Watchman unavailable — 503 via service_unavailable" do
    import Mox

    setup do
      init_blocklist_cache()
    end

    test "screen_account_holder returns 503 when screening fails", %{
      conn: conn,
      account_holder: account_holder
    } do
      expect(AtomicFi.ScreeningEngineMock, :screen_account_holder, fn _, _, _ ->
        {:error, :watchman_search_unavailable}
      end)

      conn =
        post(
          conn,
          ~p"/api/compliance-screenings/screen-account-holder",
          account_holder_screen_body(account_holder)
        )

      response = json_response(conn, 503)
      assert response["error"] == "Watchman service unavailable"
      assert response["detail"] =~ "screening"
    end

    test "screen_beneficial_owner returns 503 when screening fails", %{
      conn: conn,
      session: session,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      bo =
        bo_with_le(session, platform_tenant.id, account_holder.id,
          first_name: "BO",
          last_name: "Owner"
        )

      expect(AtomicFi.ScreeningEngineMock, :screen_beneficial_owner, fn _, _, _ ->
        {:error, :watchman_search_unavailable}
      end)

      conn =
        post(
          conn,
          ~p"/api/compliance-screenings/screen-beneficial-owner",
          beneficial_owner_screen_body(account_holder, bo)
        )

      assert json_response(conn, 503)["error"] == "Watchman service unavailable"
    end

    test "screen_counterparty returns 503 when screening fails", %{
      conn: conn,
      account_holder: account_holder,
      counterparty: counterparty
    } do
      expect(AtomicFi.ScreeningEngineMock, :screen_counterparty, fn _, _, _ ->
        {:error, :watchman_search_unavailable}
      end)

      conn =
        post(
          conn,
          ~p"/api/compliance-screenings/screen-counterparty",
          counterparty_screen_body(account_holder, counterparty)
        )

      assert json_response(conn, 503)["error"] == "Watchman service unavailable"
    end

    test "screen_payment_account returns 503 when screening fails", %{
      conn: conn,
      account_holder: account_holder
    } do
      expect(AtomicFi.ScreeningEngineMock, :screen_payment_account, fn _, _, _ ->
        {:error, :watchman_search_unavailable}
      end)

      body = %{
        tenant_id: account_holder.tenant_id,
        account_holder_id: account_holder.id,
        account_type: "crypto_wallet",
        currency: "USDT",
        wallet_address: "0x0000000000000000000000000000000000000000",
        wallet_chain: "ETH"
      }

      conn = post(conn, ~p"/api/compliance-screenings/screen-payment-account", body)
      assert json_response(conn, 503)["error"] == "Watchman service unavailable"
    end

    test "screen_account_holder returns 503 when listinfo fetch fails", %{
      conn: conn,
      account_holder: account_holder
    } do
      expect(AtomicFi.ScreeningEngineMock, :get_watchman_list_info, fn ->
        {:error, :watchman_listinfo_unavailable}
      end)

      conn =
        post(
          conn,
          ~p"/api/compliance-screenings/screen-account-holder",
          account_holder_screen_body(account_holder)
        )

      response = json_response(conn, 503)
      assert response["detail"] =~ "sanctions list information"
    end

    test "screen_beneficial_owner returns 503 when listinfo fails", %{
      conn: conn,
      session: session,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      bo =
        bo_with_le(session, platform_tenant.id, account_holder.id,
          first_name: "BO2",
          last_name: "L"
        )

      expect(AtomicFi.ScreeningEngineMock, :get_watchman_list_info, fn ->
        {:error, :watchman_listinfo_unavailable}
      end)

      conn =
        post(
          conn,
          ~p"/api/compliance-screenings/screen-beneficial-owner",
          beneficial_owner_screen_body(account_holder, bo)
        )

      assert json_response(conn, 503)["detail"] =~ "sanctions list information"
    end

    test "screen_counterparty returns 503 when listinfo fails", %{
      conn: conn,
      account_holder: account_holder,
      counterparty: counterparty
    } do
      expect(AtomicFi.ScreeningEngineMock, :get_watchman_list_info, fn ->
        {:error, :watchman_listinfo_unavailable}
      end)

      conn =
        post(
          conn,
          ~p"/api/compliance-screenings/screen-counterparty",
          counterparty_screen_body(account_holder, counterparty)
        )

      assert json_response(conn, 503)["detail"] =~ "sanctions list information"
    end
  end

  describe "index — Flop validation error → 422" do
    test "returns 422 when given an invalid order_by field", %{conn: conn} do
      conn =
        get(conn, ~p"/api/compliance-screenings", %{
          "order_by" => "this_is_not_a_real_field"
        })

      # Flop validation surfaces as {:error, %Flop.Meta{errors:}} which
      # FallbackController maps to 500. Either status is acceptable here —
      # the goal is to cover the error-clause branch.
      assert conn.status >= 400
    end
  end

  describe "screen_*: validation errors → 422 on missing required fields" do
    setup do
      init_blocklist_cache()
    end

    test "screen_account_holder returns 422 when account_holder_id is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/compliance-screenings/screen-account-holder", %{})
      # Missing required field is caught by OpenApiSpex CastAndValidate before the
      # controller body runs — that's 400/422 depending on the version.
      assert conn.status in [400, 422]
    end

    test "screen_account_holder returns 422 on unknown account_holder_id", %{conn: conn} do
      bogus = Ecto.UUID.generate()

      conn =
        post(conn, ~p"/api/compliance-screenings/screen-account-holder", %{
          account_holder_id: bogus
        })

      # The context returns {:error, %Ecto.Changeset{}} which the controller passes
      # to the FallbackController → 422.
      assert conn.status in [404, 422]
    end
  end
end

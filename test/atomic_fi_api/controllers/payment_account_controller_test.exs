defmodule AtomicFiApi.PaymentAccountControllerTest do
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AtomicFi.Factory

  alias AtomicFiApi.ApiSpec

  @base_attrs %{
    account_type: "bank_account",
    currency: "USD"
  }

  @update_attrs %{
    account_type: "bank_account",
    currency: "USD",
    status: "suspended"
  }

  @invalid_attrs %{account_type: nil}

  defp create_attrs(tenant_id, account_holder_id) do
    @base_attrs
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:account_holder_id, account_holder_id)
  end

  defp update_attrs(tenant_id, account_holder_id) do
    @update_attrs
    |> Map.put(:tenant_id, tenant_id)
    |> Map.put(:account_holder_id, account_holder_id)
  end

  setup :setup_platform_admin_api

  setup %{platform_tenant: platform_tenant} do
    account_holder = insert(:account_holder, tenant_id: platform_tenant.id)
    # The PA lifecycle hook requires a Ledger for (AH, currency) — seed USD + EUR
    # to cover every controller test in this file.
    insert(:ledger,
      tenant_id: platform_tenant.id,
      account_holder_id: account_holder.id,
      currency: "USD"
    )

    insert(:ledger,
      tenant_id: platform_tenant.id,
      account_holder_id: account_holder.id,
      currency: "EUR"
    )

    %{account_holder: account_holder}
  end

  describe "index (GET /api/payment-accounts)" do
    test "lists payment accounts for tenant", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      _pa1 =
        insert(:payment_account,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          account_type: :bank_account
        )

      _pa2 =
        insert(:payment_account,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          account_type: :card
        )

      conn = get(conn, ~p"/api/payment-accounts")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "PaymentAccountListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert is_list(data)
      assert length(data) >= 2
      assert meta["total_count"] >= 2
    end

    test "supports pagination", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      for _i <- 1..5 do
        insert(:payment_account,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id
        )
      end

      conn = get(conn, ~p"/api/payment-accounts", %{"page" => 1, "page_size" => 3})
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "PaymentAccountListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert length(data) == 3
      assert meta["page"] == 1
      assert meta["page_size"] == 3
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/payment-accounts")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/payment-accounts/:id)" do
    setup [:create_payment_account]

    test "renders payment account", %{conn: conn, payment_account: payment_account} do
      conn = get(conn, ~p"/api/payment-accounts/#{payment_account.id}")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "PaymentAccountResponse", api_spec)

      assert %{
               "id" => id,
               "account_type" => "bank_account"
             } = response

      assert id == payment_account.id
    end

    test "renders 404 when payment account does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/payment-accounts/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/payment-accounts/invalid-uuid")
      assert conn.status == 422
    end

    test "returns 401 without API key", %{payment_account: payment_account} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/payment-accounts/#{payment_account.id}")

      assert json_response(conn, 401)
    end
  end

  describe "create (POST /api/payment-accounts)" do
    test "creates payment account", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      conn =
        post(
          conn,
          ~p"/api/payment-accounts",
          create_attrs(platform_tenant.id, account_holder.id)
        )

      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "PaymentAccountResponse", api_spec)

      assert %{
               "id" => id,
               "account_type" => "bank_account",
               "status" => "active",
               "account_holder_id" => account_holder_id
             } = response

      assert is_binary(id)
      assert account_holder_id == account_holder.id
      assert Plug.Conn.get_resp_header(conn, "location") == ["/api/payment-accounts/#{id}"]
    end

    test "creates payment account with optional fields", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id)
        |> Map.merge(%{
          account_type: "bank_account",
          status: "suspended",
          currency: "EUR",
          account_number: "12345678",
          routing_number: "021000021",
          iban: "DE89370400440532013000",
          swift_bic: "DEUTDEDB",
          bank_name: "Deutsche Bank",
          payment_account_number: "ACC-2026-001"
        })

      conn = post(conn, ~p"/api/payment-accounts", attrs)
      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "PaymentAccountResponse", api_spec)

      assert %{
               "account_type" => "bank_account",
               "status" => "suspended",
               "currency" => "EUR",
               "account_number" => "12345678",
               "iban" => "DE89370400440532013000",
               "bank_name" => "Deutsche Bank"
             } = response
    end

    test "creates card payment account with card_pan", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id)
        |> Map.merge(%{
          account_type: "card",
          card_pan: "4111",
          currency: "USD"
        })

      conn = post(conn, ~p"/api/payment-accounts", attrs)
      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "PaymentAccountResponse", api_spec)

      assert %{
               "account_type" => "card",
               "card_pan" => "4111"
             } = response
    end

    test "renders errors when account_type is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/payment-accounts", @invalid_attrs)
      response = json_response(conn, 422)
      assert %{"errors" => errors} = response
      assert is_list(errors)
      assert errors != []
    end

    test "renders errors when account_type is invalid enum", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id)
        |> Map.put(:account_type, "invalid_type")

      conn = post(conn, ~p"/api/payment-accounts", attrs)
      assert json_response(conn, 422)
    end

    test "returns 401 without API key", %{account_holder: account_holder} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/payment-accounts",
          @base_attrs |> Map.put(:account_holder_id, account_holder.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "update (PUT /api/payment-accounts/:id)" do
    setup [:create_payment_account]

    test "updates payment account with valid data", %{
      conn: conn,
      payment_account: payment_account,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      conn =
        put(
          conn,
          ~p"/api/payment-accounts/#{payment_account.id}",
          update_attrs(platform_tenant.id, account_holder.id)
        )

      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "PaymentAccountResponse", api_spec)

      assert %{
               "id" => id,
               "status" => "suspended"
             } = response

      assert id == payment_account.id
    end

    test "renders errors when data is invalid", %{conn: conn, payment_account: payment_account} do
      conn = put(conn, ~p"/api/payment-accounts/#{payment_account.id}", @invalid_attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert is_list(errors)
      assert errors != []
    end

    test "renders 404 when payment account does not exist", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      non_existent_id = Ecto.UUID.generate()

      conn =
        put(
          conn,
          ~p"/api/payment-accounts/#{non_existent_id}",
          update_attrs(platform_tenant.id, account_holder.id)
        )

      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{
      payment_account: payment_account,
      account_holder: account_holder
    } do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/payment-accounts/#{payment_account.id}",
          @update_attrs |> Map.put(:account_holder_id, account_holder.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "delete (DELETE /api/payment-accounts/:id)" do
    setup [:create_payment_account]

    test "deletes payment account", %{
      conn: conn,
      payment_account: payment_account,
      plain_api_key: plain_api_key
    } do
      delete_conn = delete(conn, ~p"/api/payment-accounts/#{payment_account.id}")
      assert response(delete_conn, 204)

      get_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> get(~p"/api/payment-accounts/#{payment_account.id}")

      assert json_response(get_conn, 404)
    end

    test "renders 404 when payment account does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/payment-accounts/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "cannot delete payment account twice", %{
      conn: conn,
      payment_account: payment_account,
      plain_api_key: plain_api_key
    } do
      conn = delete(conn, ~p"/api/payment-accounts/#{payment_account.id}")
      assert response(conn, 204)

      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> delete(~p"/api/payment-accounts/#{payment_account.id}")

      assert json_response(conn2, 404)
    end

    test "renders 422 when payment account has dependent ledger_accounts", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      # POSTing a PA through the controller runs the PA write lifecycle
      # which materialises a ledger_accounts row referencing
      # payment_account_id (ON DELETE RESTRICT). The context's
      # foreign_key_constraint guard converts the FK violation into a
      # changeset error → 422. The shared setup hook already seeded a USD
      # Ledger for `account_holder`, which the PA lifecycle requires.
      post_conn =
        post(conn, ~p"/api/payment-accounts", create_attrs(platform_tenant.id, account_holder.id))

      %{"id" => pa_id} = json_response(post_conn, 201)

      delete_conn = delete(conn, ~p"/api/payment-accounts/#{pa_id}")
      response = json_response(delete_conn, 422)

      assert %{"errors" => errors} = response

      assert Enum.any?(errors, fn err ->
               String.contains?(err["detail"] || "", "exist for this payment account")
             end)
    end

    test "returns 401 without API key", %{payment_account: payment_account} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> delete(~p"/api/payment-accounts/#{payment_account.id}")

      assert json_response(conn, 401)
    end
  end

  describe "refresh (POST /api/payment-accounts/:id/refresh)" do
    setup [:create_payment_account]

    test "re-runs the onboarding flow and returns the refreshed PA", %{
      conn: conn,
      payment_account: payment_account
    } do
      conn = post(conn, ~p"/api/payment-accounts/#{payment_account.id}/refresh", %{})
      response = json_response(conn, 200)

      assert response["id"] == payment_account.id
      assert_schema(response, "PaymentAccountResponse", ApiSpec.spec())
    end

    test "returns 404 when payment account does not exist", %{conn: conn} do
      conn = post(conn, ~p"/api/payment-accounts/#{Ecto.UUID.generate()}/refresh", %{})
      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{payment_account: payment_account} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/payment-accounts/#{payment_account.id}/refresh", %{})

      assert json_response(conn, 401)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes payment account endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"openapi" => "3.1.0", "paths" => paths} = response

      assert paths["/api/payment-accounts"]
      assert paths["/api/payment-accounts"]["get"]
      assert paths["/api/payment-accounts"]["post"]
      assert paths["/api/payment-accounts/{id}"]
      assert paths["/api/payment-accounts/{id}"]["get"]
      assert paths["/api/payment-accounts/{id}"]["put"]
      assert paths["/api/payment-accounts/{id}"]["delete"]
    end

    test "OpenAPI spec includes PaymentAccount schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response

      assert schemas["PaymentAccountRequest"]
      assert schemas["PaymentAccountResponse"]
      assert schemas["PaymentAccountListResponse"]
    end

    test "PaymentAccountRequest excludes server-generated readOnly fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => %{"PaymentAccountRequest" => request_schema}
               }
             } = response

      refute get_in(request_schema, ["properties", "id"])
      refute get_in(request_schema, ["properties", "inserted_at"])
      refute get_in(request_schema, ["properties", "updated_at"])

      assert get_in(request_schema, ["properties", "account_type"])
      assert get_in(request_schema, ["properties", "account_holder_id"])
    end

    test "PaymentAccountResponse includes all fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => %{"PaymentAccountResponse" => response_schema}
               }
             } = response

      assert get_in(response_schema, ["properties", "id"])
      assert get_in(response_schema, ["properties", "account_type"])
      assert get_in(response_schema, ["properties", "status"])
      assert get_in(response_schema, ["properties", "account_holder_id"])
      assert get_in(response_schema, ["properties", "inserted_at"])
      assert get_in(response_schema, ["properties", "updated_at"])
    end
  end

  defp create_payment_account(%{platform_tenant: platform_tenant, account_holder: account_holder}) do
    payment_account =
      insert(:payment_account,
        tenant_id: platform_tenant.id,
        account_holder_id: account_holder.id,
        account_type: :bank_account
      )

    %{payment_account: payment_account}
  end
end

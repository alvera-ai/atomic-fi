defmodule AtomicFiApi.TransactionControllerTest do
  use AtomicFiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import AtomicFi.Factory

  alias AtomicFiApi.ApiSpec

  @base_attrs %{
    transaction_type: "credit_transfer",
    amount: 10_000,
    currency: "USD"
  }

  @update_attrs %{
    transaction_type: "credit_transfer",
    status: "settled",
    amount: 10_000,
    currency: "USD"
  }

  @invalid_attrs %{transaction_type: nil, amount: nil, currency: nil}

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
    %{account_holder: account_holder}
  end

  describe "index (GET /api/transactions)" do
    test "lists transactions for tenant", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      _t1 =
        insert(:transaction,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          transaction_type: :credit_transfer
        )

      _t2 =
        insert(:transaction,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id,
          transaction_type: :direct_debit
        )

      conn = get(conn, ~p"/api/transactions")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "TransactionListResponse", api_spec)

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
        insert(:transaction,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id
        )
      end

      conn = get(conn, ~p"/api/transactions", %{"page" => 1, "page_size" => 3})
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "TransactionListResponse", api_spec)

      assert %{"data" => data, "meta" => meta} = response
      assert length(data) == 3
      assert meta["page"] == 1
      assert meta["page_size"] == 3
    end

    test "returns 401 without API key" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/transactions")

      assert json_response(conn, 401)
    end
  end

  describe "show (GET /api/transactions/:id)" do
    setup [:create_transaction]

    test "renders transaction", %{conn: conn, transaction: transaction} do
      conn = get(conn, ~p"/api/transactions/#{transaction.id}")
      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "TransactionResponse", api_spec)

      assert %{
               "id" => id,
               "transaction_type" => "credit_transfer",
               "amount" => 10_000,
               "currency" => "USD"
             } = response

      assert id == transaction.id
    end

    test "renders 404 when transaction does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = get(conn, ~p"/api/transactions/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "renders 422 when id is invalid format", %{conn: conn} do
      conn = get(conn, ~p"/api/transactions/invalid-uuid")
      assert conn.status == 422
    end

    test "returns 401 without API key", %{transaction: transaction} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/transactions/#{transaction.id}")

      assert json_response(conn, 401)
    end
  end

  describe "create (POST /api/transactions)" do
    test "creates transaction", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      conn =
        post(
          conn,
          ~p"/api/transactions",
          create_attrs(platform_tenant.id, account_holder.id)
        )

      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "TransactionResponse", api_spec)

      assert %{
               "id" => id,
               "transaction_type" => "credit_transfer",
               "status" => "pending",
               "amount" => 10_000,
               "currency" => "USD",
               "account_holder_id" => account_holder_id
             } = response

      assert is_binary(id)
      assert account_holder_id == account_holder.id
      assert Plug.Conn.get_resp_header(conn, "location") == ["/api/transactions/#{id}"]
    end

    test "creates transaction with optional fields", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id)
        |> Map.merge(%{
          transaction_type: "direct_debit",
          status: "accepted",
          amount: 50_000,
          currency: "EUR",
          end_to_end_id: "E2E-TEST-001",
          instruction_id: "INSTR-001",
          status_reason_code: "ACCP",
          requested_execution_date: "2026-03-01",
          settlement_date: "2026-03-02",
          transaction_external_id: "ext-txn-ctrl-001"
        })

      conn = post(conn, ~p"/api/transactions", attrs)
      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "TransactionResponse", api_spec)

      assert %{
               "transaction_type" => "direct_debit",
               "status" => "accepted",
               "amount" => 50_000,
               "currency" => "EUR",
               "end_to_end_id" => "E2E-TEST-001",
               "instruction_id" => "INSTR-001",
               "status_reason_code" => "ACCP",
               "settlement_date" => "2026-03-02"
             } = response
    end

    test "creates transaction with payment account links", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      debtor_account =
        insert(:payment_account,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id
        )

      creditor_account =
        insert(:payment_account,
          tenant_id: platform_tenant.id,
          account_holder_id: account_holder.id
        )

      attrs =
        create_attrs(platform_tenant.id, account_holder.id)
        |> Map.merge(%{
          transaction_type: "internal_transfer",
          debtor_payment_account_id: debtor_account.id,
          creditor_payment_account_id: creditor_account.id
        })

      conn = post(conn, ~p"/api/transactions", attrs)
      response = json_response(conn, 201)
      api_spec = ApiSpec.spec()

      assert_schema(response, "TransactionResponse", api_spec)

      assert %{
               "transaction_type" => "internal_transfer",
               "debtor_payment_account_id" => debtor_id,
               "creditor_payment_account_id" => creditor_id
             } = response

      assert debtor_id == debtor_account.id
      assert creditor_id == creditor_account.id
    end

    test "renders errors when required fields are missing", %{conn: conn} do
      conn = post(conn, ~p"/api/transactions", @invalid_attrs)
      response = json_response(conn, 422)
      assert %{"errors" => errors} = response
      assert is_list(errors)
      assert errors != []
    end

    test "renders errors when transaction_type is invalid enum", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      attrs =
        create_attrs(platform_tenant.id, account_holder.id)
        |> Map.put(:transaction_type, "invalid_type")

      conn = post(conn, ~p"/api/transactions", attrs)
      assert json_response(conn, 422)
    end

    test "returns 401 without API key", %{account_holder: account_holder} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/transactions",
          @base_attrs |> Map.put(:account_holder_id, account_holder.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "update (PUT /api/transactions/:id)" do
    setup [:create_transaction]

    test "updates transaction with valid data", %{
      conn: conn,
      transaction: transaction,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      conn =
        put(
          conn,
          ~p"/api/transactions/#{transaction.id}",
          update_attrs(platform_tenant.id, account_holder.id)
        )

      response = json_response(conn, 200)
      api_spec = ApiSpec.spec()

      assert_schema(response, "TransactionResponse", api_spec)

      assert %{
               "id" => id,
               "status" => "settled"
             } = response

      assert id == transaction.id
    end

    test "renders errors when data is invalid", %{conn: conn, transaction: transaction} do
      conn = put(conn, ~p"/api/transactions/#{transaction.id}", @invalid_attrs)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert is_list(errors)
      assert errors != []
    end

    test "renders 404 when transaction does not exist", %{
      conn: conn,
      platform_tenant: platform_tenant,
      account_holder: account_holder
    } do
      non_existent_id = Ecto.UUID.generate()

      conn =
        put(
          conn,
          ~p"/api/transactions/#{non_existent_id}",
          update_attrs(platform_tenant.id, account_holder.id)
        )

      assert json_response(conn, 404)
    end

    test "returns 401 without API key", %{
      transaction: transaction,
      account_holder: account_holder
    } do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put(
          ~p"/api/transactions/#{transaction.id}",
          @update_attrs |> Map.put(:account_holder_id, account_holder.id)
        )

      assert json_response(conn, 401)
    end
  end

  describe "delete (DELETE /api/transactions/:id)" do
    setup [:create_transaction]

    test "deletes transaction", %{
      conn: conn,
      transaction: transaction,
      plain_api_key: plain_api_key
    } do
      delete_conn = delete(conn, ~p"/api/transactions/#{transaction.id}")
      assert response(delete_conn, 204)

      get_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> get(~p"/api/transactions/#{transaction.id}")

      assert json_response(get_conn, 404)
    end

    test "renders 404 when transaction does not exist", %{conn: conn} do
      non_existent_id = Ecto.UUID.generate()
      conn = delete(conn, ~p"/api/transactions/#{non_existent_id}")
      assert json_response(conn, 404)
    end

    test "cannot delete transaction twice", %{
      conn: conn,
      transaction: transaction,
      plain_api_key: plain_api_key
    } do
      conn = delete(conn, ~p"/api/transactions/#{transaction.id}")
      assert response(conn, 204)

      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("x-api-key", plain_api_key)
        |> delete(~p"/api/transactions/#{transaction.id}")

      assert json_response(conn2, 404)
    end

    test "returns 401 without API key", %{transaction: transaction} do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> delete(~p"/api/transactions/#{transaction.id}")

      assert json_response(conn, 401)
    end
  end

  describe "OpenAPI spec validation" do
    test "OpenAPI spec includes transaction endpoints", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"openapi" => "3.1.0", "paths" => paths} = response

      assert paths["/api/transactions"]
      assert paths["/api/transactions"]["get"]
      assert paths["/api/transactions"]["post"]
      assert paths["/api/transactions/{id}"]
      assert paths["/api/transactions/{id}"]["get"]
      assert paths["/api/transactions/{id}"]["put"]
      assert paths["/api/transactions/{id}"]["delete"]
    end

    test "OpenAPI spec includes Transaction schemas", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{"components" => %{"schemas" => schemas}} = response

      assert schemas["TransactionRequest"]
      assert schemas["TransactionResponse"]
      assert schemas["TransactionListResponse"]
    end

    test "TransactionRequest excludes server-generated readOnly fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => %{"TransactionRequest" => request_schema}
               }
             } = response

      refute get_in(request_schema, ["properties", "id"])
      refute get_in(request_schema, ["properties", "inserted_at"])
      refute get_in(request_schema, ["properties", "updated_at"])

      assert get_in(request_schema, ["properties", "transaction_type"])
      assert get_in(request_schema, ["properties", "amount"])
      assert get_in(request_schema, ["properties", "currency"])
      assert get_in(request_schema, ["properties", "account_holder_id"])
    end

    test "TransactionResponse includes all fields", %{conn: conn} do
      conn = get(conn, ~p"/api/openapi")
      response = json_response(conn, 200)

      assert %{
               "components" => %{
                 "schemas" => %{"TransactionResponse" => response_schema}
               }
             } = response

      assert get_in(response_schema, ["properties", "id"])
      assert get_in(response_schema, ["properties", "transaction_type"])
      assert get_in(response_schema, ["properties", "status"])
      assert get_in(response_schema, ["properties", "amount"])
      assert get_in(response_schema, ["properties", "currency"])
      assert get_in(response_schema, ["properties", "account_holder_id"])
      assert get_in(response_schema, ["properties", "inserted_at"])
      assert get_in(response_schema, ["properties", "updated_at"])
    end
  end

  defp create_transaction(%{platform_tenant: platform_tenant, account_holder: account_holder}) do
    transaction =
      insert(:transaction,
        tenant_id: platform_tenant.id,
        account_holder_id: account_holder.id,
        transaction_type: :credit_transfer,
        amount: 10_000,
        currency: "USD"
      )

    %{transaction: transaction}
  end
end

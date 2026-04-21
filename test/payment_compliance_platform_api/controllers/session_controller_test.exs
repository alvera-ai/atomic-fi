defmodule PaymentCompliancePlatformApi.SessionControllerTest do
  use PaymentCompliancePlatformWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions
  import PaymentCompliancePlatform.Factory

  alias PaymentCompliancePlatformApi.ApiSpec

  @password "password123"

  defp build_auth_fixtures(%{conn: conn}) do
    tenant = insert(:tenant)
    role = insert(:role, tenant_id: tenant.id)

    user =
      insert(:user,
        tenant_id: tenant.id,
        hashed_password: Bcrypt.hash_pwd_salt(@password)
      )

    insert(:user_role_mapping, user_id: user.id, role_id: role.id)

    conn = put_req_header(conn, "content-type", "application/json")

    %{conn: conn, tenant: tenant, role: role, user: user}
  end

  describe "create (POST /api/sessions) — public" do
    setup :build_auth_fixtures

    test "returns 201 with session_token on valid credentials", %{
      conn: conn,
      user: user,
      tenant: tenant,
      role: role
    } do
      attrs = %{email: user.email, password: @password, tenant_slug: tenant.slug}

      conn = post(conn, ~p"/api/sessions", attrs)
      response = json_response(conn, 201)

      assert_schema(response, "SessionResponse", ApiSpec.spec())

      assert is_binary(response["bearer"])
      assert response["type"] == "user"
      assert response["tenant"]["id"] == tenant.id
      assert response["tenant"]["slug"] == tenant.slug
      assert response["role"]["id"] == role.id
      assert response["user"]["id"] == user.id
      assert response["user"]["email"] == user.email
      # api_key block must be null on Bearer sessions
      assert is_nil(response["api_key"])
      # expires_at is set (default 24h window) and in the future
      assert {:ok, expires_at, _} = DateTime.from_iso8601(response["expires_at"])
      assert DateTime.compare(expires_at, DateTime.utc_now()) == :gt
    end

    test "respects custom expires_in", %{conn: conn, user: user, tenant: tenant} do
      attrs = %{
        email: user.email,
        password: @password,
        tenant_slug: tenant.slug,
        expires_in: 300
      }

      conn = post(conn, ~p"/api/sessions", attrs)
      response = json_response(conn, 201)

      {:ok, expires_at, _} = DateTime.from_iso8601(response["expires_at"])
      seconds_from_now = DateTime.diff(expires_at, DateTime.utc_now(), :second)
      # Allow some slack for request latency
      assert seconds_from_now > 290 and seconds_from_now <= 310
    end

    test "returns 401 on wrong password", %{conn: conn, user: user, tenant: tenant} do
      attrs = %{email: user.email, password: "WRONG", tenant_slug: tenant.slug}

      conn = post(conn, ~p"/api/sessions", attrs)
      assert json_response(conn, 401)
    end

    test "returns 401 on unknown email", %{conn: conn, tenant: tenant} do
      attrs = %{
        email: "nobody-#{Ecto.UUID.generate()}@example.com",
        password: @password,
        tenant_slug: tenant.slug
      }

      conn = post(conn, ~p"/api/sessions", attrs)
      assert json_response(conn, 401)
    end

    test "returns 401 when tenant_slug does not exist", %{conn: conn, user: user} do
      attrs = %{
        email: user.email,
        password: @password,
        tenant_slug: "does-not-exist-#{Ecto.UUID.generate()}"
      }

      conn = post(conn, ~p"/api/sessions", attrs)
      assert json_response(conn, 401)
    end

    test "returns 401 when user does not belong to the tenant_slug's tenant",
         %{conn: conn, user: user} do
      other_tenant = insert(:tenant)

      attrs = %{email: user.email, password: @password, tenant_slug: other_tenant.slug}

      conn = post(conn, ~p"/api/sessions", attrs)
      assert json_response(conn, 401)
    end

    test "returns 401 when user has no role assigned", %{conn: conn, tenant: tenant} do
      role_less_user =
        insert(:user,
          tenant_id: tenant.id,
          hashed_password: Bcrypt.hash_pwd_salt(@password)
        )

      attrs = %{
        email: role_less_user.email,
        password: @password,
        tenant_slug: tenant.slug
      }

      conn = post(conn, ~p"/api/sessions", attrs)
      assert json_response(conn, 401)
    end

    test "returns 422 on missing required fields", %{conn: conn} do
      conn = post(conn, ~p"/api/sessions", %{email: "x@example.com"})
      assert json_response(conn, 422)
    end

    test "returned Bearer token authorises subsequent requests", %{
      conn: conn,
      user: user,
      tenant: tenant
    } do
      attrs = %{email: user.email, password: @password, tenant_slug: tenant.slug}
      %{"bearer" => token} = post(conn, ~p"/api/sessions", attrs) |> json_response(201)

      verify_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer " <> token)
        |> get(~p"/api/sessions/verify")

      response = json_response(verify_conn, 200)
      assert response["user"]["id"] == user.id
      assert response["type"] == "user"
      # session_token is NOT re-exposed on verify
      assert is_nil(response["bearer"])
    end
  end

  describe "verify (GET /api/sessions/verify)" do
    test "accepts X-API-Key and returns api-key info", ctx do
      ctx = Map.merge(ctx, Enum.into(setup_platform_admin_api(ctx), %{}))
      verify_conn = get(ctx.conn, ~p"/api/sessions/verify")
      response = json_response(verify_conn, 200)

      assert_schema(response, "SessionResponse", ApiSpec.spec())
      assert response["type"] == "api"
      assert response["api_key"]["id"] == ctx.api_key.id
      assert is_nil(response["user"])
      assert is_nil(response["bearer"])
    end

    test "returns 401 without credentials" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/sessions/verify")

      assert json_response(conn, 401)
    end

    test "returns 401 with invalid Bearer token" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer not-a-valid-token")
        |> get(~p"/api/sessions/verify")

      assert json_response(conn, 401)
    end
  end

  describe "delete (DELETE /api/sessions)" do
    setup :build_auth_fixtures

    test "revokes Bearer session and token becomes invalid", %{
      conn: conn,
      user: user,
      tenant: tenant
    } do
      attrs = %{email: user.email, password: @password, tenant_slug: tenant.slug}
      %{"bearer" => token} = post(conn, ~p"/api/sessions", attrs) |> json_response(201)

      delete_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> token)
        |> delete(~p"/api/sessions")

      assert response(delete_conn, 204)

      retry_conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer " <> token)
        |> get(~p"/api/sessions/verify")

      assert json_response(retry_conn, 401)
    end

    test "returns 422 when called with X-API-Key (non-Bearer session)", ctx do
      ctx = Map.merge(ctx, Enum.into(setup_platform_admin_api(ctx), %{}))
      delete_conn = delete(ctx.conn, ~p"/api/sessions")
      response = json_response(delete_conn, 422)
      assert response["errors"]["detail"] =~ "Only Bearer"
    end
  end

  describe "OpenAPI spec" do
    test "spec includes session endpoints + schemas", %{conn: conn} do
      response = get(conn, ~p"/api/openapi") |> json_response(200)

      paths = response["paths"]
      assert paths["/api/sessions"]["post"]
      assert paths["/api/sessions"]["delete"]
      assert paths["/api/sessions/verify"]["get"]

      schemas = response["components"]["schemas"]
      assert schemas["SessionRequest"]
      assert schemas["SessionResponse"]

      # writeOnly auth fields appear in Request
      req_props = schemas["SessionRequest"]["properties"]
      assert Map.has_key?(req_props, "email")
      assert Map.has_key?(req_props, "password")
      assert Map.has_key?(req_props, "tenant_slug")

      # ...and are stripped from Response
      resp_props = schemas["SessionResponse"]["properties"]
      refute Map.has_key?(resp_props, "email")
      refute Map.has_key?(resp_props, "password")
      refute Map.has_key?(resp_props, "tenant_slug")
    end
  end
end

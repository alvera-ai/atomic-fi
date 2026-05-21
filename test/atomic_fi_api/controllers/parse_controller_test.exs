defmodule AtomicFiApi.ParseControllerTest do
  use AtomicFiWeb.ConnCase, async: true

  describe "POST /api/parse — request validation (no LLM involved)" do
    test "rejects an empty body (422)", %{conn: conn} do
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/parse", "{}")

      assert json_response(resp, 422)
    end

    test "rejects a missing files array (422)", %{conn: conn} do
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/parse", Jason.encode!(%{"not_files" => []}))

      assert json_response(resp, 422)
    end

    test "well-shaped body with unknown document_type → per-file error (200)", %{conn: conn} do
      # The OpenApiSpex enum constraint is informational here — the
      # controller reports the bad document_type inline (per-file
      # success: false) rather than rejecting the whole request. That
      # matches how the Python service behaved.
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/parse",
          Jason.encode!(%{
            "files" => [
              %{
                "name" => "x.png",
                "content_type" => "image/png",
                "document_type" => "selfie",
                "data_base64" => Base.encode64(<<0>>)
              }
            ]
          })
        )

      body = json_response(resp, 200)
      assert [%{"success" => false, "error" => err}] = body["results"]
      assert err =~ "invalid document_type"
    end

    test "well-shaped body with invalid base64 → per-file error (200)", %{conn: conn} do
      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/parse",
          Jason.encode!(%{
            "files" => [
              %{
                "name" => "x.png",
                "content_type" => "image/png",
                "document_type" => "passport",
                # Not valid base64 — Base.decode64/1 returns :error.
                "data_base64" => "!!!!"
              }
            ]
          })
        )

      body = json_response(resp, 200)
      assert [%{"filename" => "x.png", "success" => false, "error" => err}] = body["results"]
      assert err =~ "invalid base64"
    end
  end
end

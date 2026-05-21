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

  # Ported from example-apps/onboarding-flow/e2e/ai-extraction.spec.ts.
  # Drives the local Ollama vision model — the only LLM transport this repo
  # has today, so it runs as part of the normal suite (no exclude tag).
  describe "POST /api/parse — document extraction (ai-extraction.spec.ts)" do
    @passport Path.expand("../../support/fixtures/documents/usa-passport.jpg", __DIR__)

    # Real local vision extraction is slow — well past ExUnit's 60s default.
    # Sits above the controller's 5-min per-file timeout so that fires first.
    @tag timeout: 360_000
    test "extracts structured data from an uploaded passport image", %{conn: conn} do
      data_base64 = @passport |> File.read!() |> Base.encode64()

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> post(
          ~p"/api/parse",
          Jason.encode!(%{
            "files" => [
              %{
                "name" => "usa-passport.jpg",
                "content_type" => "image/jpeg",
                "document_type" => "passport",
                "data_base64" => data_base64
              }
            ]
          })
        )

      body = json_response(resp, 200)

      assert [%{"filename" => "usa-passport.jpg", "success" => true, "data" => data}] =
               body["results"]

      assert is_map(data) and map_size(data) > 0
    end
  end
end

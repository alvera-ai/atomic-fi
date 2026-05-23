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
  # The LLM transport is pointed at Mockoon (see config/test.exs), so this
  # runs in `mix test` without Ollama. A developer can opt back into a real
  # Ollama via config/test.secret.exs.
  describe "POST /api/parse — document extraction (ai-extraction.spec.ts)" do
    @passport Path.expand("../../support/fixtures/documents/usa-passport.jpg", __DIR__)

    # Generous timeout retained — a real Ollama run via test.secret.exs
    # can take minutes per request.
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

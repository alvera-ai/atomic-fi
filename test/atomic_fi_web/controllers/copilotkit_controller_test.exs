defmodule AtomicFiWeb.CopilotkitControllerTest do
  @moduledoc """
  Tests `POST /api/copilotkit` — the CopilotKit Runtime Protocol
  passthrough.

  The non-streaming operations (`availableAgents`, `loadAgentState`)
  return constant JSON; we assert that constant.

  `generateCopilotResponse` is the streaming mutation; it hits a live
  Ollama daemon. That branch is tagged `:ollama` and excluded from
  the default test run.
  """
  use AtomicFiWeb.ConnCase, async: true

  describe "availableAgents query" do
    test "returns the constant empty-agents payload", %{conn: conn} do
      body =
        conn
        |> post_json(%{
          "operationName" => "availableAgents",
          "query" => "query availableAgents { availableAgents { agents { id } } }"
        })
        |> json_response(200)

      assert body == %{
               "data" => %{"availableAgents" => %{"agents" => []}}
             }
    end
  end

  describe "loadAgentState query" do
    test "returns threadExists: false with the caller's threadId", %{conn: conn} do
      body =
        conn
        |> post_json(%{
          "operationName" => "loadAgentState",
          "variables" => %{"data" => %{"threadId" => "thread-xyz"}},
          "query" => "query loadAgentState($data: LoadAgentStateInput!) { ... }"
        })
        |> json_response(200)

      assert body["data"]["loadAgentState"]["threadId"] == "thread-xyz"
      assert body["data"]["loadAgentState"]["threadExists"] == false
      assert body["data"]["loadAgentState"]["state"] == "{}"
      assert body["data"]["loadAgentState"]["messages"] == []
    end
  end

  describe "unknown / malformed operations" do
    test "unknown operationName → 400 with error", %{conn: conn} do
      body =
        conn
        |> post_json(%{"operationName" => "somethingElse"})
        |> json_response(400)

      assert body["errors"] |> List.first() |> Map.get("message") =~ "somethingElse"
    end

    test "missing operationName → 400", %{conn: conn} do
      body =
        conn
        |> post_json(%{"query" => "{ __typename }"})
        |> json_response(400)

      assert body["errors"] |> List.first() |> Map.get("message") =~ "operationName"
    end
  end

  defp post_json(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/copilotkit", Jason.encode!(body))
  end
end

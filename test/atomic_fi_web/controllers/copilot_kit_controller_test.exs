defmodule AtomicFiWeb.CopilotKitControllerTest do
  @moduledoc """
  Tests `POST /api/copilotkit` — the CopilotKit Runtime Protocol
  passthrough.

  `availableAgents` / `loadAgentState` return constant JSON.
  `generateCopilotResponse` streams `multipart/mixed` chunks and drives
  the local Ollama reasoning model (see `config/test.secret.exs`); the
  full suite runs it — nothing is excluded (`test/test_helper.exs`).
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

  describe "generateCopilotResponse mutation" do
    # A local reasoning model is slow — past ExUnit's 60s default. Sits
    # above ReqLLM's 5-min receive timeout so that surfaces first.
    @tag timeout: 360_000
    test "streams the LLM turn as multipart/mixed parts, ending hasNext:false", %{conn: conn} do
      conn =
        post_json(conn, %{
          "operationName" => "generateCopilotResponse",
          "variables" => %{
            "data" => %{
              "threadId" => "thread-jdm",
              "messages" => [
                %{
                  "textMessage" => %{
                    "role" => "user",
                    "content" => "Reply with exactly the word: hello"
                  }
                }
              ],
              "frontend" => %{"actions" => []}
            }
          }
        })

      assert conn.status == 200

      assert conn |> get_resp_header("content-type") |> List.first() =~
               ~s(multipart/mixed; boundary="-")

      parts = conn |> response(200) |> decode_parts()

      # First part carries the non-deferred fields, echoing our threadId.
      assert hd(parts)["data"]["generateCopilotResponse"]["threadId"] == "thread-jdm"
      # Last part is the stream terminator.
      assert List.last(parts) == %{"hasNext" => false}
      # The assistant's reply streamed as a TextMessageOutput.
      assert Enum.any?(parts, &text_message?/1)
    end

    @tag timeout: 360_000
    test "relays an add_node tool call as an ActionExecutionMessageOutput", %{conn: conn} do
      conn =
        post_json(conn, %{
          "operationName" => "generateCopilotResponse",
          "variables" => %{
            "data" => %{
              "threadId" => "thread-tool",
              "messages" => [
                %{
                  "textMessage" => %{
                    "role" => "user",
                    "content" => "Add an expression node named amount-floor to the graph."
                  }
                }
              ],
              "frontend" => %{
                "actions" => [
                  %{
                    "name" => "add_node",
                    "description" => "Add a node to the open decision graph.",
                    "jsonSchema" =>
                      Jason.encode!(%{
                        "type" => "object",
                        "properties" => %{
                          "type" => %{"type" => "string", "description" => "JDM node kind."},
                          "name" => %{"type" => "string", "description" => "Node name."}
                        },
                        "required" => ["type", "name"]
                      })
                  }
                ]
              }
            }
          }
        })

      assert conn.status == 200
      parts = conn |> response(200) |> decode_parts()

      # The full round trip: the model emits a tool_call, the stream
      # relays it as an ActionExecutionMessageOutput the React side runs.
      action = Enum.find_value(parts, &action_execution_message/1)
      assert action, "expected an ActionExecutionMessageOutput in the stream"
      assert action["name"] == "add_node"
      assert {:ok, args} = Jason.decode(action["arguments"])
      assert is_map(args)
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────

  defp post_json(conn, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(~p"/api/copilotkit", Jason.encode!(body))
  end

  # Split a multipart/mixed body (boundary "-") into decoded JSON parts —
  # mirrors AtomicFi.CopilotKitContext.IncrementalTest's reader.
  defp decode_parts(body) do
    body
    |> String.split("\r\n---")
    |> Enum.flat_map(fn part ->
      cond do
        part == "" -> []
        String.starts_with?(part, "--") -> []
        true -> [decode_part(part)]
      end
    end)
  end

  defp decode_part("\r\n" <> rest), do: decode_part(rest)

  defp decode_part(part) do
    [_headers, json] = String.split(part, "\r\n\r\n", parts: 2)
    json |> String.trim_trailing() |> Jason.decode!()
  end

  defp text_message?(%{"incremental" => incrementals}) do
    Enum.any?(incrementals, fn inc ->
      Enum.any?(inc["items"] || [], &(&1["__typename"] == "TextMessageOutput"))
    end)
  end

  defp text_message?(_), do: false

  defp action_execution_message(%{"incremental" => incrementals}) do
    Enum.find_value(incrementals, fn inc ->
      Enum.find(inc["items"] || [], &(&1["__typename"] == "ActionExecutionMessageOutput"))
    end)
  end

  defp action_execution_message(_), do: nil
end

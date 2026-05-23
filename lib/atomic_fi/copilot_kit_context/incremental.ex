defmodule AtomicFi.CopilotKitContext.Incremental do
  @moduledoc """
  Encoder for GraphQL Incremental Delivery (`@defer`/`@stream` directives)
  over `multipart/mixed`. Mirrors the wire format produced by
  `@graphql-yoga/plugin-defer-stream@1.10.5`, which the CopilotKit React
  client (`@copilotkit/runtime-client-gql@1.10.5`) consumes.

  Wire shape:

      --⏎
      Content-Type: application/json; charset=utf-8⏎
      ⏎
      <json-payload>⏎
      --⏎
      Content-Type: application/json; charset=utf-8⏎
      ⏎
      <json-payload>⏎
      ...
      ----⏎

  All chunks except the final one carry `hasNext: true`; the final chunk
  carries `hasNext: false` and the terminator boundary `----`.

  Boundary is `-` per `Content-Type: multipart/mixed; boundary="-"`.
  This module emits parts via `Plug.Conn.chunk/2`; the caller is
  responsible for `put_resp_content_type/2` + `send_chunked/2` first.
  """

  import Plug.Conn, only: [chunk: 2]

  @boundary "-"
  @part_header "Content-Type: application/json; charset=utf-8\r\n\r\n"

  @doc """
  Emit the FIRST multipart part — the initial response with non-deferred,
  non-streamed fields. CopilotKit's `generateCopilotResponse` mutation
  selects `threadId`, `runId`, `extensions` at this level; everything
  else (`messages`, `metaEvents`, `status`) is deferred or streamed.

  Pass `:hasNext` to control the terminating flag (defaults to `true`
  since the loop almost always follows up with `messages` / `status`).
  """
  @spec send_initial(Plug.Conn.t(), String.t(), String.t(), keyword()) :: Plug.Conn.t()
  def send_initial(conn, thread_id, run_id, opts \\ []) do
    payload = %{
      "data" => %{
        "generateCopilotResponse" => %{
          "threadId" => thread_id,
          "runId" => run_id,
          "extensions" => nil,
          "messages" => [],
          "metaEvents" => []
        }
      },
      "hasNext" => Keyword.get(opts, :hasNext, true)
    }

    write_part(conn, payload)
  end

  @doc """
  Emit an `@stream` continuation — a new item appended to a list field.

    `path`   — JSON path of the list field, e.g.
               `["generateCopilotResponse", "messages"]`.
    `items`  — list of items to append (usually one, for one streamed
               value per chunk).

  GraphQL Incremental Delivery uses `items` for `@stream` and `data` for
  `@defer`.
  """
  @spec stream_chunk(Plug.Conn.t(), [String.t()], [map()]) :: Plug.Conn.t()
  def stream_chunk(conn, path, items) when is_list(path) and is_list(items) do
    payload = %{
      "incremental" => [
        %{"path" => path, "items" => items}
      ],
      "hasNext" => true
    }

    write_part(conn, payload)
  end

  @doc """
  Emit an `@defer` resolution — data filled in for a previously-empty
  field. CopilotKit uses this for `status` after the response is complete.
  """
  @spec defer_chunk(Plug.Conn.t(), [String.t()], map()) :: Plug.Conn.t()
  def defer_chunk(conn, path, data) when is_list(path) and is_map(data) do
    payload = %{
      "incremental" => [
        %{"path" => path, "data" => data}
      ],
      "hasNext" => true
    }

    write_part(conn, payload)
  end

  @doc """
  Emit the FINAL part — `{"hasNext": false}` — and the multipart
  terminator. After this the response stream is closed; the caller
  should not write further chunks.
  """
  @spec send_final(Plug.Conn.t()) :: Plug.Conn.t()
  def send_final(conn) do
    final_payload = %{"hasNext" => false}
    body = build_part_body(final_payload) <> "\r\n--#{@boundary}--\r\n"

    case chunk(conn, body) do
      {:ok, conn} -> conn
      {:error, _reason} -> conn
    end
  end

  # ── internals ──────────────────────────────────────────────────────

  defp write_part(conn, payload) do
    body = build_part_body(payload)

    case chunk(conn, body) do
      {:ok, conn} -> conn
      {:error, _reason} -> conn
    end
  end

  defp build_part_body(payload) do
    "\r\n--#{@boundary}\r\n" <> @part_header <> Jason.encode!(payload)
  end
end

defmodule AtomicFi.CopilotKitContext.IncrementalTest do
  @moduledoc """
  Verifies the wire shape of GraphQL Incremental Delivery chunks
  written via `Plug.Conn.chunk/2`. We use `Plug.Test.conn/2` +
  `Phoenix.ConnTest`-style chunked-response reading to assert on the
  raw multipart/mixed body the React client will parse.
  """
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias AtomicFi.CopilotKitContext.Incremental

  setup do
    {:ok, conn: open_chunked()}
  end

  test "send_initial writes a boundary part with threadId / runId / empty messages", %{conn: conn} do
    conn = Incremental.send_initial(conn, "thread-1", "run-1")
    body = sent_body(conn)

    # Boundary string is "-", so per RFC 2046 the on-the-wire boundary
    # is "\r\n--" + "-" + "\r\n" = "\r\n---\r\n".
    assert body =~ "\r\n---\r\n"
    assert body =~ "Content-Type: application/json; charset=utf-8\r\n\r\n"

    payload = first_part_json(conn)

    assert payload["data"]["generateCopilotResponse"]["threadId"] == "thread-1"
    assert payload["data"]["generateCopilotResponse"]["runId"] == "run-1"
    assert payload["data"]["generateCopilotResponse"]["messages"] == []
    assert payload["hasNext"] == true
  end

  test "stream_chunk encodes path + items as a GraphQL @stream continuation", %{conn: conn} do
    item = %{"__typename" => "TextMessageOutput", "content" => "hi"}

    conn =
      Incremental.stream_chunk(
        conn,
        ["generateCopilotResponse", "messages"],
        [item]
      )

    payload = first_part_json(conn)

    assert [%{"path" => ["generateCopilotResponse", "messages"], "items" => [^item]}] =
             payload["incremental"]

    assert payload["hasNext"] == true
  end

  test "defer_chunk encodes path + data as a GraphQL @defer resolution", %{conn: conn} do
    conn =
      Incremental.defer_chunk(
        conn,
        ["generateCopilotResponse"],
        %{"status" => %{"code" => "Success"}}
      )

    payload = first_part_json(conn)

    assert [%{"path" => ["generateCopilotResponse"], "data" => data}] = payload["incremental"]
    assert data == %{"status" => %{"code" => "Success"}}
    assert payload["hasNext"] == true
  end

  test "send_final emits hasNext:false + multipart terminator", %{conn: conn} do
    conn = Incremental.send_final(conn)
    body = sent_body(conn)

    payload = first_part_json(conn)
    assert payload == %{"hasNext" => false}
    # The closing terminator is "\r\n--" + boundary + "--\r\n", i.e.
    # "\r\n-----\r\n" for boundary="-".
    assert String.ends_with?(body, "\r\n-----\r\n")
  end

  test "a multi-part stream is shaped end-to-end", %{conn: conn} do
    msg = %{"__typename" => "TextMessageOutput", "content" => "hello"}

    conn =
      conn
      |> Incremental.send_initial("t", "r")
      |> Incremental.stream_chunk(["generateCopilotResponse", "messages"], [msg])
      |> Incremental.defer_chunk(["generateCopilotResponse"], %{
        "status" => %{"code" => "Success"}
      })
      |> Incremental.send_final()

    body = sent_body(conn)

    payloads = decode_all_parts(body)
    assert length(payloads) == 4

    [initial, stream, defer, final] = payloads
    assert initial["data"]["generateCopilotResponse"]["threadId"] == "t"
    assert hd(stream["incremental"])["items"] == [msg]
    assert hd(defer["incremental"])["data"]["status"]["code"] == "Success"
    assert final == %{"hasNext" => false}
  end

  # ── helpers ────────────────────────────────────────────────────────

  defp open_chunked do
    conn(:post, "/api/copilotkit", "")
    |> put_resp_content_type("multipart/mixed; boundary=\"-\"")
    |> send_chunked(200)
  end

  # Plug.Test's `sent_resp/1` doesn't surface chunked output — chunked
  # responses are streaming, not finalized — but Plug.Conn.chunk/2 still
  # appends each chunk's bytes onto `conn.resp_body`. Reading directly
  # is the canonical Phoenix.ConnTest pattern for inspecting a chunked
  # response in tests.
  defp sent_body(conn), do: IO.iodata_to_binary(conn.resp_body)

  defp first_part_json(conn) do
    conn
    |> sent_body()
    |> first_payload()
  end

  # Walk the multipart/mixed body and return every part's decoded JSON.
  defp decode_all_parts(body) do
    body
    # On the wire each part is delimited by "\r\n--" + boundary + ...
    # With boundary "-" that's "\r\n---". The terminator is
    # "\r\n--" + "-" + "--\r\n" = "\r\n-----\r\n".
    |> String.split("\r\n---")
    |> Enum.flat_map(fn part ->
      cond do
        part == "" -> []
        # Terminator section: leading "--\r\n" with no body.
        String.starts_with?(part, "--") -> []
        true -> [decode_part(part)]
      end
    end)
  end

  defp first_payload(body) do
    body |> decode_all_parts() |> List.first()
  end

  defp decode_part("\r\n" <> rest) do
    [_headers, json] = String.split(rest, "\r\n\r\n", parts: 2)
    json |> String.trim_trailing() |> Jason.decode!()
  end

  defp decode_part(part) do
    [_headers, json] = String.split(part, "\r\n\r\n", parts: 2)
    json |> String.trim_trailing() |> Jason.decode!()
  end
end

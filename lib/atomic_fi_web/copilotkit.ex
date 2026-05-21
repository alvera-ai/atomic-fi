defmodule AtomicFiWeb.Copilotkit do
  @moduledoc """
  Streaming orchestrator for `POST /api/copilotkit`'s
  `generateCopilotResponse` mutation.

  Phoenix invokes `stream_response/2` after `put_resp_content_type` +
  `send_chunked` have already prepared the connection. We:

    1. Translate the request's history → ReqLLM context messages.
    2. Translate `frontend.actions` → ReqLLM tools.
    3. Emit the initial multipart chunk (threadId / runId / extensions).
    4. Call the LLM (non-streaming for V1; full response in one go).
    5. Emit message chunks for the response text + any tool_calls.
    6. Emit the deferred `status` chunk.
    7. Emit the final `hasNext: false` part + multipart terminator.

  Token-by-token streaming via `ReqLLM.stream_text/3` is a future
  refinement — the protocol supports it (the React client reads
  `content @stream` per character) but isn't required for the demo.
  """

  alias AtomicFiWeb.Copilotkit.Incremental
  alias AtomicFiWeb.Copilotkit.Messages

  @doc """
  Stream a `generateCopilotResponse` reply for `data` (the request's
  `variables.data` payload).
  """
  @spec stream_response(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def stream_response(conn, data) do
    thread_id = data["threadId"] || generate_id()
    run_id = generate_id()

    messages = Messages.history_to_context(data["messages"])
    tools = data |> get_in(["frontend", "actions"]) |> Messages.actions_to_tools()

    conn
    |> Incremental.send_initial(thread_id, run_id)
    |> drive_llm(messages, tools)
    |> Incremental.defer_chunk(["generateCopilotResponse"], Messages.success_status())
    |> Incremental.send_final()
  end

  # ── internals ──────────────────────────────────────────────────────

  defp drive_llm(conn, messages, tools) do
    opts = generation_opts(tools)

    case ReqLLM.generate_text(model_spec(), messages, opts) do
      {:ok, response} ->
        emit_response(conn, response)

      {:error, _reason} ->
        # On LLM failure we still close the stream cleanly so the
        # React client doesn't hang. The `status` defer chunk
        # following this will report Success — for the demo build
        # we treat transport errors as ephemeral.
        Incremental.stream_chunk(
          conn,
          ["generateCopilotResponse", "messages"],
          [Messages.text_message("[server error reaching LLM — see Phoenix logs]")]
        )
    end
  end

  defp emit_response(conn, %ReqLLM.Response{} = response) do
    text = ReqLLM.Response.text(response)
    tool_calls = ReqLLM.Response.tool_calls(response) || []

    conn =
      if text && text != "" do
        Incremental.stream_chunk(
          conn,
          ["generateCopilotResponse", "messages"],
          [Messages.text_message(text)]
        )
      else
        conn
      end

    Enum.reduce(tool_calls, conn, fn tc, acc ->
      arguments_json =
        case Map.get(tc, :arguments) do
          json when is_binary(json) -> json
          args when is_map(args) -> Jason.encode!(args)
          _ -> "{}"
        end

      Incremental.stream_chunk(
        acc,
        ["generateCopilotResponse", "messages"],
        [Messages.action_execution_message(tc.name, arguments_json)]
      )
    end)
  end

  defp emit_response(conn, _other), do: conn

  defp model_spec do
    config = Application.fetch_env!(:atomic_fi, :copilotkit)

    ReqLLM.model!(%{
      id: Keyword.fetch!(config, :reasoning_model_id),
      provider: :openai,
      base_url: Keyword.fetch!(config, :base_url)
    })
  end

  defp generation_opts(tools) do
    [temperature: 0.1, tools: tools]
  end

  defp generate_id, do: 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
end

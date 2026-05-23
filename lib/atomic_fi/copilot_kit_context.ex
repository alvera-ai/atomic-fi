defmodule AtomicFi.CopilotKitContext do
  @moduledoc """
  JDM-editor copilot — the context behind `POST /api/copilotkit`'s
  `generateCopilotResponse` mutation.

  A context-layer sibling of `AtomicFi.RuleEngine` (decision evaluation)
  and `AtomicFi.DocumentParser` (vision extraction).
  `AtomicFiWeb.CopilotKitController` is a dumb pass-through: it calls
  `stream_response/2` and nothing else.

  ## Two entry points

    * `complete/2` — one LLM turn. Pure: ReqLLM messages + tools in, a
      transport-free `t:completion/0` out (assistant text + tool calls).
      Unit-tested directly against the configured model.

    * `stream_response/2` — the full `generateCopilotResponse`
      orchestration: translate the CopilotKit request → ReqLLM, run
      `complete/2`, and stream the reply back over the already
      `send_chunked/2`'d connection as GraphQL Incremental Delivery
      `multipart/mixed` parts.

  The reasoning model + transport come from `config :atomic_fi, :copilotkit`
  (local Ollama by default).
  """

  alias AtomicFi.CopilotKitContext.Incremental
  alias AtomicFi.CopilotKitContext.Messages

  @messages_path ["generateCopilotResponse", "messages"]

  @typedoc "A tool call the model emitted — the action name + its raw JSON arguments string."
  @type tool_call :: %{name: String.t(), arguments: String.t()}

  @typedoc "A finished LLM turn — assistant text and any tool calls."
  @type completion :: %{text: String.t(), tool_calls: [tool_call()]}

  @doc """
  Stream a `generateCopilotResponse` reply for `data` (the request's
  `variables.data` payload) over an already-chunked connection.
  """
  @spec stream_response(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def stream_response(conn, data) do
    thread_id = data["threadId"] || generate_id()
    run_id = generate_id()

    messages = Messages.history_to_context(data["messages"])
    tools = data |> get_in(["frontend", "actions"]) |> Messages.actions_to_tools()

    conn
    |> Incremental.send_initial(thread_id, run_id)
    |> stream_completion(messages, tools)
    |> Incremental.defer_chunk(["generateCopilotResponse"], Messages.success_status())
    |> Incremental.send_final()
  end

  @doc """
  Run one LLM turn over `messages` with `tools` available.

  Returns `{:ok, completion}`, or `{:error, reason}` where `reason` is
  ReqLLM's error (transport failure, etc.) — the caller decides how to
  surface it.
  """
  @spec complete([ReqLLM.Message.t()], [ReqLLM.Tool.t()]) ::
          {:ok, completion()} | {:error, term()}
  def complete(messages, tools) when is_list(messages) and is_list(tools) do
    case ReqLLM.generate_text(model_spec(), messages, generation_opts(tools)) do
      {:ok, %ReqLLM.Response{} = response} -> {:ok, extract(response)}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── streaming ───────────────────────────────────────────────────────

  defp stream_completion(conn, messages, tools) do
    case complete(messages, tools) do
      {:ok, %{text: text, tool_calls: tool_calls}} ->
        conn
        |> stream_text(text)
        |> stream_tool_calls(tool_calls)

      {:error, _reason} ->
        # Close the stream cleanly so the React client doesn't hang; the
        # Phoenix log carries the real reason. The demo build treats LLM
        # transport errors as ephemeral.
        stream_message(
          conn,
          Messages.text_message("[server error reaching LLM — see Phoenix logs]")
        )
    end
  end

  defp stream_text(conn, ""), do: conn
  defp stream_text(conn, text), do: stream_message(conn, Messages.text_message(text))

  defp stream_tool_calls(conn, tool_calls) do
    Enum.reduce(tool_calls, conn, fn %{name: name, arguments: arguments}, acc ->
      stream_message(acc, Messages.action_execution_message(name, arguments))
    end)
  end

  defp stream_message(conn, message),
    do: Incremental.stream_chunk(conn, @messages_path, [message])

  defp generate_id, do: 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  # ── LLM turn ────────────────────────────────────────────────────────

  defp extract(%ReqLLM.Response{} = response) do
    %{
      text: ReqLLM.Response.text(response) || "",
      tool_calls:
        response |> ReqLLM.Response.tool_calls() |> List.wrap() |> Enum.map(&to_tool_call/1)
    }
  end

  # ReqLLM.ToolCall carries the name + arguments under :function (the
  # OpenAI wire shape — %{name: string, arguments: JSON-string}); there
  # is no top-level :name / :arguments.
  defp to_tool_call(%ReqLLM.ToolCall{function: %{name: name, arguments: arguments}}) do
    %{name: name, arguments: encode_arguments(arguments)}
  end

  defp encode_arguments(json) when is_binary(json), do: json
  defp encode_arguments(map) when is_map(map), do: Jason.encode!(map)

  defp model_spec do
    config = Application.fetch_env!(:atomic_fi, :copilotkit)

    ReqLLM.model!(%{
      id: Keyword.fetch!(config, :reasoning_model_id),
      provider: :openai,
      base_url: Keyword.fetch!(config, :base_url)
    })
  end

  defp generation_opts(tools) do
    config = Application.fetch_env!(:atomic_fi, :copilotkit)

    # ReqLLM's OpenAI provider resolves a credential even against Ollama;
    # without :api_key it raises before the request is sent. Mirrors
    # AtomicFi.DocumentParser.
    [temperature: 0.1, tools: tools, api_key: Keyword.fetch!(config, :api_key)]
  end
end

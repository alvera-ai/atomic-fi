defmodule AtomicFiWeb.Copilotkit.Messages do
  @moduledoc """
  Translation between CopilotKit's GraphQL message types and the shapes
  ReqLLM understands.

  CopilotKit message variants on the input side (`messages: [MessageInput]`):

    * `TextMessageInput`           role + content (string)
    * `ActionExecutionMessageInput` name + arguments (JSON string) + id
    * `ResultMessageInput`         actionExecutionId + result
    * `AgentStateMessageInput`     agent-mode state snapshot
    * `ImageMessageInput`          format + bytes (base64)

  On the output side (`messages @stream`):

    * `TextMessageOutput`
    * `ActionExecutionMessageOutput`
    * `ResultMessageOutput`
    * `AgentStateMessageOutput`
    * `ImageMessageOutput`

  For the JDM editor's flow we handle Text + ActionExecution + Result.
  AgentState / Image are protocol-defined but unused; we pass them
  through harmlessly (input) or never emit them (output).
  """

  alias ReqLLM.Message.ContentPart

  @doc """
  Convert the input `messages` array from a `generateCopilotResponse`
  request into a list of `%ReqLLM.Message{}`s. Drops messages whose
  shapes we don't translate (preserves a working text conversation).
  """
  @spec history_to_context([map()]) :: [ReqLLM.Message.t()]
  def history_to_context(nil), do: []

  def history_to_context(messages) when is_list(messages) do
    messages
    |> Enum.map(&translate_input/1)
    |> Enum.reject(&is_nil/1)
  end

  defp translate_input(%{"textMessage" => %{"role" => role, "content" => content}})
       when is_binary(content) do
    %ReqLLM.Message{role: to_role(role), content: [ContentPart.text(content)]}
  end

  defp translate_input(%{"actionExecutionMessage" => %{"name" => name, "arguments" => args} = m}) do
    # CopilotKit sends actionExecution as a separate input variant; the
    # LLM sees it as an assistant message announcing a tool_call.
    %ReqLLM.Message{
      role: :assistant,
      content: [ContentPart.text("[tool_call] #{name} #{args}")],
      metadata: %{tool_call_id: m["id"]}
    }
  end

  defp translate_input(%{
         "resultMessage" => %{"actionExecutionId" => id, "result" => result} = m
       }) do
    # The browser ran the action; we feed the result back to the LLM
    # as a user message tagged with the action name + call id.
    %ReqLLM.Message{
      role: :user,
      content: [ContentPart.text("[tool_result #{m["actionName"]} #{id}] #{result}")]
    }
  end

  defp translate_input(_unknown), do: nil

  @doc """
  Convert the request's `frontend.actions` array into a ReqLLM tool list.
  These are the actions the React side has registered (via
  `useCopilotAction`); the LLM may emit `tool_calls` for them, which the
  loop relays back to the browser.
  """
  @spec actions_to_tools([map()] | nil) :: [ReqLLM.Tool.t()]
  def actions_to_tools(nil), do: []

  def actions_to_tools(actions) when is_list(actions) do
    Enum.flat_map(actions, &translate_action/1)
  end

  defp translate_action(%{"name" => name, "jsonSchema" => schema_json} = action)
       when is_binary(name) do
    description = Map.get(action, "description", "")

    case decode_schema(schema_json) do
      {:ok, schema} ->
        [
          ReqLLM.tool(
            name: name,
            description: description,
            parameter_schema: schema,
            callback: fn _ -> {:ok, "executed in the browser"} end
          )
        ]

      :error ->
        []
    end
  end

  defp translate_action(_), do: []

  defp decode_schema(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      _ -> :error
    end
  end

  defp decode_schema(_), do: :error

  @doc """
  Build a `TextMessageOutput` map for the response stream.
  """
  @spec text_message(String.t(), String.t() | nil) :: map()
  def text_message(content, parent_id \\ nil) do
    %{
      "__typename" => "TextMessageOutput",
      "id" => generate_id(),
      "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "status" => %{"__typename" => "SuccessMessageStatus", "code" => "Success"},
      "content" => content,
      "role" => "assistant",
      "parentMessageId" => parent_id
    }
  end

  @doc """
  Build an `ActionExecutionMessageOutput` map for the response stream.
  The `arguments` field is the JSON arguments string the LLM emitted —
  the React side runs the action with these and posts a `ResultMessage`
  back in a subsequent request.
  """
  @spec action_execution_message(String.t(), String.t(), String.t() | nil) :: map()
  def action_execution_message(name, arguments_json, parent_id \\ nil) do
    %{
      "__typename" => "ActionExecutionMessageOutput",
      "id" => generate_id(),
      "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "status" => %{"__typename" => "SuccessMessageStatus", "code" => "Success"},
      "name" => name,
      "arguments" => arguments_json,
      "parentMessageId" => parent_id
    }
  end

  @doc """
  Build the deferred `status` field for the final defer chunk.
  """
  @spec success_status() :: map()
  def success_status do
    %{
      "status" => %{
        "__typename" => "BaseResponseStatus",
        "code" => "Success"
      }
    }
  end

  defp generate_id, do: 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  defp to_role("user"), do: :user
  defp to_role("assistant"), do: :assistant
  defp to_role("system"), do: :system
  defp to_role(_), do: :user
end

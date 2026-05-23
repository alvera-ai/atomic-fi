defmodule AtomicFi.CopilotKitContextTest do
  @moduledoc """
  Tests for `AtomicFi.CopilotKitContext.complete/2` — the JDM-editor
  copilot's LLM turn.

  Drives the local Ollama reasoning model (see `config/test.secret.exs`);
  the full suite runs it — nothing is excluded (`test/test_helper.exs`).
  """
  use ExUnit.Case, async: true

  alias AtomicFi.CopilotKitContext
  alias ReqLLM.Message.ContentPart

  defp user(text), do: %ReqLLM.Message{role: :user, content: [ContentPart.text(text)]}

  # A minimal stand-in for the editor's real `add_node` CopilotKit action.
  defp add_node_tool do
    ReqLLM.tool(
      name: "add_node",
      description: "Add a node to the open decision graph.",
      parameter_schema: [
        type: [type: :string, required: true, doc: "JDM node kind, e.g. expressionNode."],
        name: [type: :string, required: true, doc: "Node name."]
      ],
      callback: fn _ -> {:ok, "executed in the browser"} end
    )
  end

  describe "complete/2 — plain text turn" do
    # A local reasoning model is slow — past ExUnit's 60s default. Sits
    # above ReqLLM's 5-min receive timeout so that surfaces first.
    @tag timeout: 360_000
    test "returns assistant text and no tool calls when no tool is offered" do
      assert {:ok, %{text: text, tool_calls: []}} =
               CopilotKitContext.complete([user("Reply with exactly the word: hello")], [])

      assert is_binary(text) and text != ""
    end
  end

  describe "complete/2 — tool call" do
    @tag timeout: 360_000
    test "surfaces an add_node tool call carrying the name + JSON arguments" do
      assert {:ok, %{tool_calls: tool_calls}} =
               CopilotKitContext.complete(
                 [user("Add an expression node named amount-floor to the graph.")],
                 [add_node_tool()]
               )

      # The bug this guards: the tool name + args live under
      # %ReqLLM.ToolCall{}'s :function, not top-level :name / :arguments —
      # extracting them wrong crashed the whole stream with a KeyError.
      assert [%{name: "add_node", arguments: arguments} | _] = tool_calls

      # Arguments are the raw JSON string the model emitted — decodable,
      # and shaped by the add_node schema (a node kind + a name).
      assert {:ok, decoded} = Jason.decode(arguments)
      assert is_binary(decoded["type"])
      assert is_binary(decoded["name"])
    end
  end
end

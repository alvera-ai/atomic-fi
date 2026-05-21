defmodule AtomicFi.DocumentParserTest do
  @moduledoc """
  Tests for `AtomicFi.DocumentParser`.

  Anything that hits a live Ollama daemon is tagged `:ollama` and
  excluded from the default test run (see `test/test_helper.exs`).
  """
  use ExUnit.Case, async: true

  alias AtomicFi.DocumentParser

  describe "parse/4 — input validation (no LLM involved)" do
    test "rejects unknown document_type" do
      assert {:error, {:invalid_document_type, "selfie"}} =
               DocumentParser.parse(<<>>, "image/png", "selfie")
    end

    test "rejects unsupported content types" do
      assert {:error, {:unsupported_content_type, "text/plain"}} =
               DocumentParser.parse("hi", "text/plain", "passport")
    end

    test "custom without :custom_schema is :custom_schema_required" do
      assert {:error, :custom_schema_required} =
               DocumentParser.parse(tiny_png(), "image/png", "custom")
    end
  end

  # A 1x1 transparent PNG (smallest valid PNG bytes — sufficient to
  # exercise the image-content-part branch without hitting an LLM).
  defp tiny_png do
    <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6,
      0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 250, 207, 0, 0, 0, 2,
      0, 1, 226, 33, 188, 51, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>
  end
end

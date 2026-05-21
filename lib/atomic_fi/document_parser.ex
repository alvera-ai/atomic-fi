defmodule AtomicFi.DocumentParser do
  @moduledoc """
  Elixir port of the retired `example-apps/document-agent-server`
  (Python/FastAPI/Gemini). Extracts structured data from documents
  (PDFs or images) by:

    1. Rasterising PDFs to PNG via `poppler-utils` (`pdftoppm`).
    2. Calling an Ollama vision model through ReqLLM's OpenAI-compatible
       path with `response_format: json_schema` so the model emits JSON
       conforming to the target document's schema.
    3. Decoding the JSON text into a plain map.

  ReqLLM is reached via `:lotus_web`'s transitive dep — no separate LLM
  client. Provider swap (Ollama → Gemini / OpenAI / Anthropic) is a
  config change in `:atomic_fi, :document_parser, :model`; the code
  doesn't move.

  See [docs/local-dev-architecture.md](docs/local-dev-architecture.md)
  §A.3 for the request-path trace.
  """

  alias AtomicFi.DocumentParser.DocumentType
  alias AtomicFi.DocumentParser.Poppler
  alias ReqLLM.Message.ContentPart

  @doc """
  Parse one document. Returns the extracted JSON shape as a plain map.

  ## Arguments

    * `bytes` — raw PDF or image bytes
    * `content_type` — MIME type (`"application/pdf"`, `"image/png"`, …)
    * `document_type` — one of `DocumentType.all/0`
    * `opts`:
      * `:custom_schema` — JSON Schema map (required when
        `document_type == "custom"`)
      * `:custom_prompt` — override the default extraction prompt
      * `:model` — ReqLLM model spec; defaults to the configured
        Ollama vision model

  Fails loud on every invariant — missing poppler binary, missing
  custom schema, malformed LLM response. Returns `{:error, reason}`
  for failures the caller is expected to report on (LLM HTTP errors,
  JSON decode failures, etc.).
  """
  @spec parse(binary(), String.t(), String.t(), keyword()) ::
          {:ok, map(), map()} | {:error, term()}
  def parse(bytes, content_type, document_type, opts \\ [])
      when is_binary(bytes) and is_binary(content_type) and is_binary(document_type) do
    if DocumentType.valid?(document_type) do
      with {:ok, parts} <- build_content_parts(bytes, content_type),
           {:ok, schema} <- resolve_schema(document_type, opts),
           prompt = resolve_prompt(document_type, opts),
           messages = build_messages(prompt, parts),
           {:ok, response} <-
             ReqLLM.generate_object(model_spec(opts), messages, schema, generate_opts(opts)),
           {:ok, data} <- decode_response(response) do
        {:ok, data, usage_info(response)}
      end
    else
      {:error, {:invalid_document_type, document_type}}
    end
  end

  # ── internals ───────────────────────────────────────────────────────

  defp build_content_parts(bytes, "application/pdf") do
    case Poppler.rasterize_pdf(bytes) do
      {:ok, pages} ->
        {:ok, Enum.map(pages, &ContentPart.image(&1, "image/png"))}

      err ->
        err
    end
  end

  defp build_content_parts(bytes, "image/" <> _ = content_type) do
    {:ok, [ContentPart.image(bytes, content_type)]}
  end

  defp build_content_parts(_bytes, content_type) do
    {:error, {:unsupported_content_type, content_type}}
  end

  defp resolve_schema("custom", opts) do
    case Keyword.get(opts, :custom_schema) do
      schema when is_map(schema) and map_size(schema) > 0 ->
        {:ok, schema}

      _ ->
        {:error, :custom_schema_required}
    end
  end

  defp resolve_schema(document_type, _opts) do
    {:ok, DocumentType.schema_module(document_type).json_schema()}
  end

  defp resolve_prompt("custom", opts) do
    Keyword.get(opts, :custom_prompt, DocumentType.default_custom_prompt())
  end

  defp resolve_prompt(document_type, opts) do
    Keyword.get(opts, :custom_prompt, DocumentType.prompt(document_type))
  end

  defp build_messages(prompt, image_parts) do
    [
      %ReqLLM.Message{
        role: :user,
        content: [ContentPart.text(prompt) | image_parts]
      }
    ]
  end

  defp model_spec(opts) do
    case Keyword.get(opts, :model) do
      nil ->
        config = Application.fetch_env!(:atomic_fi, :document_parser)

        ReqLLM.model!(%{
          id: Keyword.fetch!(config, :vision_model_id),
          provider: :openai,
          base_url: Keyword.fetch!(config, :base_url)
        })

      other ->
        other
    end
  end

  defp generate_opts(opts) do
    Keyword.merge(
      [temperature: 0.0],
      Keyword.take(opts, [:temperature, :max_tokens, :provider_options])
    )
  end

  defp decode_response(%ReqLLM.Response{} = response) do
    case ReqLLM.Response.object(response) do
      nil ->
        case ReqLLM.Response.text(response) do
          nil ->
            {:error, {:empty_llm_response, response}}

          text when is_binary(text) ->
            Jason.decode(text)
        end

      object when is_map(object) ->
        {:ok, object}
    end
  end

  defp decode_response(other), do: {:error, {:unexpected_response_shape, other}}

  defp usage_info(%ReqLLM.Response{} = response) do
    case ReqLLM.Response.usage(response) do
      nil ->
        %{input_tokens: nil, output_tokens: nil, total_tokens: nil}

      %{} = usage ->
        %{
          input_tokens: Map.get(usage, :input_tokens),
          output_tokens: Map.get(usage, :output_tokens),
          total_tokens: Map.get(usage, :total_tokens)
        }
    end
  end
end

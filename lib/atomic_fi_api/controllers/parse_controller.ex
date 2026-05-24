defmodule AtomicFiApi.ParseController do
  @moduledoc """
  `POST /api/parse` — extract structured data from one or more documents.

  Body shape (JSON + base64) — see `AtomicFi.OpenApiSchema.ParseRequest`.
  The controller is the typed boundary: OpenApiSpex casts the body to a
  `%ParseRequest{}` and the action passes the typed struct straight into
  `AtomicFi.DocumentParser` per the repo's Controller/Context Contract.

  Concurrency: `Task.async_stream` processes files in parallel up to a
  cap. Each file's extraction is independent; failures on one file
  don't fail the whole request — the response is per-file success/error.
  """

  use AtomicFiApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias AtomicFi.DocumentParser
  alias AtomicFi.OpenApiSchema
  alias AtomicFi.OpenApiSchema.ParseRequest
  alias AtomicFi.OpenApiSchema.ParseResponse

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  action_fallback AtomicFiApi.FallbackController

  tags(["Documents"])

  @max_concurrency 4
  # Local vision models (Ollama) are slow at JSON-schema-constrained
  # extraction; a single file can take a few minutes on modest hardware.
  @per_file_timeout :timer.minutes(5)

  operation(:create,
    summary: "Extract structured data from documents",
    description: """
    Accepts a JSON body with one or more base64-encoded documents (PDF or image)
    and a target `document_type` per file. Returns one `ExtractionResult` per
    input file.

    Backed by a local Ollama vision model in dev (`llama3.2-vision:11b`);
    production deployments switch the provider by overriding
    `OLLAMA_VISION_MODEL` / `LITER_LLM_BASE_URL` env vars — same code path.
    """,
    request_body: {"Parse request", "application/json", ParseRequest.schema(), required: true},
    responses: [
      ok: {"Parse response", "application/json", ParseResponse},
      unprocessable_entity:
        {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
    ]
  )

  def create(conn, _params) do
    # OpenApiSpex's CastAndValidate plug validates the body against
    # ParseRequest; we read the validated maps via string keys because
    # the schema isn't backed by a typed `x-struct`. That's fine — the
    # validation has already enforced shape + types upstream.
    files = fetch_files(conn.body_params)
    results = run_in_parallel(files)

    conn
    |> put_status(:ok)
    |> json(%{results: results})
  end

  defp fetch_files(%{"files" => files}), do: files
  defp fetch_files(%{files: files}), do: files

  defp run_in_parallel(files) do
    files
    |> Task.async_stream(
      &parse_one/1,
      max_concurrency: @max_concurrency,
      timeout: @per_file_timeout,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, :timeout} -> timeout_result()
      {:exit, reason} -> error_result("unknown", "unknown", inspect(reason))
    end)
  end

  defp parse_one(file) when is_map(file) do
    name = lookup!(file, "name")
    content_type = lookup!(file, "content_type")
    document_type = lookup!(file, "document_type")
    data_base64 = lookup!(file, "data_base64")

    with {:ok, bytes} <- Base.decode64(data_base64),
         {:ok, data, usage} <-
           DocumentParser.parse(bytes, content_type, document_type, parse_opts(file)) do
      %{
        filename: name,
        document_type: document_type,
        success: true,
        data: data,
        usage: usage
      }
    else
      :error ->
        error_result(name, document_type, "invalid base64 in data_base64")

      {:error, reason} ->
        error_result(name, document_type, format_error(reason))
    end
  end

  defp lookup!(map, key) do
    Map.get(map, key) || Map.fetch!(map, String.to_existing_atom(key))
  end

  defp parse_opts(file) do
    [
      custom_schema: Map.get(file, "output_schema") || Map.get(file, :output_schema),
      custom_prompt: Map.get(file, "prompt") || Map.get(file, :prompt)
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp error_result(filename, document_type, error) do
    %{
      filename: filename,
      document_type: document_type,
      success: false,
      data: nil,
      error: error
    }
  end

  defp timeout_result do
    error_result("unknown", "unknown", "extraction timed out")
  end

  defp format_error({:invalid_document_type, t}), do: "invalid document_type: #{t}"
  defp format_error({:unsupported_content_type, t}), do: "unsupported content_type: #{t}"
  defp format_error(:custom_schema_required), do: "output_schema is required for custom documents"

  defp format_error({:pdftoppm_failed, code, out}),
    do: "pdftoppm failed (exit #{code}): #{out}"

  defp format_error({:pdftotext_failed, code, out}),
    do: "pdftotext failed (exit #{code}): #{out}"

  defp format_error({:empty_llm_response, _}), do: "LLM returned an empty response"

  defp format_error(%Jason.DecodeError{} = e),
    do: "LLM JSON decode failed: #{Exception.message(e)}"

  defp format_error(other), do: inspect(other)
end

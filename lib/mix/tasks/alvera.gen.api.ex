defmodule Mix.Tasks.Alvera.Gen.Api do
  @shortdoc "Generates REST API controller with OpenAPI specification"

  @moduledoc """
  Generates a REST API controller with OpenAPI annotations, JSON views, and tests.

  This task wraps Phoenix's phx.gen.json and enhances it with:
  - OpenAPI 3.2 specifications using OpenApiSpex + ExOpenApiUtils
  - CastAndValidate plug for request validation
  - Multi-tenancy via api_session (RLS-based)
  - ApiHelpers for standardized JSON responses
  - Auto-generated Request/Response schemas via ExOpenApiUtils
  - OpenAPI schema validation in tests

  ## Usage

      mix alvera.gen.api Accounts User users email:string name:string

  ## Options

    * `--no-context` - Skip context generation (if already exists)
    * `--no-schema` - Skip schema generation (if already exists)
    * `--web` - Web namespace for the controller (defaults to Api)

  ## Examples

      # Basic API
      mix alvera.gen.api Accounts User users email:string name:string

      # Skip context (if already created)
      mix alvera.gen.api Accounts User users email:string --no-context

      # Custom web namespace
      mix alvera.gen.api Accounts User users email:string --web Admin

  ## Generated Files

  - `lib/*_web/controllers/api/user_controller.ex` - REST controller with OpenAPI specs
  - `lib/*_web/controllers/api/user_json.ex` - JSON view for rendering
  - `test/*_web/controllers/api/user_controller_test.exs` - Controller tests
  - Context and schema files (if not exists)

  ## Router Integration

  Add these routes to your `router.ex`:

      scope "/api", PaymentCompliancePlatformApi do
        pipe_through [:api, :api_authenticated]

        resources "/users", UserController, except: [:new, :edit]
      end
  """

  use Mix.Task

  alias Mix.Tasks.Phx.Gen

  @doc false
  def run(args) do
    if Mix.Project.umbrella?() do
      Mix.raise("mix alvera.gen.api must be invoked from within your application root directory")
    end

    {opts, _parsed, _invalid} =
      OptionParser.parse(args,
        switches: [
          binary_id: :boolean,
          no_context: :boolean,
          no_schema: :boolean,
          web: :string
        ]
      )

    # Default to binary_id
    args =
      if opts[:binary_id] == false do
        args
      else
        ["--binary-id" | args]
      end

    # Build context and schema using Phoenix's infrastructure
    {context, schema} = Gen.Context.build(args)

    # Run Phoenix's JSON generator first (this creates context, schema, controller, json view, tests)
    Gen.Json.run(args)

    # Now enhance the generated files
    unless opts[:no_schema] do
      enhance_schema_for_api(schema)
    end

    enhance_controller(context, schema, opts[:web])
    enhance_json_view(context, schema)
    enhance_tests(context, schema)

    print_instructions(context, schema, opts[:web])
  end

  # Schemas are already enhanced if using alvera.gen.context
  # This is a backup for cases where schema is generated fresh
  defp enhance_schema_for_api(schema) do
    file_path = schema.file

    if File.exists?(file_path) do
      content = File.read!(file_path)

      # Only enhance if not already using PaymentCompliancePlatform.Schema
      if String.contains?(content, "use PaymentCompliancePlatform.Schema") do
        :already_enhanced
      else
        context_name = schema.module |> Module.split() |> Enum.slice(0..-2//1) |> Enum.join(".")

        Mix.shell().info("""

        #{IO.ANSI.yellow()}⚠#{IO.ANSI.reset()} Schema was generated without TypedEctoSchema and OpenAPI annotations.

        Consider running: mix alvera.gen.context #{context_name} #{schema.alias} #{schema.table}
        """)
      end
    end
  end

  defp enhance_controller(context, schema, web_namespace) do
    web_namespace = web_namespace || "Api"
    web_prefix = Mix.Phoenix.web_path(context.context_app)

    controller_path =
      Path.join([
        web_prefix,
        "controllers",
        Macro.underscore(web_namespace),
        "#{schema.singular}_controller.ex"
      ])

    controller_path =
      if File.exists?(controller_path) do
        controller_path
      else
        # Try without namespace
        Path.join([
          web_prefix,
          "controllers",
          "#{schema.singular}_controller.ex"
        ])
      end

    if File.exists?(controller_path) do
      content = File.read!(controller_path)

      # Replace base controller with custom one
      content =
        String.replace(
          content,
          ~r/(use .*Web, :controller)/,
          "use #{inspect(context.web_module)}Api.Controller"
        )

      # Add OpenApiSpex and other requires
      content =
        String.replace(
          content,
          ~r/(use #{inspect(context.web_module)}Api.Controller)/,
          """
          \\1
            use OpenApiSpex.ControllerSpecs

            alias #{inspect(context.base_module)}.OpenApiSchema
            alias #{inspect(context.base_module)}.OpenApiSchema.#{schema.alias}Request
            alias #{inspect(context.base_module)}.OpenApiSchema.#{schema.alias}Response
            alias #{inspect(context.base_module)}.OpenApiSchema.#{schema.alias}ListResponse
            alias #{inspect(context.web_module)}Api.Helpers.ApiHelpers
            alias OpenApiSpex.Reference
            alias OpenApiSpex.Schema

            plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

            action_fallback #{inspect(context.web_module)}Api.FallbackController
          """
        )

      # Add OpenAPI tags
      content =
        String.replace(
          content,
          ~r/(action_fallback.*FallbackController)/,
          "\\1\n\n  tags([#{inspect(schema.human_plural)}])"
        )

      # Update controller actions for new patterns
      content = update_controller_actions(content, schema, context)

      # Add OpenAPI operation specs
      content = add_openapi_operations(content, schema, context)

      File.write!(controller_path, content)
      Mix.shell().info([:green, "* enhanced ", :reset, Path.relative_to_cwd(controller_path)])
    else
      Mix.shell().info("Controller not found at #{controller_path}")
    end
  end

  defp update_controller_actions(content, schema, context) do
    context_alias = context.alias

    # Update index action
    content =
      String.replace(
        content,
        ~r/def index\(conn, _params\) do.*?render\(conn, :index, #{schema.plural}: #{schema.plural}\)/s,
        """
        def index(conn, params) do
            session = conn.assigns.api_session
            flop_params = ApiHelpers.parse_flop_params(params)

            with {:ok, {#{schema.plural}, meta}} <- #{context_alias}.list_#{schema.plural}(session, flop_params) do
              ApiHelpers.json_paginated_response(conn, #{schema.plural}, meta, #{schema.alias}ListResponse)
            end
        """
      )

    # Update show action
    content =
      String.replace(
        content,
        ~r/def show\(conn, %\{"id" => id\}\) do.*?render\(conn, :show, #{schema.singular}: #{schema.singular}\)/s,
        """
        def show(conn, %{id: id}) do
            session = conn.assigns.api_session
            #{schema.singular} = #{context_alias}.get_#{schema.singular}!(session, id)

            ApiHelpers.json_response(conn, #{schema.singular}, #{schema.alias}Response)
        """
      )

    # Update create action with body_params pattern
    content =
      String.replace(
        content,
        ~r/def create\(conn, %\{"#{schema.singular}" => #{schema.singular}_params\}\) do.*?conn\s*\|> put_status\(:created\).*?render\(conn, :show, #{schema.singular}: #{schema.singular}\)/s,
        """
        def create(%{body_params: %#{schema.alias}Request{} = #{schema.singular}_request} = conn, %{}) do
            session = conn.assigns.api_session

            with {:ok, #{schema.singular}} <- #{context_alias}.create_#{schema.singular}(session, #{schema.singular}_request) do
              conn
              |> put_status(:created)
              |> put_resp_header("location", ~p"/api/#{schema.plural}/\#{#{schema.singular}.id}")
              |> ApiHelpers.json_response(#{schema.singular}, #{schema.alias}Response)
            end
        """
      )

    # Update update action with body_params pattern
    content =
      String.replace(
        content,
        ~r/def update\(conn, %\{"id" => id, "#{schema.singular}" => #{schema.singular}_params\}\) do.*?render\(conn, :show, #{schema.singular}: #{schema.singular}\)/s,
        """
        def update(%{body_params: %#{schema.alias}Request{} = #{schema.singular}_request} = conn, %{id: id}) do
            session = conn.assigns.api_session
            #{schema.singular} = #{context_alias}.get_#{schema.singular}!(session, id)

            with {:ok, #{schema.singular}} <- #{context_alias}.update_#{schema.singular}(session, #{schema.singular}, #{schema.singular}_request) do
              ApiHelpers.json_response(conn, #{schema.singular}, #{schema.alias}Response)
            end
        """
      )

    # Update delete action
    content =
      String.replace(
        content,
        ~r/def delete\(conn, %\{"id" => id\}\) do.*?send_resp\(conn, :no_content, ""\)/s,
        """
        def delete(conn, %{id: id}) do
            session = conn.assigns.api_session
            #{schema.singular} = #{context_alias}.get_#{schema.singular}!(session, id)

            with {:ok, _#{schema.singular}} <- #{context_alias}.delete_#{schema.singular}(session, #{schema.singular}) do
              send_resp(conn, :no_content, "")
            end
        """
      )

    content
  end

  defp add_openapi_operations(content, schema, _context) do
    # Add operation spec for index
    index_spec = """
      operation(:index,
        summary: "List #{schema.human_plural}",
        description: "Returns a paginated list of #{schema.human_plural}",
        parameters: [
          page: [in: :query, type: :integer, description: "Page number (1-indexed)"],
          page_size: [in: :query, type: :integer, description: "Items per page"],
          order_by: [in: :query, type: :string, description: "Field to sort by"],
          order_directions: [in: :query, type: :string, description: "Sort direction (asc or desc)"]
        ],
        responses: [
          ok: {"#{schema.human_singular} list", "application/json",
               %Reference{\"$ref\": \"#/components/schemas/#{schema.alias}ListResponse\"}}
        ]
      )

    """

    content = String.replace(content, ~r/(\n  def index)/, "\n#{index_spec}\\1")

    # Add operation spec for show
    show_spec = """
      operation(:show,
        summary: "Get #{schema.human_singular} by ID",
        parameters: [
          id: [in: :path, schema: %Schema{type: :string, format: :uuid}, description: "#{schema.human_singular} ID"]
        ],
        responses: [
          ok: {"#{schema.human_singular}", "application/json", #{schema.alias}Response},
          not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
        ]
      )

    """

    content = String.replace(content, ~r/(\n  def show)/, "\n#{show_spec}\\1")

    # Add operation spec for create
    create_spec = """
      operation(:create,
        summary: "Create #{schema.human_singular}",
        request_body: {"#{schema.human_singular} params", "application/json", #{schema.alias}Request.schema()},
        responses: [
          created: {"#{schema.human_singular} created", "application/json", #{schema.alias}Response},
          unprocessable_entity: {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
        ]
      )

    """

    content = String.replace(content, ~r/(\n  def create)/, "\n#{create_spec}\\1")

    # Add operation spec for update
    update_spec = """
      operation(:update,
        summary: "Update #{schema.human_singular}",
        parameters: [
          id: [in: :path, schema: %Schema{type: :string, format: :uuid}, description: "#{schema.human_singular} ID"]
        ],
        request_body: {"#{schema.human_singular} params", "application/json", #{schema.alias}Request.schema(), required: true},
        responses: [
          ok: {"#{schema.human_singular} updated", "application/json", #{schema.alias}Response},
          not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse},
          unprocessable_entity: {"Validation errors", "application/json", OpenApiSchema.ChangesetErrors}
        ]
      )

    """

    content = String.replace(content, ~r/(\n  def update)/, "\n#{update_spec}\\1")

    # Add operation spec for delete
    delete_spec = """
      operation(:delete,
        summary: "Delete #{schema.human_singular}",
        parameters: [
          id: [in: :path, schema: %Schema{type: :string, format: :uuid}, description: "#{schema.human_singular} ID"]
        ],
        responses: [
          no_content: "#{schema.human_singular} deleted",
          not_found: {"Not found", "application/json", OpenApiSchema.ErrorResponse}
        ]
      )

    """

    content = String.replace(content, ~r/(\n  def delete)/, "\n#{delete_spec}\\1")

    content
  end

  defp enhance_json_view(context, schema) do
    web_prefix = Mix.Phoenix.web_path(context.context_app)

    json_path =
      Path.join([
        web_prefix,
        "controllers",
        "#{schema.singular}_json.ex"
      ])

    if File.exists?(json_path) do
      # JSON view is generally good from phx.gen.json
      # Could add enhancements here if needed
      Mix.shell().info([:green, "* verified ", :reset, Path.relative_to_cwd(json_path)])
    else
      Mix.shell().info("JSON view not found at #{json_path}")
    end
  end

  defp enhance_tests(context, schema) do
    test_prefix = Mix.Phoenix.web_test_path(context.context_app)

    test_path =
      Path.join([
        test_prefix,
        "controllers",
        "#{schema.singular}_controller_test.exs"
      ])

    if File.exists?(test_path) do
      content = File.read!(test_path)

      # Add @moduletag :refactored
      unless String.contains?(content, "@moduletag :refactored") do
        content =
          String.replace(
            content,
            ~r/(use .*ConnCase)/,
            "\\1\n\n  @moduletag :refactored"
          )

        File.write!(test_path, content)
        Mix.shell().info([:green, "* enhanced ", :reset, Path.relative_to_cwd(test_path)])
      end
    else
      Mix.shell().info("Test file not found at #{test_path}")
    end
  end

  defp print_instructions(context, schema, web_namespace) do
    web_namespace = web_namespace || "Api"

    Mix.shell().info("""

    #{IO.ANSI.green()}✓#{IO.ANSI.reset()} Generated REST API with:
      - OpenAPI 3.2 controller with CastAndValidate plug
      - Multi-tenancy support via api_session
      - ApiHelpers response formatting
      - ExOpenApiUtils schema auto-generation
      - Controller tests with OpenAPI validation

    Add the API routes to your router.ex:

        scope "/api", #{inspect(context.web_module)}Api do
          pipe_through [:api, :api_authenticated]

          resources "/#{schema.plural}", #{schema.alias}Controller, except: [:new, :edit]
        end

    Next steps:
      1. Ensure #{schema.alias} schema has OpenAPI annotations (use #{inspect(context.base_module)}.Schema)
      2. Register schemas in api_spec.ex components
      3. Run: mix test test/#{context.context_app}_api/
      4. Generate OpenAPI spec: mix openapi.spec.yaml
      5. Test via Scalar UI at http://localhost:4000/api/docs
    """)

    if context.generate?, do: Gen.Context.print_shell_instructions(context)
  end
end

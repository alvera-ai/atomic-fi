defmodule Mix.Tasks.Alvera.Gen.Live do
  @shortdoc "Generates LiveView, templates, and context for a resource with Petal Components"

  @moduledoc """
  Generates LiveView modules and templates using Petal Components with optional features.

  This generator creates a complete LiveView CRUD interface with:
  - Petal Components for UI
  - Multi-tenancy (tenant-scoped queries)
  - Optional AI search integration
  - Optional data table views
  - Custom route prefixes

  ## Usage

      mix alvera.gen.live Blog Post posts title:string content:text status:enum:draft:published

  ## Options

    * `--ai-search` - Include AI search components
    * `--data-table` - Use data table layout (default: false)
    * `--route-root` - Custom route prefix (e.g., "/admin")
    * `--no-context` - Skip context generation
    * `--no-schema` - Skip schema generation

  ## Examples

      # Basic LiveView
      mix alvera.gen.live Accounts User users email:string name:string

      # With AI search
      mix alvera.gen.live Blog Post posts title:string --ai-search

      # With data table view
      mix alvera.gen.live Products Product products name:string price:decimal --data-table

      # With custom route root
      mix alvera.gen.live Admin Settings settings key:string value:text --route-root /admin

      # All features combined
      mix alvera.gen.live Docs Article articles title:string --ai-search --data-table --route-root /docs

  ## Generated Files

  - `lib/*_web/live/<resource>_live/index.ex` - List view LiveView
  - `lib/*_web/live/<resource>_live/edit.ex` - Edit/New view LiveView
  - `lib/*_web/live/<resource>_live/form_component.ex` - Form component
  - `lib/*_web/live/<resource>_live/index.html.heex` - List template
  - `lib/*_web/live/<resource>_live/edit.html.heex` - Edit template
  - `lib/*_web/live/<resource>_live/form_component.html.heex` - Form template
  - `lib/*_web/live/<resource>_live/ai_component.ex` - AI search component (if --ai-search)
  - `lib/*_web/live/<resource>_live/ai_component.html.heex` - AI search template (if --ai-search)
  - `test/*_web/live/<resource>_live_test.exs` - LiveView tests
  """

  use Mix.Task

  alias Mix.Phoenix.{Context, Schema}
  alias Mix.Tasks.Phx.Gen

  @doc false
  def run(args) do
    if Mix.Project.umbrella?() do
      Mix.raise(
        "mix alvera.gen.live must be invoked from within your *_web application root directory"
      )
    end

    {opts, _parsed, _invalid} =
      OptionParser.parse(args,
        switches: [
          ai_search: :boolean,
          data_table: :boolean,
          route_root: :string,
          no_context: :boolean,
          no_schema: :boolean
        ],
        aliases: [a: :ai_search, d: :data_table]
      )

    ai_search = opts[:ai_search] || false
    data_table = opts[:data_table] || false
    route_root = opts[:route_root]

    {context, schema} = Gen.Context.build(args)
    Gen.Context.prompt_for_code_injection(context)

    binding = [
      context: context,
      schema: schema,
      inputs: inputs(schema),
      ai_search: ai_search,
      data_table: data_table,
      route_root: route_root
    ]

    paths = Mix.Phoenix.generator_paths()

    prompt_for_conflicts(context, ai_search)

    context
    |> copy_new_files(binding, paths, ai_search, data_table)
    |> maybe_inject_imports()
    |> print_shell_instructions(ai_search, route_root)
  end

  defp prompt_for_conflicts(context, ai_search) do
    context
    |> files_to_be_generated(ai_search)
    |> Kernel.++(context_files(context))
    |> Mix.Phoenix.prompt_for_conflicts()
  end

  defp context_files(%Context{generate?: true} = context) do
    Gen.Context.files_to_be_generated(context)
  end

  defp context_files(%Context{generate?: false}) do
    []
  end

  defp files_to_be_generated(%Context{schema: schema, context_app: context_app}, ai_search) do
    web_prefix = Mix.Phoenix.web_path(context_app)
    test_prefix = Mix.Phoenix.web_test_path(context_app)
    web_path = to_string(schema.web_path)
    live_subdir = "#{schema.singular}_live"
    web_live = Path.join([web_prefix, "live", web_path, live_subdir])
    test_live = Path.join([test_prefix, "live", web_path])

    base_files = [
      {:eex, "edit.ex", Path.join(web_live, "edit.ex")},
      {:eex, "index.ex", Path.join(web_live, "index.ex")},
      {:eex, "form_component.ex", Path.join(web_live, "form_component.ex")},
      {:eex, "form_component.html.heex", Path.join(web_live, "form_component.html.heex")},
      {:eex, "index.html.heex", Path.join(web_live, "index.html.heex")},
      {:eex, "edit.html.heex", Path.join(web_live, "edit.html.heex")},
      {:eex, "live_test.exs", Path.join(test_live, "#{schema.singular}_live_test.exs")}
    ]

    if ai_search do
      base_files ++
        [
          {:eex, "ai_component.ex", Path.join(web_live, "ai_component.ex")},
          {:eex, "ai_component.html.heex", Path.join(web_live, "ai_component.html.heex")}
        ]
    else
      base_files
    end
  end

  defp copy_new_files(%Context{} = context, binding, paths, ai_search, data_table) do
    files = files_to_be_generated(context, ai_search)

    binding =
      Keyword.put(binding, :assigns, %{
        web_namespace: inspect(context.web_module),
        gettext: true
      })

    # Choose template source based on data_table flag
    source =
      if data_table do
        "priv/templates/mix/alvera.gen.live.data_table"
      else
        "priv/templates/mix/alvera.gen.live"
      end

    Mix.Phoenix.copy_from(paths, source, binding, files)
    if context.generate?, do: Gen.Context.copy_new_files(context, paths, binding)

    context
  end

  defp maybe_inject_imports(%Context{context_app: ctx_app} = context) do
    web_prefix = Mix.Phoenix.web_path(ctx_app)
    [lib_prefix, web_dir] = Path.split(web_prefix)
    file_path = Path.join(lib_prefix, "#{web_dir}.ex")
    file = File.read!(file_path)
    inject = "import #{inspect(context.web_module)}.CoreComponents"

    if String.contains?(file, inject) do
      :ok
    else
      do_inject_imports(context, file, file_path, inject)
    end

    context
  end

  defp do_inject_imports(context, file, file_path, inject) do
    relative_path = Path.relative_to_cwd(file_path)
    Mix.shell().info([:green, "* injecting ", :reset, relative_path])

    new_file =
      String.replace(
        file,
        "use Phoenix.Component",
        "use Phoenix.Component\n      #{inject}"
      )

    if file == new_file do
      Mix.shell().info("""

      Could not find use Phoenix.Component in #{file_path}.

      Please make sure LiveView is installed and that #{inspect(context.web_module)}
      defines both `live_view/0` and `live_component/0` functions,
      and that both functions import #{inspect(context.web_module)}.CoreComponents.
      """)
    else
      File.write!(file_path, new_file)
    end
  end

  @doc false
  def print_shell_instructions(
        %Context{schema: schema, context_app: ctx_app} = context,
        ai_search,
        route_root
      ) do
    prefix = Module.concat(context.web_module, schema.web_namespace)
    web_path = Mix.Phoenix.web_path(ctx_app)

    route_instructions = live_route_instructions(schema, route_root)
    ai_note = if ai_search, do: "\n  - AI search components for semantic search", else: ""

    if schema.web_namespace do
      Mix.shell().info("""

      Add the live routes to your #{schema.web_namespace} :browser scope in #{web_path}/router.ex:

          scope "/#{schema.web_path}", #{inspect(prefix)}, as: :#{schema.web_path} do
            pipe_through :browser
            ...

      #{for line <- route_instructions, do: "      #{line}"}
          end
      """)
    else
      Mix.shell().info("""

      Add the live routes to your browser scope in #{web_path}/router.ex:

      #{for line <- route_instructions, do: "    #{line}"}
      """)
    end

    Mix.shell().info("""

    #{IO.ANSI.green()}✓#{IO.ANSI.reset()} Generated LiveView with:
      - Petal Components for UI
      - Multi-tenancy (tenant-scoped queries)#{ai_note}
      - Comprehensive form validations
      - LiveView tests

    Next steps:
      1. Add the routes to your router.ex (see above)
      2. Update the generated LiveViews to fetch current_user/tenant from socket.assigns
      3. Run: mix test
    """)

    if context.generate?, do: Gen.Context.print_shell_instructions(context)
    maybe_print_upgrade_info()

    context
  end

  defp maybe_print_upgrade_info do
    if !Code.ensure_loaded?(Phoenix.LiveView.JS) do
      Mix.shell().info("""

      You must update :phoenix_live_view to v0.18 or later and
      :phoenix_live_dashboard to v0.7 or later to use the features
      in this generator.
      """)
    end
  end

  defp live_route_instructions(schema, route_root) do
    base_path =
      if route_root do
        "#{route_root}/#{schema.plural}"
      else
        "/#{schema.plural}"
      end

    [
      ~s|live "#{base_path}", #{inspect(schema.alias)}Live.Index, :index\n|,
      ~s|live "#{base_path}/new", #{inspect(schema.alias)}Live.Edit, :new\n|,
      ~s|live "#{base_path}/:id", #{inspect(schema.alias)}Live.Edit, :edit\n|
    ]
  end

  @doc false
  def inputs(%Schema{} = schema) do
    Enum.map(schema.attrs, fn
      {_, {:references, _}} ->
        ""

      {key, :integer} ->
        ~s(<.field type="number" field={@form[#{inspect(key)}]} />)

      {key, :float} ->
        ~s(<.field type="number" step="any" field={@form[#{inspect(key)}]} />)

      {key, :decimal} ->
        ~s(<.field type="number" step="any" field={@form[#{inspect(key)}]} />)

      {key, :boolean} ->
        ~s(<.field type="checkbox" field={@form[#{inspect(key)}]} />)

      {key, :text} ->
        ~s(<.field type="textarea" field={@form[#{inspect(key)}]} rows="6" />)

      {key, :date} ->
        ~s(<.field type="date" field={@form[#{inspect(key)}]} />)

      {key, :time} ->
        ~s(<.field type="time" field={@form[#{inspect(key)}]} />)

      {key, :time_usec} ->
        ~s(<.field type="time" field={@form[#{inspect(key)}]} />)

      {key, :utc_datetime} ->
        ~s(<.field type="datetime-local" field={@form[#{inspect(key)}]} />)

      {key, :utc_datetime_usec} ->
        ~s(<.field type="datetime-local" field={@form[#{inspect(key)}]} />)

      {key, :naive_datetime} ->
        ~s(<.field type="datetime-local" field={@form[#{inspect(key)}]} />)

      {key, :naive_datetime_usec} ->
        ~s(<.field type="datetime-local" field={@form[#{inspect(key)}]} />)

      {key, {:array, :integer}} ->
        ~s(<.field type="select" field={@form[#{inspect(key)}]} multiple options={[{"Option 1", 1}, {"Option 2", 2}]} />)

      {key, {:array, :string}} ->
        ~s(<.field type="select" field={@form[#{inspect(key)}]} multiple options={[{"Option 1", "option1"}, {"Option 2", "option2"}]} />)

      {key, {:array, _}} ->
        ~s(<.field type="select" field={@form[#{inspect(key)}]} multiple options={[{"Option 1", "option1"}, {"Option 2", "option2"}]} />)

      {key, {:enum, values}} ->
        options = Enum.map_join(values, ", ", &inspect/1)

        ~s(<.field type="select" field={@form[#{inspect(key)}]} options={[#{options}]} prompt="Choose a value" />)

      {key, _} ->
        ~s(<.field type="text" field={@form[#{inspect(key)}]} />)
    end)
  end
end

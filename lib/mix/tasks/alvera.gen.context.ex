defmodule Mix.Tasks.Alvera.Gen.Context do
  @shortdoc "Generates an Alvera context with TypedEctoSchema, OpenAPI, multi-tenancy, and factories"

  @moduledoc """
  Opinionated context generator with TypedEctoSchema, OpenAPI, multi-tenancy, and ExMachina factories.

  Automatically generates:
  - TypedEctoSchema (not Ecto.Schema)
  - OpenAPI annotations
  - Multi-tenancy with tenant_id
  - Binary UUIDs (not auto-increment IDs)
  - ExMachina factories (not Phoenix fixtures)
  - @moduletag :refactored in tests

  ## Usage

      mix alvera.gen.context Accounts User users email:string name:string

  ## Multi-Tenancy

  All resources automatically include:
  - `belongs_to :tenant, Tenant`
  - `tenant_id` field with foreign key
  - Composite unique indexes
  - Tenant-scoped context functions
  """

  use Mix.Task

  alias Mix.Tasks.Phx.Gen

  # RLS configuration: Hardcoded tenant-based multi-tenancy
  # This is an architectural decision, not runtime config
  defp get_rls_config do
    %{
      field: :tenant_id,
      table: :tenants,
      module: PaymentCompliancePlatform.TenantContext.Tenant
    }
  end

  @doc false
  def run(args) do
    if Mix.Project.umbrella?() do
      Mix.raise(
        "mix alvera.gen.context must be invoked from within your application root directory"
      )
    end

    # Validate args format before passing to Phoenix
    case args do
      [context_name, schema_name, _table_name | _]
      when is_binary(context_name) and is_binary(schema_name) ->
        # Ensure schema name is a valid module name
        unless String.match?(schema_name, ~r/^[A-Z][a-zA-Z0-9]*$/) do
          Mix.raise("""
          Expected the schema name to be a valid module name (PascalCase).

          Example:
              mix alvera.gen.context SessionContext Session sessions field:type
          """)
        end

      _ ->
        Mix.raise("""
        Invalid arguments.

        Expected format:
            mix alvera.gen.context ContextName SchemaName table_name field:type ...

        Example:
            mix alvera.gen.context SessionContext Session sessions type:string active:boolean
        """)
    end

    # Opinionated defaults: no fixtures (binary_id set in config)
    # Flags must come AFTER positional args for Phoenix
    args_with_flags = args ++ ["--no-fixtures", "--no-context"]

    # Build context and schema using Phoenix's infrastructure
    {context, schema} = Gen.Context.build(args_with_flags)

    # Get RLS configuration
    rls = get_rls_config()

    # Prompt for conflicts
    prompt_for_conflicts(context)

    # Run Phoenix schema generator (schema + migration only, no context)
    Gen.Context.run(args_with_flags)

    # Generate our own context, test, and factory files using templates
    paths = Mix.Phoenix.generator_paths()

    binding = [
      context: context,
      schema: schema,
      rls_field: rls.field,
      rls_table: rls.table,
      rls_module: rls.module
    ]

    copy_new_files(context, binding, paths)

    # Enhance generated schema and migration files
    enhance_schema_file(schema)
    enhance_migration_file(schema)

    # Generate factory file
    generate_factory(schema, context, binding, paths)

    print_instructions(context, schema)
  end

  defp prompt_for_conflicts(context) do
    context
    |> files_to_be_generated()
    |> Mix.Phoenix.prompt_for_conflicts()
  end

  defp files_to_be_generated(%{context_app: context_app} = context) do
    context_lib = Mix.Phoenix.context_lib_path(context_app, context.basename)
    test_path = Mix.Phoenix.context_test_path(context_app, context.basename)

    [
      {:eex, "context.ex", context_lib <> ".ex"},
      {:eex, "context_test.exs", test_path <> "_test.exs"}
    ]
  end

  defp copy_new_files(context, binding, paths) do
    files = files_to_be_generated(context)
    Mix.Phoenix.copy_from(paths, "priv/templates/mix/alvera.gen.context", binding, files)
    context
  end

  # Enhance schema to use TypedEctoSchema and OpenAPI
  defp enhance_schema_file(schema) do
    file_path = schema.file
    rls = get_rls_config()

    if File.exists?(file_path) do
      content = File.read!(file_path)

      # Replace use Ecto.Schema with use PaymentCompliancePlatform.Schema
      content =
        String.replace(
          content,
          "use Ecto.Schema",
          "use PaymentCompliancePlatform.Schema"
        )

      # Remove import Ecto.Changeset (ExOpenApiUtils already imports it)
      content =
        String.replace(
          content,
          ~r/\n\s*import Ecto\.Changeset\n/,
          "\n"
        )

      # Replace schema with typed_schema
      content = String.replace(content, ~r/schema "/, "typed_schema \"")

      # Add @derive directive for Flop configuration
      filterable_fields = get_filterable_fields(schema, rls)
      sortable_fields = get_sortable_fields(schema)

      flop_derive = """
        @derive {
          Flop.Schema,
          filterable: #{inspect(filterable_fields)},
          sortable: #{inspect(sortable_fields)},
          default_limit: 20,
          max_limit: 100
        }
      """

      content =
        String.replace(
          content,
          ~r/(@primary_key)/,
          "#{flop_derive}\n\n  \\1"
        )

      # Add RLS field before timestamps
      rls_field_name = rls.field |> to_string() |> String.trim_trailing("_id")

      content =
        String.replace(
          content,
          ~r/timestamps\(\)/,
          """
          # Multi-tenancy: #{rls.field} references #{rls.table} for RLS
              belongs_to :#{rls_field_name}, #{inspect(rls.module)}

              timestamps(type: :utc_datetime_usec)
          """
        )

      # Add OpenAPI annotations before typed_schema
      openapi_annotations = generate_openapi_annotations(schema, rls)

      content =
        String.replace(
          content,
          ~r/(typed_schema)/,
          "#{openapi_annotations}\n\n  \\1"
        )

      # Update changeset to include RLS field
      content = add_rls_field_to_changeset(content, schema, rls)

      File.write!(file_path, content)

      Mix.shell().info([:green, "* enhanced ", :reset, Path.relative_to_cwd(file_path)])
    end
  end

  # Generate OpenAPI annotations for schema fields
  defp generate_openapi_annotations(schema, rls) do
    property_annotations =
      schema.attrs
      |> Enum.reject(fn {_key, type} -> match?({:references, _}, type) end)
      |> Enum.map(fn {key, type} ->
        openapi_type = map_ecto_to_openapi_type(type)

        "  open_api_property(schema: %Schema{type: #{inspect(openapi_type)}}, key: #{inspect(key)})"
      end)
      |> Enum.join("\n")

    fields = [:id] ++ Keyword.keys(schema.attrs) ++ [rls.field, :inserted_at, :updated_at]
    required_fields = get_required_fields(schema, rls)

    """
      # OpenAPI annotations
    #{property_annotations}

      open_api_schema(
        title: "#{schema.human_singular}",
        description: "#{schema.human_singular} schema",
        required: #{inspect(required_fields)},
        properties: #{inspect(fields)}
      )
    """
  end

  defp map_ecto_to_openapi_type(:string), do: :string
  defp map_ecto_to_openapi_type(:text), do: :string
  defp map_ecto_to_openapi_type(:integer), do: :integer
  defp map_ecto_to_openapi_type(:float), do: :number
  defp map_ecto_to_openapi_type(:decimal), do: :number
  defp map_ecto_to_openapi_type(:boolean), do: :boolean
  defp map_ecto_to_openapi_type(:date), do: :string
  defp map_ecto_to_openapi_type(:time), do: :string
  defp map_ecto_to_openapi_type(:naive_datetime), do: :string
  defp map_ecto_to_openapi_type(:utc_datetime), do: :string
  defp map_ecto_to_openapi_type(:binary_id), do: :string
  defp map_ecto_to_openapi_type({:array, _}), do: :array
  defp map_ecto_to_openapi_type({:enum, _}), do: :string
  defp map_ecto_to_openapi_type(_), do: :string

  defp get_required_fields(schema, rls) do
    # Typically the first field and RLS field are required
    case schema.attrs do
      [{first_key, _} | _] -> [first_key, rls.field]
      [] -> [rls.field]
    end
  end

  defp get_filterable_fields(schema, rls) do
    # Common filterable fields: id, string fields, enum fields, status, and RLS field
    basic_fields = [:id, rls.field]

    attr_fields =
      schema.attrs
      |> Enum.filter(fn {_key, type} ->
        type in [:string, :integer, :boolean, :date, :naive_datetime, :utc_datetime] ||
          match?({:enum, _}, type)
      end)
      |> Enum.map(fn {key, _} -> key end)

    (basic_fields ++ attr_fields) |> Enum.uniq()
  end

  defp get_sortable_fields(schema) do
    # Common sortable fields: id, string fields, dates, timestamps
    basic_fields = [:id, :inserted_at, :updated_at]

    attr_fields =
      schema.attrs
      |> Enum.filter(fn {_key, type} ->
        type in [:string, :integer, :date, :naive_datetime, :utc_datetime, :decimal, :float]
      end)
      |> Enum.map(fn {key, _} -> key end)

    (basic_fields ++ attr_fields) |> Enum.uniq()
  end

  defp add_rls_field_to_changeset(content, _schema, rls) do
    # Add RLS field to cast
    content =
      String.replace(
        content,
        ~r/\|> cast\(attrs, \[([^\]]+)\]\)/,
        "|> cast(attrs, [\\1, #{inspect(rls.field)}])"
      )

    # Add RLS field to validate_required if there are required fields
    content =
      String.replace(
        content,
        ~r/\|> validate_required\(\[([^\]]+)\]\)/,
        "|> validate_required([\\1, #{inspect(rls.field)}])"
      )

    content
  end

  # Enhance migration to add RLS field and composite indexes
  defp enhance_migration_file(schema) do
    rls = get_rls_config()
    migrations_path = "priv/repo/migrations"
    pattern = Path.join(migrations_path, "*_create_#{schema.table}.exs")

    case Path.wildcard(pattern) do
      [migration_file | _] ->
        content = File.read!(migration_file)

        # Add RLS field before timestamps
        content =
          String.replace(
            content,
            ~r/timestamps\(\)/,
            """
            # Multi-tenancy: #{rls.field} references #{rls.table} for RLS
                  add #{inspect(rls.field)}, references(#{inspect(rls.table)}, type: :binary_id, on_delete: :delete_all),
                    null: false,
                    comment: "#{String.capitalize(to_string(rls.field))} for multi-tenancy (RLS)"

                  timestamps(type: :utc_datetime_usec)
            """
          )

        # Add indexes after the create table block
        indexes = generate_indexes(schema, rls)

        content =
          String.replace(
            content,
            ~r/(end)\s*\n\s*end\s*\n\s*end/,
            "\\1\n\n#{indexes}  end\n"
          )

        File.write!(migration_file, content)
        Mix.shell().info([:green, "* enhanced ", :reset, Path.relative_to_cwd(migration_file)])

      [] ->
        Mix.shell().info("Migration file not found for #{schema.table}")
    end
  end

  defp generate_indexes(schema, rls) do
    base_indexes = """
        # Multi-tenancy indexes
        create index(:#{schema.table}, [#{inspect(rls.field)}])
    """

    # Add composite unique indexes for fields marked as unique
    unique_indexes =
      schema.attrs
      |> Enum.filter(fn {_key, type} ->
        (is_list(type) && :unique in type) || match?({_, :unique}, type)
      end)
      |> Enum.map(fn {key, _} ->
        "    create unique_index(:#{schema.table}, [#{inspect(key)}, #{inspect(rls.field)}])"
      end)
      |> Enum.join("\n")

    if unique_indexes != "" do
      base_indexes <> "\n" <> unique_indexes <> "\n"
    else
      base_indexes
    end
  end

  # Generate ExMachina factory as a separate module file using template
  defp generate_factory(schema, _context, binding, paths) do
    # Ensure factory directory exists
    factory_dir = "test/support/factory"
    File.mkdir_p!(factory_dir)

    # Generate factory file using template
    factory_file = Path.join(factory_dir, "#{Macro.underscore(schema.alias)}_factory.ex")
    files = [{:eex, "factory.ex", factory_file}]

    Mix.Phoenix.copy_from(paths, "priv/templates/mix/alvera.gen.context", binding, files)

    # Extract base module name from schema.module
    # e.g., "PaymentCompliancePlatform.ApiKeyContext.ApiKey" -> "PaymentCompliancePlatform"
    base_module =
      schema.module
      |> Module.split()
      |> hd()

    factory_module_name = "#{base_module}.Factory.#{schema.alias}Factory"

    # Update main factory.ex to use the new factory module
    main_factory_file = "test/support/factory.ex"

    if File.exists?(main_factory_file) do
      content = File.read!(main_factory_file)

      use_statement = "  use #{factory_module_name}"

      # Add use statement before the final 'end' if it doesn't already exist
      unless String.contains?(content, use_statement) do
        content =
          String.replace(
            content,
            ~r/\nend\n$/,
            "\n#{use_statement}\nend\n"
          )

        File.write!(main_factory_file, content)

        Mix.shell().info([
          :green,
          "* injected ",
          :reset,
          "#{schema.singular}_factory into ",
          Path.relative_to_cwd(main_factory_file)
        ])
      end
    else
      Mix.shell().info([:yellow, "* warning ", :reset, "test/support/factory.ex not found"])
    end
  end

  defp print_instructions(_context, _schema) do
    rls = get_rls_config()

    Mix.shell().info("""

    #{IO.ANSI.green()}✓#{IO.ANSI.reset()} Generated Alvera context with:
      - TypedEctoSchema with OpenAPI annotations
      - Multi-tenancy (#{rls.field} references #{rls.table})
      - RLS-scoped context functions
      - ExMachina factory definition
      - @moduletag :refactored in tests

    Next steps:
      1. Review the generated files
      2. Run: mix ecto.migrate
      3. Run: mix test
    """)
  end
end

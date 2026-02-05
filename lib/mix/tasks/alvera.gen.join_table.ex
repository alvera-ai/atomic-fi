defmodule Mix.Tasks.Alvera.Gen.JoinTable do
  @shortdoc "Generates a join table mapping schema for many-to-many relationships"

  @moduledoc """
  Generates a complete join table pattern with mapping schema, following CRM standards.

  Generates:
  - Mapping schema with composite primary keys (no ID, no timestamps)
  - Migration with unique composite index
  - ExMachina factory for the mapping
  - Updates parent schemas with many_to_many and has_many relationships

  ## Usage

      mix alvera.gen.join_table <table_name> <Schema1> <Schema2>

  ## Examples

      # User <-> Role many-to-many
      mix alvera.gen.join_table user_roles User Role

      # ApiKey <-> Role many-to-many
      mix alvera.gen.join_table api_roles ApiKey Role

  ##Generated Files:

  1. Migration (composite primary key, unique index)
  2. Mapping schema (e.g., UserRoleMapping)
  3. Factory for mapping
  4. Updates to parent schemas with join_through using schema name
  """

  use Mix.Task

  @doc false
  def run(args) do
    if Mix.Project.umbrella?() do
      Mix.raise(
        "mix alvera.gen.join_table must be invoked from within your application root directory"
      )
    end

    case args do
      [table_name, schema1, schema2] ->
        generate_join_table(table_name, schema1, schema2)

      _ ->
        Mix.raise("""
        Invalid arguments. Expected:

            mix alvera.gen.join_table <table_name> <Schema1> <Schema2>

        Examples:

            mix alvera.gen.join_table user_roles User Role
            mix alvera.gen.join_table api_roles ApiKey Role
        """)
    end
  end

  defp generate_join_table(table_name, schema1_name, schema2_name) do
    # Normalize schema names
    schema1 = normalize_schema_name(schema1_name)
    schema2 = normalize_schema_name(schema2_name)

    # Derive table names and field names (using standard Ecto naming)
    table1 = derive_table_name(schema1)
    table2 = derive_table_name(schema2)
    field1 = derive_field_name(schema1)
    field2 = derive_field_name(schema2)

    # Generate mapping schema name (e.g., UserRoleMapping)
    mapping_schema_name = generate_mapping_schema_name(table_name)

    # Generate all files
    migration_file = generate_migration(table_name, table1, table2, field1, field2)

    mapping_file =
      generate_mapping_schema(mapping_schema_name, table_name, schema1, schema2, field1, field2)

    factory_file = generate_factory(mapping_schema_name, schema1, schema2, field1, field2)

    # Update parent schemas
    update_schema_with_associations(schema1, schema2, mapping_schema_name)
    update_schema_with_associations(schema2, schema1, mapping_schema_name)

    # Update main factory to include new factory
    update_main_factory(mapping_schema_name)

    print_instructions(
      table_name,
      schema1,
      schema2,
      mapping_schema_name,
      migration_file,
      mapping_file,
      factory_file
    )
  end

  defp normalize_schema_name(name) do
    # Remove "Context" suffix if present and get just the schema name
    name
    |> String.split(".")
    |> List.last()
  end

  defp derive_table_name(schema) do
    # Convert schema name to table name (e.g., "User" -> "users", "ApiKey" -> "api_keys")
    schema
    |> Macro.underscore()
    |> Inflex.pluralize()
  end

  defp derive_field_name(schema) do
    # Convert schema to field name (e.g., "User" -> "user_id", "ApiKey" -> "api_key_id")
    "#{Macro.underscore(schema)}_id"
  end

  defp generate_mapping_schema_name(table_name) do
    # Convert table_name to PascalCase + "Mapping"
    # e.g., "user_roles" -> "UserRoleMapping"
    table_name
    |> String.replace("_", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
    |> Kernel.<>("Mapping")
  end

  defp generate_migration(table_name, table1, table2, field1, field2) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
    migration_name = "create_#{table_name}"
    migration_file = "priv/repo/migrations/#{timestamp}_#{migration_name}.exs"

    module_name = Macro.camelize("create_#{table_name}")

    content = """
    defmodule AlveraPhoenixTemplateServer.Repo.Migrations.#{module_name} do
      use Ecto.Migration

      def change do
        create table(:#{table_name}, primary_key: false) do
          add :#{field1}, references(:#{table1}, type: :binary_id, on_delete: :delete_all),
            null: false,
            primary_key: true

          add :#{field2}, references(:#{table2}, type: :binary_id, on_delete: :delete_all),
            null: false,
            primary_key: true
        end

        create unique_index(:#{table_name}, [:#{field1}, :#{field2}])
        create index(:#{table_name}, [:#{field2}])
      end
    end
    """

    File.write!(migration_file, content)
    Mix.shell().info([:green, "* creating ", :reset, migration_file])
    migration_file
  end

  defp generate_mapping_schema(mapping_name, table_name, schema1, schema2, field1, field2) do
    # Determine which context to put the mapping in (use RoleContext as default if Role is one of the schemas)
    context = if schema2 == "Role", do: "RoleContext", else: determine_context(schema1)

    mapping_file =
      "lib/alvera_phoenix_template_server/#{Macro.underscore(context)}/#{Macro.underscore(mapping_name)}.ex"

    # Get full module names
    schema1_module =
      find_schema_module(schema1) ||
        "AlveraPhoenixTemplateServer.#{determine_context(schema1)}.#{schema1}"

    schema2_module =
      find_schema_module(schema2) ||
        "AlveraPhoenixTemplateServer.#{determine_context(schema2)}.#{schema2}"

    # Derive association names
    assoc1 = Macro.underscore(schema1)
    assoc2 = Macro.underscore(schema2)

    content = """
    defmodule AlveraPhoenixTemplateServer.#{context}.#{mapping_name} do
      @moduledoc \"\"\"
      Join table schema linking #{schema1} to #{schema2} for many-to-many relationships.

      This is a mapping table without id or timestamps, using composite primary key.
      Allows use of cast_assoc for managing #{String.downcase(schema1)}-#{String.downcase(schema2)} relationships.
      \"\"\"
      use AlveraPhoenixTemplateServer.Schema

      alias #{schema1_module}
      alias #{schema2_module}

      @primary_key false
      @foreign_key_type :binary_id

      typed_schema "#{table_name}" do
        belongs_to :#{assoc1}, #{schema1}, primary_key: true
        belongs_to :#{assoc2}, #{schema2}, primary_key: true
      end

      @doc \"\"\"
      Changeset for creating a #{Macro.underscore(mapping_name)} association.
      \"\"\"
      @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
      def changeset(#{Macro.underscore(mapping_name)}, attrs) do
        #{Macro.underscore(mapping_name)}
        |> cast(attrs, [:#{field1}, :#{field2}])
        |> validate_required([:#{field1}, :#{field2}])
        |> foreign_key_constraint(:#{field1})
        |> foreign_key_constraint(:#{field2})
        |> unique_constraint([:#{field1}, :#{field2}], name: :#{table_name}_#{field1}_#{field2}_index)
      end
    end
    """

    File.mkdir_p!(Path.dirname(mapping_file))
    File.write!(mapping_file, content)
    Mix.shell().info([:green, "* creating ", :reset, mapping_file])
    mapping_file
  end

  defp generate_factory(mapping_name, schema1, schema2, field1, field2) do
    factory_file = "test/support/factory/#{Macro.underscore(mapping_name)}_factory.ex"

    # Derive association names and variable names
    assoc1 = Macro.underscore(schema1)
    assoc2 = Macro.underscore(schema2)
    factory1 = String.to_atom(assoc1)
    factory2 = String.to_atom(assoc2)

    content = """
    defmodule AlveraPhoenixTemplateServer.Factory.#{mapping_name}Factory do
      @moduledoc \"\"\"
      Factory for #{mapping_name} join table schema.
      \"\"\"

      defmacro __using__(_opts) do
        quote do
          alias AlveraPhoenixTemplateServer.RoleContext.#{mapping_name}

          def #{Macro.underscore(mapping_name)}_factory(attrs \\\\ %{}) do
            # Only create #{assoc1} if neither :#{assoc1} nor :#{field1} is provided
            #{assoc1} =
              if Map.has_key?(attrs, :#{assoc1}) or Map.has_key?(attrs, :#{field1}) do
                Map.get(attrs, :#{assoc1})
              else
                insert(:#{factory1})
              end

            #{field1} = Map.get(attrs, :#{field1}, #{assoc1} && #{assoc1}.id)

            # Only create #{assoc2} if neither :#{assoc2} nor :#{field2} is provided
            #{assoc2} =
              if Map.has_key?(attrs, :#{assoc2}) or Map.has_key?(attrs, :#{field2}) do
                Map.get(attrs, :#{assoc2})
              else
                tenant_id = if #{assoc1}, do: #{assoc1}.tenant_id
                insert(:#{factory2}, tenant_id: tenant_id)
              end

            #{field2} = Map.get(attrs, :#{field2}, #{assoc2} && #{assoc2}.id)

            %#{mapping_name}{
              #{field1}: #{field1},
              #{field2}: #{field2}
            }
          end
        end
      end
    end
    """

    File.mkdir_p!(Path.dirname(factory_file))
    File.write!(factory_file, content)
    Mix.shell().info([:green, "* creating ", :reset, factory_file])
    factory_file
  end

  defp update_schema_with_associations(schema1, schema2, mapping_name) do
    schema_file = find_schema_file(schema1)

    if schema_file && File.exists?(schema_file) do
      content = File.read!(schema_file)

      # Derive names
      field_name = schema2 |> Macro.underscore() |> Inflex.pluralize()

      mapping_field =
        "#{Macro.underscore(mapping_name) |> String.replace("_mapping", "")}_mappings"

      schema2_module = find_schema_module(schema2) || "AlveraPhoenixTemplateServer.#{schema2}"
      _mapping_module = "AlveraPhoenixTemplateServer.RoleContext.#{mapping_name}"

      # Add alias for mapping if not present
      content =
        unless content =~ ~r/alias.*#{mapping_name}/ do
          String.replace(
            content,
            ~r/(  use AlveraPhoenixTemplateServer\.Schema\n)/,
            "\\1\n  alias AlveraPhoenixTemplateServer.RoleContext.#{mapping_name}"
          )
        else
          content
        end

      # Check if many_to_many already exists
      if content =~ ~r/many_to_many :#{field_name}/ do
        Mix.shell().info([
          :yellow,
          "* skipping ",
          :reset,
          "#{schema_file} - many_to_many :#{field_name} already exists"
        ])
      else
        # Add both many_to_many and has_many before timestamps
        associations = """
            # Many-to-many relationship with #{Inflex.pluralize(schema2)}
            many_to_many :#{field_name}, #{schema2_module},
              join_through: #{mapping_name},
              on_replace: :delete

            # Direct access to join table for cast_assoc operations
            has_many :#{mapping_field}, #{mapping_name}, on_replace: :delete
        """

        updated_content =
          String.replace(
            content,
            ~r/(    timestamps\(type: :utc_datetime_usec\))/,
            "#{associations}\n\\1"
          )

        File.write!(schema_file, updated_content)
        Mix.shell().info([:green, "* updated ", :reset, schema_file])
      end
    end
  end

  defp update_main_factory(mapping_name) do
    factory_file = "test/support/factory.ex"

    if File.exists?(factory_file) do
      content = File.read!(factory_file)
      factory_line = "  use AlveraPhoenixTemplateServer.Factory.#{mapping_name}Factory"

      unless content =~ ~r/#{mapping_name}Factory/ do
        updated_content =
          String.replace(
            content,
            ~r/(  use AlveraPhoenixTemplateServer\.Factory\..*Factory\n)(?!.*Factory)/,
            "\\1#{factory_line}\n"
          )

        File.write!(factory_file, updated_content)
        Mix.shell().info([:green, "* updated ", :reset, factory_file])
      end
    end
  end

  defp determine_context(schema_name) do
    # Try to find which context the schema belongs to
    schema_file = find_schema_file(schema_name)

    if schema_file do
      case Regex.run(~r/lib\/alvera_phoenix_template_server\/(\w+_context)/, schema_file) do
        [_, context] -> Macro.camelize(context)
        _ -> "#{schema_name}Context"
      end
    else
      "#{schema_name}Context"
    end
  end

  defp find_schema_file(schema_name) do
    # Search for schema file in lib directory
    underscore_name = Macro.underscore(schema_name)

    # Try to find the file
    Path.wildcard("lib/**/#{underscore_name}.ex")
    |> Enum.find(&File.exists?/1)
  end

  defp find_schema_module(schema_name) do
    # Try to find the full module name
    schema_file = find_schema_file(schema_name)

    if schema_file do
      content = File.read!(schema_file)

      case Regex.run(~r/defmodule\s+([\w\.]+)\s+do/, content) do
        [_, module] -> module
        _ -> nil
      end
    else
      nil
    end
  end

  defp print_instructions(
         table_name,
         schema1,
         schema2,
         mapping_name,
         migration_file,
         mapping_file,
         factory_file
       ) do
    field_name1 = schema2 |> Macro.underscore() |> Inflex.pluralize()
    field_name2 = schema1 |> Macro.underscore() |> Inflex.pluralize()

    mapping_field1 =
      "#{Macro.underscore(mapping_name) |> String.replace("_mapping", "")}_mappings"

    Mix.shell().info("""

    Join table #{table_name} with mapping schema created successfully!

    Generated files:
        * #{migration_file}
        * #{mapping_file}
        * #{factory_file}

    Updated files:
        * Parent schemas with many_to_many and has_many relationships
        * test/support/factory.ex

    Next steps:

        1. Review the generated files
        2. Run migration: mix ecto.migrate

    The following associations were added:

        #{schema1}:
          - many_to_many :#{field_name1} (through #{mapping_name})
          - has_many :#{mapping_field1}

        #{schema2}:
          - many_to_many :#{field_name2} (through #{mapping_name})
          - has_many :#{String.replace(mapping_field1, schema1 |> Macro.underscore(), schema2 |> Macro.underscore())}

    Example usage with cast_assoc:

        # Using cast_assoc for fine-grained control
        user
        |> Ecto.Changeset.cast(%{#{mapping_field1}: [%{role_id: role.id}]}, [])
        |> Ecto.Changeset.cast_assoc(:#{mapping_field1})
        |> Repo.update()

    Example usage with many_to_many:

        # Simple association management
        user
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:#{field_name1}, [role1, role2])
        |> Repo.update()
    """)
  end
end

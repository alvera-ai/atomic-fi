defmodule AtomicFiWeb.ChangesetJSONTest do
  use ExUnit.Case, async: true

  alias AtomicFiWeb.ChangesetJSON

  defmodule TestSchema do
    use Ecto.Schema
    import Ecto.Changeset

    schema "test" do
      field :name, :string
      field :age, :integer
    end

    def changeset(struct, attrs) do
      struct
      |> cast(attrs, [:name, :age])
      |> validate_required([:name])
      |> validate_number(:age, greater_than: 17)
    end
  end

  describe "error/1" do
    test "renders a JSON:API-shaped error array from a changeset" do
      changeset = TestSchema.changeset(%TestSchema{}, %{age: 10})

      assert %{errors: errors} = ChangesetJSON.error(%{changeset: changeset})
      assert is_list(errors)
      assert length(errors) == 2

      [age_err, name_err] = Enum.sort_by(errors, & &1.source.pointer)

      assert age_err.detail =~ "greater than"
      assert age_err.source == %{pointer: "/age"}
      assert age_err.title == "Invalid value"

      assert name_err.detail == "can't be blank"
      assert name_err.source == %{pointer: "/name"}
    end

    test "interpolates %{count}-style placeholders from opts" do
      changeset =
        TestSchema.changeset(%TestSchema{}, %{name: "x", age: 5})

      %{errors: errors} = ChangesetJSON.error(%{changeset: changeset})
      assert Enum.find(errors, &(&1.source.pointer == "/age")).detail =~ "17"
    end
  end
end

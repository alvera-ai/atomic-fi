defmodule AtomicFi.AccountHolderContext.AccountHolder.RawBodyTest do
  use ExUnit.Case, async: true

  alias AtomicFi.AccountHolderContext.AccountHolder.RawBody

  describe "changeset/2" do
    test "casts data and metadata from string-keyed input" do
      changeset =
        RawBody.changeset(%RawBody{}, %{
          "data" => %{"foo" => "bar"},
          "metadata" => %{"source" => "api"}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :data) == %{"foo" => "bar"}
      assert Ecto.Changeset.get_change(changeset, :metadata) == %{"source" => "api"}
    end

    test "ignores unknown fields" do
      changeset = RawBody.changeset(%RawBody{}, %{"unknown" => "x"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :data) == nil
    end

    test "defaults to empty maps when no input" do
      raw_body = %RawBody{}
      assert raw_body.data == %{}
      assert raw_body.metadata == %{}
    end
  end
end

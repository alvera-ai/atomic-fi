defmodule AtomicFi.ComplianceScreeningContext.SanctionsMatchTest do
  use ExUnit.Case, async: true

  alias AtomicFi.ComplianceScreeningContext.SanctionsMatch.{
    WatchmanAddress,
    WatchmanBusiness,
    WatchmanContact,
    WatchmanPerson
  }

  describe "embedded changesets" do
    test "WatchmanBusiness.changeset/2 casts the four business fields" do
      changeset =
        WatchmanBusiness.changeset(%WatchmanBusiness{}, %{
          "name" => "AcmeCo",
          "registration_number" => "REG-1",
          "incorporation_date" => "2020-01-01",
          "dissolved_date" => nil
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :name) == "AcmeCo"
      assert Ecto.Changeset.get_change(changeset, :registration_number) == "REG-1"
    end

    test "WatchmanAddress.changeset/2 casts address fields" do
      changeset =
        WatchmanAddress.changeset(%WatchmanAddress{}, %{
          "line1" => "1 Main St",
          "city" => "NYC",
          "country" => "US"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :city) == "NYC"
    end

    test "WatchmanPerson.changeset/2 casts person fields" do
      changeset =
        WatchmanPerson.changeset(%WatchmanPerson{}, %{
          "given_name" => "Jane",
          "family_name" => "Doe",
          "nationalities" => ["US", "GB"]
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :nationalities) == ["US", "GB"]
    end

    test "WatchmanContact.changeset/2 casts contact fields" do
      changeset =
        WatchmanContact.changeset(%WatchmanContact{}, %{
          "emails" => ["x@y.z"],
          "phones" => [],
          "websites" => ["https://x.com"]
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :emails) == ["x@y.z"]
    end
  end
end

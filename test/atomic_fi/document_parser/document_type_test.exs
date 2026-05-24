defmodule AtomicFi.DocumentParser.DocumentTypeTest do
  use ExUnit.Case, async: true

  alias AtomicFi.DocumentParser.DocumentType
  alias AtomicFi.DocumentParser.Schemas.BankStatement
  alias AtomicFi.DocumentParser.Schemas.IdentityDocument
  alias AtomicFi.DocumentParser.Schemas.MemorandumOfAssociation

  describe "valid?/1" do
    test "accepts every documented type" do
      for t <-
            ~w(passport driving_licence national_id visa bank_statement memorandum custom) do
        assert DocumentType.valid?(t), "expected #{inspect(t)} to be valid"
      end
    end

    test "rejects anything else" do
      refute DocumentType.valid?("photo")
      refute DocumentType.valid?("")
      refute DocumentType.valid?(nil)
      refute DocumentType.valid?(:passport)
    end
  end

  describe "schema_module/1" do
    test "all identity-document types map to IdentityDocument" do
      for t <- ~w(passport driving_licence national_id visa) do
        assert DocumentType.schema_module(t) == IdentityDocument
      end
    end

    test "bank_statement and memorandum map to their own schemas" do
      assert DocumentType.schema_module("bank_statement") == BankStatement
      assert DocumentType.schema_module("memorandum") == MemorandumOfAssociation
    end

    test "calling with custom is a programmer error — not routed here" do
      assert_raise FunctionClauseError, fn ->
        DocumentType.schema_module("custom")
      end
    end
  end

  describe "prompt/1" do
    test "passport prompt mentions passport and the id_type=passport hint" do
      p = DocumentType.prompt("passport")
      assert p =~ "passport"
      assert p =~ "id_type should be 'passport'"
    end

    test "driving_licence prompt is identity-shaped with the right id_type" do
      p = DocumentType.prompt("driving_licence")
      assert p =~ "driving licence"
      assert p =~ "id_type should be 'driving_licence'"
    end

    test "bank_statement prompt asks for every transaction" do
      assert DocumentType.prompt("bank_statement") =~ "every single transaction"
    end

    test "memorandum prompt mentions share structure" do
      assert DocumentType.prompt("memorandum") =~ "share structure"
    end
  end

  describe "schemas" do
    test "IdentityDocument JSON Schema is shaped correctly" do
      schema = IdentityDocument.json_schema()
      assert schema["type"] == "object"
      assert schema["required"] == ["personal_info", "document_info"]
      assert get_in(schema, ["properties", "personal_info", "type"]) == "object"
      assert get_in(schema, ["properties", "document_info", "type"]) == "object"
    end

    test "BankStatement schema has an array of transactions" do
      schema = BankStatement.json_schema()
      txns = get_in(schema, ["properties", "transactions"])
      assert txns["type"] == "array"
      assert is_map(txns["items"])
      assert txns["items"]["type"] == "object"
    end

    test "MemorandumOfAssociation schema has arrays for shareholders/directors/amendments" do
      schema = MemorandumOfAssociation.json_schema()

      for field <- ~w(shareholders directors amendments business_activities) do
        assert get_in(schema, ["properties", field, "type"]) == "array",
               "expected #{field} to be an array"
      end
    end
  end
end

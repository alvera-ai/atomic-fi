defmodule AtomicFi.DocumentParser.Schemas.MemorandumOfAssociation do
  @moduledoc """
  JSON Schema for a Memorandum of Association. Ported from the Python
  `document-agent-server`'s Pydantic `MemorandumOfAssociation`, which
  embeds `Shareholder`, `Director`, `Amendment`, and `business_activities`.
  """

  @shareholder %{
    "type" => "object",
    "additionalProperties" => false,
    "properties" => %{
      "name" => %{"type" => ["string", "null"], "description" => "Shareholder name"},
      "nationality" => %{"type" => ["string", "null"], "description" => "Nationality"},
      "shares" => %{"type" => ["integer", "null"], "description" => "Number of shares"},
      "share_percentage" => %{
        "type" => ["number", "null"],
        "description" => "Ownership percentage"
      }
    }
  }

  @director %{
    "type" => "object",
    "additionalProperties" => false,
    "properties" => %{
      "name" => %{"type" => ["string", "null"], "description" => "Director name"},
      "nationality" => %{"type" => ["string", "null"], "description" => "Nationality"},
      "role" => %{
        "type" => ["string", "null"],
        "description" => "chairman, managing director, director, etc."
      }
    }
  }

  @amendment %{
    "type" => "object",
    "additionalProperties" => false,
    "properties" => %{
      "date" => %{
        "type" => ["string", "null"],
        "description" => "Amendment date YYYY-MM-DD"
      },
      "description" => %{
        "type" => ["string", "null"],
        "description" => "What was amended"
      }
    }
  }

  @json_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["shareholders", "directors", "business_activities", "amendments"],
    "properties" => %{
      "company_name" => %{
        "type" => ["string", "null"],
        "description" => "Full legal company name"
      },
      "registered_address" => %{
        "type" => ["string", "null"],
        "description" => "Registered office address"
      },
      "date_of_formation" => %{
        "type" => ["string", "null"],
        "description" => "Date of formation YYYY-MM-DD"
      },
      "capital_amount" => %{
        "type" => ["number", "null"],
        "description" => "Total capital amount"
      },
      "capital_currency" => %{
        "type" => ["string", "null"],
        "description" => "Currency of capital"
      },
      "shareholders" => %{"type" => "array", "items" => @shareholder},
      "directors" => %{"type" => "array", "items" => @director},
      "business_activities" => %{
        "type" => "array",
        "items" => %{"type" => "string"}
      },
      "signing_authority" => %{
        "type" => ["string", "null"],
        "description" => "Signing authority and conditions"
      },
      "quorum_rules" => %{
        "type" => ["string", "null"],
        "description" => "Quorum requirements"
      },
      "amendments" => %{"type" => "array", "items" => @amendment}
    }
  }

  def name, do: "MemorandumOfAssociation"
  def json_schema, do: @json_schema
end

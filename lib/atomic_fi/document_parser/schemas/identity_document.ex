defmodule AtomicFi.DocumentParser.Schemas.IdentityDocument do
  @moduledoc """
  JSON Schema for an identity document (passport / driving licence /
  national ID / visa).

  Ported one-shot from the Python `document-agent-server`'s Pydantic
  `IdentityDocument` model (`example-apps/document-agent-server/app/
  schemas.py`). The shape is what we send to Ollama (or any
  OpenAI-compatible provider) via `response_format: json_schema` so
  the model returns JSON conforming to it.
  """

  @json_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["personal_info", "document_info"],
    "properties" => %{
      "personal_info" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "first_name" => %{"type" => ["string", "null"], "description" => "First/given name"},
          "last_name" => %{"type" => ["string", "null"], "description" => "Last/family name"},
          "full_name" => %{
            "type" => ["string", "null"],
            "description" => "Full name as shown on document"
          },
          "date_of_birth" => %{
            "type" => ["string", "null"],
            "description" => "Date of birth YYYY-MM-DD"
          },
          "gender" => %{"type" => ["string", "null"], "description" => "M or F"},
          "nationality" => %{
            "type" => ["string", "null"],
            "description" => "Nationality or citizenship"
          },
          "phone" => %{"type" => ["string", "null"], "description" => "Phone number if present"},
          "address" => %{
            "type" => ["string", "null"],
            "description" => "Residential address if present"
          }
        }
      },
      "document_info" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "id_type" => %{
            "type" => ["string", "null"],
            "description" => "passport, driving_licence, national_id, visa, other"
          },
          "id_number" => %{
            "type" => ["string", "null"],
            "description" => "Document ID/number"
          },
          "issue_date" => %{
            "type" => ["string", "null"],
            "description" => "Issue date YYYY-MM-DD"
          },
          "expiry_date" => %{
            "type" => ["string", "null"],
            "description" => "Expiry date YYYY-MM-DD"
          },
          "issuing_authority" => %{
            "type" => ["string", "null"],
            "description" => "Issuing authority"
          },
          "issuing_country" => %{
            "type" => ["string", "null"],
            "description" => "Issuing country"
          }
        }
      }
    }
  }

  def name, do: "IdentityDocument"
  def json_schema, do: @json_schema
end

defmodule AtomicFi.DocumentParser.Schemas.BankStatement do
  @moduledoc """
  JSON Schema for a bank statement. Ported from the Python
  `document-agent-server`'s Pydantic `BankStatement` (which embeds
  `BankAccountInfo` and a list of `Transaction`).
  """

  @transaction %{
    "type" => "object",
    "additionalProperties" => false,
    "properties" => %{
      "date" => %{"type" => ["string", "null"], "description" => "Transaction date YYYY-MM-DD"},
      "description" => %{"type" => ["string", "null"], "description" => "Transaction narration"},
      "reference" => %{"type" => ["string", "null"], "description" => "Reference number"},
      "debit" => %{"type" => ["number", "null"], "description" => "Debit amount (money out)"},
      "credit" => %{"type" => ["number", "null"], "description" => "Credit amount (money in)"},
      "balance" => %{
        "type" => ["number", "null"],
        "description" => "Running balance after transaction"
      }
    }
  }

  @bank_account_info %{
    "type" => "object",
    "additionalProperties" => false,
    "properties" => %{
      "account_holder" => %{
        "type" => ["string", "null"],
        "description" => "Account holder name"
      },
      "account_number" => %{
        "type" => ["string", "null"],
        "description" => "Account number (may be masked)"
      },
      "iban" => %{"type" => ["string", "null"], "description" => "IBAN if present"},
      "account_type" => %{
        "type" => ["string", "null"],
        "description" => "savings, current, etc."
      },
      "currency" => %{
        "type" => ["string", "null"],
        "description" => "Currency code (AED, USD, etc.)"
      },
      "bank_name" => %{"type" => ["string", "null"], "description" => "Bank name"},
      "branch" => %{
        "type" => ["string", "null"],
        "description" => "Branch name or code"
      }
    }
  }

  @json_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["account", "transactions"],
    "properties" => %{
      "account" => @bank_account_info,
      "statement_period_start" => %{
        "type" => ["string", "null"],
        "description" => "Start date YYYY-MM-DD"
      },
      "statement_period_end" => %{
        "type" => ["string", "null"],
        "description" => "End date YYYY-MM-DD"
      },
      "opening_balance" => %{
        "type" => ["number", "null"],
        "description" => "Opening balance"
      },
      "closing_balance" => %{
        "type" => ["number", "null"],
        "description" => "Closing balance"
      },
      "total_debits" => %{
        "type" => ["number", "null"],
        "description" => "Sum of all debits"
      },
      "total_credits" => %{
        "type" => ["number", "null"],
        "description" => "Sum of all credits"
      },
      "transactions" => %{
        "type" => "array",
        "description" => "All transactions",
        "items" => @transaction
      }
    }
  }

  def name, do: "BankStatement"
  def json_schema, do: @json_schema
end

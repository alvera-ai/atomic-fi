defmodule AtomicFi.DocumentParser.DocumentType do
  @moduledoc """
  Enumeration of supported document types, mirroring the Python
  `document-agent-server`'s `DocumentType` enum.

  Maps each type to (a) its target JSON Schema module and (b) its
  extraction prompt. `:custom` is the escape hatch — caller supplies
  the JSON schema + prompt in the request.
  """

  alias AtomicFi.DocumentParser.Schemas.BankStatement
  alias AtomicFi.DocumentParser.Schemas.IdentityDocument
  alias AtomicFi.DocumentParser.Schemas.MemorandumOfAssociation

  @types ~w(passport driving_licence national_id visa bank_statement memorandum custom)

  def all, do: @types

  def valid?(t) when is_binary(t), do: t in @types
  def valid?(_), do: false

  def schema_module("passport"), do: IdentityDocument
  def schema_module("driving_licence"), do: IdentityDocument
  def schema_module("national_id"), do: IdentityDocument
  def schema_module("visa"), do: IdentityDocument
  def schema_module("bank_statement"), do: BankStatement
  def schema_module("memorandum"), do: MemorandumOfAssociation
  # "custom" has no built-in schema module — the caller supplies one
  # via the `:custom_schema` option to `DocumentParser.parse/4`. The
  # parser routes "custom" through a separate code path before
  # reaching this function; a raise here means a bug upstream.

  # Prompts are direct ports of example-apps/document-agent-server/app/prompts.py.
  @identity_prompt """
  You are a document data extractor. Extract all personal and document information \
  from this {doc_type}. Use null for fields not found. \
  Dates in YYYY-MM-DD format. gender: M or F. \
  id_type should be '{id_type}'. \
  Correct obvious OCR errors using context.\
  """

  def prompt("passport"),
    do:
      @identity_prompt
      |> String.replace("{doc_type}", "passport")
      |> String.replace("{id_type}", "passport")

  def prompt("driving_licence"),
    do:
      @identity_prompt
      |> String.replace("{doc_type}", "driving licence")
      |> String.replace("{id_type}", "driving_licence")

  def prompt("national_id"),
    do:
      @identity_prompt
      |> String.replace("{doc_type}", "national ID card")
      |> String.replace("{id_type}", "national_id")

  def prompt("visa"),
    do:
      @identity_prompt
      |> String.replace("{doc_type}", "visa document")
      |> String.replace("{id_type}", "visa")

  def prompt("bank_statement"),
    do: """
    You are a bank statement data extractor. \
    Extract ALL information from this bank statement. \
    Include every single transaction — do not skip or summarize. \
    Dates in YYYY-MM-DD format. Amounts as numbers without currency symbols. \
    For debit/credit: if the statement uses a single amount column with DR/CR indicators, \
    map debits to the debit field and credits to the credit field. \
    Calculate total_debits and total_credits as sums if not shown on the statement.\
    """

  def prompt("memorandum"),
    do: """
    You are a legal document data extractor specializing in \
    Memorandum and Articles of Association. \
    Extract all fields: company name, registered address, share structure \
    (each shareholder with name, nationality, shares, ownership %), \
    directors (name, nationality, role), \
    business activities, signing authority, quorum rules, capital amount/currency, \
    date of formation, and amendment history. \
    Dates in YYYY-MM-DD format. Amounts as numbers without currency symbols. \
    If the document is in Arabic and English, prefer the English text. \
    Use null for fields not found.\
    """

  @default_custom_prompt "Extract all relevant data from this document according to " <>
                           "the provided schema. Use null for fields not found. Dates " <>
                           "in YYYY-MM-DD format."

  def default_custom_prompt, do: @default_custom_prompt
end

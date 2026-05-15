defmodule AtomicFi.BlocklistContext.Normalizer do
  @moduledoc """
  Data quality normalization for account holder names and company names.

  Normalizes names by:
  - Stripping titles (Mr., Mrs., Dr., etc.)
  - Standardizing suffixes (Jr., Sr., III, etc.)
  - Fixing casing (titlecase names, uppercase company names)
  - Removing entity types from company names (LLC, Inc, Corp, etc.)

  Rules are loaded at compile time from priv/normalization_rules.exs.
  """

  # Load normalization rules at compile time
  @external_resource normalization_rules_path =
                       Path.join([
                         :code.priv_dir(:atomic_fi),
                         "normalization_rules.exs"
                       ])
  @normalization_rules (case File.read(normalization_rules_path) do
                          {:ok, content} ->
                            {rules, _} = Code.eval_string(content)
                            rules

                          {:error, reason} ->
                            raise "Failed to load normalization rules: #{inspect(reason)}"
                        end)

  @titles @normalization_rules.titles
  @suffixes @normalization_rules.suffixes
  @entity_types @normalization_rules.entity_types

  @doc """
  Normalize a first name by stripping titles and fixing casing.

  ## Examples

      iex> normalize_first_name("mr. john")
      "John"

      iex> normalize_first_name("MARY")
      "Mary"
  """
  def normalize_first_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.trim()
    |> strip_titles()
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @doc """
  Normalize a last name by stripping titles, standardizing suffixes, and fixing casing.

  ## Examples

      iex> normalize_last_name("smith jr.")
      "Smith Jr"

      iex> normalize_last_name("mr. doe")
      "Doe"
  """
  def normalize_last_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.trim()
    |> strip_titles()
    |> standardize_suffixes()
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @doc """
  Normalize a company name by removing entity types and converting to uppercase.

  ## Examples

      iex> normalize_company_name("Acme Corp LLC")
      "ACME"

      iex> normalize_company_name("test company, inc.")
      "TEST COMPANY"
  """
  def normalize_company_name(name) when is_binary(name) do
    name
    |> String.upcase()
    |> String.trim()
    |> remove_entity_types()
    |> String.trim()
  end

  # Private helpers

  defp strip_titles(name) do
    # Remove common titles from the beginning of the name
    Enum.reduce(@titles, name, fn title, acc ->
      # Match title at the beginning with optional period and whitespace
      # Examples: "mr smith", "mr. smith", "mr  smith"
      String.replace(acc, ~r/^#{Regex.escape(title)}\.?\s+/i, "")
    end)
  end

  defp standardize_suffixes(name) do
    # Standardize suffixes by removing periods
    # Examples: "jr." -> "jr", "sr." -> "sr", "iii." -> "iii"
    Enum.reduce(@suffixes, name, fn suffix, acc ->
      # Remove period from suffix if present
      String.replace(acc, ~r/\b#{Regex.escape(suffix)}\./i, suffix)
    end)
  end

  defp remove_entity_types(name) do
    # Remove common entity types (LLC, Inc, Corp, etc.)
    # Handles: "ACME LLC", "ACME, LLC", "ACME INC.", "ACME CORPORATION"
    Enum.reduce(@entity_types, name, fn entity_type, acc ->
      # Match entity type with optional comma, period, or whitespace
      # Examples: ", LLC", " INC.", " CORP", "CORPORATION"
      String.replace(acc, ~r/[,\s]*\b#{Regex.escape(String.upcase(entity_type))}\b\.?/i, "")
    end)
  end
end

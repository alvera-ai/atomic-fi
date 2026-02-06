defmodule PaymentCompliancePlatform.DecisionContext.BlocklistValidator do
  @moduledoc """
  Validates account holder data against blocklist cache.

  Performs fast O(1) exact term lookups and optimized regex pattern matching
  against the tenant-scoped ETS blocklist cache.

  Returns match details for creating BlocklistMatch structs.
  """

  alias PaymentCompliancePlatform.DecisionContext.{BlocklistCache, Normalizer}

  @doc """
  Validate first name against blocklist.

  First normalizes the name, then checks against exact terms and regex patterns.

  Returns:
  - `{:ok, normalized_value}` if name passes blocklist checks
  - `{:error, :blocklisted, match_type, matched_term, reason}` if name is blocked

  ## Examples

      iex> validate_first_name(tenant_id, "Mr. Test")
      {:error, :blocklisted, :exact, "test", "Generic test placeholder name"}

      iex> validate_first_name(tenant_id, "Jane")
      {:ok, "Jane"}
  """
  def validate_first_name(tenant_id, first_name) when is_binary(first_name) do
    normalized = Normalizer.normalize_first_name(first_name)
    check_blocklist(tenant_id, :first_name, normalized)
  end

  @doc """
  Validate last name against blocklist.

  First normalizes the name, then checks against exact terms and regex patterns.

  Returns:
  - `{:ok, normalized_value}` if name passes blocklist checks
  - `{:error, :blocklisted, match_type, matched_term, reason}` if name is blocked

  ## Examples

      iex> validate_last_name(tenant_id, "Doe")
      {:error, :blocklisted, :exact, "doe", "Demo blocked surname"}

      iex> validate_last_name(tenant_id, "Smith")
      {:ok, "Smith"}
  """
  def validate_last_name(tenant_id, last_name) when is_binary(last_name) do
    normalized = Normalizer.normalize_last_name(last_name)
    check_blocklist(tenant_id, :last_name, normalized)
  end

  @doc """
  Validate company name against blocklist.

  First normalizes the name, then checks against exact terms and regex patterns.

  Returns:
  - `{:ok, normalized_value}` if name passes blocklist checks
  - `{:error, :blocklisted, match_type, matched_term, reason}` if name is blocked

  ## Examples

      iex> validate_company_name(tenant_id, "Acme Corp LLC")
      {:error, :blocklisted, :exact, "acme", "Generic placeholder company"}

      iex> validate_company_name(tenant_id, "Valid Company Inc")
      {:ok, "VALID COMPANY"}
  """
  def validate_company_name(tenant_id, company_name) when is_binary(company_name) do
    normalized = Normalizer.normalize_company_name(company_name)
    check_blocklist(tenant_id, :company_name, normalized)
  end

  # Private helpers

  defp check_blocklist(tenant_id, scope, normalized_value) do
    # CRITICAL: Verify cache is initialized before validation
    # Fail fast with exception if cache is not loaded to prevent false negatives
    unless BlocklistCache.cache_initialized?(tenant_id) do
      raise """
      BlocklistCache not initialized for tenant #{tenant_id}.

      Cache must be populated before screening can proceed. This prevents
      accidentally allowing blocked entities through due to empty cache.

      Solutions:
      - Wait for Quantum scheduler to populate cache (runs hourly)
      - Manually trigger cache refresh: POST /api/tenants/refresh-blocklist-cache
      - Run seeds.exs to populate demo blocklist entries

      Health check: BlocklistCache.health_check()
      """
    end

    # 1. Check exact match (O(1) MapSet lookup)
    exact_terms = BlocklistCache.get_exact_terms(tenant_id, scope)
    downcased = String.downcase(normalized_value)

    if MapSet.member?(exact_terms, downcased) do
      # Return match details for BlocklistMatch creation
      {:error, :blocklisted, :exact, downcased, "Exact match on blocklist"}
    else
      # 2. Check regex (single combined pattern match)
      regex_pattern = BlocklistCache.get_regex_pattern(tenant_id, scope)

      if regex_pattern && Regex.match?(regex_pattern, normalized_value) do
        {:error, :blocklisted, :regex, normalized_value, "Regex pattern match on blocklist"}
      else
        {:ok, normalized_value}
      end
    end
  end
end

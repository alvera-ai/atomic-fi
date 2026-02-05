defmodule PaymentCompliancePlatform.SessionContext.SessionManager do
  @moduledoc """
  Manages API sessions with in-memory caching (Cachex) backed by database persistence.

  **Cache-first strategy:**
  - Sessions are stored in DB **only on cache miss**
  - Most requests served from cache (no DB hit)
  - DB provides audit trail and persistence across restarts
  - Tracks IP address, user agent, and session data in metadata

  **Session lifetime:**
  - API key sessions never expire on their own (expires_at: nil)
  - Sessions are only invalidated when the API key is deactivated/deleted
  - Cache TTL (15 min) ensures fresh data from DB
  """

  import Ecto.Query
  require Logger

  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.SessionContext.Session

  @cache_ttl :timer.minutes(15)

  @doc """
  Get or create session for an API key.

  Flow:
  1. Check cache -> Hit: return cached session (no DB access)
  2. Cache miss -> Check DB -> Found: cache and return
  3. Not in DB -> Create in DB, cache, and return
  """
  def get_or_create_session(api_key, metadata \\ %{}) do
    cache_key = cache_key(api_key.id)

    case Cachex.get(:api_session_cache, cache_key) do
      {:ok, nil} ->
        # Cache miss - check DB or create
        session = get_from_db_or_create(api_key, metadata)
        Cachex.put(:api_session_cache, cache_key, session, ttl: @cache_ttl)
        {:ok, session}

      {:ok, session} ->
        # Cache hit - return immediately (no DB access)
        {:ok, session}

      {:error, reason} ->
        # Cache error - fall back to DB only
        Logger.warning("Cache error: #{inspect(reason)}, falling back to DB")
        session = get_from_db_or_create(api_key, metadata)
        {:ok, session}
    end
  end

  @doc """
  Store data in session metadata (updates DB and invalidates cache).
  """
  def put_session_data(session_id, key, value) do
    case Repo.get(Session, session_id) do
      nil ->
        {:error, :session_not_found}

      session ->
        updated_metadata = Map.put(session.metadata, to_string(key), value)

        changeset = Session.changeset(session, %{metadata: updated_metadata})

        case Repo.update(changeset) do
          {:ok, updated_session} ->
            # Invalidate cache to force reload
            invalidate_cache(session.api_key_id)
            {:ok, updated_session}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Get data from session metadata.
  """
  def get_session_data(session, key) do
    Map.get(session.metadata, to_string(key))
  end

  @doc """
  Clear inactive sessions (run periodically via SessionCleaner).

  Removes API sessions where:
  - Session is marked as inactive, OR
  - Associated API key is inactive/deleted
  """
  def clear_expired_sessions do
    # Delete sessions that are inactive or whose API key is inactive
    from(s in Session,
      left_join: k in assoc(s, :api_key),
      where: s.type == :api and (s.active == false or is_nil(k.id) or k.active == false)
    )
    |> Repo.delete_all(skip_multi_tenancy_check: true)
  end

  @doc """
  Invalidate cached session for an API key.
  """
  def invalidate_cache(api_key_id) do
    Cachex.del(:api_session_cache, cache_key(api_key_id))
  end

  # Private functions

  defp get_from_db_or_create(api_key, metadata) do
    # Look for active session for this API key
    query =
      from s in Session,
        where: s.type == :api and s.api_key_id == ^api_key.id and s.active == true,
        order_by: [desc: s.inserted_at],
        limit: 1,
        preload: [:api_key, :role, :tenant, :customer]

    case Repo.one(query, skip_multi_tenancy_check: true) do
      nil ->
        # No session exists - create new one in DB
        create_session(api_key, metadata)

      session ->
        # Return existing active session
        session
    end
  end

  defp create_session(api_key, metadata) do
    session_token = :crypto.strong_rand_bytes(32)

    # Build metadata with IP, user agent, and Cloudflare headers
    session_metadata =
      %{}
      |> Map.put("ip_address", Map.get(metadata, :ip_address))
      |> Map.put("user_agent", Map.get(metadata, :user_agent))
      |> Map.put("created_at", DateTime.to_iso8601(DateTime.utc_now()))
      |> Map.merge(Map.get(metadata, :cloudflare_metadata, %{}))

    %Session{}
    |> Session.changeset(%{
      type: :api,
      api_key_id: api_key.id,
      role_id: api_key.role_id,
      tenant_id: api_key.tenant_id,
      customer_id: api_key.customer_id,
      active: true,
      session_token: session_token,
      metadata: session_metadata,
      # API key sessions never expire on their own
      expires_at: nil
    })
    |> Repo.insert!(skip_multi_tenancy_check: true)
    |> Repo.preload([:api_key, :role, :tenant, :customer], skip_multi_tenancy_check: true)
  end

  defp cache_key(api_key_id) do
    "api_session:#{api_key_id}"
  end
end

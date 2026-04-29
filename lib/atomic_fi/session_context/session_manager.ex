defmodule AtomicFi.SessionContext.SessionManager do
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

  alias AtomicFi.ApiKeyContext.ApiKey
  alias AtomicFi.Repo
  alias AtomicFi.RoleContext.Role
  alias AtomicFi.SessionContext.Session
  alias AtomicFi.TenantContext.Tenant
  alias AtomicFi.UserContext.User
  alias AtomicFi.UserContext.UserToken

  @cache_ttl :timer.minutes(15)

  @default_bearer_expires_in 86_400
  @max_bearer_expires_in 2_592_000

  @session_preloads [:user, :user_token, :api_key, :role, :tenant, :customer]

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
  - Associated API key has been deleted (doesn't exist in api_keys table)
  """
  def clear_expired_sessions do
    # Subquery to find API key IDs that exist
    existing_api_key_ids =
      from(k in ApiKey,
        select: k.id
      )

    # Delete sessions that are inactive OR whose API key no longer exists
    # Using a subquery to avoid left join (not supported in PostgreSQL delete_all)
    # Note: api_key_id cannot be null for type=:api due to DB constraint
    from(s in Session,
      where:
        s.type == :api and
          (s.active == false or s.api_key_id not in subquery(existing_api_key_ids))
    )
    |> Repo.delete_all(skip_multi_tenancy_check: true)
  end

  @doc """
  Invalidate cached session for an API key.
  """
  def invalidate_cache(api_key_id) do
    Cachex.del(:api_session_cache, cache_key(api_key_id))
  end

  # ── Bearer sessions (POST /api/sessions) ───────────────────────────

  @doc """
  Creates a fresh UserToken + Session pair for Bearer API authentication.

  Always creates new — each `POST /api/sessions` gets its own token+session.
  The UserToken is SHA-256 hashed in `users_tokens` (context:
  `"user-session-api-token"`). The Session links via `user_token_id`.

  Returns `{plaintext_token, session}` — the plaintext is handed to the caller
  and never stored. The session is preloaded with user/user_token/role/tenant.

  ## Options

    * `:expires_in` — session duration in seconds (default: 86400 / 24h,
      clamped to [60, 2592000]).
    * `:metadata` — map of request metadata (`:ip_address`, `:user_agent`,
      `:cloudflare_metadata`).
  """
  @spec create_user_session_api_token(User.t(), Tenant.t(), Role.t(), keyword()) ::
          {String.t(), Session.t()}
  def create_user_session_api_token(
        %User{} = user,
        %Tenant{} = tenant,
        %Role{} = role,
        opts \\ []
      ) do
    {plaintext_token, user_token_struct} = UserToken.build_user_session_api_token(user)
    user_token = Repo.insert!(user_token_struct, skip_multi_tenancy_check: true)

    expires_in = clamp_expires_in(Keyword.get(opts, :expires_in))

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(expires_in, :second)
      |> DateTime.truncate(:second)

    metadata = build_metadata(Keyword.get(opts, :metadata, %{}))

    session =
      %Session{}
      |> Session.changeset(%{
        type: :user,
        user_id: user.id,
        user_token_id: user_token.id,
        role_id: role.id,
        tenant_id: tenant.id,
        customer_id: role.customer_id,
        active: true,
        session_token: :crypto.strong_rand_bytes(32),
        metadata: metadata,
        expires_at: expires_at
      })
      |> Repo.insert!(skip_multi_tenancy_check: true)
      |> Repo.preload(@session_preloads, skip_multi_tenancy_check: true)

    Cachex.put(:api_session_cache, user_token_cache_key(user_token.id), session, ttl: @cache_ttl)

    {plaintext_token, session}
  end

  @doc """
  Looks up an active Bearer session by its linked `user_token_id`.

  Used by `AtomicFiApi.Plugs.ApiAuthentication` after verifying
  the incoming Bearer token via
  `UserToken.verify_user_session_api_token_query/1`. Cache-first; falls back
  to DB on miss.
  """
  @spec get_session_by_user_token_id(Ecto.UUID.t() | nil) :: Session.t() | nil
  def get_session_by_user_token_id(user_token_id) when is_binary(user_token_id) do
    cache_key = user_token_cache_key(user_token_id)

    case Cachex.get(:api_session_cache, cache_key) do
      {:ok, nil} ->
        case fetch_bearer_session_from_db(user_token_id) do
          nil ->
            nil

          session ->
            Cachex.put(:api_session_cache, cache_key, session, ttl: @cache_ttl)
            session
        end

      {:ok, session} ->
        session

      {:error, _reason} ->
        fetch_bearer_session_from_db(user_token_id)
    end
  end

  def get_session_by_user_token_id(_), do: nil

  @doc """
  Revokes a Bearer session — deactivates it and deletes the linked UserToken.

  Invalidates the user_token cache key so subsequent Bearer requests with the
  revoked token get 401.
  """
  @spec revoke_bearer_session(Session.t()) :: :ok
  def revoke_bearer_session(%Session{user_token_id: user_token_id} = session)
      when is_binary(user_token_id) do
    session
    |> Session.changeset(%{active: false})
    |> Repo.update!(skip_multi_tenancy_check: true)

    if user_token = Repo.get(UserToken, user_token_id, skip_multi_tenancy_check: true) do
      Repo.delete!(user_token, skip_multi_tenancy_check: true)
    end

    Cachex.del(:api_session_cache, user_token_cache_key(user_token_id))
    :ok
  end

  # Private functions

  defp get_from_db_or_create(api_key, metadata) do
    # Look for active session for this API key
    query =
      from s in Session,
        where: s.type == :api and s.api_key_id == ^api_key.id and s.active == true,
        order_by: [desc: s.inserted_at],
        limit: 1,
        preload: ^@session_preloads

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
    |> Repo.preload(@session_preloads, skip_multi_tenancy_check: true)
  end

  defp cache_key(api_key_id) do
    "api_session:#{api_key_id}"
  end

  defp user_token_cache_key(user_token_id), do: "user_token_session:#{user_token_id}"

  defp clamp_expires_in(nil), do: @default_bearer_expires_in

  defp clamp_expires_in(seconds) when is_integer(seconds),
    do: min(max(seconds, 60), @max_bearer_expires_in)

  defp clamp_expires_in(_), do: @default_bearer_expires_in

  defp build_metadata(metadata) when is_map(metadata) do
    %{}
    |> Map.put("ip_address", Map.get(metadata, :ip_address))
    |> Map.put("user_agent", Map.get(metadata, :user_agent))
    |> Map.put("created_at", DateTime.to_iso8601(DateTime.utc_now()))
    |> Map.merge(Map.get(metadata, :cloudflare_metadata, %{}))
  end

  defp fetch_bearer_session_from_db(user_token_id) do
    Repo.one(
      from(s in Session,
        where: s.user_token_id == ^user_token_id and s.active == true,
        preload: ^@session_preloads
      ),
      skip_multi_tenancy_check: true
    )
  end
end

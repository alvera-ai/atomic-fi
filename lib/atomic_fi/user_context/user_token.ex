defmodule AtomicFi.UserContext.UserToken do
  @moduledoc """
  User tokens for Bearer session API authentication.

  Follows the phx.gen.auth hashed-token pattern: the plaintext token is
  Base64url-encoded and returned once to the caller; only the SHA-256 hash is
  stored in the database. A DB compromise therefore cannot be used to
  impersonate users.

  ## Contexts

  | Context | Transport | Validity |
  |---------|-----------|----------|
  | `"user-session-api-token"` | `Authorization: Bearer <token>` | 30 days |

  Bearer tokens are exchanged for by `POST /api/sessions` and link to a
  `Session` row via `session.user_token_id` for tenant-scoped authorization.

  Intentionally narrower than platform's `UserToken`: this repo does not yet
  have cookie session, confirmation, or password-reset flows. Add them when
  those flows are introduced.
  """
  use AtomicFi.Schema

  import Ecto.Query

  alias AtomicFi.UserContext.User

  @hash_algorithm :sha256
  @rand_size 32
  @user_session_api_token_validity_in_days 30

  @user_session_api_token_context "user-session-api-token"

  @doc "Public accessor — the context string stored in `users_tokens.context`."
  def user_session_api_token_context, do: @user_session_api_token_context

  typed_schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, User

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @doc """
  Builds a SHA-256 hashed Bearer token for a user.

  Returns `{plaintext_token, %UserToken{}}`. The plaintext is returned to the
  caller ONCE; only the hash is stored. Verification compares the hash of an
  incoming token against the stored hash and asserts `sent_to == user.email`,
  so changing a user's email invalidates outstanding Bearer tokens.
  """
  @spec build_user_session_api_token(User.t()) :: {String.t(), t()}
  def build_user_session_api_token(%User{} = user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{
       token: hashed_token,
       context: @user_session_api_token_context,
       sent_to: user.email,
       user_id: user.id
     }}
  end

  @doc """
  Builds a query that verifies an incoming Bearer token and selects the
  matching `%UserToken{}` row (NOT the user — the caller looks up the linked
  `Session` via `session.user_token_id`).

  Returns `:error` if the token is not valid Base64url.
  """
  @spec verify_user_session_api_token_query(String.t()) ::
          {:ok, Ecto.Query.t()} | :error
  def verify_user_session_api_token_query(token) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from t in token_and_context_query(hashed_token, @user_session_api_token_context),
            join: user in assoc(t, :user),
            where:
              t.inserted_at > ago(@user_session_api_token_validity_in_days, "day") and
                t.sent_to == user.email,
            select: t

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc "Returns tokens matching an exact hash + context."
  @spec token_and_context_query(binary(), String.t()) :: Ecto.Query.t()
  def token_and_context_query(token, context) do
    from __MODULE__, where: [token: ^token, context: ^context]
  end
end

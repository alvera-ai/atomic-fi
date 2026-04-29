# Authentication

This guide covers the authentication system in the Payments Compliance Platform.

## Overview

The template supports multiple authentication methods:

- **Email/Password**: Local authentication with bcrypt
- **Two-Factor (2FA)**: TOTP-based authentication
- **OAuth**: Placeholder for Auth0/Keycloak (optional)

## Architecture

```
User
 ├── hashed_password (bcrypt)
 ├── confirmed_at (email confirmation)
 ├── UserToken (session, reset, confirmation)
 └── UserTotp (2FA secret + backup codes)
```

## Email/Password Authentication

### User Schema

**File**: `lib/atomic_fi/user_context/user.ex`

```elixir
defmodule AtomicFi.UserContext.User do
  use AtomicFi.Schema

  typed_schema "users" do
    field :email, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :confirmed_at, :utc_datetime
    field :status, :string, default: "active"

    belongs_to :owner, AtomicFi.TenantContext.Tenant

    has_many :tokens, AtomicFi.UserContext.UserToken
    has_one :totp, AtomicFi.UserContext.UserTotp

    timestamps(type: :utc_datetime)
  end

  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password, :owner_id])
    |> validate_email()
    |> validate_password(opts)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unique_constraint(:email, name: :users_email_owner_id_index)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  def valid_password?(%User{hashed_password: hashed}, password)
      when is_binary(hashed) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed)
  end

  def valid_password?(_, _), do: false
end
```

### Registration

```elixir
defmodule AtomicFi.UserContext do
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, user} ->
        {:ok, _} = deliver_user_confirmation_instructions(user)
        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def deliver_user_confirmation_instructions(user) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
    Repo.insert!(user_token)

    # Send confirmation email
    Mailer.deliver(
      UserEmail.confirmation_email(user, url_for_token(encoded_token))
    )
  end
end
```

### Login

```elixir
def get_user_by_email_and_password(email, password, tenant_id) do
  user =
    User
    |> where(email: ^email, owner_id: ^tenant_id)
    |> Repo.one()

  if User.valid_password?(user, password), do: user
end
```

### Session Management

**File**: `lib/atomic_fi/user_context/user_token.ex`

```elixir
defmodule AtomicFi.UserContext.UserToken do
  use AtomicFi.Schema

  @hash_algorithm :sha256
  @session_validity_in_days 60

  typed_schema "user_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string

    belongs_to :user, AtomicFi.UserContext.User

    timestamps(updated_at: false)
  end

  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(32)
    {token, %UserToken{token: token, context: "session", user_id: user.id}}
  end

  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    {:ok, query}
  end
end
```

## Two-Factor Authentication (2FA)

### TOTP Schema

**File**: `lib/atomic_fi/user_context/user_totp.ex`

```elixir
defmodule AtomicFi.UserContext.UserTotp do
  use AtomicFi.Schema

  typed_schema "user_totps" do
    field :secret, :string, redact: true
    field :backup_codes, {:array, :string}, redact: true

    belongs_to :user, AtomicFi.UserContext.User

    timestamps(type: :utc_datetime)
  end

  def changeset(totp, attrs) do
    totp
    |> cast(attrs, [:secret, :backup_codes, :user_id])
    |> validate_required([:secret, :user_id])
    |> unique_constraint(:user_id)
  end
end
```

### Enable 2FA

```elixir
def enable_totp(user) do
  secret = NimbleTOTP.secret()
  backup_codes = generate_backup_codes(10)

  attrs = %{
    user_id: user.id,
    secret: secret,
    backup_codes: Enum.map(backup_codes, &hash_backup_code/1)
  }

  %UserTotp{}
  |> UserTotp.changeset(attrs)
  |> Repo.insert()
  |> case do
    {:ok, totp} ->
      # Return secret and backup codes for user to save
      {:ok, totp, secret, backup_codes}

    {:error, changeset} ->
      {:error, changeset}
  end
end

defp generate_backup_codes(count) do
  for _ <- 1..count, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end

defp hash_backup_code(code) do
  :crypto.hash(:sha256, code) |> Base.encode16(case: :lower)
end
```

### Verify TOTP

```elixir
def verify_totp(user, code) do
  with %UserTotp{secret: secret} <- get_user_totp(user),
       true <- NimbleTOTP.valid?(secret, code) do
    {:ok, :valid}
  else
    nil -> {:error, :not_enabled}
    false -> {:error, :invalid_code}
  end
end

def verify_backup_code(user, code) do
  with %UserTotp{backup_codes: codes} = totp <- get_user_totp(user),
       hashed <- hash_backup_code(code),
       true <- hashed in codes do
    # Remove used backup code
    new_codes = List.delete(codes, hashed)
    update_totp(totp, %{backup_codes: new_codes})

    {:ok, :valid}
  else
    nil -> {:error, :not_enabled}
    false -> {:error, :invalid_code}
  end
end
```

### Generate QR Code

```elixir
def totp_qr_code(user, secret) do
  otpauth_url = "otpauth://totp/PaymentsCompliancePlatform:#{user.email}?secret=#{secret}&issuer=PaymentsCompliancePlatform"

  otpauth_url
  |> EQRCode.encode()
  |> EQRCode.png()
end
```

## OAuth Integration (Optional)

### Configuration

**File**: `config/config.exs`

```elixir
# Uncomment to enable OAuth
# config :ueberauth, Ueberauth,
#   providers: [
#     oidc: {Ueberauth.Strategy.OIDC,
#       issuer: System.get_env("OIDC_ISSUER"),
#       client_id: System.get_env("OIDC_CLIENT_ID"),
#       client_secret: System.get_env("OIDC_CLIENT_SECRET"),
#       redirect_uri: "http://localhost:4000/auth/oidc/callback"
#     }
#   ]
```

### Auth Controller

**File**: `lib/atomic_fi_web/controllers/auth_controller.ex`

```elixir
defmodule AtomicFiWeb.AuthController do
  use AtomicFiWeb, :controller
  plug Ueberauth

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    # Extract user info from OAuth provider
    %{info: %{email: email, name: name}} = auth

    # Find or create user
    case UserContext.find_or_create_from_oauth(email, name) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> redirect(to: ~p"/")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Authentication failed: #{reason}")
        |> redirect(to: ~p"/login")
    end
  end

  def callback(%{assigns: %{ueberauth_failure: _fails}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate")
    |> redirect(to: ~p"/login")
  end
end
```

## Web Integration

### Plugs

**File**: `lib/atomic_fi_web/user_auth.ex`

```elixir
defmodule AtomicFiWeb.UserAuth do
  import Plug.Conn
  import Phoenix.Controller

  def fetch_current_user(conn, _opts) do
    user_token = get_session(conn, :user_token)
    user = user_token && UserContext.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  def require_confirmed_user(conn, _opts) do
    if conn.assigns[:current_user] && conn.assigns[:current_user].confirmed_at do
      conn
    else
      conn
      |> put_flash(:error, "You must confirm your email to access this page.")
      |> redirect(to: ~p"/")
      |> halt()
    end
  end

  def log_in_user(conn, user) do
    token = UserContext.generate_user_session_token(user)

    conn
    |> renew_session()
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && UserContext.delete_user_session_token(user_token)

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end
end
```

### Router

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :protect_from_forgery
  plug :put_secure_browser_headers
  plug AtomicFiWeb.UserAuth, :fetch_current_user
end

# Public routes
scope "/", AtomicFiWeb do
  pipe_through :browser

  get "/register", UserRegistrationController, :new
  post "/register", UserRegistrationController, :create
  get "/login", UserSessionController, :new
  post "/login", UserSessionController, :create
end

# Authenticated routes
scope "/", AtomicFiWeb do
  pipe_through [:browser, :require_authenticated_user]

  get "/settings", UserSettingsController, :edit
  put "/settings", UserSettingsController, :update
  delete "/logout", UserSessionController, :delete
end

# OAuth routes (if enabled)
scope "/auth", AtomicFiWeb do
  pipe_through :browser

  get "/:provider", AuthController, :request
  get "/:provider/callback", AuthController, :callback
end
```

### LiveView Hooks

**File**: `lib/atomic_fi_web/live/hooks/user_on_mount_hooks.ex`

```elixir
defmodule AtomicFiWeb.UserOnMountHooks do
  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:require_authenticated_user, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: ~p"/login")}
    end
  end

  def on_mount(:require_confirmed_user, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user && socket.assigns.current_user.confirmed_at do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: ~p"/")}
    end
  end

  defp mount_current_user(socket, session) do
    case session do
      %{"user_token" => user_token} ->
        assign_new(socket, :current_user, fn ->
          UserContext.get_user_by_session_token(user_token)
        end)

      %{} ->
        assign_new(socket, :current_user, fn -> nil end)
    end
  end
end
```

## Testing

### Setup Helper

**File**: `test/support/conn_case.ex`

```elixir
def register_and_log_in_user(%{conn: conn}) do
  user = AtomicFi.AccountsFixtures.user_fixture()
  %{conn: log_in_user(conn, user), user: user}
end

def log_in_user(conn, user) do
  token = AtomicFi.UserContext.generate_user_session_token(user)

  conn
  |> Phoenix.ConnTest.init_test_session(%{})
  |> Plug.Conn.put_session(:user_token, token)
end
```

### Controller Tests

```elixir
test "redirects if user is not logged in", %{conn: conn} do
  conn = get(conn, ~p"/settings")
  assert redirected_to(conn) == ~p"/login"
end

test "renders settings page when logged in", %{conn: conn, user: user} do
  conn = log_in_user(conn, user)
  conn = get(conn, ~p"/settings")
  assert html_response(conn, 200) =~ "Settings"
end
```

## Security Best Practices

### Password Hashing

- ✅ Use bcrypt (included)
- ✅ Minimum 12 characters
- ✅ Redact password fields in logs

### Session Management

- ✅ 60-day session validity
- ✅ Renew session on login
- ✅ Clear session on logout
- ✅ Signed cookies

### 2FA

- ✅ TOTP standard (RFC 6238)
- ✅ Backup codes (one-time use)
- ✅ QR code generation
- ✅ Secret stored encrypted

### OAuth

- ✅ Use environment variables for secrets
- ✅ Validate redirect URIs
- ✅ Check issuer/audience claims

## Next Steps

- [Multi-Tenancy Guide](multi-tenancy.md) - Tenant scoping
- [Testing Guide](testing.md) - Auth testing strategies
- [API Development](api-development.md) - API authentication
